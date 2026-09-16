import Foundation

protocol InMailRepository: Sendable {
    func threads(cursor: String?) async throws -> InMailPage
    func thread(_ id: InMailThreadID) async throws -> (InMailThread, [InMailMessage])
    func send(_ draft: InMailDraft) async throws -> InMailThread
    func reply(thread: InMailThreadID, body: String) async throws -> InMailMessage
}

actor GreenfieldInMailRepository: InMailRepository {
    private let client: GreenfieldClient
    let capabilities: InMailBackendCapabilities
    private var memory: InMailPage?

    init(client: GreenfieldClient, capabilities: InMailBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func cached() -> InMailPage? { memory }

    func threads(cursor: String?) async throws -> InMailPage {
        guard capabilities.list else { throw APIError.unavailable("Couldn't load messages.") }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: InMailBackendCapabilities.Paths.inbox(cursor: cursor)
        )
        log(op: "list", id: nil, started: started)
        let page = InMailPayloadDecoder.page(from: value)
        if cursor == nil { memory = page }
        return page
    }

    func thread(_ id: InMailThreadID) async throws -> (InMailThread, [InMailMessage]) {
        guard capabilities.thread else { throw APIError.unavailable("Couldn't load messages.") }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: InMailBackendCapabilities.Paths.thread(id)
        )
        log(op: "thread", id: id, started: started)
        guard let thread = InMailPayloadDecoder.thread(value["thread"] ?? value) else {
            throw APIError.invalidResponse
        }
        return (thread, InMailPayloadDecoder.messages(from: value, viewerID: nil))
    }

    func send(_ draft: InMailDraft) async throws -> InMailThread {
        guard capabilities.send else { throw APIError.unavailable("Couldn't send message.") }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: InMailBackendCapabilities.Paths.compose,
            body: .object([
                "to": .string(draft.toHandle),
                "subject": .string(draft.subject),
                "body": .string(draft.body)
            ])
        )
        log(op: "send", id: nil, started: started)
        if let thread = InMailPayloadDecoder.thread(value["thread"] ?? value) { return thread }
        throw APIError.invalidResponse
    }

    func reply(thread: InMailThreadID, body: String) async throws -> InMailMessage {
        guard capabilities.reply else { throw APIError.unavailable("Couldn't send message.") }
        let started = Date()
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: InMailBackendCapabilities.Paths.reply(thread),
            body: .object(["body": .string(body)])
        )
        log(op: "reply", id: thread, started: started)
        if let message = InMailPayloadDecoder.message(value["message"] ?? value, viewerID: nil) { return message }
        throw APIError.invalidResponse
    }

    private func log(op: String, id: String?, started: Date) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if let id {
            ModulaLog.network.debug("in-mail \(op, privacy: .public) id=\(id, privacy: .public) \(ms, privacy: .public)ms")
        } else {
            ModulaLog.network.debug("in-mail \(op, privacy: .public) \(ms, privacy: .public)ms")
        }
    }
}
