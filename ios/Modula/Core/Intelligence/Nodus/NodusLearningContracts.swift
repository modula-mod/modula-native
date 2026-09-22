import Foundation

enum NodusReconciliationResult: String, Sendable, Equatable, Codable {
    case confirmed
    case corrected
    case partiallyCorrect = "partially_correct"
    case stale
    case unverifiable
    case conflictingEvidence = "conflicting_evidence"
}

enum NodusTrainingEligibility: String, Sendable, Equatable, Codable {
    case ineligible
    case pendingReview = "pending_review"
    case approved
    case rejected
}

enum NodusPrivacyClass: String, Sendable, Equatable, Codable {
    case publicData = "public"
    case internalNonSecret = "internal_non_secret"
    case personal
    case privateData = "private"
}

struct NodusLearningCandidate: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let question: String
    let originalAnswer: String
    let verifiedAnswer: String
    let originalConfidence: Double
    let result: NodusReconciliationResult
    let sourceVerificationID: UUID
    var trainingEligibility: NodusTrainingEligibility
    let privacyClass: NodusPrivacyClass
    let globalTrainingConsent: Bool
    let createdAt: Date
}

struct NodusReconciliation: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let verificationID: UUID
    let result: NodusReconciliationResult
    let reconciledAt: Date
}

struct NodusTrainingDatasetRevision: Sendable, Equatable, Codable, Identifiable {
    let id: String
    let parentRevision: String?
    let approvedCandidateIDs: [UUID]
    let approvedCandidateHashes: [String: String]
    let sourceVerificationIDs: [UUID]
    let contentHash: String
    let approvalState: String
    let createdAt: Date
}
