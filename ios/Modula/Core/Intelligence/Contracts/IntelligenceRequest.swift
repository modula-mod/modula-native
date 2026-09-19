import Foundation

/// Attribution for who originated an intelligence request. Structural only — no personal content.
enum IntelligenceRequestSource: String, Sendable, Equatable, Hashable, Codable {
    case system
    case nativeFeature = "native-feature"
    case hostedModule = "hosted-module"
    case developerDiagnostics = "developer-diagnostics"
    case test
}

/// Stable native request contract shared by all providers.
struct IntelligenceRequest: Sendable, Equatable, Identifiable {
    let id: UUID
    let capability: IntelligenceCapability
    let input: IntelligenceValue
    let privacy: IntelligencePrivacy
    let allowedToolIDs: Set<String>
    let source: IntelligenceRequestSource

    init(
        id: UUID = UUID(),
        capability: IntelligenceCapability,
        input: IntelligenceValue,
        privacy: IntelligencePrivacy,
        allowedToolIDs: Set<String> = [],
        source: IntelligenceRequestSource = .system
    ) {
        self.id = id
        self.capability = capability
        self.input = input
        self.privacy = privacy
        self.allowedToolIDs = allowedToolIDs
        self.source = source
    }
}
