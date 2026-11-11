import Foundation

protocol MessagingRepository: Sendable {
    func conversations(cursor: String?) async throws -> ConversationPage
    func conversation(_ id: ConversationID, cursor: String?) async throws -> MessagePage
    func send(conversation: ConversationID, message: MessageDraft) async throws -> Message
    func startConversation(handle: String, text: String?) async throws -> Conversation
    func markRead(conversation: ConversationID) async throws
    func messageRequests() async throws -> [MessageRequest]
    func acceptRequest(id: String) async throws -> Conversation
    func declineRequest(id: String) async throws
    func unreadSummary() async throws -> Int?
}

actor GreenfieldMessagingRepository: MessagingRepository {
    private let client: GreenfieldClient
    let capabilities: MessagingBackendCapabilities
    private var conversationMemory: [ConversationID: ConversationPage] = [:]
    private var messageMemory: [ConversationID: MessagePage] = [:]

    init(client: GreenfieldClient, capabilities: MessagingBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func cachedConversations() -> ConversationPage? { conversationMemory["root"] }
    func cachedMessages(for id: ConversationID) -> MessagePage? { messageMemory[id] }

    func conversations(cursor: String?) async throws -> ConversationPage {
        guard capabilities.listConversations else {
            throw APIError.unavailable("Couldn't load messages.")
        }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: MessagingBackendCapabilities.Paths.conversations(cursor: cursor)
        )
        log(op: "conversations", id: nil, started: started)
        let page = MessagingPayloadDecoder.conversationPage(from: value)
        if cursor == nil {
            conversationMemory["root"] = page
            ModulaWarmCache.store(value, name: "inbox", account: await client.currentAccountID())
        }
        return page
    }

    /// Inbox first page saved by the previous launch (this account only).
    func warmConversations() async -> ConversationPage? {
        if let cached = conversationMemory["root"] { return cached }
        guard let value = await ModulaWarmCache.load(name: "inbox", account: await client.currentAccountID()) else { return nil }
        let page = MessagingPayloadDecoder.conversationPage(from: value)
        return page.items.isEmpty ? nil : page
    }

    func conversation(_ id: ConversationID, cursor: String?) async throws -> MessagePage {
        guard capabilities.listMessages else {
            throw APIError.unavailable("Couldn't load messages.")
        }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: MessagingBackendCapabilities.Paths.messages(conversationID: id, cursor: cursor)
        )
        log(op: "messages", id: id, started: started)
        let page = MessagingPayloadDecoder.messagePage(from: value, conversationID: id, viewerID: nil)
        if cursor == nil { messageMemory[id] = page }
        return page
    }

    func send(conversation: ConversationID, message: MessageDraft) async throws -> Message {
        guard capabilities.send else {
            throw APIError.unavailable("Couldn't send message.")
        }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: MessagingBackendCapabilities.Paths.send(conversationID: conversation),
            body: .object(Self.sendBody(message))
        )
        log(op: "send", id: conversation, started: started)
        let payload = value["message"] ?? value
        if let decoded = MessagingPayloadDecoder.message(payload, conversationID: conversation, viewerID: nil) {
            return decoded
        }
        throw APIError.invalidResponse
    }

    /// Starts (or reuses) the direct conversation with `handle`. When `text` is set the server
    /// sends it as the first message in the same request.
    func startConversation(handle: String, text: String?) async throws -> Conversation {
        guard capabilities.startConversation else {
            throw APIError.unavailable("Couldn't start this chat.")
        }
        let started = Date()
        var body: [String: JSONValue] = ["handle": .string(handle)]
        if let text, !text.isEmpty { body["text"] = .string(text) }
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: MessagingBackendCapabilities.Paths.startConversation,
            body: .object(body)
        )
        log(op: "start", id: nil, started: started)
        if let conversation = MessagingPayloadDecoder.conversation(value["conversation"] ?? value) {
            conversationMemory["root"] = nil
            return conversation
        }
        throw APIError.invalidResponse
    }

    func markRead(conversation: ConversationID) async throws {
        guard capabilities.markRead else { return }
        let started = Date()
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: MessagingBackendCapabilities.Paths.read(conversationID: conversation),
            body: .object([:])
        )
        log(op: "read", id: conversation, started: started)
    }

    func messageRequests() async throws -> [MessageRequest] {
        guard capabilities.messageRequests else {
            throw APIError.unavailable("Couldn't load messages.")
        }
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.requests)
        return (value["items"]?.array ?? value.array ?? []).compactMap(MessagingPayloadDecoder.request)
    }

    func acceptRequest(id: String) async throws -> Conversation {
        guard capabilities.acceptRequest else {
            throw APIError.unavailable("Couldn't update this request.")
        }
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: MessagingBackendCapabilities.Paths.acceptRequest(id: id),
            body: .object([:])
        )
        if let conversation = MessagingPayloadDecoder.conversation(value["conversation"] ?? value) {
            return conversation
        }
        throw APIError.invalidResponse
    }

    func declineRequest(id: String) async throws {
        guard capabilities.declineRequest else {
            throw APIError.unavailable("Couldn't update this request.")
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: MessagingBackendCapabilities.Paths.declineRequest(id: id),
            body: .object([:])
        )
    }

    func unreadSummary() async throws -> Int? {
        guard capabilities.unreadSummary else { return nil }
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: MessagingBackendCapabilities.Paths.unreadSummary
        )
        return value["unreadCount"]?.int ?? value["count"]?.int
    }

    // MARK: Messaging v2

    /// Is the messaging v2 API deployed? A made-up chat id gets the API's own NOT_FOUND envelope when the
    /// route exists; an unknown route gets a non-envelope 404 (decoded as invalidResponse / REQUEST_FAILED).
    func probeV2() async -> Bool {
        do {
            let _: JSONValue = try await client.authenticatedJSON("GET", path: "/v1/conversations/modula-route-probe/typing")
            return true
        } catch APIError.rejected(404, "NOT_FOUND") {
            return true
        } catch APIError.rejected(403, _) {
            return true
        } catch {
            return false
        }
    }

    private static func esc(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func messagePath(_ conversation: ConversationID, _ message: MessageID) -> String {
        "/v1/conversations/\(esc(conversation))/messages/\(esc(message))"
    }

    func react(conversation: ConversationID, message: MessageID, emoji: String, on: Bool) async throws -> [MessageReaction] {
        let base = Self.messagePath(conversation, message) + "/reactions"
        let value: JSONValue
        if on {
            value = try await client.authenticatedJSON("PUT", path: base, body: .object(["emoji": .string(emoji)]))
        } else {
            let q = emoji.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? emoji
            value = try await client.authenticatedJSON("DELETE", path: base + "?emoji=\(q)", body: nil)
        }
        return (value["reactions"]?.array ?? []).compactMap { r in
            r["emoji"]?.string.map { MessageReaction(emoji: $0, count: r["count"]?.int ?? 1, mine: r["mine"]?.bool ?? false) }
        }
    }

    func edit(conversation: ConversationID, message: MessageID, text: String) async throws -> Message {
        let value: JSONValue = try await client.authenticatedJSON(
            "PATCH", path: Self.messagePath(conversation, message), body: .object(["text": .string(text)])
        )
        guard let decoded = MessagingPayloadDecoder.message(value["message"] ?? value, conversationID: conversation, viewerID: nil) else {
            throw APIError.invalidResponse
        }
        return decoded
    }

    func unsend(conversation: ConversationID, message: MessageID) async throws {
        let _: JSONValue = try await client.authenticatedJSON("DELETE", path: Self.messagePath(conversation, message), body: nil)
    }

    func pingTyping(conversation: ConversationID) async throws {
        let _: JSONValue = try await client.authenticatedJSON("POST", path: "/v1/conversations/\(Self.esc(conversation))/typing", body: .object([:]))
    }

    func typing(conversation: ConversationID) async throws -> [ConversationParticipant] {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: "/v1/conversations/\(Self.esc(conversation))/typing")
        return (value["typing"]?.array ?? []).compactMap(MessagingPayloadDecoder.participant)
    }

    func setMuted(conversation: ConversationID, muted: Bool) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST", path: "/v1/conversations/\(Self.esc(conversation))/mute", body: .object(["muted": .bool(muted)])
        )
    }

    func setArchived(conversation: ConversationID, archived: Bool) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST", path: "/v1/conversations/\(Self.esc(conversation))/archive", body: .object(["archived": .bool(archived)])
        )
    }

    /// Live routes (already deployed): block a profile and report a message or profile.
    func block(profile: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON("POST", path: "/v1/profiles/\(Self.esc(profile))/block", body: .object([:]))
    }

    func report(targetType: String, targetID: String, category: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST", path: "/v1/reports",
            body: .object(["targetType": .string(targetType), "targetId": .string(targetID), "category": .string(category)])
        )
    }


    /// Probe messaging v3 (`GET /v1/messaging/capabilities`). Nil means the route is not deployed yet
    /// (current production, no migration 089). A 401 is not treated as "missing".
    func probeV3() async -> MessagingBackendCapabilities? {
        do {
            let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.capabilities)
            return MessagingPayloadDecoder.capabilitiesV3(from: value)
        } catch {
            return nil
        }
    }

    static func sendBody(_ message: MessageDraft) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["text": .string(message.text)]
        if let reply = message.replyToID { body["replyToMessageId"] = .string(reply) }
        if let client = message.clientMessageId, (8...64).contains(client.count) {
            body["clientMessageId"] = .string(client)
        }
        if message.kind != .text {
            body["kind"] = .string(message.kind.rawValue)
        }
        if !message.attachments.isEmpty {
            body["attachments"] = .array(message.attachments.map { item in
                var object: [String: JSONValue] = [
                    "attachmentId": .string(item.attachmentId),
                    "durationMs": .number(Double(item.durationMs)),
                ]
                if !item.waveform.isEmpty {
                    object["waveform"] = .array(item.waveform.prefix(128).map { .number(min(1, max(0, $0))) })
                }
                return .object(object)
            })
        }
        return body
    }

    func privacy() async throws -> MessagingPrivacy {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.privacy)
        return MessagingPayloadDecoder.privacy(value["privacy"] ?? value)
    }

    func updatePrivacy(_ patch: [String: JSONValue]) async throws -> MessagingPrivacy {
        let value: JSONValue = try await client.authenticatedJSON("PATCH", path: MessagingBackendCapabilities.Paths.privacy, body: .object(patch))
        return MessagingPayloadDecoder.privacy(value["privacy"] ?? value)
    }

    func createGroup(title: String, description: String?, handles: [String]) async throws -> Conversation {
        var body: [String: JSONValue] = ["title": .string(title), "handles": .array(handles.map { .string($0) })]
        if let description, !description.isEmpty { body["description"] = .string(description) }
        let value: JSONValue = try await client.authenticatedJSON("POST", path: MessagingBackendCapabilities.Paths.groups, body: .object(body))
        if let conversation = MessagingPayloadDecoder.conversation(value["conversation"] ?? value) {
            return conversation
        }
        throw APIError.invalidResponse
    }

    func group(_ id: ConversationID) async throws -> GroupDetail {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.group(id))
        if let detail = MessagingPayloadDecoder.groupDetail(value["group"] ?? value) { return detail }
        throw APIError.invalidResponse
    }

    func updateGroup(_ id: ConversationID, title: String?, description: String?) async throws -> GroupDetail {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let description { body["description"] = .string(description) }
        let value: JSONValue = try await client.authenticatedJSON("PATCH", path: MessagingBackendCapabilities.Paths.group(id), body: .object(body))
        if let detail = MessagingPayloadDecoder.groupDetail(value["group"] ?? value) { return detail }
        throw APIError.invalidResponse
    }

    func addGroupMembers(_ id: ConversationID, handles: [String]) async throws -> (added: [String], group: GroupDetail) {
        let value: JSONValue = try await client.authenticatedJSON(
            "POST", path: MessagingBackendCapabilities.Paths.groupMembers(id),
            body: .object(["handles": .array(handles.map { .string($0) })])
        )
        guard let group = MessagingPayloadDecoder.groupDetail(value["group"] ?? value) else { throw APIError.invalidResponse }
        let added = (value["added"]?.array ?? []).compactMap(\.string)
        return (added, group)
    }

    func removeGroupMember(_ id: ConversationID, actor: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON("DELETE", path: MessagingBackendCapabilities.Paths.groupMember(id, actor: actor), body: nil)
    }

    func setGroupRole(_ id: ConversationID, actor: String, role: GroupRole) async throws -> GroupDetail {
        let value: JSONValue = try await client.authenticatedJSON(
            "POST", path: MessagingBackendCapabilities.Paths.groupMemberRole(id, actor: actor),
            body: .object(["role": .string(role.rawValue)])
        )
        if let group = MessagingPayloadDecoder.groupDetail(value["group"] ?? value) { return group }
        throw APIError.invalidResponse
    }

    func leaveGroup(_ id: ConversationID) async throws {
        let _: JSONValue = try await client.authenticatedJSON("POST", path: MessagingBackendCapabilities.Paths.groupLeave(id), body: .object([:]))
    }

    func reactionDetails(conversation: ConversationID, message: MessageID) async throws -> [MessageReactionDetail] {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.reactions(conversation, message))
        return MessagingPayloadDecoder.reactionDetails(value)
    }

    func receipts(conversation: ConversationID, message: MessageID) async throws -> MessageReceipts {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.receipts(conversation, message))
        return MessagingPayloadDecoder.receipts(value)
    }

    func searchMessages(query: String, conversationID: ConversationID?, cursor: String?, limit: Int = 30) async throws -> HistorySearchPage {
        var path = MessagingBackendCapabilities.Paths.historySearch + "?limit=\(min(50, max(1, limit)))"
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(encoded)"
        }
        if let conversationID, let encoded = conversationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&conversationId=\(encoded)"
        }
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        let value: JSONValue = try await client.authenticatedJSON("GET", path: path)
        return MessagingPayloadDecoder.searchPage(from: value)
    }

    func presenceHeartbeat() async throws -> Int {
        let value: JSONValue = try await client.authenticatedJSON("POST", path: MessagingBackendCapabilities.Paths.presenceHeartbeat, body: .object([:]))
        return value["onlineWindowMs"]?.int ?? 70_000
    }

    func presence(actorIDs: [String]) async throws -> [PresenceItem] {
        let clipped = Array(actorIDs.prefix(50))
        guard !clipped.isEmpty else { return [] }
        let query = clipped.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }.joined(separator: ",")
        let value: JSONValue = try await client.authenticatedJSON("GET", path: MessagingBackendCapabilities.Paths.presence + "?actorIds=\(query)")
        return MessagingPayloadDecoder.presenceItems(value)
    }

    private func log(op: String, id: String?, started: Date) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if let id {
            ModulaLog.network.debug("messaging \(op, privacy: .public) id=\(id, privacy: .public) \(ms, privacy: .public)ms")
        } else {
            ModulaLog.network.debug("messaging \(op, privacy: .public) \(ms, privacy: .public)ms")
        }
    }
}
