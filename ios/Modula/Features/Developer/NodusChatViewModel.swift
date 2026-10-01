import Foundation
import Observation
import SwiftUI
import UIKit

enum NodusDeveloperRating: String, Sendable, Equatable, Codable, CaseIterable {
    case good
    case wrong
    case unsure
    case outdated
    case hallucinated

    var displayName: String { rawValue.capitalized }
    var needsCorrection: Bool { self == .wrong || self == .outdated || self == .hallucinated }
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
        try? FileManager.default.createDirectory(at: resolvedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.writeExport(records, to: resolvedExport)
    }

    func upsert(_ evaluation: NodusDeveloperEvaluation) throws {
        records.removeAll { $0.id == evaluation.id }
        records.append(evaluation)
        let encoder = JSONEncoder.modulaNodus
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: [.atomic, .completeFileProtection])
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
        try data.write(to: url, options: [.atomic, .completeFileProtection])
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
typealias NodusChatMessage = NodusMessage

@MainActor @Observable
final class NodusChatViewModel {
    var input = ""
    private(set) var messages: [NodusMessage] = []
    private(set) var conversations: [NodusConversation] = []
    private(set) var activeConversation: NodusConversation?
    private(set) var availability: IntelligenceAvailability = .modelNotInstalled
    private(set) var loadState: NodusLoadState = .unloaded
    private(set) var modelIdentity: NodusModelIdentity?
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var verificationStatus: String?
    private(set) var evaluationStatus: String?
    private(set) var progressText: String?
    private(set) var progressStage: NodusReasoningStage?
    private(set) var ratings: [UUID: NodusDeveloperRating] = [:]
    private(set) var attachmentImages: [UUID: UIImage] = [:]
    private(set) var reactions: [UUID: [String]] = [:]
    private(set) var library = NodusLibrarySnapshot()
    private var generationTask: Task<Void, Never>?
    private var conversationStore: NodusConversationStore?
    private let attachmentFiles = PrivateFileStore(domain: .nodusConversations)
    private let reactionKey = "nodus.chat.reactions.v1"

    var thinkStep: NodusThinkStep {
        let stored = activeConversation.flatMap { library.placement(for: $0.id)?.thinkSteps } ?? 0
        return NodusThinkStep.resolve(stored: stored, mode: activeConversation?.reasoningMode ?? .standard)
    }

    var canSend: Bool {
        availability == .available
            && activeConversation != nil
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
    }

    func configure(using app: AppEnvironment) async {
        conversationStore = app.nodusConversationStore
        conversations = await app.nodusConversationStore.all()
        if let first = conversations.first {
            setActive(first)
        } else if let created = try? await app.nodusConversationStore.create() {
            setActive(created)
            conversations = await app.nodusConversationStore.all()
        }
        loadReactions()
        hydrateImages()
        await reloadLibrary()
        await refresh(using: app.intelligence)
    }

    func refresh(using intelligence: ModulaIntelligence) async {
        let snapshot = await intelligence.diagnosticsSnapshot()
        availability = snapshot.nodusProviderAvailability ?? .modelNotInstalled
        loadState = snapshot.nodusLoadState ?? .unloaded
        modelIdentity = snapshot.nodusModelIdentity
    }

    func newConversation(projectID: UUID? = nil, folderID: UUID? = nil) async {
        guard let conversationStore, let created = try? await conversationStore.create() else { return }
        if projectID != nil || folderID != nil {
            library = (try? await conversationStore.place(conversationID: created.id, projectID: projectID, folderID: folderID)) ?? library
        }
        conversations = await conversationStore.all()
        setActive(created)
    }

    func duplicate(_ conversation: NodusConversation) async {
        guard let conversationStore else { return }
        let copy = NodusConversation(
            title: "\(conversation.title) copy",
            modelID: conversation.modelID,
            modelStage: conversation.modelStage,
            reasoningMode: conversation.reasoningMode,
            searchEnabled: conversation.searchEnabled,
            attachedKnowledgeCollectionIDs: conversation.attachedKnowledgeCollectionIDs,
            memoryEnabled: conversation.memoryEnabled,
            messages: conversation.messages
        )
        try? await conversationStore.upsert(copy)
        if let placement = library.placement(for: conversation.id) {
            library = (try? await conversationStore.place(conversationID: copy.id, projectID: placement.projectID, folderID: placement.folderID)) ?? library
            if !placement.note.isEmpty {
                library = (try? await conversationStore.setChatNote(id: copy.id, note: placement.note)) ?? library
            }
        }
        conversations = await conversationStore.all()
        setActive(copy)
    }

