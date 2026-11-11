import Foundation
import Observation

@MainActor @Observable
final class MessagingStore {
    private let repository: GreenfieldMessagingRepository
    private let client: GreenfieldClient
    private(set) var capabilities: MessagingBackendCapabilities
    /// People typing in each open chat (`GET /v1/conversations/:id/typing`, v2 only).
    private(set) var typingPeople: [ConversationID: [ConversationParticipant]] = [:]
    private var lastTypingPing: [ConversationID: Date] = [:]
    private var probedV2 = false
    /// Device-only personal touches (never synced, never shown to the other person).
    private(set) var nicknames: [ConversationID: String] = MessagingLocalStore.dictionary("messages.nicknames.v1")
    private(set) var wallpapers: [ConversationID: String] = MessagingLocalStore.dictionary("messages.wallpapers.v1")
    private(set) var starredIDs: Set<MessageID> = Set(UserDefaults.standard.stringArray(forKey: "messages.starred.v1") ?? [])

    private(set) var conversations: [Conversation] = [] {
        didSet { conversationsRevision &+= 1 }
    }
    /// Bumped on every `conversations` write; keys the inbox sort cache below.
    @ObservationIgnored private var conversationsRevision = 0
    /// Inbox redraws (typing, presence, unread ticks) used to re-sort every chat each time.
    @ObservationIgnored private var newestFirstCache: (revision: Int, sorted: [Conversation])?
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
        didSet { MessagingDraftStore.scheduleSave(drafts) }
    }
    /// Chats pinned to the top of the inbox. Device-only: Greenfield has no conversation pin route.
    private(set) var pinnedIDs: [ConversationID] = MessagingPinStore.load()
    /// Device-only archive list. The mute/archive route already exists; the client previously dropped
    /// archived chats from memory, so they could not be opened again. IDs and a light snapshot stay local.
    private var archivedIDs: Set<ConversationID> = MessagingIDSetStore.load("messages.archived.v1")
    private var archivedSnapshots: [ConversationID: MessagingArchivedSnapshot] = MessagingArchiveSnapshotStore.load()
    /// Device-only hidden chats, revealed after Face ID / device passcode in the current session.
    private var hiddenIDs: Set<ConversationID> = MessagingIDSetStore.load("messages.hidden.v1")
    private(set) var hiddenUnlockedThisSession = false
    /// Device-only folder name per conversation (never synced).
    private var folderAssignments: [ConversationID: String] = MessagingLocalStore.dictionary("messages.folders.v1")
    /// Local unmute deadlines for timed mute. The server mute flag is still boolean.
    private var muteUntil: [ConversationID: Date] = MessagingDateStore.load("messages.muteUntil.v1")
    private(set) var sendingIDs: Set<MessageID> = []

    private(set) var requests: [MessageRequest] = []
    private(set) var requestState: MessagingLoadState = .idle
    private(set) var requestBusyIDs: Set<String> = []

    /// Server-owned unread total. Never summed from loaded rows.
    private(set) var accountUnreadCount: Int?
    private(set) var actionError: String?
    private(set) var privacy = MessagingPrivacy()
    private(set) var privacyState: MessagingLoadState = .idle
    private(set) var presenceByActor: [String: PresenceItem] = [:]
    private(set) var groups: [ConversationID: GroupDetail] = [:]
    private(set) var historyHits: [HistorySearchHit] = []
    private(set) var historyHasMore = false
    private(set) var historyCursor: String?
    private(set) var historyState: MessagingLoadState = .idle
    private(set) var historyQuery = ""
    private(set) var reactionDetails: [MessageID: [MessageReactionDetail]] = [:]
    private(set) var receiptsByMessage: [MessageID: MessageReceipts] = [:]
    private(set) var realtimeConnected = false
    private var realtime: MessagingRealtimeClient?
    private var presenceHeartbeatTask: Task<Void, Never>?

    init(client: GreenfieldClient, capabilities: MessagingBackendCapabilities = .production) {
        self.client = client
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
        inboxConversations(includeArchived: false, includeHidden: false)
    }

    /// Open inbox rows, with pinned chats first. Archived and hidden chats are listed in their own folders.
    func inboxConversations(includeArchived: Bool, includeHidden: Bool) -> [Conversation] {
        let pool = conversations.filter { conversation in
            (includeArchived || !isArchived(conversation.id))
            && (includeHidden || !isHidden(conversation.id))
        }
        let sortedAll: [Conversation]
        if let cache = newestFirstCache, cache.revision == conversationsRevision {
            sortedAll = cache.sorted
        } else {
            sortedAll = MessagingOrdering.conversationsNewestFirst(conversations)
            newestFirstCache = (conversationsRevision, sortedAll)
        }
        let allowed = Set(pool.map(\.id))
        let newest = pool.count == conversations.count ? sortedAll : sortedAll.filter { allowed.contains($0.id) }
        let pinned = pinnedIDs.compactMap { id in newest.first { $0.id == id } }
        let ordered = pinned + newest.filter { !pinnedIDs.contains($0.id) }
        let query = conversationQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ordered }
        return ordered.filter { matchesInboxQuery($0, query: query) }
    }

    func matchesInboxQuery(_ conversation: Conversation, query: String) -> Bool {
        conversation.title.lowercased().contains(query)
            || ((nicknames[conversation.id] ?? "").lowercased().contains(query))
            || (conversation.handleLabel?.lowercased().contains(query) ?? false)
            || (conversation.lastMessage?.body.lowercased().contains(query) ?? false)
    }

    var searchIsLocalOnly: Bool { true }

    func loadInboxIfNeeded() async {
        guard conversationState == .idle || conversations.isEmpty else { return }
        await refreshInbox()
    }

    func refreshInbox() async {
        // Backend not live yet: show a calm empty inbox instead of an error.
        guard capabilities.listConversations else { conversationState = .loaded; return }
        if conversations.isEmpty, let warm = await repository.warmConversations(), conversations.isEmpty {
            adoptInbox(warm.items, replacing: false)
        }
        let hasContent = !conversations.isEmpty
        conversationState = hasContent ? .refreshing : .loading
        actionError = nil
        do {
            let page = try await repository.conversations(cursor: nil)
            adoptInbox(page.items, replacing: true)
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
        adoptInbox(page.items + conversations.filter { !fresh.contains($0.id) }, replacing: true)
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
        if let v3 = await repository.probeV3() {
            var merged = v3
            merged.photoVideo = false
            merged.report = true
            merged.block = true
            capabilities = merged
            MessagingV3FlagStore.save(merged)
            CallManager.shared.updateCapabilities(merged.calls)
            await loadPrivacyIfNeeded()
            startRealtimeIfNeeded()
            return
        }
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
                            replyTo: m.replyTo, editedAt: updated.editedAt ?? Date(), isDeleted: false,
                            kind: m.kind, attachments: m.attachments, mentions: m.mentions, clientMessageId: m.clientMessageId)
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
                        delivery: m.delivery, isOwn: true, localDraft: nil, isDeleted: true, kind: m.kind)
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
        if capabilities.privacyControls, !privacy.typingIndicators { return }
        let now = Date()
        if let last = lastTypingPing[id], now.timeIntervalSince(last) < 3 { return }
        lastTypingPing[id] = now
        if let realtime, realtime.isConnected {
            realtime.sendTyping(conversationID: id)
        } else {
            Task { try? await repository.pingTyping(conversation: id) }
        }
    }

    func toggleMute(_ id: ConversationID) async {
        guard capabilities.mute, let current = conversation(id: id) else { return }
        if current.isMuted {
            await unmuteNow(id)
        } else {
            await mute(id: id, for: .forever)
        }
    }

    func archive(_ id: ConversationID) async {
        guard capabilities.archive, let current = conversation(id: id) else { return }
        rememberArchived(current)
        HapticEngine.shared.play(.confirmation)
        do { try await repository.setArchived(conversation: id, archived: true) } catch {
            forgetArchived(id)
            actionError = "Couldn't archive this chat."
        }
    }

    func unarchive(_ id: ConversationID) async {
        guard capabilities.archive else { return }
        let wasArchived = isArchived(id)
        forgetArchived(id)
        HapticEngine.shared.play(.selection)
        do { try await repository.setArchived(conversation: id, archived: false) } catch {
            if wasArchived, let snapshot = archivedSnapshots[id] {
                rememberArchived(snapshot.conversation)
            }
            actionError = "Couldn't unarchive this chat."
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

    // MARK: Device-only reading position (roadmap #03)

    /// Newest message this device saw while the reader was at the end of a chat. Local only:
    /// it is not a server read receipt and doesn't sync between devices.
    private(set) var lastReadIDs: [ConversationID: MessageID] = MessagingLocalStore.dictionary("messages.lastRead.v1")

    func markReadLocally(_ messageID: MessageID, in id: ConversationID) {
        guard !messageID.hasPrefix("local-"), lastReadIDs[id] != messageID else { return }
        lastReadIDs[id] = messageID
        MessagingLocalStore.save(lastReadIDs, "messages.lastRead.v1")
    }

    /// First incoming message after this device's saved position, if that position is in the
    /// loaded page. Nil when there is no saved position or it isn't loaded (nothing is guessed).
    func firstUnreadLocally(in id: ConversationID) -> MessageID? {
        let items = messages(for: id)
        guard let anchor = lastReadIDs[id], let index = items.firstIndex(where: { $0.id == anchor }) else { return nil }
        return items[(index + 1)...].first(where: { !$0.isOwn && !$0.isDeleted })?.id
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
                message: MessageDraft(conversationID: id, text: text, clientMessageId: freshClientMessageId())
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

    @discardableResult
    func send(conversation id: ConversationID, viewer: ConversationParticipant, replyTo: Message? = nil) async -> Message? {
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard capabilities.send else {
            actionError = "Couldn't send message."
            return nil
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
                message: MessageDraft(conversationID: id, text: text, replyToID: capabilities.reply ? replyTo?.id : nil, clientMessageId: freshClientMessageId())
            )
            replace(localID: localID, in: id, with: confirmedWithDelivery(confirmed, fallbackReply: optimistic.replyTo))
            sendingIDs.remove(localID)
            HapticEngine.shared.play(.success)
            return threads[id]?.first(where: { $0.id == confirmed.id })
        } catch {
            markFailed(localID: localID, in: id)
            sendingIDs.remove(localID)
            drafts[id] = text
            actionError = "Couldn't send message."
            HapticEngine.shared.play(.failure)
            return nil
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

    // MARK: - Device-only inbox organisation (archive, hide, folders, timed mute)

    func isArchived(_ id: ConversationID) -> Bool { archivedIDs.contains(id) }
    func isHidden(_ id: ConversationID) -> Bool { hiddenIDs.contains(id) }

    var archivedConversations: [Conversation] {
        let live = conversations.filter { isArchived($0.id) }
        let missing = archivedIDs.subtracting(live.map(\.id)).compactMap { archivedSnapshots[$0]?.conversation }
        return MessagingOrdering.conversationsNewestFirst(live + missing)
    }

    var hiddenConversations: [Conversation] {
        MessagingOrdering.conversationsNewestFirst(conversations.filter { isHidden($0.id) })
    }

    var folderNames: [String] {
        Array(Set(folderAssignments.values.filter { !$0.isEmpty })).sorted()
    }

    func folder(for id: ConversationID) -> String? {
        folderAssignments[id].flatMap { $0.isEmpty ? nil : $0 }
    }

    func conversations(inFolder name: String) -> [Conversation] {
        inboxConversations(includeArchived: false, includeHidden: false).filter { folder(for: $0.id) == name }
    }

    func setFolder(_ name: String?, for id: ConversationID) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { folderAssignments[id] = nil } else { folderAssignments[id] = trimmed }
        MessagingLocalStore.save(folderAssignments, "messages.folders.v1")
    }

    func hide(_ id: ConversationID) {
        hiddenIDs.insert(id)
        MessagingIDSetStore.save(hiddenIDs, "messages.hidden.v1")
        HapticEngine.shared.play(.confirmation)
    }

    func unhide(_ id: ConversationID) {
        hiddenIDs.remove(id)
        MessagingIDSetStore.save(hiddenIDs, "messages.hidden.v1")
        HapticEngine.shared.play(.selection)
    }

    func unlockHiddenFolder() { hiddenUnlockedThisSession = true }

    func lockHiddenFolder() { hiddenUnlockedThisSession = false }

    func muteUntilDate(for id: ConversationID) -> Date? { muteUntil[id] }

    func mute(id: ConversationID, for duration: MessageMuteDuration) async {
        guard capabilities.mute else { return }
        await applyMute(id, muted: true)
        if duration == .forever {
            muteUntil[id] = nil
        } else {
            muteUntil[id] = Date().addingTimeInterval(duration.seconds)
        }
        MessagingDateStore.save(muteUntil, "messages.muteUntil.v1")
    }

    func unmuteNow(_ id: ConversationID) async {
        muteUntil[id] = nil
        MessagingDateStore.save(muteUntil, "messages.muteUntil.v1")
        await applyMute(id, muted: false)
    }

    /// Applies expired timed mutes. Safe to call when the inbox or a chat appears.
    func expireTimedMutesIfNeeded() async {
        let now = Date()
        let expired = muteUntil.filter { $0.value <= now }.map(\.key)
        guard !expired.isEmpty else { return }
        for id in expired {
            muteUntil[id] = nil
            await applyMute(id, muted: false)
        }
        MessagingDateStore.save(muteUntil, "messages.muteUntil.v1")
    }

    private func applyMute(_ id: ConversationID, muted: Bool) async {
        guard capabilities.mute else { return }
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isMuted = muted
        }
        do { try await repository.setMuted(conversation: id, muted: muted) } catch {
            if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].isMuted = !muted }
            actionError = "Couldn't update mute."
        }
    }

    func markAllVisibleRead() async {
        let unread = visibleConversations.filter(\.isUnread)
        for conversation in unread {
            await markConversationRead(conversation.id)
        }
    }

    #if DEBUG
    func resetInboxOrganisationForTesting() {
        archivedIDs = []
        archivedSnapshots = [:]
        hiddenIDs = []
        hiddenUnlockedThisSession = false
        folderAssignments = [:]
        muteUntil = [:]
        MessagingIDSetStore.save([], "messages.archived.v1")
        MessagingArchiveSnapshotStore.save([:])
        MessagingIDSetStore.save([], "messages.hidden.v1")
        MessagingLocalStore.save([:], "messages.folders.v1")
        MessagingDateStore.save([:], "messages.muteUntil.v1")
    }

    func archiveLocallyForTesting(_ id: ConversationID) {
        if let current = conversation(id: id) { rememberArchived(current) }
    }

    func setMuteUntilForTesting(_ id: ConversationID, date: Date?) {
        muteUntil[id] = date
        MessagingDateStore.save(muteUntil, "messages.muteUntil.v1")
    }

    func installDebugThread(_ items: [Message], conversationID: ConversationID) {
        threads[conversationID] = items
    }
    #endif

    private func rememberArchived(_ conversation: Conversation) {
        var stored = conversation
        stored.isArchived = true
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].isArchived = true
        } else {
            conversations.append(stored)
        }
        archivedIDs.insert(conversation.id)
        archivedSnapshots[conversation.id] = MessagingArchivedSnapshot(conversation: stored)
        MessagingIDSetStore.save(archivedIDs, "messages.archived.v1")
        MessagingArchiveSnapshotStore.save(archivedSnapshots)
    }

    private func forgetArchived(_ id: ConversationID) {
        archivedIDs.remove(id)
        archivedSnapshots[id] = nil
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = false
        }
        MessagingIDSetStore.save(archivedIDs, "messages.archived.v1")
        MessagingArchiveSnapshotStore.save(archivedSnapshots)
    }

    /// Reconciles a server inbox page with local archive/hide flags without inventing chats the API never returned,
    /// while keeping archived snapshots so the Archived folder still has something to show.
    private func adoptInbox(_ items: [Conversation], replacing: Bool) {
        var incoming = items
        for index in incoming.indices {
            if archivedIDs.contains(incoming[index].id) {
                incoming[index].isArchived = true
                archivedSnapshots[incoming[index].id] = MessagingArchivedSnapshot(conversation: incoming[index])
            }
        }
        if replacing {
            let incomingIDs = Set(incoming.map(\.id))
            let retained = conversations.filter { !incomingIDs.contains($0.id) && isArchived($0.id) }
            conversations = incoming + retained
            MessagingArchiveSnapshotStore.save(archivedSnapshots)
        } else {
            conversations = incoming
        }
    }
}

