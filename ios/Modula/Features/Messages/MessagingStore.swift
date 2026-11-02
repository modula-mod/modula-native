import Foundation
import Observation

@MainActor @Observable
final class MessagingStore {
    private let repository: GreenfieldMessagingRepository
    private(set) var capabilities: MessagingBackendCapabilities
    /// People typing in each open chat (`GET /v1/conversations/:id/typing`, v2 only).
    private(set) var typingPeople: [ConversationID: [ConversationParticipant]] = [:]
    private var lastTypingPing: [ConversationID: Date] = [:]
    private var probedV2 = false
    /// Device-only personal touches (never synced, never shown to the other person).
    private(set) var nicknames: [ConversationID: String] = MessagingLocalStore.dictionary("messages.nicknames.v1")
    private(set) var wallpapers: [ConversationID: String] = MessagingLocalStore.dictionary("messages.wallpapers.v1")
    private(set) var starredIDs: Set<MessageID> = Set(UserDefaults.standard.stringArray(forKey: "messages.starred.v1") ?? [])

    private(set) var conversations: [Conversation] = []
    private(set) var conversationCursor: String?
    private(set) var conversationHasMore = false
    private(set) var conversationState: MessagingLoadState = .idle
    var conversationQuery = ""

    private(set) var threads: [ConversationID: [Message]] = [:]
    private(set) var threadCursors: [ConversationID: String?] = [:]
    private(set) var threadHasMore: [ConversationID: Bool] = [:]
    private(set) var threadState: [ConversationID: MessagingLoadState] = [:]
    /// Unsent text per chat. Persisted on this device so a half-written reply survives leaving the chat or
    /// relaunching (loss aversion: losing typed words feels worse than the effort of writing them).
    var drafts: [ConversationID: String] = MessagingDraftStore.load() {
        didSet { MessagingDraftStore.save(drafts) }
    }
    /// Chats pinned to the top of the inbox. Device-only: Greenfield has no conversation pin route.
    private(set) var pinnedIDs: [ConversationID] = MessagingPinStore.load()
    private(set) var sendingIDs: Set<MessageID> = []

    private(set) var requests: [MessageRequest] = []
    private(set) var requestState: MessagingLoadState = .idle
    private(set) var requestBusyIDs: Set<String> = []

    /// Server-owned unread total. Never summed from loaded rows.
    private(set) var accountUnreadCount: Int?
    private(set) var actionError: String?
    /// Coalesces duplicate share/story requests for the same recipient and first
    /// message while GreenField atomically creates or reuses the direct thread.
    private var startingConversations: [String: Task<Conversation, Error>] = [:]

    init(client: GreenfieldClient, capabilities: MessagingBackendCapabilities = .production) {
        self.repository = GreenfieldMessagingRepository(client: client, capabilities: capabilities)
        var caps = capabilities
        caps.report = true
        caps.block = true
        self.capabilities = caps
    }

    func isPinned(_ id: ConversationID) -> Bool { pinnedIDs.contains(id) }

    func togglePin(_ id: ConversationID) {
        if let i = pinnedIDs.firstIndex(of: id) { pinnedIDs.remove(at: i) }
        else { pinnedIDs.insert(id, at: 0); if pinnedIDs.count > MessagingPinStore.limit { pinnedIDs.removeLast() } }
        MessagingPinStore.save(pinnedIDs)
    }

