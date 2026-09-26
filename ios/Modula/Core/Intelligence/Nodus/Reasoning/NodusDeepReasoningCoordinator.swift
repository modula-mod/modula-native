import Foundation

enum NodusReasoningStage: String, Sendable, CaseIterable {
    case classifying
    case checkingMemory
    case searchingKnowledge
    case searchingWeb
    case drafting
    case reviewing
    case finalizing

    var displayName: String {
        switch self {
        case .classifying: "Understanding request…"
        case .checkingMemory: "Checking memory…"
        case .searchingKnowledge: "Searching knowledge…"
        case .searchingWeb: "Searching the web…"
        case .drafting: "Drafting answer…"
        case .reviewing: "Reviewing answer…"
        case .finalizing: "Finalizing answer…"
        }
    }
}

struct NodusGenerationBudget: Sendable, Equatable {
    let maximumOutputTokens: Int
    let reasoningMode: NodusReasoningMode

    static let standard = NodusGenerationBudget(maximumOutputTokens: 384, reasoningMode: .standard)
    static let deep = NodusGenerationBudget(maximumOutputTokens: 512, reasoningMode: .deep)
}

struct NodusDeepReasoningCoordinator: Sendable {
    func run(
        prompt: String,
        taskMode: NodusTaskMode,
        budget: NodusContextBudget,
        generate: @escaping @Sendable (String, Int) async throws -> (NodusAnswer, UUID),
        progress: @escaping @Sendable (NodusReasoningStage) async -> Void
    ) async throws -> (answer: NodusAnswer, requestID: UUID, passes: Int) {
        try Task.checkCancellation()
        await progress(.drafting)
        let draft = try await generate(prompt, budget.maximumOutputTokens)
        guard budget.maximumInferencePasses > 1 else { return (draft.0, draft.1, 1) }

        try Task.checkCancellation()
        await progress(.reviewing)
        let critiquePrompt = """
        Review the draft against the supplied evidence and authority contract. Identify unsupported, stale, contradictory, or uncited claims. Do not expose hidden reasoning; return only a concise revision brief.

        ORIGINAL CONTEXT:
        \(prompt)

        DRAFT:
        \(draft.0.answer)
        """
        let critique = try await generate(critiquePrompt, min(256, budget.maximumOutputTokens))

        try Task.checkCancellation()
        await progress(.finalizing)
        let finalPrompt = """
        Produce the final answer only. Correct the draft using the review and original evidence. Do not mention this review process or reveal private reasoning.

        ORIGINAL CONTEXT:
        \(prompt)

        DRAFT:
        \(draft.0.answer)

        REVISION BRIEF:
        \(critique.0.answer)
        """
        let final = try await generate(finalPrompt, budget.maximumOutputTokens)
        return (final.0, final.1, min(3, budget.maximumInferencePasses))
    }
}