enum MessagingDraftStore {
    static let key = "messages.drafts.v1"
    static let maxChats = 50
    static let maxLength = 4000

    static func load(_ defaults: UserDefaults = .standard) -> [ConversationID: String] {
        (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    @MainActor private static var pending: Task<Void, Never>?

    @MainActor static func scheduleSave(_ drafts: [ConversationID: String], _ defaults: UserDefaults = .standard) {
        pending?.cancel()
        let snapshot = drafts
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save(snapshot, defaults)
        }
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


enum MessageMuteDuration: String, CaseIterable, Identifiable, Sendable {
    case hour, eightHours, week, forever
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hour: "1 hour"
        case .eightHours: "8 hours"
        case .week: "1 week"
        case .forever: "Until I unmute"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .hour: 60 * 60
        case .eightHours: 8 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .forever: 0
        }
    }
}

struct MessagingArchivedSnapshot: Hashable, Sendable {
    var conversation: Conversation
}

enum MessagingIDSetStore {
    static func load(_ key: String, _ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
    static func save(_ ids: Set<String>, _ key: String, _ defaults: UserDefaults = .standard) {
        if ids.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(Array(ids), forKey: key) }
    }
}

enum MessagingDateStore {
    static func load(_ key: String, _ defaults: UserDefaults = .standard) -> [String: Date] {
        let raw = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }
    static func save(_ value: [String: Date], _ key: String, _ defaults: UserDefaults = .standard) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value.mapValues(\.timeIntervalSince1970), forKey: key)
        }
    }
}

