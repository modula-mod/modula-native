import Foundation
import Observation
import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider
import Darwin

/// What the account's installation says about a module, supplied by Product Hub.
enum ModuleInstallGate: Equatable, Sendable {
    /// Runnable installation; `descriptor` is the verified install descriptor when the
    /// store holds one (Product Hub version switching), used for the integrity check.
    case runnable(descriptor: ModuleInstallDescriptor?)
    case notInstalled
}

@MainActor @Observable
final class ModuleRuntimeController {
    nonisolated static let bridgeVersion = "0.1.0"
    /// Bundled RN contract still advertised as 0.1.0 so existing modules stay compatible.
    nonisolated static let hostVersion = "0.1.0"
    /// Product UI / MPS host contract. Catalogue APIs already advertise `ModulaHost.version`.
    nonisolated static let productUIHostVersion = "1.0.0"
    /// Capabilities this host implements. Anything else a manifest declares is denied.
    nonisolated static let supportedCapabilities: Set<String> = ModuleCapabilityBroker.supported
    private var factory: RCTReactNativeFactory?
    private var factoryDelegate: RuntimeDelegate?
    private(set) var initializationCount = 0
    /// Keyed by native session ID (never exposed to JS).
    private(set) var sessions: [String: ModuleSession] = [:]
    /// Surface token → native session ID. The only way a JS request reaches a session.
    private var tokens: [String: String] = [:]
    /// Per-surface prop delivery (set by the surface's view controller).
    private var surfaceUpdaters: [String: ([String: Any]) -> Void] = [:]
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
    /// Raw bundled manifest JSON per module, for the integrity digest.
    private(set) var manifestJSON: [String: JSONValue] = [:]
    private(set) var accountID: String?
    private(set) var lastRejectedAction: String?
    /// Injected by AppEnvironment from Product Hub. nil (unit tests, previews) skips the gate.
    var installationGate: ((String) -> ModuleInstallGate)?
    var activation: ModuleActivationController?
    var productUIRecordSource: ((String, String) -> [ProductUIRecord])?
    var now: () -> Date = Date.init
    private let processStartedUptime = ProcessInfo.processInfo.systemUptime
    var state: String { factory == nil ? "uninitialized" : "initialized" }

