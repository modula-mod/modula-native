import Foundation
import Observation

struct ModuleManifest: Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let runtime: String
    let entry: String
    let permissions: [String]
    let minHostVersion: String
    let minBridgeVersion: String
    let collections: [String]?
    /// Optional store artwork/copy. Absent in older manifests; Product Hub falls back to placeholders.
    var presentation: ModulePresentation? = nil
}

struct ModulePresentation: Codable, Sendable, Hashable {
    struct Screenshot: Codable, Sendable, Hashable { let source: String; let alt: String? }
    let subtitle: String?
    let tint: String?
    let icon: String?
    let cover: String?
    let screenshots: [Screenshot]?
}

@MainActor @Observable
final class ModuleSession: Identifiable {
    enum State: String { case idle, preparing, startingRuntime, loadingModule, ready, suspended, failed, unavailable }
    let id = UUID().uuidString
    let manifest: ModuleManifest
    var state: State = .preparing
    var environment: ModuleEnvironment
    var error: String?
    let startedAt = ContinuousClock.now
    var loadMilliseconds: Double?
    var dataReadyMilliseconds: Double?
    var isValid = true
    let accountID: String?
    let initialLocalPath: String?
    var expiresAt = Date().addingTimeInterval(15 * 60)
    init(manifest: ModuleManifest, environment: ModuleEnvironment, accountID: String? = nil, initialLocalPath: String? = nil) {
        self.accountID = accountID
        self.manifest = manifest
        self.environment = environment
        self.initialLocalPath = initialLocalPath
    }
}
