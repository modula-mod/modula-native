import Foundation

struct NodusPersistentState: Sendable, Equatable, Codable {
    var missions: [VerificationMissionDraft] = []
    var results: [NodusVerificationResult] = []
    var reconciliations: [NodusReconciliation] = []
    var learningCandidates: [NodusLearningCandidate] = []
    var datasetRevisions: [NodusTrainingDatasetRevision] = []
}

actor NodusVerificationStore {
    private let fileURL: URL
    nonisolated let approvedExportURL: URL
    private var state: NodusPersistentState

    init(fileURL: URL? = nil, approvedExportURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.approvedExportURL = approvedExportURL
            ?? Self.defaultFileURL.deletingLastPathComponent().appending(path: "approved-learning-candidates.jsonl")
        self.state = (try? Self.load(from: self.fileURL)) ?? NodusPersistentState()
        try? Self.writeApprovedExport(state.learningCandidates, to: self.approvedExportURL)
    }

    @discardableResult
    func createMission(
        question: String,
        answer: NodusAnswer,
        reason: NodusVerificationReason,
        connectivityAvailable: Bool,
        now: Date = Date()
    ) throws -> VerificationMissionDraft {
        let mission = VerificationMissionDraft(
            id: UUID(), question: question, nodusAnswer: answer.answer,
            nodusModelVersion: answer.modelVersion, confidence: answer.confidence,
            freshness: answer.freshness, reason: reason,
            state: connectivityAvailable ? .readyToSync : .queuedOffline, createdAt: now
        )
        state.missions.append(mission)
        try persist()
        return mission
    }

    func setConnectivityAvailable(_ available: Bool) throws {
        guard available else { return }
        for index in state.missions.indices where state.missions[index].state == .queuedOffline {
            state.missions[index].state = .readyToSync
        }
        try persist()
    }

    func snapshot() -> NodusPersistentState { state }

    func mission(id: UUID) -> VerificationMissionDraft? { state.missions.first { $0.id == id } }

    func record(
        result: NodusVerificationResult,
        reconciliation: NodusReconciliation,
        candidate: NodusLearningCandidate?
    ) throws {
        guard let index = state.missions.firstIndex(where: { $0.id == result.verificationID }) else {
            throw NodusVerificationValidationError.missionMismatch
        }
        state.missions[index].state = .verified
        state.results.append(result)
        state.reconciliations.append(reconciliation)
        if let candidate { state.learningCandidates.append(candidate) }
        try persist()
    }

    func update(candidate: NodusLearningCandidate) throws {
        guard let index = state.learningCandidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        state.learningCandidates[index] = candidate
        try persist()
    }

    func add(revision: NodusTrainingDatasetRevision) throws {
        state.datasetRevisions.append(revision)
        try persist()
    }

    @discardableResult
    func createCorrectionCandidate(
        prompt: String,
        answer: NodusAnswer,
        rating: NodusDeveloperRating,
        correction: String,
        reasoningMode: NodusReasoningMode,
        searchEnabled: Bool,
        knowledgeSources: [String],
        memoryItemIDs: [UUID],
        searchSources: [URL],
        privacyClass: NodusPrivacyClass = .personal,
        globalTrainingConsent: Bool = false,
        now: Date = Date()
    ) throws -> NodusLearningCandidate {
        let cleanCorrection = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCorrection.isEmpty else {
            throw IntelligenceError.invalidRequest(detail: "A correction is required")
        }
        let verificationID = UUID()
        state.missions.append(VerificationMissionDraft(
            id: verificationID, question: prompt, nodusAnswer: answer.answer,
            nodusModelVersion: answer.modelVersion, confidence: answer.confidence,
            freshness: answer.freshness, reason: .userRequested,
            state: .verified, createdAt: now
        ))
        let eligible = globalTrainingConsent
            && (privacyClass == .publicData || privacyClass == .internalNonSecret)
        let result: NodusReconciliationResult = rating == .outdated ? .stale : .corrected
        let candidate = NodusLearningCandidate(
            id: UUID(), question: prompt, originalAnswer: answer.answer,
            verifiedAnswer: cleanCorrection, originalConfidence: answer.confidence.answer,
            result: result, sourceVerificationID: verificationID,
            trainingEligibility: eligible ? .pendingReview : .ineligible,
            privacyClass: privacyClass, globalTrainingConsent: globalTrainingConsent,
            createdAt: now, rating: rating, modelVersion: answer.modelVersion,
            reasoningMode: reasoningMode, searchEnabled: searchEnabled,
            knowledgeSources: knowledgeSources, memoryItemIDs: memoryItemIDs,
            searchSources: searchSources, freshness: answer.freshness
        )
        state.learningCandidates.append(candidate)
        try persist()
        return candidate
    }

    @discardableResult
    func reviewCandidate(id: UUID, approve: Bool, now: Date = Date()) throws -> NodusLearningCandidate? {
        guard let index = state.learningCandidates.firstIndex(where: { $0.id == id }) else { return nil }
        if approve,
           state.learningCandidates[index].globalTrainingConsent,
           state.learningCandidates[index].privacyClass == .publicData
            || state.learningCandidates[index].privacyClass == .internalNonSecret {
            state.learningCandidates[index].trainingEligibility = .approved
        } else if approve {
            state.learningCandidates[index].trainingEligibility = .ineligible
        } else {
            state.learningCandidates[index].trainingEligibility = .rejected
        }
        state.learningCandidates[index].reviewedAt = now
        try persist()
        return state.learningCandidates[index]
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try Self.writeApprovedExport(state.learningCandidates, to: approvedExportURL)
    }

    private static func load(from url: URL) throws -> NodusPersistentState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NodusPersistentState.self, from: Data(contentsOf: url))
    }

    private static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "Modula/Nodus/verification-state.json")
    }

    private static func writeApprovedExport(_ candidates: [NodusLearningCandidate], to url: URL) throws {
        let approved = candidates.filter { $0.trainingEligibility == .approved }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for candidate in approved {
            data.append(try encoder.encode(candidate))
            data.append(Data("\n".utf8))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
