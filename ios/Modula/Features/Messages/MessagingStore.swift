import Foundation
import Observation

@MainActor @Observable
final class MessagingStore {
    private let repository: GreenfieldMessagingRepository
    let capabilities: MessagingBackendCapabilities

    private(set) var conversations: [Conversation] = []
    private(set) var conversationCursor: String?
    private(set) var conversationHasMore = false
    private(set) var conversationState: MessagingLoadState = .idle
    var conversationQuery = ""

    private(set) var threads: [ConversationID: [Message]] = [:]
    private(set) var threadCursors: [ConversationID: String?] = [:]
    private(set) var threadHasMore: [ConversationID: Bool] = [:]
    private(set) var threadState: [ConversationID: MessagingLoadState] = [:]
    var drafts: [ConversationID: String] = [:]
    private(set) var sendingIDs: Set<MessageID> = []

    private(set) var requests: [MessageRequest] = []
    private(set) var requestState: MessagingLoadState = .idle
    private(set) var requestBusyIDs: Set<String> = []

    /// Server-owned unread total. Never summed from loaded rows.
    private(set) var accountUnreadCount: Int?
    private(set) var actionError: String?

    init(client: GreenfieldClient, capabilities: MessagingBackendCapabilities = .production) {
        self.repository = GreenfieldMessagingRepository(client: client, capabilities: capabilities)
        self.capabilities = capabilities
    }

