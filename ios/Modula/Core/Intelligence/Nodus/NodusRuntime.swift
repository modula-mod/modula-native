import Foundation

enum NodusTaskMode: String, Sendable, Equatable, Codable, CaseIterable {
    case generalAnswer = "GENERAL_ANSWER"
    case modulaAnswer = "MODULA_ANSWER"
    case summarize = "SUMMARIZE"
    case rewrite = "REWRITE"
    case classify = "CLASSIFY"
    case extract = "EXTRACT"
    case classifyFreshness = "CLASSIFY_FRESHNESS"
    case shouldAbstain = "SHOULD_ABSTAIN"
    case verifyRecommendation = "VERIFY_RECOMMENDATION"
    case classifyIntent = "CLASSIFY_INTENT"
    case structuredAction = "STRUCTURED_ACTION"

    static func defaultMode(for capability: IntelligenceCapability) -> Self {
        switch capability {
        case .generate: .generalAnswer
        case .rewrite: .rewrite
        case .summarize: .summarize
        case .classify: .classify
        case .extract: .extract
        case .intent: .classifyIntent
        case .toolCall: .structuredAction
        }
    }
}

enum NodusPromptContract {
    static let system = "You are Nodus, Modula's concise general-purpose offline assistant. Never claim live information without current evidence. Actions are proposals only."

    static func prompt(mode: NodusTaskMode, input: String) -> String {
        """
        TASK: \(mode.rawValue)

        INPUT:
        \(input.trimmingCharacters(in: .whitespacesAndNewlines))

        OUTPUT CONTRACT:
        \(outputContract(for: mode))
        """
    }

    static func normalize(_ generated: String) -> String {
        var value = generated
        if let expression = try? NSRegularExpression(pattern: "<think>.*?</think>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            value = expression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: ""
            )
        }
        return value
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func outputContract(for mode: NodusTaskMode) -> String {
        switch mode {
        case .generalAnswer: "Answer directly in concise prose."
        case .modulaAnswer: "Answer from accepted Modula architecture. Do not invent capabilities."
        case .summarize: "Return only an accurate concise summary."
        case .rewrite: "Return only the rewritten text while preserving meaning."
        case .classify: "Return only the requested classification label."
        case .extract: "Return only the requested facts."
        case .classifyFreshness: "Return exactly one label: stable | possibly_stale | current_data_required | unknown."
        case .shouldAbstain: "Return exactly one label: answer | answer_with_uncertainty | abstain."
        case .verifyRecommendation: "Return exactly one label: not_needed | recommended | required."
        case .classifyIntent: "Return only the supported intent label or unsupported."
        case .structuredAction: "Return one JSON object using the supported Modula intent schema. Return {\"type\":\"unsupported\"} for an unsupported capability. Do not add prose."
        }
    }
}

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
    func modelIdentity() async -> NodusModelIdentity?
}

extension NodusRuntime {
    func modelIdentity() async -> NodusModelIdentity? { nil }
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
        if prompt.contains("CANCEL_TEST") {
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
