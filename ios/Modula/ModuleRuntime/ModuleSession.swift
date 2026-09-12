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
    var isValid = true
    init(manifest: ModuleManifest, environment: ModuleEnvironment) {
        self.manifest = manifest
        self.environment = environment
    }
}
