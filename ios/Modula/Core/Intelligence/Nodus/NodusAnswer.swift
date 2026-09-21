import Foundation

enum NodusConfidenceBand: String, Sendable, Equatable, Codable, CaseIterable {
    case high
    case medium
    case low
    case needsVerification = "needs-verification"

    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .needsVerification: "Needs verification"
        }
    }
}

struct NodusConfidence: Sendable, Equatable, Codable {
    let answer: Double
    let evidence: Double
    let freshness: Double
    let band: NodusConfidenceBand

    init(answer: Double, evidence: Double, freshness: Double, band: NodusConfidenceBand) {
        self.answer = Self.clamp(answer)
        self.evidence = Self.clamp(evidence)
        self.freshness = Self.clamp(freshness)
        self.band = band
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

enum NodusFreshness: String, Sendable, Equatable, Codable, CaseIterable {
    case stable
    case possiblyStale = "possibly_stale"
    case currentDataRequired = "current_data_required"
    case unknown

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .possiblyStale: "Possibly stale"
        case .currentDataRequired: "Current data needed"
        case .unknown: "Unknown"
        }
    }
}

enum NodusEvidenceState: String, Sendable, Equatable, Codable {
    case modelKnowledge = "model_knowledge"
    case localEvidence = "local_evidence"
    case noReliableEvidence = "no_reliable_evidence"
    case conflictingEvidence = "conflicting_evidence"
}

struct NodusAnswer: Sendable, Equatable, Codable {
    let answer: String
    let confidence: NodusConfidence
    let freshness: NodusFreshness
    let evidenceState: NodusEvidenceState
    let verificationRecommended: Bool
    let abstained: Bool
    let reasons: [String]
    let modelVersion: String
    let latencySeconds: Double?
    let tokensPerSecond: Double?

    var intelligenceValue: IntelligenceValue {
        .object([
            "answer": .string(answer),
            "confidence": .object([
                "answer": .double(confidence.answer),
                "evidence": .double(confidence.evidence),
                "freshness": .double(confidence.freshness),
                "band": .string(confidence.band.rawValue),
            ]),
            "freshness": .string(freshness.rawValue),
            "evidenceState": .string(evidenceState.rawValue),
            "verificationRecommended": .bool(verificationRecommended),
            "abstained": .bool(abstained),
            "reasons": .array(reasons.map(IntelligenceValue.string)),
            "modelVersion": .string(modelVersion),
            "latencySeconds": latencySeconds.map(IntelligenceValue.double) ?? .null,
            "tokensPerSecond": tokensPerSecond.map(IntelligenceValue.double) ?? .null,
        ])
    }
}
