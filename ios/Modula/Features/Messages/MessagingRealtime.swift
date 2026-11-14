import Foundation

/// Authenticated messaging socket (`GET /v1/messaging/socket`). The bearer travels in the
/// request header via `GreenfieldClient.webSocketRequest`. Events carry ids only; the store
/// refetches over REST. Polling stays as the fallback when this is not connected.
@MainActor
final class MessagingRealtimeClient {
    enum Event: Sendable {
        case hello(actorId: String, heartbeatMs: Int)
        case messageCreated(conversationID: ConversationID, messageID: MessageID, senderID: String, kind: MessageKind)
        case messageUpdated(conversationID: ConversationID, messageID: MessageID)
        case messageDeleted(conversationID: ConversationID, messageID: MessageID)
        case reactionChanged(conversationID: ConversationID, messageID: MessageID)
        case typing(conversationID: ConversationID, actorID: String, expiresAt: Date?)
        case read(conversationID: ConversationID, actorID: String, readAt: Date?)
        case conversationUpdated(conversationID: ConversationID, reason: String)
        case presence(PresenceItem)
        case error(String)
        case disconnected
    }

    private let client: GreenfieldClient
    private let path: String
    private var task: URLSessionWebSocketTask?
    private var pump: Task<Void, Never>?
    private var heart: Task<Void, Never>?
    private var heartbeatMs: Int
    private var session: URLSession?
    var onEvent: ((Event) -> Void)?
    private(set) var isConnected = false

    init(client: GreenfieldClient, path: String, heartbeatMs: Int) {
        self.client = client
        self.path = path
        self.heartbeatMs = max(heartbeatMs, 10_000)
    }

    func start() {
        stop()
        pump = Task { [weak self] in await self?.run() }
    }

    func stop() {
        pump?.cancel(); pump = nil
        heart?.cancel(); heart = nil
        task?.cancel(); task = nil
        isConnected = false
    }

    func sendTyping(conversationID: ConversationID) {
        send(object: ["type": .string("typing"), "conversationId": .string(conversationID)])
    }

    private func run() async {
        while !Task.isCancelled {
            do {
                let request = try await client.webSocketRequest(path: path)
                let session = URLSession(configuration: .default)
                self.session = session
                let socket = session.webSocketTask(with: request)
                task = socket
                socket.resume()
                await listen(socket)
            } catch {
                isConnected = false
                onEvent?(.disconnected)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func listen(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled, task === socket {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                handle(data)
            } catch {
                break
            }
        }
        if task === socket {
            isConnected = false
            heart?.cancel(); heart = nil
            onEvent?(.disconnected)
        }
    }

    private func handle(_ data: Data) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        let type = value["type"]?.string ?? ""
        switch type {
        case "hello":
            isConnected = true
            if let ms = value["heartbeatMs"]?.int, ms > 0 { heartbeatMs = ms }
            startHeartbeat()
            onEvent?(.hello(actorId: value["actorId"]?.string ?? "", heartbeatMs: heartbeatMs))
        case "pong":
            break
        case "message.created":
            guard let conversation = value["conversationId"]?.string, let message = value["messageId"]?.string else { return }
            onEvent?(.messageCreated(conversationID: conversation, messageID: message, senderID: value["senderId"]?.string ?? "", kind: MessageKind(parsing: value["kind"]?.string)))
        case "message.updated":
            guard let conversation = value["conversationId"]?.string, let message = value["messageId"]?.string else { return }
            onEvent?(.messageUpdated(conversationID: conversation, messageID: message))
        case "message.deleted":
            guard let conversation = value["conversationId"]?.string, let message = value["messageId"]?.string else { return }
            onEvent?(.messageDeleted(conversationID: conversation, messageID: message))
        case "reaction.changed":
            guard let conversation = value["conversationId"]?.string, let message = value["messageId"]?.string else { return }
            onEvent?(.reactionChanged(conversationID: conversation, messageID: message))
        case "typing":
            guard let conversation = value["conversationId"]?.string, let actor = value["actorId"]?.string else { return }
            onEvent?(.typing(conversationID: conversation, actorID: actor, expiresAt: MessagingPayloadDecoder.decodeDate(value["expiresAt"]?.string)))
        case "read":
            guard let conversation = value["conversationId"]?.string, let actor = value["actorId"]?.string else { return }
            onEvent?(.read(conversationID: conversation, actorID: actor, readAt: MessagingPayloadDecoder.decodeDate(value["readAt"]?.string)))
        case "conversation.updated":
            guard let conversation = value["conversationId"]?.string else { return }
            onEvent?(.conversationUpdated(conversationID: conversation, reason: value["reason"]?.string ?? ""))
        case "presence":
            guard let actor = value["actorId"]?.string else { return }
            onEvent?(.presence(PresenceItem(actorId: actor, status: PresenceStatus(parsing: value["status"]?.string), lastActiveAt: MessagingPayloadDecoder.decodeDate(value["lastActiveAt"]?.string))))
        case "error":
            onEvent?(.error(value["reason"]?.string ?? "socket"))
        default:
            break
        }
    }

    private func startHeartbeat() {
        heart?.cancel()
        let interval = heartbeatMs
        heart = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(interval))
                self?.send(object: ["type": .string("ping")])
            }
        }
    }

    private func send(object: [String: JSONValue]) {
        guard let task, let data = try? JSONEncoder().encode(JSONValue.object(object)),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }
}

enum MessagingV3FlagStore {
    static let key = "messages.v3.flags.v1"

    static func save(_ caps: MessagingBackendCapabilities) {
        UserDefaults.standard.set([
            "idempotentSend": caps.idempotentSend,
            "notificationMarkRead": caps.notificationMarkRead,
            "notificationReply": caps.notificationReply,
        ] as [String: Bool], forKey: key)
    }

    static var idempotentSend: Bool { flag("idempotentSend") }
    static var notificationMarkRead: Bool { flag("notificationMarkRead") }

    private static func flag(_ name: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool])?[name] ?? false
    }
}