enum MessagingArchiveSnapshotStore {
    private static let key = "messages.archivedSnapshots.v1"

    static func load(_ defaults: UserDefaults = .standard) -> [ConversationID: MessagingArchivedSnapshot] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: SnapshotDTO].self, from: data) else { return [:] }
        return raw.mapValues { MessagingArchivedSnapshot(conversation: $0.conversation) }
    }

    static func save(_ value: [ConversationID: MessagingArchivedSnapshot], _ defaults: UserDefaults = .standard) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        let raw = Dictionary(uniqueKeysWithValues: value.map { ($0.key, SnapshotDTO($0.value.conversation)) })
        defaults.set(try? JSONEncoder().encode(raw), forKey: key)
    }

    private struct SnapshotDTO: Codable {
        var id: String
        var kind: String
        var title: String
        var handle: String?
        var updatedAt: Date
        var unreadCount: Int
        var preview: String
        var participantNames: [String]
        var participantIDs: [String]
        var participantHandles: [String]

        init(_ conversation: Conversation) {
            id = conversation.id
            kind = conversation.kind.rawValue
            title = conversation.title
            handle = conversation.handleLabel
            updatedAt = conversation.updatedAt
            unreadCount = conversation.unreadCount
            preview = conversation.lastMessage?.body ?? ""
            participantNames = conversation.participants.map(\.displayName)
            participantIDs = conversation.participants.map(\.id)
            participantHandles = conversation.participants.map(\.handle)
        }

        var conversation: Conversation {
            let people: [ConversationParticipant] = zip(participantIDs, zip(participantHandles, participantNames)).map { id, pair in
                ConversationParticipant(id: id, handle: pair.0, displayName: pair.1, avatarURL: nil)
            }
            let previewMessage: MessagePreview? = preview.isEmpty ? nil : MessagePreview(id: "archived-\(id)", body: preview, sentAt: updatedAt, senderID: people.first?.id)
            var conversation = Conversation(
                id: id,
                kind: ConversationKind(parsing: kind),
                participants: people,
                lastMessage: previewMessage,
                unreadCount: unreadCount,
                updatedAt: updatedAt,
                titleOverride: title
            )
            conversation.isArchived = true
            return conversation
        }
    }
}

