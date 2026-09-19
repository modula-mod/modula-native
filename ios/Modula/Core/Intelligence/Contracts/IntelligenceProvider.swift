import Foundation

/// Execution-scoped infrastructure — not personal content.
///
/// Cancellation uses Swift structured concurrency (`Task.checkCancellation()`).
struct IntelligenceExecutionContext: Sendable {
    let source: IntelligenceRequestSource
    let authorizedToolIDs: Set<String>
    let grantedPermissions: Set<String>
    let remoteIntelligencePermitted: Bool
    let diagnostics: IntelligenceDiagnosticsSink?

    init(
        source: IntelligenceRequestSource,
        authorizedToolIDs: Set<String> = [],
        grantedPermissions: Set<String> = [],
        remoteIntelligencePermitted: Bool = false,
        diagnostics: IntelligenceDiagnosticsSink? = nil
    ) {
        self.source = source
        self.authorizedToolIDs = authorizedToolIDs
        self.grantedPermissions = grantedPermissions
        self.remoteIntelligencePermitted = remoteIntelligencePermitted
        self.diagnostics = diagnostics
    }
}

/// Adapter contract for local and remote intelligence backends.
///
/// Mission 03 will add `AppleSystemIntelligenceProvider` without changing this protocol surface.
protocol IntelligenceProvider: Sendable {
    var id: String { get }
    var executionKind: IntelligenceExecutionKind { get }
    var capabilities: Set<IntelligenceCapability> { get }

    func availability() async -> IntelligenceAvailability

    func execute(
        _ request: IntelligenceRequest,
        context: IntelligenceExecutionContext
    ) async throws -> IntelligenceResponse
}
