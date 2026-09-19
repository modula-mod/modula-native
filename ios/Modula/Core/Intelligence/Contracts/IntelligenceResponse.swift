import Foundation

/// Successful intelligence result with mandatory provider provenance.
///
/// Does not expose chain-of-thought. Callers can always determine which provider
/// executed, whether it was local or remote, which capability ran, and which request matched.
struct IntelligenceResponse: Sendable, Equatable {
    let requestID: UUID
    let capability: IntelligenceCapability
    let output: IntelligenceValue
    let providerID: String
    let executionKind: IntelligenceExecutionKind
    let duration: Duration?

    init(
        requestID: UUID,
        capability: IntelligenceCapability,
        output: IntelligenceValue,
        providerID: String,
        executionKind: IntelligenceExecutionKind,
        duration: Duration? = nil
    ) {
        self.requestID = requestID
        self.capability = capability
        self.output = output
        self.providerID = providerID
        self.executionKind = executionKind
        self.duration = duration
    }
}
