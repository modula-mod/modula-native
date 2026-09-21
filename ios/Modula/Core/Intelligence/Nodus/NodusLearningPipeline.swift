import CryptoKit
import Foundation

actor NodusLearningPipeline {
    private let store: NodusVerificationStore
    private let trustStore: NodusVerificationTrustStore

    init(store: NodusVerificationStore, trustStore: NodusVerificationTrustStore) {
        self.store = store
        self.trustStore = trustStore
    }

    @discardableResult
    func ingest(
        _ result: NodusVerificationResult,
        privacyClass: NodusPrivacyClass = .personal,
        globalTrainingConsent: Bool = false,
        now: Date = Date()
    ) async throws -> (NodusReconciliation, NodusLearningCandidate?) {
        guard let mission = await store.mission(id: result.verificationID) else {
            throw NodusVerificationValidationError.missionMismatch
        }
        try trustStore.validate(result, mission: mission)
        let classification = Self.reconcile(mission: mission, result: result)
        let reconciliation = NodusReconciliation(
            id: UUID(), verificationID: result.verificationID, result: classification, reconciledAt: now
        )
        let eligibleForReview = globalTrainingConsent
            && (privacyClass == .publicData || privacyClass == .internalNonSecret)
        let candidate: NodusLearningCandidate? = if [.corrected, .partiallyCorrect, .stale].contains(classification) {
            NodusLearningCandidate(
                id: UUID(), question: mission.question, originalAnswer: mission.nodusAnswer,
                verifiedAnswer: result.verifiedAnswer, originalConfidence: mission.confidence.answer,
                result: classification, sourceVerificationID: result.verificationID,
                trainingEligibility: eligibleForReview ? .pendingReview : .ineligible, privacyClass: privacyClass,
                globalTrainingConsent: globalTrainingConsent, createdAt: now
            )
        } else { nil }
        try await store.record(result: result, reconciliation: reconciliation, candidate: candidate)
        return (reconciliation, candidate)
    }

    func review(candidateID: UUID, approve: Bool) async throws -> NodusLearningCandidate? {
        let snapshot = await store.snapshot()
        guard var candidate = snapshot.learningCandidates.first(where: { $0.id == candidateID }) else { return nil }
        if approve {
            guard candidate.globalTrainingConsent,
                  candidate.privacyClass == .publicData || candidate.privacyClass == .internalNonSecret else {
                candidate.trainingEligibility = .ineligible
                try await store.update(candidate: candidate)
                return candidate
            }
            candidate.trainingEligibility = .approved
        } else {
            candidate.trainingEligibility = .rejected
        }
        try await store.update(candidate: candidate)
        return candidate
    }

    func buildDatasetRevision(id: String, parent: String? = nil, now: Date = Date()) async throws -> NodusTrainingDatasetRevision {
        let approved = await store.snapshot().learningCandidates
            .filter { $0.trainingEligibility == .approved }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let identifiers = approved.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var candidateHashes: [String: String] = [:]
        for candidate in approved {
            let digest = SHA256.hash(data: try encoder.encode(candidate))
            candidateHashes[candidate.id.uuidString] = digest.map { String(format: "%02x", $0) }.joined()
        }
        let sourceVerificationIDs = approved.map(\.sourceVerificationID)
            .sorted { $0.uuidString < $1.uuidString }
        let revisionMaterial = candidateHashes.keys.sorted()
            .map { "\($0):\(candidateHashes[$0]!)" }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(revisionMaterial.utf8))
        let revision = NodusTrainingDatasetRevision(
            id: id, parentRevision: parent, approvedCandidateIDs: identifiers,
            approvedCandidateHashes: candidateHashes, sourceVerificationIDs: sourceVerificationIDs,
            contentHash: digest.map { String(format: "%02x", $0) }.joined(),
            approvalState: "approved-for-experiment", createdAt: now
        )
        try await store.add(revision: revision)
        return revision
    }

    private static func reconcile(mission: VerificationMissionDraft, result: NodusVerificationResult) -> NodusReconciliationResult {
        switch result.result {
        case .unverifiable: return .unverifiable
        case .conflictingEvidence: return .conflictingEvidence
        case .confirmed: return .confirmed
        case .corrected:
            return mission.freshness == .currentDataRequired ? .stale : .corrected
        case .partiallyCorrect: return .partiallyCorrect
        }
    }
}