    init(manifests injected: [ModuleManifest]? = nil, manifestJSON injectedJSON: [String: JSONValue] = [:]) {
        if let injected {
            manifests = injected
            manifestJSON = injectedJSON
            return
        }
        if let url = Bundle.main.url(forResource: "manifests", withExtension: "json"),
           let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([ModuleManifest].self, from: data) {
            manifests = values
            if case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
                for item in items { if let id = item["id"]?.string { manifestJSON[id] = item } }
            }
        }
    }

    func prepare(moduleID: String, environment: ModuleEnvironment, initialLocalPath: String? = nil) -> ModuleSession? {
        let cached = activation?.active(accountID: accountID, moduleId: moduleID)
        let bundled = manifests.first(where: { $0.id == moduleID })
        guard let manifest = cached?.hostManifest ?? bundled else { return nil }
        let gate = installationGate?(moduleID)
        let descriptor: ModuleInstallDescriptor? = {
            if case .runnable(let d)? = gate { return d }
            return cached?.descriptor
        }()
        let policy = ModulePolicy.grant(manifest: manifest, descriptor: descriptor, supported: Self.supportedCapabilities)
        let session = ModuleSession(manifest: manifest, environment: environment, accountID: accountID,
                                    initialLocalPath: initialLocalPath, granted: policy.granted, now: now())
        session.deniedCapabilities = policy.denied
        session.cachedRelease = cached
        lastSession = session
        // Gate order: compatibility → installation → integrity → permissions → bundle/frontend.
        switch ModuleCompatibility.evaluate(manifest, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: Self.bridgeVersion) {
        case .compatible: break
        case .unsupportedRuntime:
            return blocked(session, .unavailable, "\(manifest.name) uses a runtime this app doesn’t support.")
        case .updateRequired:
            return blocked(session, .updateRequired, "\(manifest.name) needs a newer version of Modula. Update the app to open it.")
        case .moduleOutdated:
            return blocked(session, .updateRequired, "This version of \(manifest.name) is too old for this app. Update it in Product Hub.")
        }
        if gate == .notInstalled && cached == nil {
            return blocked(session, .notInstalled, "\(manifest.name) isn’t installed on your account. Install it from Product Hub to open it.")
        }
        if let descriptor, ModuleReleaseVerifier.verify(moduleID: moduleID, bundledManifest: manifestJSON[moduleID], descriptor: descriptor) != nil {
            return blocked(session, .integrityFailed, "\(manifest.name) didn’t pass its integrity check, so it wasn’t opened.")
        }
        if !policy.requiredDenied.isEmpty {
            return blocked(session, .permissionDenied, "\(manifest.name) needs permissions that aren’t granted for this installation.")
        }
        if let cached, cached.gameSha256 != nil {
            do {
                session.webGameEntry = try activation?.store.verifiedGameEntry(for: cached)
                guard session.webGameEntry != nil else { throw WebGamePackageError.invalid("cache unavailable") }
                session.runtimeKind = .webGame
                session.state = .ready
            } catch {
                return blocked(session, .integrityFailed, "\(manifest.name) failed game package verification.")
            }
        } else if manifest.runtime == "web-game" {
            return blocked(session, .integrityFailed, "\(manifest.name) has no verified game package.")
        } else if let cached, cached.frontendMediaType == ProductUIDocument.mediaType {
            do {
                let data = try activation?.store.frontendData(for: cached) ?? Data()
                session.productUI = try ProductUIDocument.parse(data: data, productId: cached.moduleId, version: cached.version)
                session.runtimeKind = .declarativeProductUI
                session.state = .ready
            } catch {
                return blocked(session, .integrityFailed, "\(manifest.name) didn’t pass its frontend integrity check, so it wasn’t opened.")
            }
        }
        ModulaLog.runtime.debug("Preparing module surface")
        sessions[session.id] = session
        tokens[session.surfaceToken] = session.id
        if session.runtimeKind == .bundledReactNative,
           ProcessInfo.processInfo.arguments.contains("--runtime-unavailable") ||
            Bundle.main.url(forResource: "main", withExtension: "jsbundle") == nil {
            session.state = .unavailable
            session.error = "The module bundle is unavailable."
        }
        return session
    }

    private func blocked(_ session: ModuleSession, _ state: ModuleSession.State, _ message: String) -> ModuleSession {
        session.state = state
        session.error = message
        session.isValid = false
        return session
    }

    /// Why `prepare` would refuse a module before creating a session (nil when it can try).
    nonisolated static func unavailableReason(for moduleID: String, in manifests: [ModuleManifest]) -> String? {
        guard let manifest = manifests.first(where: { $0.id == moduleID }) else {
            return "This module isn’t included in this version of Modula."
        }
        switch ModuleCompatibility.evaluate(manifest, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: bridgeVersion) {
        case .compatible: return nil
        case .unsupportedRuntime: return "\(manifest.name) uses a runtime this app doesn’t support."
        case .updateRequired: return "\(manifest.name) needs a newer version of Modula. Update the app to open it."
        case .moduleOutdated: return "This version of \(manifest.name) is too old for this app. Update it in Product Hub."
        }
    }

    func unavailableReason(for moduleID: String) -> String? { Self.unavailableReason(for: moduleID, in: manifests) }

    /// Resolve the session for a JS request from its surface token only. The JS-supplied
    /// module ID must match the bound module; a native session ID is never accepted.
    func session(forToken token: String, moduleID: String) -> ModuleSession? {
        guard let id = tokens[token], let session = sessions[id], session.surfaceToken == token,
              session.manifest.id == moduleID else { return nil }
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

    /// Valid, unexpired, registered, same account. Authorized activity renews the TTL;
    /// expiry ends the session into the `expired` host state.
    func authorize(_ session: ModuleSession, renew: Bool = true) -> Bool {
        guard session.isValid, sessions[session.id] === session, session.accountID == accountID else { return false }
        let current = now()
        guard session.expiresAt > current else { expire(session); return false }
        if renew, session.state != .suspended { session.renew(now: current) }
        return true
    }
    func expire(_ session: ModuleSession) {
        guard session.isValid else { return }
        deliver("unmounted", to: session)
        session.isValid = false
        release(session)
        session.state = .expired
        session.error = "\(session.manifest.name) was closed after 15 minutes without activity."
    }
    func reject(_ reason: String) { lastRejectedAction = reason }

    func markNativeUsable() {
        guard nativeUsableMilliseconds == nil else { return }
        nativeUsableMilliseconds = (ProcessInfo.processInfo.systemUptime - processStartedUptime) * 1_000
    }

    func makeSurface(_ session: ModuleSession) -> UIView? {
        ModulaLog.runtime.debug("Creating module surface, valid \(session.isValid)")
        guard session.isValid else { return nil }
        if session.runtimeKind == .declarativeProductUI || session.runtimeKind == .webGame { return nil }
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
        if let hosting = view as? RCTSurfaceHostingProxyRootView {
            // Per-surface delivery: lifecycle/appearance updates become new root props of
            // this surface only. Nothing is broadcast to the shared JS context.
            surfaceUpdaters[session.id] = { [weak hosting] props in hosting?.appProperties = props }
        }
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, let session, session.isValid, session.state == .loadingModule else { return }
            self.fail(session, message: "The module did not become ready. Try again.")
        }
        return view
    }

    func initialProperties(for session: ModuleSession) -> [String: Any] {
        let userID: Any = session.grantedCapabilities.contains(ModulePolicy.identityUserID) ? (session.accountID as Any? ?? NSNull()) : NSNull()
        return [
            "surfaceToken": session.surfaceToken, "moduleID": session.manifest.id,
            "bridgeVersion": Self.bridgeVersion, "environment": session.environment.dictionary,
            "userID": userID, "signedIn": session.accountID != nil,
            "initialPath": session.initialLocalPath as Any? ?? NSNull(),
            "lifecycle": session.lastEvent, "eventSequence": session.eventSequence,
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
        deliver("active", to: session)
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

    /// Host hidden (tab switch, a route pushed on top): keep the surface and its React
    /// state alive; the TTL is not renewed while suspended.
    func suspend(_ session: ModuleSession) {
        guard session.isValid, session.state == .ready || session.state == .loadingModule else { return }
        if session.state == .ready { session.state = .suspended }
        deliver("suspended", to: session)
    }
    /// Host visible again. An expired session moves to the expired state instead.
    func resume(_ session: ModuleSession) {
        guard session.isValid, sessions[session.id] === session else { return }
        guard session.expiresAt > now() else { expire(session); return }
        if session.state == .suspended { session.state = .ready }
        session.renew(now: now())
        deliver("resumed", to: session)
    }

    /// Real teardown: the hosting view was removed (closed, popped, account change).
    func unmount(_ session: ModuleSession) {
        ModulaLog.runtime.debug("Unmounting module surface")
        guard session.isValid else { release(session); return }
        deliver("unmounted", to: session)
        session.isValid = false
        release(session)
        memoryAfterCloseMB = residentMemoryMB()
        if session.state != .failed { session.state = .idle }
    }
    private func release(_ session: ModuleSession) {
        sessions.removeValue(forKey: session.id)
        tokens.removeValue(forKey: session.surfaceToken)
        surfaceUpdaters.removeValue(forKey: session.id)
    }
    func update(_ environment: ModuleEnvironment, session: ModuleSession) {
        guard session.isValid, environment != session.environment else { return }
        session.environment = environment
        deliver("appearanceChanged", to: session)
    }
    func lifecycle(_ name: String) {
        if name == "memoryPressure" { memoryWarnings += 1 }
        for session in sessions.values {
            if name == "backgrounded" && session.state == .ready { session.state = .suspended }
            if name == "active" && session.state == .suspended { session.state = .ready }
            deliver(name, to: session)
        }
    }

    /// Delivers one event to one surface by updating that surface's root props.
    /// Returns the props delivered (unit tests assert per-surface isolation on these).
    @discardableResult
    func deliver(_ name: String, to session: ModuleSession) -> [String: Any] {
        session.eventSequence += 1
        session.lastEvent = name
        let props = initialProperties(for: session)
        surfaceUpdaters[session.id]?(props)
        eventObserver?(session.id, props)
        return props
    }
    /// Test/diagnostic tap: (native session ID, props delivered to that surface).
    var eventObserver: ((String, [String: Any]) -> Void)?
}

/// Capability policy. The effective grant is manifest ∩ host-supported ∩ (when the
/// installation carries a verified install descriptor) what the registry granted, mapped
/// from registry vocabulary (`storage:records` or `records:*`) to host actions (`backend.records.*`).
enum ModulePolicy {
    static let identityUserID = "identity.userID"
    /// Host capability prefix → legacy registry permission that must be granted for it.
    static let registryPermission: [(prefix: String, permission: String)] = [("backend.records.", "storage:records")]

    struct Grant: Equatable { let granted: Set<String>; let denied: [String]; let requiredDenied: [String] }

    static func grant(manifest: ModuleManifest, descriptor: ModuleInstallDescriptor?, supported: Set<String>) -> Grant {
        let declared = Set(manifest.permissions)
        var granted = declared.intersection(supported)
        var withheld: Set<String> = []
        if let descriptor {
            let allowed = Set(descriptor.grantedPermissions)
            for capability in granted where !registryAllows(capability, granted: allowed) {
                withheld.insert(capability)
            }
            granted.subtract(withheld)
        }
        let denied = declared.subtracting(granted).sorted()
        // Declared capabilities the registry withheld make the module unusable: block it
        // natively (permission-denied state). Capabilities this host doesn't implement are
        // denied per call instead (PERMISSION_DENIED / UNSUPPORTED_ACTION).
        return Grant(granted: granted, denied: denied, requiredDenied: withheld.sorted())
    }

    /// Host record actions covered by the registry grants on an installation.
    static func hostCapabilities(coveredBy granted: [String]) -> [String] {
        let allowed = Set(granted)
        var covered = ModuleCapabilityBroker.supported.filter { capability in
            capability.hasPrefix("backend.records.") && registryAllows(capability, granted: allowed)
        }.sorted()
        if granted.contains(where: { $0.hasPrefix("media:") && ($0.hasSuffix(":read") || $0.hasSuffix(":write")) }) {
            covered.append("mediaPicker")
        }
        if granted.contains(where: { $0.hasPrefix("sharing:") }) {
            covered.append("share")
        }
        return Array(Set(covered)).sorted()
    }

    /// Places a registry permission in the review list by its vocabulary family.
    /// New ids that follow the published patterns do not require a host rebuild.
    static func classify(_ permission: String) -> String {
        let parts = permission.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first, !head.isEmpty else { return "unrecognized" }
        let action = parts.last ?? ""
        switch head {
        case "records":
            return parts.count >= 3 && ["read", "write", "delete"].contains(action) ? "records" : "unrecognized"
        case "media":
            return parts.count >= 3 && ["read", "write"].contains(action) ? "media" : "unrecognized"
        case "sharing":
            return parts.count >= 3 && ["read", "write"].contains(action) ? "sharing" : "unrecognized"
        case "files":
            return parts.count >= 2 ? "files" : "unrecognized"
        case "schemas", "routes", "events", "search", "widgets", "plugins", "connectors",
             "profile-tabs", "board-surfaces", "tools":
            return "server"
        case "functions":
            return "server"
        case "settings":
            return parts.count >= 2 && parts[1] == "register" ? "server" : "settings"
        case "notifications":
            return "notifications"
        case "jobs":
            return "jobs"
        case "ai":
            return "ai"
        case "network":
            return "network"
        case "dimon":
            return "dimon"
        default:
            // Future families stay reviewable without a native rebuild.
            return parts.count >= 2 ? String(head.prefix(40)) : "unrecognized"
        }
    }

    static func registryAllows(_ capability: String, granted: Set<String>) -> Bool {
        guard let rule = registryPermission.first(where: { capability.hasPrefix($0.prefix) }) else { return true }
        if granted.contains(rule.permission) { return true }
        guard capability.hasPrefix("backend.records.") else { return false }
        let suffix: String
        switch capability {
        case "backend.records.list", "backend.records.get": suffix = ":read"
        case "backend.records.create", "backend.records.update": suffix = ":write"
        case "backend.records.delete": suffix = ":delete"
        default: return false
        }
        return granted.contains { $0.hasPrefix("records:") && $0.hasSuffix(suffix) }
    }
}

/// Release integrity before any module JS runs. The install descriptor Product Hub
/// verified against the registry is re-checked here: its own digest must recompute, it
/// must name this module, and it must not be revoked/quarantined. When the bundled
/// manifest JSON is available and the descriptor carries `manifest.bundledManifestSha256`
/// (reserved; the registry doesn't publish a per-platform bundled digest yet), the
/// canonical SHA-256 of the bundled manifest must equal it.
enum ModuleReleaseVerifier {
    enum Failure: Equatable { case descriptorDigest, wrongModule, revoked, bundledDigest }

    static func verify(moduleID: String, bundledManifest: JSONValue?, descriptor: ModuleInstallDescriptor) -> Failure? {
        guard descriptor.computedSha256 == descriptor.descriptorSha256 else { return .descriptorDigest }
        guard descriptor.moduleId == moduleID else { return .wrongModule }
        if descriptor.revoked || descriptor.quarantined { return .revoked }
        if let expected = descriptor.raw["manifest"]?["bundledManifestSha256"]?.string {
            guard let bundledManifest, CanonicalJSON.sha256Hex(bundledManifest) == expected else { return .bundledDigest }
        }
        return nil
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
