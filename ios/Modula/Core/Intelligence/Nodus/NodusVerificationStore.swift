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
    private var state: NodusPersistentState

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.state = (try? Self.load(from: self.fileURL)) ?? NodusPersistentState()
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

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
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
}
