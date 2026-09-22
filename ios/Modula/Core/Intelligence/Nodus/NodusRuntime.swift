import Foundation

enum NodusLoadState: String, Sendable, Equatable, Codable {
    case unloaded
    case loading
    case loaded
    case generating
    case failed
}

struct NodusRuntimeGeneration: Sendable, Equatable {
    let text: String
    let modelVersion: String
    let completed: Bool
    let tokensPerSecond: Double?
    let modelConsistency: Double?
}

protocol NodusRuntime: Sendable {
    func availability() async -> IntelligenceAvailability
    func loadState() async -> NodusLoadState
    func load() async throws
    func generate(prompt: String, capability: IntelligenceCapability) async throws -> NodusRuntimeGeneration
    func unload() async
}

actor UnavailableNodusRuntime: NodusRuntime {
    private let availabilityState: IntelligenceAvailability

    init(availability: IntelligenceAvailability = .modelNotInstalled) {
        availabilityState = availability
    }

    func availability() -> IntelligenceAvailability { availabilityState }
    func loadState() -> NodusLoadState { .unloaded }
    func load() throws { throw IntelligenceError.providerUnavailable(providerID: NodusIntelligenceProvider.providerID) }
    func generate(prompt: String, capability: IntelligenceCapability) throws -> NodusRuntimeGeneration {
        throw IntelligenceError.providerUnavailable(providerID: NodusIntelligenceProvider.providerID)
    }
    func unload() {}
}

#if DEBUG
/// Deterministic UI seam only. Real-model acceptance uses `MLXNodusRuntime`.
actor NodusUITestRuntime: NodusRuntime {
    private var state: NodusLoadState = .unloaded

    func availability() -> IntelligenceAvailability { .available }
    func loadState() -> NodusLoadState { state }
    func load() { state = .loaded }

    func generate(prompt: String, capability: IntelligenceCapability) async throws -> NodusRuntimeGeneration {
        state = .generating
        defer { state = .loaded }
        if prompt == "CANCEL_TEST" {
            try await Task.sleep(for: .seconds(5))
        }
        try Task.checkCancellation()
        let text = prompt.localizedCaseInsensitiveContains("weather")
            ? "I don't have enough reliable current information. Verify when online."
            : "Bucharest is the capital of Romania."
        return NodusRuntimeGeneration(
            text: text, modelVersion: "Nodus UI fixture", completed: true,
            tokensPerSecond: 100, modelConsistency: 1
        )
    }

    func unload() { state = .unloaded }
}
#endif
