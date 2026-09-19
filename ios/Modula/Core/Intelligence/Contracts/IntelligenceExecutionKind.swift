import Foundation

/// Provider provenance: declared by the provider itself, never inferred from its name.
enum IntelligenceExecutionKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case local
    case remote
}
