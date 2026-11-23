import Foundation
import Observation

@MainActor @Observable
final class InMailStore {
    private let repository: GreenfieldInMailRepository
    let capabilities: InMailBackendCapabilities

    private(set) var threads: [InMailThread] = []
    private(set) var loadState: MessagingLoadState = .idle
    var query = ""
    var draft = InMailDraft()
    private(set) var sendState: MessageDeliveryState = .sent
    private(set) var sendError: String?
    private(set) var messages: [InMailThreadID: [InMailMessage]] = [:]
    private(set) var threadState: [InMailThreadID: MessagingLoadState] = [:]
    var replyDrafts: [InMailThreadID: String] = [:]
    private(set) var actionError: String?

    init(client: GreenfieldClient, capabilities: InMailBackendCapabilities = .production) {
        self.repository = GreenfieldInMailRepository(client: client, capabilities: capabilities)
        self.capabilities = capabilities
    }

    var visibleThreads: [InMailThread] {
        let ordered = threads.sorted { $0.updatedAt > $1.updatedAt }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ordered }
        return ordered.filter {
            $0.subject.lowercased().contains(q)
            || $0.participants.contains { $0.displayName.lowercased().contains(q) }
            || $0.preview.lowercased().contains(q)
        }
    }

    func loadIfNeeded() async {
        guard loadState == .idle || threads.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard capabilities.list else { loadState = .loaded; return }
        let hasContent = !threads.isEmpty
        loadState = hasContent ? .refreshing : .loading
        do {
            let page = try await repository.threads(cursor: nil)
            threads = page.items
            loadState = .loaded
        } catch let api as APIError {
            if hasContent {
                loadState = .loaded
                actionError = "Couldn't load messages."
            } else if let cached = await repository.cached(), !cached.items.isEmpty {
                threads = cached.items
                loadState = .loaded
            } else {
                loadState = .failed(api == .unauthenticated ? api.userFacingMessage : "Couldn't load messages.")
            }
        } catch {
            loadState = hasContent ? .loaded : .failed("Couldn't load messages.")
        }
    }

    func loadThread(_ id: InMailThreadID) async {
        if messages[id] != nil { return }
        threadState[id] = .loading
        do {
            let result = try await repository.thread(id)
            upsert(result.0)
            messages[id] = result.1.sorted { $0.createdAt < $1.createdAt }
            threadState[id] = .loaded
        } catch {
            threadState[id] = .failed("Couldn't load messages.")
        }
    }

    func sendDraft() async -> InMailThread? {
        if let error = InMailValidation.recipient(draft.toHandle) {
            sendError = error; sendState = .failed; return nil
        }
        if let error = InMailValidation.subject(draft.subject) {
            sendError = error; sendState = .failed; return nil
        }
        if let error = InMailValidation.body(draft.body) {
            sendError = error; sendState = .failed; return nil
        }
        guard capabilities.send else {
            sendError = "Couldn't send message."
            sendState = .failed
            return nil
        }
        sendState = .sending
        sendError = nil
        HapticEngine.shared.play(.lightImpact)
        do {
            let thread = try await repository.send(draft)
            upsert(thread)
            draft = InMailDraft()
            sendState = .sent
            HapticEngine.shared.play(.success)
            return thread
        } catch {
            sendState = .failed
            sendError = "Couldn't send message."
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    func reply(to id: InMailThreadID) async {
        let text = (replyDrafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard capabilities.reply else {
            actionError = "Couldn't send message."
            return
        }
        HapticEngine.shared.play(.lightImpact)
        do {
            let message = try await repository.reply(thread: id, body: text)
            var items = messages[id] ?? []
            items.append(message)
            messages[id] = items
            replyDrafts[id] = ""
            HapticEngine.shared.play(.success)
        } catch {
            actionError = "Couldn't send message."
            HapticEngine.shared.play(.failure)
        }
    }

    func thread(id: InMailThreadID) -> InMailThread? {
        threads.first { $0.id == id }
    }

    #if DEBUG
    func installDebugThreads(_ items: [InMailThread]) {
        threads = items
        loadState = .loaded
    }

    func installDebugMessages(_ id: InMailThreadID, items: [InMailMessage]) {
        messages[id] = items
        threadState[id] = .loaded
    }
    #endif

    private func upsert(_ thread: InMailThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
    }
}