enum MessageThreadSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, from, links, images, starred
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .from: "From"
        case .links: "Links"
        case .images: "Images"
        case .starred: "Starred"
        }
    }

    func matches(_ message: Message, query: String, starredIDs: Set<MessageID>, senderNeedle: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = message.body.text.lowercased()
        let hasText = q.isEmpty || text.contains(q) || message.sender.displayName.lowercased().contains(q) || message.sender.handle.lowercased().contains(q)
        let url = MessageInlineContent.firstURL(in: message.body.text)
        switch self {
        case .all: return hasText
        case .from:
            let needle = (senderNeedle ?? query).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return false }
            return message.sender.displayName.lowercased().contains(needle) || message.sender.handle.lowercased().contains(needle)
        case .links:
            return url != nil && (q.isEmpty || text.contains(q) || (url?.absoluteString.lowercased().contains(q) ?? false))
        case .images:
            guard let url, case .image = MessageInlineContent.classify(url) else { return false }
            return q.isEmpty || text.contains(q)
        case .starred:
            return starredIDs.contains(message.id) && (q.isEmpty || hasText)
        }
    }
}

enum MessageRecentTokenStore {
    static let key = "messages.recentTokens.v1"
    static let limit = 12

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        Array((defaults.stringArray(forKey: key) ?? []).prefix(limit))
    }

    static let reactionKey = "messages.lastReaction.v1"

    static func remember(_ token: String, _ defaults: UserDefaults = .standard) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = load(defaults).filter { $0 != trimmed }
        items.insert(trimmed, at: 0)
        defaults.set(Array(items.prefix(limit)), forKey: key)
    }

    static func lastReaction(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: reactionKey)
    }

    static func rememberReaction(_ emoji: String, _ defaults: UserDefaults = .standard) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: reactionKey)
        remember(trimmed, defaults)
    }
}

