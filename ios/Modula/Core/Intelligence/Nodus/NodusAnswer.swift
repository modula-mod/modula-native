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
    var taskMode: NodusTaskMode? = nil

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
            "taskMode": taskMode.map { .string($0.rawValue) } ?? .null,
        ])
    }

    static func parse(_ value: IntelligenceValue) -> NodusAnswer? {
        guard let object = value.objectValue,
              let text = object["answer"]?.stringValue,
              let confidenceObject = object["confidence"]?.objectValue,
              let answerConfidence = confidenceObject["answer"]?.doubleValue,
              let evidenceConfidence = confidenceObject["evidence"]?.doubleValue,
              let freshnessConfidence = confidenceObject["freshness"]?.doubleValue,
              let bandRaw = confidenceObject["band"]?.stringValue,
              let band = NodusConfidenceBand(rawValue: bandRaw),
              let freshnessRaw = object["freshness"]?.stringValue,
              let freshness = NodusFreshness(rawValue: freshnessRaw),
              let evidenceRaw = object["evidenceState"]?.stringValue,
              let evidence = NodusEvidenceState(rawValue: evidenceRaw),
              let verification = object["verificationRecommended"]?.boolValue,
              let abstained = object["abstained"]?.boolValue,
              let modelVersion = object["modelVersion"]?.stringValue else { return nil }
        return NodusAnswer(
            answer: text,
            confidence: NodusConfidence(
                answer: answerConfidence,
                evidence: evidenceConfidence,
                freshness: freshnessConfidence,
                band: band
            ),
            freshness: freshness,
            evidenceState: evidence,
            verificationRecommended: verification,
            abstained: abstained,
            reasons: object["reasons"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            modelVersion: modelVersion,
            latencySeconds: object["latencySeconds"]?.doubleValue,
            tokensPerSecond: object["tokensPerSecond"]?.doubleValue,
            taskMode: object["taskMode"]?.stringValue.flatMap(NodusTaskMode.init(rawValue:))
        )
    }
}
