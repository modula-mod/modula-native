import Foundation

enum NodusVerificationReason: String, Sendable, Equatable, Codable {
    case lowConfidence = "low_confidence"
    case freshnessRequired = "freshness_required"
    case userRequested = "user_requested"
    case conflictingInformation = "conflicting_information"
}

enum NodusVerificationState: String, Sendable, Equatable, Codable {
    case queuedOffline = "queued_offline"
    case readyToSync = "ready_to_sync"
    case submitted
    case verified
    case failed
}

struct VerificationMissionDraft: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let question: String
    let nodusAnswer: String
    let nodusModelVersion: String
    let confidence: NodusConfidence
    let freshness: NodusFreshness
    let reason: NodusVerificationReason
    var state: NodusVerificationState
    let createdAt: Date
}

enum NodusVerificationOutcome: String, Sendable, Equatable, Codable {
    case confirmed
    case corrected
    case partiallyCorrect = "partially_correct"
    case unverifiable
    case conflictingEvidence = "conflicting_evidence"
}

struct NodusVerificationSource: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let publisher: String
    let retrievedAt: Date
}

struct NodusVerificationProvenance: Sendable, Equatable, Codable {
    let missionID: String
    let akiDecisionID: String?
}

struct NodusVerificationResult: Sendable, Equatable, Codable {
    let schemaVersion: Int
    let verificationID: UUID
    let question: String
    let verifiedAnswer: String
    let result: NodusVerificationOutcome
    let sources: [NodusVerificationSource]
    let verifiedAt: Date
    let confidence: Double
    let provenance: NodusVerificationProvenance
    let signerID: String
    let signature: Data

    struct SignedPayload: Sendable, Equatable, Codable {
        let schemaVersion: Int
        let verificationID: UUID
        let question: String
        let verifiedAnswer: String
        let result: NodusVerificationOutcome
        let sources: [NodusVerificationSource]
        let verifiedAt: Date
        let confidence: Double
        let provenance: NodusVerificationProvenance
        let signerID: String
    }

    var signedPayload: SignedPayload {
        SignedPayload(
            schemaVersion: schemaVersion, verificationID: verificationID, question: question,
            verifiedAnswer: verifiedAnswer, result: result, sources: sources, verifiedAt: verifiedAt,
            confidence: confidence, provenance: provenance, signerID: signerID
        )
    }
}