    func placeActive(projectID: UUID?, folderID: UUID?) async {
        guard let id = activeConversation?.id else { return }
        await place(id, projectID: projectID, folderID: folderID)
    }

    func place(_ conversationID: UUID, projectID: UUID?, folderID: UUID?) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.place(conversationID: conversationID, projectID: projectID, folderID: folderID)) ?? library
    }

    func createProject(name: String, symbol: String, brief: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.createProject(name: name, symbol: symbol, brief: brief)) ?? library
    }

    func updateProject(_ project: NodusProject, name: String, symbol: String, brief: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.updateProject(id: project.id, name: name, symbol: symbol, brief: brief)) ?? library
    }

    func setProjectArchived(_ project: NodusProject, archived: Bool) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setProjectArchived(id: project.id, archived: archived)) ?? library
    }

    func deleteProject(_ project: NodusProject) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.deleteProject(id: project.id)) ?? library
    }

    func createFolder(name: String, projectID: UUID?) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.createFolder(name: name, projectID: projectID)) ?? library
    }

    func renameFolder(_ folder: NodusFolder, name: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.renameFolder(id: folder.id, name: name)) ?? library
    }

    func deleteFolder(_ folder: NodusFolder) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.deleteFolder(id: folder.id)) ?? library
    }

    func setArchived(_ conversation: NodusConversation, archived: Bool) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatArchived(id: conversation.id, archived: archived)) ?? library
    }

    func setFavorite(_ conversation: NodusConversation, favorite: Bool) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatFavorite(id: conversation.id, favorite: favorite)) ?? library
    }

    func setImportant(_ conversation: NodusConversation, important: Bool) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: conversation.id, important: important)) ?? library
    }

    func setColor(_ conversation: NodusConversation, color: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: conversation.id, color: color)) ?? library
    }

    func setInstructions(_ conversation: NodusConversation, instructions: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: conversation.id, instructions: instructions)) ?? library
    }

    func setPersona(_ text: String) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: id, persona: text)) ?? library
    }

    func toggleSkill(_ skill: NodusSkill) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        var enabled = NodusSkill.enabled(in: library.placement(for: id)?.skillIDs ?? "")
        if let index = enabled.firstIndex(of: skill) {
            enabled.remove(at: index)
        } else {
            enabled.append(skill)
        }
        library = (try? await conversationStore.setChatFlags(id: id, skillIDs: NodusSkill.stored(from: enabled))) ?? library
    }

    var activePersona: String {
        activeConversation.flatMap { library.placement(for: $0.id)?.persona } ?? ""
    }

    var activeSkills: [NodusSkill] {
        let stored = activeConversation.flatMap { library.placement(for: $0.id)?.skillIDs } ?? ""
        return NodusSkill.enabled(in: stored)
    }

    var messageDensity: String {
        let stored = activeConversation.flatMap { library.placement(for: $0.id)?.messageDensity } ?? ""
        return stored == "compact" ? "compact" : "comfortable"
    }

    var showMessageTimes: Bool {
        activeConversation.flatMap { library.placement(for: $0.id)?.showTimes } == true
    }

    var messageTextSize: String {
        let stored = activeConversation.flatMap { library.placement(for: $0.id)?.textSize } ?? ""
        return ["small", "regular", "large"].contains(stored) ? stored : "regular"
    }

    var messageFont: Font {
        switch messageTextSize {
        case "small": messageDensity == "compact" ? .caption : .subheadline
        case "large": messageDensity == "compact" ? .body : .title3
        default: messageDensity == "compact" ? .subheadline : .body
        }
    }

    func setMessageDensity(_ density: String) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: id, messageDensity: density)) ?? library
    }

    func setShowTimes(_ show: Bool) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: id, showTimes: show)) ?? library
    }

    func setMessageTextSize(_ size: String) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        library = (try? await conversationStore.setChatFlags(id: id, textSize: size)) ?? library
    }

    func savePrompt(title: String, body: String, projectID: UUID?, id: UUID? = nil) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.savePrompt(title: title, body: body, projectID: projectID, id: id)) ?? library
    }

    func deletePrompt(id: UUID) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.deletePrompt(id: id)) ?? library
    }

    func fork(_ conversation: NodusConversation, through messageID: UUID? = nil) async {
        guard let conversationStore else { return }
        let kept: [NodusMessage]
        if let messageID, let index = conversation.messages.firstIndex(where: { $0.id == messageID }) {
            kept = Array(conversation.messages[...index])
        } else {
            kept = conversation.messages
        }
        let copy = NodusConversation(
            title: "Fork of \(conversation.title)",
            modelID: conversation.modelID,
            modelStage: conversation.modelStage,
            reasoningMode: conversation.reasoningMode,
            searchEnabled: conversation.searchEnabled,
            attachedKnowledgeCollectionIDs: conversation.attachedKnowledgeCollectionIDs,
            memoryEnabled: conversation.memoryEnabled,
            messages: kept
        )
        try? await conversationStore.upsert(copy)
        let source = library.placement(for: conversation.id)
        library = (try? await conversationStore.setChatFlags(
            id: copy.id,
            forkedFrom: conversation.id,
            copy: source
        )) ?? library
        conversations = await conversationStore.all()
        setActive(copy)
    }

    func setNote(_ conversation: NodusConversation, note: String) async {
        guard let conversationStore else { return }
        library = (try? await conversationStore.setChatNote(id: conversation.id, note: note)) ?? library
    }

    private func reloadLibrary() async {
        guard let conversationStore else { return }
        library = await conversationStore.librarySnapshot()
    }

    func select(_ conversation: NodusConversation) { setActive(conversation) }

    func renameActive(to title: String) async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        try? await conversationStore.rename(id: id, title: title)
        await reloadActive(id: id)
    }

    func setPinned(_ conversation: NodusConversation, pinned: Bool) async {
        guard let conversationStore else { return }
        var copy = conversation
        copy.pinned = pinned
        copy.updatedAt = Date()
        try? await conversationStore.upsert(copy)
        conversations = await conversationStore.all()
        if activeConversation?.id == conversation.id { setActive(copy) }
    }

    func delete(_ conversation: NodusConversation) async {
        if conversation.id == activeConversation?.id {
            await deleteActive()
            return
        }
        guard let conversationStore else { return }
        try? await conversationStore.delete(id: conversation.id)
        conversations = await conversationStore.all()
    }

    func deleteActive() async {
        guard let id = activeConversation?.id, let conversationStore else { return }
        cancel()
        try? await conversationStore.delete(id: id)
        conversations = await conversationStore.all()
        if let next = conversations.first { setActive(next) }
        else if let created = try? await conversationStore.create() {
            setActive(created)
            conversations = await conversationStore.all()
        }
    }

    func searchConversations(_ query: String) async {
        guard let conversationStore else { return }
        conversations = await conversationStore.search(query)
    }

    func setReasoningMode(_ mode: NodusReasoningMode) async {
        await setThinkSteps(mode == .deep ? NodusThinkStep.deep.rawValue : NodusThinkStep.standard.rawValue)
    }

    func setThinkSteps(_ steps: Int) async {
        guard var conversation = activeConversation, let conversationStore else { return }
        let step = NodusThinkStep.resolve(stored: steps, mode: conversation.reasoningMode)
        conversation.reasoningMode = step.reasoningMode
        conversation.updatedAt = Date()
        try? await conversationStore.upsert(conversation)
        library = (try? await conversationStore.setChatFlags(id: conversation.id, thinkSteps: step.rawValue)) ?? library
        setActive(conversation)
    }

    func setSearchEnabled(_ enabled: Bool) async {
        guard var conversation = activeConversation, let conversationStore else { return }
        conversation.searchEnabled = enabled
        conversation.updatedAt = Date()
        try? await conversationStore.upsert(conversation)
        setActive(conversation)
    }

    func setMemoryEnabled(_ enabled: Bool) async {
        guard var conversation = activeConversation, let conversationStore else { return }
        conversation.memoryEnabled = enabled
        conversation.updatedAt = Date()
        try? await conversationStore.upsert(conversation)
        setActive(conversation)
    }

    func setKnowledgeCollections(_ ids: Set<UUID>) async {
        guard var conversation = activeConversation, let conversationStore else { return }
        conversation.attachedKnowledgeCollectionIDs = ids
        conversation.updatedAt = Date()
        try? await conversationStore.upsert(conversation)
        setActive(conversation)
    }

    func toggleReaction(_ symbol: String, on messageID: UUID) {
        var current = reactions[messageID] ?? []
        if let index = current.firstIndex(of: symbol) {
            current.remove(at: index)
        } else {
            current.append(symbol)
        }
        reactions[messageID] = current.isEmpty ? nil : current
        let stored = Dictionary(uniqueKeysWithValues: reactions.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(stored, forKey: reactionKey)
    }

    func send(using app: AppEnvironment, imageData: [Data] = []) {
        guard canSend, let conversation = activeConversation else { return }
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        errorMessage = nil
        verificationStatus = nil
        evaluationStatus = nil
        progressText = NodusReasoningStage.classifying.displayName
        progressStage = .classifying
        isGenerating = true
        messages.append(NodusMessage(role: .user, text: question))
        if loadState == .unloaded { loadState = .loading }
        let engine = app.makeNodusConversationEngine()
        let projectBrief = library.instructions(for: conversation.id)
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await engine.send(
                    question: question,
                    conversationID: conversation.id,
                    projectBrief: projectBrief,
                    progress: { stage in
                        await MainActor.run { [weak self] in
                            self?.progressText = stage.displayName
                            self?.progressStage = stage
                        }
                    }
                )
                setActive(result.conversation)
                if !imageData.isEmpty,
                   let userID = result.conversation.messages.last(where: { $0.role == .user && $0.text == question })?.id {
                    store(imageData, for: userID)
                }
                conversations = await app.nodusConversationStore.all()
            } catch let error as NodusSearchError {
                errorMessage = error.localizedDescription
                await reloadActive(id: conversation.id)
            } catch let error as IntelligenceError {
                if error != .requestCancelled { errorMessage = error.code }
                await reloadActive(id: conversation.id)
            } catch is CancellationError {
                await reloadActive(id: conversation.id)
            } catch {
                errorMessage = "Nodus generation failed"
                await reloadActive(id: conversation.id)
            }
            isGenerating = false
            progressText = nil
            progressStage = nil
            generationTask = nil
            await refresh(using: app.intelligence)
        }
    }

    /// Compatibility seam for accepted NODUS-01D unit tests. Production workspace chat uses the
    /// persisted conversation engine above.
    func send(using intelligence: ModulaIntelligence) {
        guard availability == .available,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isGenerating else { return }
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedHistory = messages.suffix(8)
        let context = boundedHistory.map { "\($0.role == .user ? "User" : "Nodus"): \($0.text)" }.joined(separator: "\n")
        let conversationInput = context.isEmpty ? question : "RECENT CONVERSATION:\n\(context)\n\nCURRENT USER MESSAGE:\n\(question)"
        input = ""
        messages.append(NodusMessage(role: .user, text: question))
        isGenerating = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await intelligence.executeDiagnostic(
                    IntelligenceRequest(
                        capability: .generate,
                        input: .object([
                            "text": .string(conversationInput),
                            "taskMode": .string(NodusTaskMode.generalAnswer.rawValue),
                        ]),
                        privacy: .localOnly,
                        source: .developerDiagnostics
                    ),
                    usingProviderID: NodusIntelligenceProvider.providerID
                )
                guard let answer = NodusAnswer.parse(response.output) else {
                    throw IntelligenceError.providerFailure(providerID: NodusIntelligenceProvider.providerID, detail: "INVALID_NODUS_ENVELOPE")
                }
                messages.append(NodusMessage(role: .nodus, text: answer.answer, answer: answer, requestID: response.requestID))
            } catch let error as IntelligenceError {
                if error != .requestCancelled { errorMessage = error.code }
            } catch is CancellationError {
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
        progressText = nil
        progressStage = nil
    }

    func clear() {
        cancel()
        messages.removeAll()
        errorMessage = nil
        verificationStatus = nil
        evaluationStatus = nil
        if let id = activeConversation?.id, let conversationStore {
            Task { [weak self] in
                try? await conversationStore.clear(id: id)
                await self?.reloadActive(id: id)
            }
        }
    }

    func queueVerification(for message: NodusMessage, store: NodusVerificationStore) async {
        guard let answer = message.answer else { return }
        let question = prompt(before: message.id)
        do {
            _ = try await store.createMission(
                question: question, answer: answer,
                reason: answer.freshness == .currentDataRequired ? .freshnessRequired : .lowConfidence,
                connectivityAvailable: false
            )
            verificationStatus = "Verification queued locally"
        } catch {
            verificationStatus = "Could not queue verification"
        }
    }

    func rate(
        _ rating: NodusDeveloperRating,
        message: NodusMessage,
        store: NodusDeveloperEvaluationStore,
        correction: String? = nil,
        learningStore: NodusVerificationStore? = nil
    ) async {
        guard let answer = message.answer else { return }
        let prompt = prompt(before: message.id)
        let identity = modelIdentity ?? NodusModelIdentity(
            id: "nodus-unknown", displayName: answer.modelVersion,
            stage: .experimentalCandidate, shippingAllowed: false,
            baseModel: "Qwen/Qwen3-1.7B", baseRevision: "unknown",
            quantization: "unknown", runtimeFormat: "mlx"
        )
        do {
            try await store.upsert(NodusDeveloperEvaluation(
                id: message.id, modelID: identity.id, modelStage: identity.stage,
                prompt: prompt, response: message.text, rating: rating,
                confidence: answer.confidence.band, freshness: answer.freshness,
                note: correction, createdAt: Date()
            ))
            if rating.needsCorrection,
               let correction,
               !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let learningStore {
                _ = try await learningStore.createCorrectionCandidate(
                    prompt: prompt, answer: answer, rating: rating, correction: correction,
                    reasoningMode: message.details?.reasoningMode ?? .standard,
                    searchEnabled: message.details?.searchEnabled ?? false,
                    knowledgeSources: message.citations.filter { $0.kind == .knowledge }.map(\.sourceName),
                    memoryItemIDs: message.details?.memoryItemIDs ?? [],
                    searchSources: message.citations.compactMap { $0.kind == .web ? $0.url : nil }
                )
                evaluationStatus = "Saved locally · Learning Candidate created"
            } else {
                evaluationStatus = "Saved locally"
            }
            ratings[message.id] = rating
        } catch {
            evaluationStatus = "Could not save evaluation"
        }
    }

    func remember(
        _ message: NodusMessage,
        scope: NodusMemoryScope,
        using store: NodusMemoryStore
    ) async {
        do {
            _ = try await store.add(
                text: message.text, kind: .generalFact, scope: scope,
                conversationID: scope == .conversation ? activeConversation?.id : nil,
                source: .message
            )
            evaluationStatus = "Remembered after confirmation"
        } catch {
            evaluationStatus = error.localizedDescription
        }
    }

    private func prompt(before messageID: UUID) -> String {
        let responseIndex = messages.firstIndex(where: { $0.id == messageID }) ?? messages.endIndex
        return messages[..<responseIndex].last(where: { $0.role == .user })?.text ?? ""
    }

    private func setActive(_ conversation: NodusConversation) {
        activeConversation = conversation
        messages = conversation.messages
        hydrateImages()
    }

    private func loadReactions() {
        let stored = UserDefaults.standard.dictionary(forKey: reactionKey) as? [String: [String]] ?? [:]
        reactions = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func hydrateImages() {
        for message in messages {
            let filename = "attachment-\(message.id.uuidString).jpg"
            guard attachmentImages[message.id] == nil,
                  let data = try? attachmentFiles.loadData(filename: filename),
                  let image = UIImage(data: data) else { continue }
            attachmentImages[message.id] = image
        }
    }

    private func store(_ payloads: [Data], for messageID: UUID) {
        guard let first = payloads.first else { return }
        let filename = "attachment-\(messageID.uuidString).jpg"
        try? attachmentFiles.saveData(first, filename: filename)
        if let image = UIImage(data: first) {
            attachmentImages[messageID] = image
        }
    }

    private func reloadActive(id: UUID) async {
        guard let conversationStore else { return }
        conversations = await conversationStore.all()
        if let conversation = await conversationStore.conversation(id: id) { setActive(conversation) }
    }
}
#endif
