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
        if cursor == nil { conversationMemory["root"] = page }
        return page
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
            body: .object(["text": .string(message.text)])
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

    private func log(op: String, id: String?, started: Date) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if let id {
            ModulaLog.network.debug("messaging \(op, privacy: .public) id=\(id, privacy: .public) \(ms, privacy: .public)ms")
        } else {
            ModulaLog.network.debug("messaging \(op, privacy: .public) \(ms, privacy: .public)ms")
        }
    }
}
