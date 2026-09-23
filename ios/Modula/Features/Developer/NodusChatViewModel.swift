import Foundation
import Observation

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
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var verificationStatus: String?
    private var generationTask: Task<Void, Never>?

    var canSend: Bool {
        availability == .available && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    func refresh(using intelligence: ModulaIntelligence) async {
        let snapshot = await intelligence.diagnosticsSnapshot()
        availability = snapshot.nodusProviderAvailability ?? .modelNotInstalled
        loadState = snapshot.nodusLoadState ?? .unloaded
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
}
#endif
