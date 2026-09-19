import Foundation

/// Native intelligence capabilities aligned with Greenfield `@modula/intelligence-core`.
///
/// Do not add vision, speech, image generation, embeddings, RAG, agents, or training here
/// until a dedicated mission expands the contract.
enum IntelligenceCapability: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case generate
    case rewrite
    case summarize
    case classify
    case extract
    case intent
    case toolCall = "tool-call"
}
