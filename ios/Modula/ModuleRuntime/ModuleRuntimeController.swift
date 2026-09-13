import Foundation
import Observation
import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider
import Darwin

@MainActor @Observable
final class ModuleRuntimeController {
    static let bridgeVersion = "0.1.0"
    private var factory: RCTReactNativeFactory?
    private var factoryDelegate: RuntimeDelegate?
    private(set) var initializationCount = 0
    private(set) var sessions: [String: ModuleSession] = [:]
    private(set) var lastSession: ModuleSession?
    private(set) var memoryWarnings = 0
    private(set) var initializationMilliseconds: Double?
    private(set) var nativeUsableMilliseconds: Double?
    private(set) var memoryBeforeRuntimeMB: Double?
    private(set) var memoryWithModuleMB: Double?
    private(set) var memoryAfterCloseMB: Double?
    private(set) var firstVaultDataReadyMilliseconds: Double?
    private(set) var firstRuntimeReadyMilliseconds: Double?
    private(set) var vaultMountMilliseconds: [Double] = []
    private(set) var manifests: [ModuleManifest] = []
    private(set) var accountID: String?
    private(set) var lastRejectedAction: String?
    private let processStartedUptime = ProcessInfo.processInfo.systemUptime
    var state: String { factory == nil ? "uninitialized" : "initialized" }

    init() {
        if let url = Bundle.main.url(forResource: "manifests", withExtension: "json"),
           let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([ModuleManifest].self, from: data) {
            manifests = values
        }
    }

    func prepare(moduleID: String, environment: ModuleEnvironment, initialLocalPath: String? = nil) -> ModuleSession? {
        guard let manifest = manifests.first(where: { $0.id == moduleID }), manifest.runtime == "react-native",
              manifest.minBridgeVersion == Self.bridgeVersion, manifest.minHostVersion == "0.1.0" else { return nil }
        let session = ModuleSession(manifest: manifest, environment: environment, accountID: accountID, initialLocalPath: initialLocalPath)
        ModulaLog.runtime.debug("Preparing module surface")
        sessions[session.id] = session
        lastSession = session
        if ProcessInfo.processInfo.arguments.contains("--runtime-unavailable") ||
            Bundle.main.url(forResource: "main", withExtension: "jsbundle") == nil {
            session.state = .unavailable
            session.error = "The module bundle is unavailable."
        }
        return session
    }

    func setAccount(_ id: String?) {
        guard id != accountID else { return }
        revokeAll()
        accountID = id
    }
    func revokeAll() {
        for session in Array(sessions.values) {
            fail(session, message: "This module session ended. Close and reopen after signing in.")
            unmount(session)
        }
    }
    func authorize(_ session: ModuleSession) -> Bool {
        session.isValid && session.expiresAt > Date() && sessions[session.id] === session && session.accountID == accountID
    }
    func reject(_ reason: String) { lastRejectedAction = reason }

    func markNativeUsable() {
        guard nativeUsableMilliseconds == nil else { return }
        nativeUsableMilliseconds = (ProcessInfo.processInfo.systemUptime - processStartedUptime) * 1_000
    }

