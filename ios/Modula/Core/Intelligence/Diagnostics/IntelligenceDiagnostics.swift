import Foundation
import OSLog

/// Structural diagnostic event — never includes prompt/input/output/tool argument content.
struct IntelligenceDiagnosticEvent: Sendable, Equatable {
    enum Status: String, Sendable, Equatable {
        case routed
        case success
        case failure
        case cancelled
    }

    let requestID: UUID
    let capability: IntelligenceCapability
    let providerID: String?
    let executionKind: IntelligenceExecutionKind?
    let duration: Duration?
    let status: Status
    let errorCode: String?
}

protocol IntelligenceDiagnosticsSink: Sendable {
    func record(_ event: IntelligenceDiagnosticEvent)
}

/// In-memory diagnostics for developer surfaces and tests.
actor IntelligenceDiagnostics: IntelligenceDiagnosticsSink {
    private(set) var lastEvent: IntelligenceDiagnosticEvent?
    private var events: [IntelligenceDiagnosticEvent] = []

    nonisolated func record(_ event: IntelligenceDiagnosticEvent) {
        Task { await self.append(event) }
        Self.log(event)
    }

    func append(_ event: IntelligenceDiagnosticEvent) {
        lastEvent = event
        events.append(event)
        if events.count > 50 {
            events.removeFirst(events.count - 50)
        }
    }

    func snapshot() -> IntelligenceDiagnosticEvent? { lastEvent }

    func recentEvents() -> [IntelligenceDiagnosticEvent] { events }

    func reset() {
        lastEvent = nil
        events.removeAll()
    }

    private static func log(_ event: IntelligenceDiagnosticEvent) {
        ModulaLog.intelligence.info(
            """
            intelligence status=\(event.status.rawValue, privacy: .public) \
            request=\(event.requestID.uuidString, privacy: .public) \
            capability=\(event.capability.rawValue, privacy: .public) \
            provider=\(event.providerID ?? "-", privacy: .public) \
            execution=\(event.executionKind?.rawValue ?? "-", privacy: .public) \
            error=\(event.errorCode ?? "-", privacy: .public)
            """
        )
    }
}

/// Box so `IntelligenceExecutionContext` can hold an actor sink as `Sendable`.
struct IntelligenceDiagnosticsBox: IntelligenceDiagnosticsSink {
    let diagnostics: IntelligenceDiagnostics

    func record(_ event: IntelligenceDiagnosticEvent) {
        diagnostics.record(event)
    }
}
