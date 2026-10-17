import Foundation
import Observation
import Security

struct ModuleManifest: Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let runtime: String
    let entry: String
    let permissions: [String]
    /// Semver range (bare version = caret), see `SemverRange`.
    let minHostVersion: String
    /// Semver range (bare version = caret), see `SemverRange`.
    let minBridgeVersion: String
    let collections: [String]?
}

@MainActor @Observable
final class ModuleSession: Identifiable {
    enum State: String {
        case idle, preparing, startingRuntime, loadingModule, ready, suspended, failed, unavailable
        case notInstalled, integrityFailed, updateRequired, permissionDenied, expired
    }
    static let timeToLive: TimeInterval = 15 * 60
    /// Native-only identity. Never sent to JavaScript.
    let id = UUID().uuidString
    /// Per-surface capability handed only to this surface's root props. Requests resolve
    /// the session from this token; it is never included in any event.
    let surfaceToken: String = ModuleSession.randomToken()
    let manifest: ModuleManifest
    var runtimeKind: ModuleRuntimeKind = .bundledReactNative
    var productUI: ProductUIDocument?
    var cachedRelease: ModuleCachedRelease?
    var state: State = .preparing
    var environment: ModuleEnvironment
    var error: String?
    /// Capabilities the policy withheld (shown by the permission-denied host state).
    var deniedCapabilities: [String] = []
    /// Effective grant: manifest ∩ install-descriptor grant ∩ host-supported.
    var grantedCapabilities: Set<String>
    let startedAt = ContinuousClock.now
    var loadMilliseconds: Double?
    var dataReadyMilliseconds: Double?
    var isValid = true
    let accountID: String?
    let initialLocalPath: String?
    var expiresAt: Date
    /// Monotonic per-surface event sequence delivered with root props.
    var eventSequence = 0
    var lastEvent = "mounted"

    init(manifest: ModuleManifest, environment: ModuleEnvironment, accountID: String? = nil,
         initialLocalPath: String? = nil, granted: Set<String>? = nil, now: Date = Date()) {
        self.accountID = accountID
        self.manifest = manifest
        self.environment = environment
        self.initialLocalPath = initialLocalPath
        self.grantedCapabilities = granted ?? Set(manifest.permissions)
        self.expiresAt = now.addingTimeInterval(Self.timeToLive)
    }

    func renew(now: Date) { expiresAt = now.addingTimeInterval(Self.timeToLive) }

    nonisolated static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random unavailable")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