    func makeSurface(_ session: ModuleSession) -> UIView? {
        ModulaLog.runtime.debug("Creating module surface, valid \(session.isValid)")
        guard session.isValid else { return nil }
        guard !ProcessInfo.processInfo.arguments.contains("--runtime-unavailable"),
              Bundle.main.url(forResource: "main", withExtension: "jsbundle") != nil else {
            session.state = .unavailable
            session.error = "The module bundle is unavailable."
            return nil
        }
        if factory == nil {
            session.state = .startingRuntime
            memoryBeforeRuntimeMB = residentMemoryMB()
            let start = ContinuousClock.now
            let delegate = RuntimeDelegate()
            delegate.dependencyProvider = RCTAppDependencyProvider()
            factoryDelegate = delegate
            factory = RCTReactNativeFactory(delegate: delegate)
            initializationCount += 1
            initializationMilliseconds = start.duration(to: .now).milliseconds
            ModulaLog.runtime.info("Runtime factory initialized")
        }
        session.state = .loadingModule
        let props = initialProperties(for: session)
        let view = factory?.rootViewFactory.view(withModuleName: "ModulaModuleRoot", initialProperties: props)
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, let session, session.isValid, session.state == .loadingModule else { return }
            self.fail(session, message: "The module did not become ready. Try again.")
        }
        return view
    }

    func initialProperties(for session: ModuleSession) -> [String: Any] {
        [
            "sessionID": session.id, "moduleID": session.manifest.id,
            "bridgeVersion": Self.bridgeVersion, "environment": session.environment.dictionary,
            "userID": session.accountID as Any? ?? NSNull(), "initialPath": session.initialLocalPath as Any? ?? NSNull()
        ]
    }

    func ready(_ session: ModuleSession) {
        guard session.isValid, session.state == .loadingModule else { return }
        session.state = .ready
        session.loadMilliseconds = session.startedAt.duration(to: .now).milliseconds
        if firstRuntimeReadyMilliseconds == nil { firstRuntimeReadyMilliseconds = session.loadMilliseconds }
        if session.manifest.id == "digital.modula.vault-notes", let duration = session.loadMilliseconds {
            vaultMountMilliseconds.append(duration)
        }
        memoryWithModuleMB = residentMemoryMB()
        emit("active", session: session)
        ModulaLog.runtime.info("Module ready in \(session.loadMilliseconds ?? 0) ms")
    }
    func fail(_ session: ModuleSession, message: String = "This module failed to load.") {
        session.state = .failed
        session.error = message
    }
    func dataReady(_ session: ModuleSession) {
        guard authorize(session), session.state == .ready else { return }
        session.dataReadyMilliseconds = session.startedAt.duration(to: .now).milliseconds
        if session.manifest.id == "digital.modula.vault-notes", firstVaultDataReadyMilliseconds == nil {
            firstVaultDataReadyMilliseconds = session.dataReadyMilliseconds
        }
    }
    func unmount(_ session: ModuleSession) {
        ModulaLog.runtime.debug("Unmounting module surface")
        guard session.isValid else { return }
        emit("unmounted", session: session)
        session.isValid = false
        sessions.removeValue(forKey: session.id)
        memoryAfterCloseMB = residentMemoryMB()
        if session.state != .failed { session.state = .idle }
    }
    func update(_ environment: ModuleEnvironment, session: ModuleSession) {
        guard session.isValid, environment != session.environment else { return }
        session.environment = environment
        emit("appearanceChanged", session: session)
    }
    func lifecycle(_ name: String) {
        if name == "memoryPressure" { memoryWarnings += 1 }
        for session in sessions.values {
            if name == "backgrounded" && session.state == .ready { session.state = .suspended }
            if name == "active" && session.state == .suspended { session.state = .ready }
            emit(name, session: session)
        }
    }
    func emit(_ name: String, session: ModuleSession) {
        let payload: [String: Any] = ["sessionID": session.id, "name": name, "environment": session.environment.dictionary]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let wire = String(data: data, encoding: .utf8) else { return }
        NotificationCenter.default.post(name: Notification.Name("ModulaHostEvent"), object: wire)
    }
}

private func residentMemoryMB() -> Double? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : nil
}

private final class RuntimeDelegate: RCTDefaultReactNativeFactoryDelegate {
    override func bundleURL() -> URL? {
        // Bundled debug is deterministic; Metro opt-in is added via local configuration.
        Bundle.main.url(forResource: "main", withExtension: "jsbundle")
    }
}

extension Duration {
    var milliseconds: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}
private extension ModuleEnvironment {
    var dictionary: [String: Any] {
        ["designContractVersion": designContractVersion, "colorScheme": colorScheme, "theme": theme,
         "darkStyle": darkStyle, "oled": oled, "accent": accent, "fontFamily": fontFamily,
         "density": density, "motionPersonality": motionPersonality, "hapticIntensity": hapticIntensity,
         "contrastPreference": contrastPreference, "transparencyPreference": transparencyPreference,
         "iconStyle": iconStyle, "interfaceShape": interfaceShape, "moduleBranding": moduleBranding,
         "reduceMotion": reduceMotion, "textScale": textScale]
    }
}
