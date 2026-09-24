import Foundation
import Observation

enum NodusDeveloperRating: String, Sendable, Equatable, Codable, CaseIterable {
    case good
    case wrong
    case unsure
    case outdated
    case hallucinated

    var displayName: String { rawValue.capitalized }
}

struct NodusDeveloperEvaluation: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let modelID: String
    let modelStage: NodusModelStage
    let prompt: String
    let response: String
    let rating: NodusDeveloperRating
    let confidence: NodusConfidenceBand
    let freshness: NodusFreshness
    let note: String?
    let createdAt: Date
}

actor NodusDeveloperEvaluationStore {
    nonisolated let exportURL: URL
    private let fileURL: URL
    private var records: [NodusDeveloperEvaluation]

    init(fileURL: URL? = nil, exportURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = support.appending(path: "Modula/Nodus")
        let resolvedFile = fileURL ?? root.appending(path: "developer-evaluations.json")
        let resolvedExport = exportURL ?? root.appending(path: "developer-evaluations.jsonl")
        self.fileURL = resolvedFile
        self.exportURL = resolvedExport
        self.records = (try? Data(contentsOf: resolvedFile))
            .flatMap { try? JSONDecoder.modulaNodus.decode([NodusDeveloperEvaluation].self, from: $0) } ?? []
        try? FileManager.default.createDirectory(
            at: resolvedFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Self.writeExport(records, to: resolvedExport)
    }

    func upsert(_ evaluation: NodusDeveloperEvaluation) throws {
        records.removeAll { $0.id == evaluation.id }
        records.append(evaluation)
        let encoder = JSONEncoder.modulaNodus
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
        try Self.writeExport(records, to: exportURL)
    }

    func snapshot() -> [NodusDeveloperEvaluation] { records }

    private static func writeExport(_ records: [NodusDeveloperEvaluation], to url: URL) throws {
        let encoder = JSONEncoder.modulaNodus
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var modulaNodus: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var modulaNodus: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#if DEBUG
struct NodusChatMessage: Identifiable, Sendable, Equatable {
    enum Role: Sendable { case user, nodus }

    let id: UUID
    let role: Role
    let text: String
    let answer: NodusAnswer?
    let requestID: UUID?

    init(id: UUID = UUID(), role: Role, text: String, answer: NodusAnswer? = nil, requestID: UUID? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.answer = answer
        self.requestID = requestID
    }
}

@MainActor @Observable
final class NodusChatViewModel {
    var input = ""
    private(set) var messages: [NodusChatMessage] = []
    private(set) var availability: IntelligenceAvailability = .modelNotInstalled
    private(set) var loadState: NodusLoadState = .unloaded
    private(set) var modelIdentity: NodusModelIdentity?
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var verificationStatus: String?
    private(set) var evaluationStatus: String?
    private(set) var ratings: [UUID: NodusDeveloperRating] = [:]
    private var generationTask: Task<Void, Never>?

    var canSend: Bool {
        availability == .available && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    func refresh(using intelligence: ModulaIntelligence) async {
        let snapshot = await intelligence.diagnosticsSnapshot()
        availability = snapshot.nodusProviderAvailability ?? .modelNotInstalled
        loadState = snapshot.nodusLoadState ?? .unloaded
        modelIdentity = snapshot.nodusModelIdentity
    }

    func send(using intelligence: ModulaIntelligence) {
        guard canSend else { return }
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedHistory = messages.suffix(8)
        let context = boundedHistory.map { message in
            "\(message.role == .user ? "User" : "Nodus"): \(message.text)"
        }.joined(separator: "\n")
        let conversationInput = context.isEmpty
            ? question
            : "RECENT CONVERSATION:\n\(context)\n\nCURRENT USER MESSAGE:\n\(question)"
        input = ""
        errorMessage = nil
        verificationStatus = nil
        messages.append(NodusChatMessage(role: .user, text: question))
        isGenerating = true
        if loadState == .unloaded { loadState = .loading }

        generationTask = Task { [weak self] in
            guard let self else { return }
            let request = IntelligenceRequest(
                capability: .generate,
                input: .object([
                    "text": .string(conversationInput),
                    "taskMode": .string(NodusTaskMode.generalAnswer.rawValue),
                ]),
                privacy: .localOnly,
                source: .developerDiagnostics
            )
            do {
                let response = try await intelligence.executeDiagnostic(
                    request,
                    usingProviderID: NodusIntelligenceProvider.providerID
                )
                guard let answer = NodusAnswer.parse(response.output) else {
                    throw IntelligenceError.providerFailure(
                        providerID: NodusIntelligenceProvider.providerID,
                        detail: "INVALID_NODUS_ENVELOPE"
                    )
                }
                messages.append(NodusChatMessage(
                    role: .nodus,
                    text: answer.answer,
                    answer: answer,
                    requestID: response.requestID
                ))
            } catch let error as IntelligenceError {
                if error != .requestCancelled { errorMessage = error.code }
            } catch is CancellationError {
                // Cancellation is an expected developer action.
            } catch {
                errorMessage = "Nodus generation failed"
            }
            isGenerating = false
            generationTask = nil
            await refresh(using: intelligence)
        }
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    func clear() {
        cancel()
        messages.removeAll()
        errorMessage = nil
        verificationStatus = nil
        evaluationStatus = nil
    }

    func queueVerification(for message: NodusChatMessage, store: NodusVerificationStore) async {
        guard let answer = message.answer else { return }
        let responseIndex = messages.firstIndex(where: { $0.id == message.id }) ?? messages.endIndex
        let question = messages[..<responseIndex].last(where: { $0.role == .user })?.text
            ?? "Nodus Chat response"
        let reason: NodusVerificationReason = answer.freshness == .currentDataRequired
            ? .freshnessRequired : .lowConfidence
        do {
            _ = try await store.createMission(
                question: question,
                answer: answer,
                reason: reason,
                connectivityAvailable: false
            )
            verificationStatus = "Verification queued locally"
        } catch {
            verificationStatus = "Could not queue verification"
        }
    }

    func rate(
        _ rating: NodusDeveloperRating,
        message: NodusChatMessage,
        store: NodusDeveloperEvaluationStore,
        note: String? = nil
    ) async {
        guard let answer = message.answer else { return }
        let responseIndex = messages.firstIndex(where: { $0.id == message.id }) ?? messages.endIndex
        let prompt = messages[..<responseIndex].last(where: { $0.role == .user })?.text ?? ""
        let identity = modelIdentity ?? NodusModelIdentity(
            id: "nodus-unknown",
            displayName: answer.modelVersion,
            stage: .experimentalCandidate,
            shippingAllowed: false,
            baseModel: "Qwen/Qwen3-1.7B",
            baseRevision: "unknown",
            quantization: "unknown",
            runtimeFormat: "mlx"
        )
        do {
            try await store.upsert(NodusDeveloperEvaluation(
                id: message.id,
                modelID: identity.id,
                modelStage: identity.stage,
                prompt: prompt,
                response: message.text,
                rating: rating,
                confidence: answer.confidence.band,
                freshness: answer.freshness,
                note: note,
                createdAt: Date()
            ))
            ratings[message.id] = rating
            evaluationStatus = "Saved locally"
        } catch {
            evaluationStatus = "Could not save evaluation"
        }
    }
}
#endif
