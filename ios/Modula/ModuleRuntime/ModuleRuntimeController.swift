import Foundation
import Observation
import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

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
    private(set) var manifests: [ModuleManifest] = []
    var state: String { factory == nil ? "uninitialized" : "initialized" }

    init() {
        if let url = Bundle.main.url(forResource: "manifests", withExtension: "json"),
           let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([ModuleManifest].self, from: data) {
            manifests = values
        }
    }

    func prepare(moduleID: String, environment: ModuleEnvironment) -> ModuleSession? {
        guard let manifest = manifests.first(where: { $0.id == moduleID }), manifest.runtime == "react-native",
              manifest.minBridgeVersion == Self.bridgeVersion, manifest.minHostVersion == "0.1.0" else { return nil }
        let session = ModuleSession(manifest: manifest, environment: environment)
        ModulaLog.runtime.debug("Preparing surface \(session.id, privacy: .public)")
        sessions[session.id] = session
        lastSession = session
        return session
    }

    func makeSurface(_ session: ModuleSession) -> UIView? {
        ModulaLog.runtime.debug("Creating surface \(session.id, privacy: .public), valid \(session.isValid)")
        guard session.isValid else { return nil }
        guard !ProcessInfo.processInfo.arguments.contains("--runtime-unavailable"),
              Bundle.main.url(forResource: "main", withExtension: "jsbundle") != nil else {
            session.state = .unavailable
            session.error = "The module bundle is unavailable."
            return nil
        }
        if factory == nil {
            session.state = .startingRuntime
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
        let props: [String: Any] = [
            "sessionID": session.id, "moduleID": session.manifest.id,
            "bridgeVersion": Self.bridgeVersion, "environment": session.environment.dictionary,
            "userID": NSNull()
        ]
        let view = factory?.rootViewFactory.view(withModuleName: "ModulaModuleRoot", initialProperties: props)
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, let session, session.isValid, session.state == .loadingModule else { return }
            self.fail(session, message: "The module did not become ready. Try again.")
        }
        return view
    }

    func ready(_ session: ModuleSession) {
        guard session.isValid, session.state == .loadingModule else { return }
        session.state = .ready
        session.loadMilliseconds = session.startedAt.duration(to: .now).milliseconds
        emit("active", session: session)
        ModulaLog.runtime.info("Module ready in \(session.loadMilliseconds ?? 0) ms")
    }
    func fail(_ session: ModuleSession, message: String = "This module failed to load.") {
        session.state = .failed
        session.error = message
    }
    func unmount(_ session: ModuleSession) {
        ModulaLog.runtime.debug("Unmounting surface \(session.id, privacy: .public)")
        guard session.isValid else { return }
        emit("unmounted", session: session)
        session.isValid = false
        sessions.removeValue(forKey: session.id)
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
        ["colorScheme": colorScheme, "oled": oled, "accent": accent, "surfacePreference": surfacePreference,
         "reduceMotion": reduceMotion, "textScale": textScale]
    }
}