    var visibleConversations: [Conversation] {
        let ordered = MessagingOrdering.conversationsNewestFirst(conversations)
        let query = conversationQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ordered }
        return ordered.filter {
            $0.title.lowercased().contains(query)
            || ($0.handleLabel?.lowercased().contains(query) ?? false)
            || ($0.lastMessage?.body.lowercased().contains(query) ?? false)
        }
    }

    var searchIsLocalOnly: Bool { true }

    func loadInboxIfNeeded() async {
        guard conversationState == .idle || conversations.isEmpty else { return }
        await refreshInbox()
    }

    func refreshInbox() async {
        // Backend not live yet: show a calm empty inbox instead of an error.
        guard capabilities.listConversations else { conversationState = .loaded; return }
        let hasContent = !conversations.isEmpty
        conversationState = hasContent ? .refreshing : .loading
        actionError = nil
        do {
            let page = try await repository.conversations(cursor: nil)
            conversations = page.items
            conversationCursor = page.nextCursor
            conversationHasMore = page.hasMore
            conversationState = .loaded
            await refreshUnreadSummary()
        } catch let api as APIError {
            if hasContent {
                conversationState = .loaded
                actionError = userMessage(api, fallback: "Couldn't load messages.")
            } else if let cached = await repository.cachedConversations(), !cached.items.isEmpty {
                conversations = cached.items
                conversationState = .loaded
                actionError = userMessage(api, fallback: "Couldn't load messages.")
            } else {
                conversationState = .failed(userMessage(api, fallback: "Couldn't load messages."))
            }
        } catch {
            conversationState = hasContent ? .loaded : .failed("Couldn't load messages.")
        }
    }

    func loadMoreConversations() async {
        guard conversationHasMore, let cursor = conversationCursor else { return }
        do {
            let page = try await repository.conversations(cursor: cursor)
            let seen = Set(conversations.map(\.id))
            conversations.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            conversationCursor = page.nextCursor
            conversationHasMore = page.hasMore
        } catch {
            actionError = "Couldn't load messages."
        }
    }

    func loadThreadIfNeeded(_ id: ConversationID) async {
        if threads[id] != nil { return }
        await refreshThread(id)
    }

    func refreshThread(_ id: ConversationID) async {
        let hasContent = !(threads[id] ?? []).isEmpty
        threadState[id] = hasContent ? .refreshing : .loading
        do {
            let page = try await repository.conversation(id, cursor: nil)
            threads[id] = MessagingOrdering.messagesChronological(page.items)
            threadCursors[id] = page.nextCursor
            threadHasMore[id] = page.hasMore
            threadState[id] = .loaded
            if capabilities.markRead {
                try? await repository.markRead(conversation: id)
            }
        } catch let api as APIError {
            if hasContent {
                threadState[id] = .loaded
                actionError = userMessage(api, fallback: "Couldn't load messages.")
            } else if let cached = await repository.cachedMessages(for: id), !cached.items.isEmpty {
                threads[id] = MessagingOrdering.messagesChronological(cached.items)
                threadState[id] = .loaded
            } else {
                threadState[id] = .failed(userMessage(api, fallback: "Couldn't load messages."))
            }
        } catch {
            threadState[id] = hasContent ? .loaded : .failed("Couldn't load messages.")
        }
    }

    func send(conversation id: ConversationID, viewer: ConversationParticipant) async {
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard capabilities.send else {
            actionError = "Couldn't send message."
            return
        }
        HapticEngine.shared.play(.lightImpact)
        let localID = "local-\(UUID().uuidString)"
        let optimistic = Message(
            id: localID,
            conversationID: id,
            sender: viewer,
            body: .text(text),
            sentAt: Date(),
            delivery: .sending,
            isOwn: true,
            localDraft: text
        )
        var items = threads[id] ?? []
        items.append(optimistic)
        threads[id] = items
        drafts[id] = ""
        sendingIDs.insert(localID)
        do {
            let confirmed = try await repository.send(
                conversation: id,
                message: MessageDraft(conversationID: id, text: text)
            )
            replace(localID: localID, in: id, with: Message(
                id: confirmed.id,
                conversationID: confirmed.conversationID,
                sender: confirmed.sender,
                body: confirmed.body,
                sentAt: confirmed.sentAt,
                delivery: confirmed.delivery == .unknown ? .sent : confirmed.delivery,
                isOwn: true,
                localDraft: nil
            ))
            sendingIDs.remove(localID)
            HapticEngine.shared.play(.success)
        } catch {
            markFailed(localID: localID, in: id)
            sendingIDs.remove(localID)
            drafts[id] = text
            actionError = "Couldn't send message."
            HapticEngine.shared.play(.failure)
        }
    }

    func retry(message: Message, viewer: ConversationParticipant) async {
        guard message.delivery == .failed, let draft = message.localDraft, !draft.isEmpty else { return }
        remove(messageID: message.id, in: message.conversationID)
        drafts[message.conversationID] = draft
        await send(conversation: message.conversationID, viewer: viewer)
    }

    func loadRequestsIfNeeded() async {
        guard requestState == .idle || requests.isEmpty else { return }
        await refreshRequests()
    }

    func refreshRequests() async {
        guard capabilities.messageRequests else { requestState = .loaded; return }
        requestState = requests.isEmpty ? .loading : .refreshing
        do {
            requests = try await repository.messageRequests()
            requestState = .loaded
        } catch let api as APIError {
            requestState = requests.isEmpty
                ? .failed(userMessage(api, fallback: "Couldn't load messages."))
                : .loaded
        } catch {
            requestState = requests.isEmpty ? .failed("Couldn't load messages.") : .loaded
        }
    }

    func acceptRequest(_ request: MessageRequest) async -> Conversation? {
        guard capabilities.acceptRequest else { return nil }
        requestBusyIDs.insert(request.id)
        do {
            let conversation = try await repository.acceptRequest(id: request.id)
            requests.removeAll { $0.id == request.id }
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: 0)
            }
            requestBusyIDs.remove(request.id)
            HapticEngine.shared.play(.success)
            return conversation
        } catch {
            requestBusyIDs.remove(request.id)
            actionError = "Couldn't update this request."
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    func declineRequest(_ request: MessageRequest) async {
        guard capabilities.declineRequest else { return }
        requestBusyIDs.insert(request.id)
        do {
            try await repository.declineRequest(id: request.id)
            requests.removeAll { $0.id == request.id }
            requestBusyIDs.remove(request.id)
            HapticEngine.shared.play(.success)
        } catch {
            requestBusyIDs.remove(request.id)
            actionError = "Couldn't update this request."
            HapticEngine.shared.play(.failure)
        }
    }

    func conversation(id: ConversationID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func messages(for id: ConversationID) -> [Message] {
        MessagingOrdering.messagesChronological(threads[id] ?? [])
    }

    func clearActionError() { actionError = nil }

    #if DEBUG
    func installDebugInbox(_ items: [Conversation]) {
        conversations = items
        conversationState = .loaded
    }

    func installDebugThread(_ id: ConversationID, messages: [Message]) {
        threads[id] = messages
        threadState[id] = .loaded
    }

    func installDebugRequests(_ items: [MessageRequest]) {
        requests = items
        requestState = .loaded
    }
    #endif

    private func refreshUnreadSummary() async {
        accountUnreadCount = try? await repository.unreadSummary()
    }

    private func replace(localID: MessageID, in conversation: ConversationID, with message: Message) {
        var items = threads[conversation] ?? []
        if let index = items.firstIndex(where: { $0.id == localID }) {
            items[index] = message
        } else {
            items.append(message)
        }
        threads[conversation] = items
    }

    private func markFailed(localID: MessageID, in conversation: ConversationID) {
        var items = threads[conversation] ?? []
        if let index = items.firstIndex(where: { $0.id == localID }) {
            var failed = items[index]
            failed.delivery = .failed
            items[index] = failed
            threads[conversation] = items
        }
    }

    private func remove(messageID: MessageID, in conversation: ConversationID) {
        threads[conversation]?.removeAll { $0.id == messageID }
    }

    private func userMessage(_ api: APIError, fallback: String) -> String {
        switch api {
        case .unauthenticated: api.userFacingMessage
        case .unconfigured: api.userFacingMessage
        default: fallback
        }
    }
}