extension MessagingStore {
    func freshClientMessageId() -> String? {
        guard capabilities.idempotentSend else { return nil }
        return UUID().uuidString
    }

    func confirmedWithDelivery(_ confirmed: Message, fallbackReply: MessageReplyPreview?) -> Message {
        var message = confirmed
        if message.delivery == .unknown { message.delivery = .sent }
        if message.replyTo == nil { message.replyTo = fallbackReply }
        return message
    }

    // MARK: Privacy

    func loadPrivacyIfNeeded() async {
        guard capabilities.privacyControls else { return }
        if privacyState == .loaded || privacyState == .loading { return }
        privacyState = .loading
        do {
            privacy = try await repository.privacy()
            privacyState = .loaded
        } catch {
            privacyState = .failed("Couldn't load chat privacy.")
        }
    }

    func setReadReceipts(_ on: Bool) async { await patchPrivacy(["readReceipts": .bool(on)]) }
    func setTypingIndicators(_ on: Bool) async { await patchPrivacy(["typingIndicators": .bool(on)]) }
    func setPresenceVisibility(_ value: PresenceVisibility) async {
        await patchPrivacy(["presenceVisibility": .string(value.rawValue)])
    }
    func setNotificationPreview(_ value: NotificationPreviewSetting) async {
        await patchPrivacy(["notificationPreview": .string(value.rawValue)])
    }

