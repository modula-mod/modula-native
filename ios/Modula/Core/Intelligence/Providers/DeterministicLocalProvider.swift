import Foundation

/// Fixture local provider that proves the native architecture without an LLM.
///
/// - ID: `modula.test.local`
/// - Network: none
/// - Model weights: none
/// - Output: deterministic fixture shapes
///
/// Never present this as a real model. Mission 03 replaces/adds a real Apple provider.
struct DeterministicLocalProvider: IntelligenceProvider {
    static let providerID = "modula.test.local"

    let id: String = Self.providerID
    let executionKind: IntelligenceExecutionKind = .local
    let capabilities: Set<IntelligenceCapability> = Set(IntelligenceCapability.allCases)

    private let availabilityState: IntelligenceAvailability

    init(availability: IntelligenceAvailability = .available) {
        self.availabilityState = availability
    }

    func availability() async -> IntelligenceAvailability {
        availabilityState
    }

    func execute(
        _ request: IntelligenceRequest,
        context: IntelligenceExecutionContext
    ) async throws -> IntelligenceResponse {
        try Task.checkCancellation()
        guard capabilities.contains(request.capability) else {
            throw IntelligenceError.capabilityUnsupported
        }

        let started = ContinuousClock.now
        let output = Self.fixtureOutput(for: request.capability)
        try Task.checkCancellation()
        let duration = ContinuousClock.now - started

        return IntelligenceResponse(
            requestID: request.id,
            capability: request.capability,
            output: output,
            providerID: id,
            executionKind: .local,
            duration: duration
        )
    }

    static func fixtureOutput(for capability: IntelligenceCapability) -> IntelligenceValue {
        switch capability {
        case .summarize:
            .object([
                "summary": .string("Deterministic local summary"),
                "source": .string(providerID),
            ])
        case .rewrite:
            .object([
                "text": .string("Deterministic local rewrite"),
                "source": .string(providerID),
            ])
        case .generate:
            .object([
                "text": .string("Deterministic local generation"),
                "source": .string(providerID),
            ])
        case .classify:
            .object([
                "label": .string("test"),
                "confidence": .double(1),
                "source": .string(providerID),
            ])
        case .extract:
            .object([
                "items": .array([]),
                "source": .string(providerID),
            ])
        case .intent:
            .object([
                "intent": .string("test"),
                "source": .string(providerID),
            ])
        case .toolCall:
            .object([
                "toolCalls": .array([]),
                "note": .string("Deterministic test provider does not invent tools"),
                "source": .string(providerID),
            ])
        }
    }
}
