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
                if (try? await repository.markRead(conversation: id)) != nil { clearUnreadLocally(id) }
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

    /// Posts `text` to an existing conversation (`POST /v1/conversations/:id/messages`, body `{text}`).
    /// Does not touch the open composer's draft.
    func sendPrepared(text: String, conversation id: ConversationID) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard capabilities.send else {
            actionError = "Couldn't send message."
            return false
        }
        do {
            let confirmed = try await repository.send(
                conversation: id,
                message: MessageDraft(conversationID: id, text: text)
            )
            let stored = Message(
                id: confirmed.id,
                conversationID: confirmed.conversationID,
                sender: confirmed.sender,
                body: confirmed.body,
                sentAt: confirmed.sentAt,
                delivery: confirmed.delivery == .unknown ? .sent : confirmed.delivery,
                isOwn: true,
                localDraft: nil
            )
            if threads[id] != nil {
                var items = threads[id] ?? []
                items.append(stored)
                threads[id] = items
            }
            let preview = confirmed.body.text.isEmpty ? text : confirmed.body.text
            noteLocalSend(stored, preview: preview)
            return true
        } catch {
            actionError = "Couldn't send message."
            return false
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

    /// Local key for a chat that doesn't exist on the server yet (drafts + optimistic bubbles).
    static func pendingDirectKey(_ handle: String) -> ConversationID {
        "pending-direct:" + handle.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    /// First send to someone with no chat yet: shows an optimistic bubble, creates the
    /// conversation with the message via `POST /v1/conversations`, then moves the thread
    /// under the real id. Returns the conversation on success; on failure the bubble is
    /// marked failed (tap to retry) and the draft is restored.
    func startDirect(handle: String, viewer: ConversationParticipant) async -> Conversation? {
        let key = Self.pendingDirectKey(handle)
        let text = (drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inFlight = (threads[key] ?? []).contains { sendingIDs.contains($0.id) }
        guard !text.isEmpty, !inFlight else { return nil }
        guard capabilities.startConversation else {
            actionError = "Couldn't start this chat."
            return nil
        }
        HapticEngine.shared.play(.lightImpact)
        let localID = "local-\(UUID().uuidString)"
        var items = threads[key] ?? []
        items.append(Message(id: localID, conversationID: key, sender: viewer, body: .text(text),
                             sentAt: Date(), delivery: .sending, isOwn: true, localDraft: text))
        threads[key] = items
        threadState[key] = .loaded
        drafts[key] = ""
        sendingIDs.insert(localID)
        do {
            let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            let conversation = try await repository.startConversation(handle: clean, text: text)
            sendingIDs.remove(localID)
            conversations.removeAll { $0.id == conversation.id }
            conversations.insert(conversation, at: 0)
            conversationState = .loaded
            // Carry the sent bubble over so the thread isn't blank while it reloads.
            let sent = (threads[key] ?? []).map { m -> Message in
                Message(id: m.id, conversationID: conversation.id, sender: m.sender, body: m.body,
                        sentAt: m.sentAt, delivery: .sent, isOwn: true, localDraft: nil)
            }
            if threads[conversation.id] == nil { threads[conversation.id] = sent }
            threads[key] = nil
            threadState[key] = nil
            HapticEngine.shared.play(.success)
            Task { await self.refreshThread(conversation.id) }
            return conversation
        } catch {
            sendingIDs.remove(localID)
            markFailed(localID: localID, in: key)
            drafts[key] = text
            if let api = error as? APIError {
                actionError = userMessage(api, fallback: "Couldn't send message.")
            } else {
                actionError = "Couldn't send message."
            }
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    /// Retry a failed first message to `handle`.
    func retryStartDirect(message: Message, handle: String, viewer: ConversationParticipant) async -> Conversation? {
        guard message.delivery == .failed, let draft = message.localDraft, !draft.isEmpty else { return nil }
        let key = Self.pendingDirectKey(handle)
        remove(messageID: message.id, in: key)
        drafts[key] = draft
        return await startDirect(handle: handle, viewer: viewer)
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

    /// Swipe / context menu "Mark as Read" (`POST /v1/conversations/:id/read`).
    func markConversationRead(_ id: ConversationID) async {
        guard capabilities.markRead, let before = conversation(id: id), before.isUnread else { return }
        clearUnreadLocally(id)
        HapticEngine.shared.play(.confirmation)
        #if DEBUG
        if MessagingDebugFixture.isEnabled { return }
        #endif
        do {
            try await repository.markRead(conversation: id)
        } catch {
            if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index] = before }
            actionError = "Couldn't mark as read."
        }
    }

    private func clearUnreadLocally(_ id: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let c = conversations[index]
        guard c.unreadCount != 0 else { return }
        conversations[index] = Conversation(
            id: c.id, kind: c.kind, participants: c.participants, lastMessage: c.lastMessage,
            unreadCount: 0, updatedAt: c.updatedAt, titleOverride: c.titleOverride
        )
    }

    /// The 1:1 conversation with a person, matched on handle (case-insensitive, optional "@") or id.
    func directConversation(with person: String) -> Conversation? {
        let key = person.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !key.isEmpty else { return nil }
        return conversations.first { c in
            c.kind != .group && c.participants.count <= 2 && c.participants.contains {
                $0.handle.lowercased() == key || $0.id.lowercased() == key
            }
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

    private func noteLocalSend(_ message: Message, preview: String) {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationID }) else { return }
        let current = conversations[index]
        conversations[index] = Conversation(
            id: current.id,
            kind: current.kind,
            participants: current.participants,
            lastMessage: MessagePreview(id: message.id, body: preview, sentAt: message.sentAt, senderID: message.sender.id),
            unreadCount: current.unreadCount,
            updatedAt: message.sentAt,
            titleOverride: current.titleOverride
        )
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