    private func patchPrivacy(_ fields: [String: JSONValue]) async {
        guard capabilities.privacyControls else { return }
        var body = fields
        if privacy.version > 0 { body["version"] = .number(Double(privacy.version)) }
        do {
            privacy = try await repository.updatePrivacy(body)
            privacyState = .loaded
            HapticEngine.shared.play(.confirmation)
        } catch APIError.rejected(409, _) {
            if let fresh = try? await repository.privacy() { privacy = fresh }
            actionError = "Chat privacy was updated on another device. Try again."
        } catch {
            actionError = "Couldn't update chat privacy."
        }
    }

    // MARK: Groups

    func createGroup(title: String, description: String?, handles: [String]) async -> Conversation? {
        guard capabilities.groups else {
            actionError = "Group chats aren't available on this server yet."
            return nil
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        do {
            let conversation = try await repository.createGroup(title: clean, description: description, handles: handles)
            conversations.removeAll { $0.id == conversation.id }
            conversations.insert(conversation, at: 0)
            conversationState = .loaded
            HapticEngine.shared.play(.success)
            return conversation
        } catch {
            actionError = (error as? APIError)?.userFacingMessage ?? "Couldn't create the group."
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    func loadGroup(_ id: ConversationID) async {
        guard capabilities.groups else { return }
        do {
            groups[id] = try await repository.group(id)
        } catch {
            actionError = "Couldn't load group info."
        }
    }

    func renameGroup(_ id: ConversationID, title: String, description: String?) async -> Bool {
        guard capabilities.groups, groups[id]?.canAdmin == true else { return false }
        do {
            groups[id] = try await repository.updateGroup(id, title: title, description: description)
            if let index = conversations.firstIndex(where: { $0.id == id }), var summary = conversations[index].group {
                summary.title = title
                summary.description = description
                conversations[index].group = summary
            }
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = "Couldn't update this group."
            return false
        }
    }

    func addGroupMembers(_ id: ConversationID, handles: [String]) async -> Bool {
        guard capabilities.groups, groups[id]?.canAdmin == true else { return false }
        do {
            let result = try await repository.addGroupMembers(id, handles: handles)
            groups[id] = result.group
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.userFacingMessage ?? "Couldn't add people to this group."
            return false
        }
    }

    func removeGroupMember(_ id: ConversationID, actor: String) async -> Bool {
        guard capabilities.groups, groups[id]?.canAdmin == true else { return false }
        do {
            try await repository.removeGroupMember(id, actor: actor)
            await loadGroup(id)
            HapticEngine.shared.play(.confirmation)
            return true
        } catch {
            actionError = "Couldn't remove this person."
            return false
        }
    }

    func setGroupRole(_ id: ConversationID, actor: String, role: GroupRole) async -> Bool {
        guard capabilities.groups, groups[id]?.isOwner == true else { return false }
        do {
            groups[id] = try await repository.setGroupRole(id, actor: actor, role: role)
            HapticEngine.shared.play(.success)
            return true
        } catch {
            actionError = "Couldn't change this role."
            return false
        }
    }

    func leaveGroup(_ id: ConversationID) async -> Bool {
        guard capabilities.groups else { return false }
        do {
            try await repository.leaveGroup(id)
            groups[id] = nil
            conversations.removeAll { $0.id == id }
            threads[id] = nil
            HapticEngine.shared.play(.confirmation)
            return true
        } catch {
            actionError = "Couldn't leave this group."
            return false
        }
    }

    func mentionCandidates(in id: ConversationID, query: String?) -> [ModulaComposerMention] {
        guard capabilities.mentions else { return [] }
        let people: [ConversationParticipant]
        if let members = groups[id]?.members {
            people = members.filter { !$0.isMe && $0.state == "active" && !$0.blocked }.map(\.participant)
        } else if let conversation = conversation(id: id) {
            people = conversation.participants
        } else {
            return []
        }
        let needle = (query ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        return people
            .filter { needle.isEmpty || $0.handle.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle) }
            .prefix(8)
            .map { ModulaComposerMention(id: $0.id, handle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL) }
    }

    // MARK: Reactors and seen-by

    func loadReactionDetails(_ message: Message) async {
        guard capabilities.reactionDetails, !message.id.hasPrefix("local-") else { return }
        do {
            reactionDetails[message.id] = try await repository.reactionDetails(conversation: message.conversationID, message: message.id)
        } catch {
            actionError = "Couldn't load who reacted."
        }
    }

    func loadReceipts(_ message: Message) async {
        guard capabilities.groupReadReceipts, message.isOwn, !message.id.hasPrefix("local-") else { return }
        do {
            receiptsByMessage[message.id] = try await repository.receipts(conversation: message.conversationID, message: message.id)
        } catch APIError.rejected(403, _) {
            receiptsByMessage[message.id] = MessageReceipts(readBy: [], notYet: [], hiddenCount: 0, receiptsDisabled: true)
        } catch {
            actionError = "Couldn't load who has read this."
        }
    }

    // MARK: History search

    func searchHistory(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        historyQuery = q
        guard capabilities.historySearch else {
            historyHits = []; historyHasMore = false; historyCursor = nil; historyState = .idle
            return
        }
        guard q.count >= 2 else {
            historyHits = []; historyHasMore = false; historyCursor = nil; historyState = .idle
            return
        }
        historyState = .loading
        do {
            let page = try await repository.searchMessages(query: q, conversationID: nil, cursor: nil)
            historyHits = page.items
            historyCursor = page.nextCursor
            historyHasMore = page.hasMore
            historyState = .loaded
        } catch {
            historyState = .failed("Couldn't search message history.")
        }
    }

    func loadMoreHistory() async {
        guard capabilities.historySearch, historyHasMore, let cursor = historyCursor, historyState != .loading else { return }
        historyState = .loading
        do {
            let page = try await repository.searchMessages(query: historyQuery, conversationID: nil, cursor: cursor)
            let seen = Set(historyHits.map(\.id))
            historyHits.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            historyCursor = page.nextCursor
            historyHasMore = page.hasMore
            historyState = .loaded
        } catch {
            historyState = .loaded
        }
    }

    // MARK: Presence

    func presence(for actorID: String) -> PresenceItem? { presenceByActor[actorID] }

    func refreshPresence(for actorIDs: [String]) async {
        guard capabilities.presence, capabilities.privacyControls == false || privacy.presenceVisibility != .nobody else {
            return
        }
        let ids = Array(Set(actorIDs.filter { !$0.isEmpty })).prefix(50)
        guard !ids.isEmpty else { return }
        if let items = try? await repository.presence(actorIDs: Array(ids)) {
            for item in items { presenceByActor[item.actorId] = item }
        }
    }

    // MARK: Voice notes

    /// Upload a recorded note through the existing attachment pipeline, then send `kind: "voice"`.
    /// Photo/video sending is never enabled here.
    func sendVoice(_ note: ModulaVoiceNote, conversation id: ConversationID, viewer: ConversationParticipant) async -> Message? {
        guard capabilities.voiceNotes, capabilities.send else {
            actionError = "Voice notes aren't available on this server yet."
            return nil
        }
        let maxMs = capabilities.voiceNoteMaxMs > 0 ? capabilities.voiceNoteMaxMs : 900_000
        guard note.durationMs > 0, note.durationMs <= maxMs else {
            actionError = "That voice note is too long."
            return nil
        }
        let allowed = capabilities.voiceNoteMimeTypes
        let mime = "audio/mp4"
        if !allowed.isEmpty, !allowed.contains(mime) {
            actionError = "This voice note format isn't supported."
            return nil
        }
        let localID = "local-\(UUID().uuidString)"
        let waveform = note.waveform.map { min(1, max(0, Double($0) / 100)) }
        let optimistic = Message(
            id: localID, conversationID: id, sender: viewer, body: .text(""),
            sentAt: Date(), delivery: .sending, isOwn: true, localDraft: nil,
            kind: .voice,
            attachments: [MessageAttachment(id: localID, kind: .audio, mimeType: mime, byteSize: 0, durationMs: note.durationMs, waveform: waveform, width: nil, height: nil, url: note.fileURL)]
        )
        var items = threads[id] ?? []
        items.append(optimistic)
        threads[id] = items
        sendingIDs.insert(localID)
        do {
            let data = try Data(contentsOf: note.fileURL)
            let prepared = PreparedMedia(id: localID, kind: .audio, data: data, mimeType: mime, filename: "voice.m4a", altText: "Voice note")
            let uploaded = try await GreenfieldMediaUploader(client: client).upload(prepared, progress: { _ in }, sessionCreated: { _, _ in })
            let confirmed = try await repository.send(
                conversation: id,
                message: MessageDraft(
                    conversationID: id,
                    text: "",
                    kind: .voice,
                    clientMessageId: freshClientMessageId(),
                    attachments: [MessageDraftAttachment(attachmentId: uploaded.remoteID, durationMs: note.durationMs, waveform: waveform)]
                )
            )
            replace(localID: localID, in: id, with: confirmedWithDelivery(confirmed, fallbackReply: nil))
            sendingIDs.remove(localID)
            HapticEngine.shared.play(.success)
            NotificationCenter.default.post(name: .modulaPushMoment, object: PushPrePromptMoment.messageSent.rawValue)
            return threads[id]?.first(where: { $0.id == confirmed.id })
        } catch {
            markFailed(localID: localID, in: id)
            sendingIDs.remove(localID)
            actionError = "Couldn't send voice note."
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    // MARK: Realtime

    func startRealtimeIfNeeded() {
        guard capabilities.realtime, let path = capabilities.realtimeSocketPath, !path.isEmpty else {
            startPresenceHeartbeatFallback()
            return
        }
        if realtime != nil { return }
        let client = MessagingRealtimeClient(client: self.client, path: path, heartbeatMs: capabilities.realtimeHeartbeatMs)
        client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleRealtime(event) }
        }
        realtime = client
        client.start()
    }

    func stopRealtime() {
        realtime?.stop()
        realtime = nil
        realtimeConnected = false
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = nil
    }

    private func startPresenceHeartbeatFallback() {
        guard capabilities.presence else { return }
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = try? await self?.repository.presenceHeartbeat()
                try? await Task.sleep(for: .seconds(25))
            }
        }
    }

    private func handleRealtime(_ event: MessagingRealtimeClient.Event) {
        switch event {
        case .hello:
            realtimeConnected = true
            presenceHeartbeatTask?.cancel()
            presenceHeartbeatTask = nil
        case .disconnected:
            realtimeConnected = false
            startPresenceHeartbeatFallback()
        case .messageCreated(let conversation, _, _, _), .messageUpdated(let conversation, _), .messageDeleted(let conversation, _):
            Task { _ = await pollThread(conversation); await pollInbox() }
        case .reactionChanged(let conversation, let message):
            if let item = messages(for: conversation).first(where: { $0.id == message }) {
                Task { await loadReactionDetails(item); _ = await pollThread(conversation) }
            } else {
                Task { _ = await pollThread(conversation) }
            }
        case .typing(let conversation, let actor, let expiresAt):
            if let expiry = expiresAt, expiry < Date() { return }
            let person = self.conversation(id: conversation)?.participants.first(where: { $0.id == actor })
                ?? groups[conversation]?.members.first(where: { $0.participant.id == actor })?.participant
            if let person {
                var people = typingPeople[conversation] ?? []
                if !people.contains(where: { $0.id == person.id }) { people.append(person) }
                typingPeople[conversation] = people
            }
        case .read(let conversation, _, _):
            Task { _ = await pollThread(conversation) }
        case .conversationUpdated(let conversation, _):
            Task {
                await pollInbox()
                if capabilities.groups { await loadGroup(conversation) }
            }
        case .presence(let item):
            presenceByActor[item.actorId] = item
        case .callUpdated(let update):
            CallManager.shared.handleRealtime(update)
        case .error:
            break
        }
    }
}