    func draftPreview(for id: ConversationID) -> String? {
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var visibleConversations: [Conversation] {
        let newest = MessagingOrdering.conversationsNewestFirst(conversations)
        // Pinned chats first in pin order, then everything else newest first.
        let pinned = pinnedIDs.compactMap { id in newest.first { $0.id == id } }
        let ordered = pinned + newest.filter { !pinnedIDs.contains($0.id) }
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

    private(set) var olderLoadingIDs: Set<ConversationID> = []

    /// Merges the newest server page with what is on screen. Older pages already loaded and local
    /// (sending / failed) bubbles are kept, so a refresh or poll never makes messages vanish or jump.
    /// Returns the server messages that were not on screen before.
    @discardableResult
    private func mergeLatest(_ page: MessagePage, into id: ConversationID) -> [Message] {
        let existing = threads[id] ?? []
        let fresh = MessagingOrdering.messagesChronological(page.items)
        let serverIDs = Set(fresh.map(\.id))
        let knownIDs = Set(existing.map(\.id))
        let oldestFresh = fresh.first?.sentAt
        let olderKept = existing.filter { m in
            !m.id.hasPrefix("local-") && !serverIDs.contains(m.id) && (oldestFresh.map { m.sentAt < $0 } ?? false)
        }
        let locals = existing.filter { $0.id.hasPrefix("local-") }
        threads[id] = olderKept + fresh + locals
        if olderKept.isEmpty {
            threadCursors[id] = page.nextCursor
            threadHasMore[id] = page.hasMore
        }
        return fresh.filter { !knownIDs.contains($0.id) }
    }

    /// Older history, one server page at a time (`GET /v1/conversations/:id/messages?cursor=`).
    func loadOlderMessages(_ id: ConversationID) async -> Bool {
        guard threadHasMore[id] == true, let cursor = threadCursors[id] ?? nil, !olderLoadingIDs.contains(id) else { return false }
        olderLoadingIDs.insert(id)
        defer { olderLoadingIDs.remove(id) }
        do {
            let page = try await repository.conversation(id, cursor: cursor)
            let existing = threads[id] ?? []
            let seen = Set(existing.map(\.id))
            threads[id] = MessagingOrdering.messagesChronological(page.items.filter { !seen.contains($0.id) }) + existing
            threadCursors[id] = page.nextCursor
            threadHasMore[id] = page.hasMore
            return true
        } catch {
            actionError = "Couldn't load earlier messages."
            return false
        }
    }

    /// Quiet near-real-time refresh while a chat is open. Greenfield has no websocket/SSE route for
    /// messages, so this re-reads the newest page. Returns how many new incoming messages arrived.
    func pollThread(_ id: ConversationID) async -> Int {
        guard capabilities.listMessages, threadState[id] == .loaded, !id.hasPrefix("pending-direct:"),
              sendingIDs.isEmpty else { return 0 }
        guard let page = try? await repository.conversation(id, cursor: nil) else { return 0 }
        if capabilities.typing {
            typingPeople[id] = (try? await repository.typing(conversation: id)) ?? []
        }
        let added = mergeLatest(page, into: id).filter { !$0.isOwn }
        if !added.isEmpty { typingPeople[id] = [] }
        if !added.isEmpty, capabilities.markRead, (try? await repository.markRead(conversation: id)) != nil {
            clearUnreadLocally(id)
        }
        return added.count
    }

    /// Quiet inbox refresh for polling: never shows a spinner or an error banner.
    func pollInbox() async {
        guard capabilities.listConversations, conversationState == .loaded,
              let page = try? await repository.conversations(cursor: nil) else { return }
        let fresh = Set(page.items.map(\.id))
        conversations = page.items + conversations.filter { !fresh.contains($0.id) }
        await refreshUnreadSummary()
        if capabilities.messageRequests, let items = try? await repository.messageRequests() { requests = items }
    }

    // MARK: Messaging v2 (lights up once the API is deployed)

    /// One probe per launch. `messages.v2.disabled` (debug default) keeps v2 hidden even when deployed.
    func probeCapabilities() async {
        guard !probedV2 else { return }
        probedV2 = true
        if UserDefaults.standard.bool(forKey: "messages.v2.disabled") { return }
        #if DEBUG
        if MessagingDebugFixture.isEnabled { return }
        #endif
        guard await repository.probeV2() else { return }
        capabilities.reactions = true
        capabilities.reply = true
        capabilities.edit = true
        capabilities.deleteOwn = true
        capabilities.typing = true
        capabilities.mute = true
        capabilities.archive = true
    }

    private func updateMessage(_ id: MessageID, in conversation: ConversationID, _ change: (inout Message) -> Void) {
        guard var items = threads[conversation], let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        threads[conversation] = items
    }

    /// Toggle a reaction: instant locally, reconciled with the server's counts, rolled back on failure.
    func toggleReaction(_ emoji: String, on message: Message) async {
        guard capabilities.reactions, !message.id.hasPrefix("local-") else { return }
        let before = message.reactions
        let adding = !(before.first { $0.emoji == emoji }?.mine ?? false)
        updateMessage(message.id, in: message.conversationID) { m in
            if let i = m.reactions.firstIndex(where: { $0.emoji == emoji }) {
                m.reactions[i].count += adding ? 1 : -1
                m.reactions[i].mine = adding
                if m.reactions[i].count <= 0 { m.reactions.remove(at: i) }
            } else if adding {
                m.reactions.append(MessageReaction(emoji: emoji, count: 1, mine: true))
            }
        }
        HapticEngine.shared.play(adding ? .lightImpact : .selection)
        do {
            let server = try await repository.react(conversation: message.conversationID, message: message.id, emoji: emoji, on: adding)
            updateMessage(message.id, in: message.conversationID) { $0.reactions = server }
        } catch {
            updateMessage(message.id, in: message.conversationID) { $0.reactions = before }
            actionError = "Couldn't react."
        }
    }

    func edit(_ message: Message, text: String) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard capabilities.edit, !clean.isEmpty else { return false }
        do {
            let updated = try await repository.edit(conversation: message.conversationID, message: message.id, text: clean)
            updateMessage(message.id, in: message.conversationID) { m in
                m = Message(id: m.id, conversationID: m.conversationID, sender: m.sender, body: .text(clean), sentAt: m.sentAt,
                            delivery: m.delivery, isOwn: true, localDraft: nil, reactions: updated.reactions,
                            replyTo: m.replyTo, editedAt: updated.editedAt ?? Date(), isDeleted: false)
            }
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = "Couldn't edit message. You can edit for 15 minutes after sending."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    func unsend(_ message: Message) async {
        guard capabilities.deleteOwn else { return }
        let before = message
        updateMessage(message.id, in: message.conversationID) { m in
            m = Message(id: m.id, conversationID: m.conversationID, sender: m.sender, body: .text(""), sentAt: m.sentAt,
                        delivery: m.delivery, isOwn: true, localDraft: nil, isDeleted: true)
        }
        do {
            try await repository.unsend(conversation: message.conversationID, message: message.id)
            HapticEngine.shared.play(.success)
        } catch {
            updateMessage(message.id, in: message.conversationID) { $0 = before }
            actionError = "Couldn't unsend message."
        }
    }

    /// Throttled "I'm typing" ping (at most every 3 s while the composer changes).
    func noteTyping(_ id: ConversationID) {
        guard capabilities.typing, !id.hasPrefix("pending-direct:") else { return }
        let now = Date()
        if let last = lastTypingPing[id], now.timeIntervalSince(last) < 3 { return }
        lastTypingPing[id] = now
        Task { try? await repository.pingTyping(conversation: id) }
    }

    func toggleMute(_ id: ConversationID) async {
        guard capabilities.mute, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let muted = !conversations[index].isMuted
        conversations[index].isMuted = muted
        HapticEngine.shared.play(.selection)
        do { try await repository.setMuted(conversation: id, muted: muted) } catch {
            if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].isMuted = !muted }
            actionError = "Couldn't update mute."
        }
    }

    func archive(_ id: ConversationID) async {
        guard capabilities.archive, let removed = conversation(id: id) else { return }
        conversations.removeAll { $0.id == id }
        HapticEngine.shared.play(.confirmation)
        do { try await repository.setArchived(conversation: id, archived: true) } catch {
            conversations.append(removed)
            actionError = "Couldn't archive this chat."
        }
    }

    /// Block (live route). Also declines a pending request from them.
    func block(_ person: ConversationParticipant) async -> Bool {
        guard capabilities.block else { return false }
        do {
            try await repository.block(profile: person.handle.isEmpty ? person.id : person.handle)
            if let request = requests.first(where: { $0.sender.id == person.id }) { await declineRequest(request) }
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = "Couldn't block this account."
            return false
        }
    }

    func report(message: Message) async -> Bool {
        do {
            try await repository.report(targetType: "message", targetID: message.id, category: "other")
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = "Couldn't send the report."
            return false
        }
    }

    // MARK: Device-only personal touches

    func title(for conversation: Conversation) -> String {
        let nick = (nicknames[conversation.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return nick.isEmpty ? conversation.title : nick
    }

    func setNickname(_ name: String, for id: ConversationID) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        nicknames[id] = clean.isEmpty ? nil : clean
        MessagingLocalStore.save(nicknames, "messages.nicknames.v1")
    }

    func wallpaper(for id: ConversationID) -> MessagesWallpaperTheme {
        MessagesWallpaperTheme(rawValue: wallpapers[id] ?? "") ?? .none
    }

    func setWallpaper(_ theme: MessagesWallpaperTheme, for id: ConversationID) {
        wallpapers[id] = theme == .none ? nil : theme.rawValue
        MessagingLocalStore.save(wallpapers, "messages.wallpapers.v1")
    }

    func isStarred(_ id: MessageID) -> Bool { starredIDs.contains(id) }

    func toggleStar(_ id: MessageID) {
        if starredIDs.contains(id) { starredIDs.remove(id) } else { starredIDs.insert(id) }
        UserDefaults.standard.set(Array(starredIDs.prefix(500)), forKey: "messages.starred.v1")
        HapticEngine.shared.play(.selection)
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
            mergeLatest(page, into: id)
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
            NotificationCenter.default.post(name: .modulaPushMoment, object: PushPrePromptMoment.messageSent.rawValue)
            return true
        } catch {
            actionError = "Couldn't send message."
            return false
        }
    }

    func send(conversation id: ConversationID, viewer: ConversationParticipant, replyTo: Message? = nil) async {
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
            localDraft: text,
            replyTo: replyTo.map { MessageReplyPreview(id: $0.id, senderName: $0.sender.displayName, body: $0.body.text, deleted: $0.isDeleted) }
        )
        var items = threads[id] ?? []
        items.append(optimistic)
        threads[id] = items
        drafts[id] = ""
        sendingIDs.insert(localID)
        do {
            let confirmed = try await repository.send(
                conversation: id,
                message: MessageDraft(conversationID: id, text: text, replyToID: capabilities.reply ? replyTo?.id : nil)
            )
            replace(localID: localID, in: id, with: Message(
                id: confirmed.id,
                conversationID: confirmed.conversationID,
                sender: confirmed.sender,
                body: confirmed.body,
                sentAt: confirmed.sentAt,
                delivery: confirmed.delivery == .unknown ? .sent : confirmed.delivery,
                isOwn: true,
                localDraft: nil,
                replyTo: confirmed.replyTo ?? optimistic.replyTo
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

    /// Creates or reuses a direct conversation through `POST /v1/conversations`.
    /// When `text` is present GreenField persists it atomically as the first
    /// message, so share callers must not follow this with a second send.
    func startConversation(handle: String, text: String?) async -> Conversation? {
        let cleanHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let cleanText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstMessage = cleanText?.isEmpty == false ? cleanText : nil
        guard !cleanHandle.isEmpty, capabilities.startConversation else {
            actionError = "Couldn't start this chat."
            return nil
        }
        let requestKey = cleanHandle.lowercased() + "\u{001F}" + (firstMessage ?? "")
        if let pending = startingConversations[requestKey] {
            do {
                let conversation = try await pending.value
                rememberStartedConversation(conversation)
                return conversation
            } catch {
                actionError = directStartError(error)
                return nil
            }
        }
        let repository = self.repository
        let task = Task { try await repository.startConversation(handle: cleanHandle, text: firstMessage) }
        startingConversations[requestKey] = task
        defer { startingConversations[requestKey] = nil }
        do {
            let conversation = try await task.value
            rememberStartedConversation(conversation)
            actionError = nil
            return conversation
        } catch {
            actionError = directStartError(error)
            return nil
        }
    }

    private func rememberStartedConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        conversationState = .loaded
    }

    private func directStartError(_ error: Error) -> String {
        if let api = error as? APIError { return userMessage(api, fallback: "Couldn't start this chat.") }
        return "Couldn't start this chat."
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
            unreadCount: 0, updatedAt: c.updatedAt, titleOverride: c.titleOverride,
            isMuted: c.isMuted, isArchived: c.isArchived
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
            titleOverride: current.titleOverride,
            isMuted: current.isMuted,
            isArchived: current.isArchived
        )
    }

    private func replace(localID: MessageID, in conversation: ConversationID, with message: Message) {
        var items = threads[conversation] ?? []
        if items.contains(where: { $0.id == message.id }) {
            items.removeAll { $0.id == localID }
        } else if let index = items.firstIndex(where: { $0.id == localID }) {
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


/// Device-local persistence for composer drafts. Bounded (50 chats, 4,000 characters each), never synced.
enum MessagingDraftStore {
    static let key = "messages.drafts.v1"
    static let maxChats = 50
    static let maxLength = 4000

    static func load(_ defaults: UserDefaults = .standard) -> [ConversationID: String] {
        (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    static func save(_ drafts: [ConversationID: String], _ defaults: UserDefaults = .standard) {
        let kept = drafts
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(maxChats)
            .reduce(into: [String: String]()) { $0[$1.key] = String($1.value.prefix(maxLength)) }
        if kept.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(kept, forKey: key) }
    }
}

/// Device-local pinned chats (max 9, like system Messages). Greenfield has no pin route.
enum MessagingPinStore {
    static let key = "messages.pinned.v1"
    static let limit = 9
    static func load(_ defaults: UserDefaults = .standard) -> [ConversationID] {
        Array((defaults.stringArray(forKey: key) ?? []).prefix(limit))
    }
    static func save(_ ids: [ConversationID], _ defaults: UserDefaults = .standard) {
        defaults.set(Array(ids.prefix(limit)), forKey: key)
    }
}


enum MessagingLocalStore {
    static func dictionary(_ key: String) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }
    static func save(_ value: [String: String], _ key: String) {
        if value.isEmpty { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(value, forKey: key) }
    }
}
