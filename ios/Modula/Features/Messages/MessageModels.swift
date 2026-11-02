import Foundation

typealias ConversationID = String
typealias MessageID = String

enum ConversationKind: String, Hashable, Sendable {
    case direct
    case group
    case request
    case unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "direct", "dm", "one_to_one", "1:1": self = .direct
        case "group": self = .group
        case "request", "pending": self = .request
        default: self = .unknown
        }
    }
}

struct ConversationParticipant: Hashable, Sendable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: URL?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var asAuthor: SocialAuthor {
        SocialAuthor(id: id, handle: handle, displayName: displayName, avatarURL: avatarURL)
    }
}

struct MessagePreview: Hashable, Sendable {
    let id: MessageID
    let body: String
    let sentAt: Date
    let senderID: String?
}

enum MessageDeliveryState: String, Hashable, Sendable {
    case sending
    case sent
    case failed
    case delivered
    case read
    case unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "sending", "pending": self = .sending
        case "sent": self = .sent
        case "failed": self = .failed
        case "delivered": self = .delivered
        case "read", "seen": self = .read
        default: self = .unknown
        }
    }
}

enum MessageBody: Hashable, Sendable {
    case text(String)
    case unsupported(String)

    var text: String {
        switch self {
        case .text(let value): value
        case .unsupported(let value): value
        }
    }
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: ConversationID
    let kind: ConversationKind
    let participants: [ConversationParticipant]
    let lastMessage: MessagePreview?
    let unreadCount: Int
    let updatedAt: Date
    let titleOverride: String?

    var title: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        let names = participants.map(\.displayName).filter { !$0.isEmpty }
        if names.isEmpty { return "Conversation" }
        return names.joined(separator: ", ")
    }

    var handleLabel: String? {
        participants.first.flatMap { $0.handle.isEmpty ? nil : "@\($0.handle)" }
    }

    var isUnread: Bool { unreadCount > 0 }
}

struct Message: Identifiable, Hashable, Sendable {
    let id: MessageID
    let conversationID: ConversationID
    let sender: ConversationParticipant
    let body: MessageBody
    let sentAt: Date
    var delivery: MessageDeliveryState
    let isOwn: Bool
    var localDraft: String?

    var previewText: String { body.text }
}

struct MessageDraft: Hashable, Sendable {
    var conversationID: ConversationID
    var text: String
}

struct ConversationPage: Sendable, Equatable {
    var items: [Conversation]
    var nextCursor: String?
    var hasMore: Bool
}

struct MessagePage: Sendable, Equatable {
    var items: [Message]
    var nextCursor: String?
    var hasMore: Bool
}

struct MessageRequest: Identifiable, Hashable, Sendable {
    let id: String
    let conversationID: ConversationID?
    let sender: ConversationParticipant
    let preview: String
    let createdAt: Date
}

enum MessagingLoadState: Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case loaded
    case failed(String)
}

struct MessagingBackendCapabilities: Sendable, Equatable {
    var listConversations = false
    var listMessages = false
    var send = false
    /// `POST /v1/conversations` {handle, text?} — start (or reuse) a 1:1 chat.
    var startConversation = false
    var markRead = false
    var messageRequests = false
    var acceptRequest = false
    var declineRequest = false
    var unreadSummary = false
    var readReceipts = false
    var presence = false
    var typing = false
    var attachments = false
    var reply = false
    var edit = false
    var deleteOwn = false
    var report = false
    var mute = false
    var archive = false
    var realtime = false
    /// Client-side quote reply: quotes the message into the text (no reply-to field on the send route).
    var quoteReply = true

    /// Live on api.modula.digital since backend migration 075_greenfield_messaging.
    static let production = MessagingBackendCapabilities(
        listConversations: true,
        listMessages: true,
        send: true,
        startConversation: true,
        markRead: true,
        messageRequests: true,
        acceptRequest: true,
        declineRequest: true,
        unreadSummary: true,
        readReceipts: true
    )

    enum Paths {
        static func conversations(cursor: String?) -> String {
            var path = "/v1/conversations?limit=30"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&cursor=\(encoded)"
            }
            return path
        }

        static func messages(conversationID: String, cursor: String?) -> String {
            var path = "/v1/conversations/\(escape(conversationID))/messages?limit=40"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&cursor=\(encoded)"
            }
            return path
        }

        static func send(conversationID: String) -> String {
            "/v1/conversations/\(escape(conversationID))/messages"
        }

        static func read(conversationID: String) -> String {
            "/v1/conversations/\(escape(conversationID))/read"
        }

        static let startConversation = "/v1/conversations"
        static let requests = "/v1/message-requests"
        static func acceptRequest(id: String) -> String { "/v1/message-requests/\(escape(id))/accept" }
        static func declineRequest(id: String) -> String { "/v1/message-requests/\(escape(id))/decline" }
        static let unreadSummary = "/v1/conversations/unread"

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}

enum MessagingPayloadDecoder {
    static func conversationPage(from value: JSONValue) -> ConversationPage {
        let items = (value["items"]?.array ?? value["conversations"]?.array ?? []).compactMap(conversation)
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let hasMore = value["hasMore"]?.bool ?? value["has_more"]?.bool ?? (next != nil)
        return ConversationPage(items: items, nextCursor: next, hasMore: hasMore)
    }

    static func messagePage(from value: JSONValue, conversationID: ConversationID, viewerID: String?) -> MessagePage {
        let items = (value["items"]?.array ?? value["messages"]?.array ?? []).compactMap {
            message($0, conversationID: conversationID, viewerID: viewerID)
        }
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let hasMore = value["hasMore"]?.bool ?? value["has_more"]?.bool ?? (next != nil)
        return MessagePage(items: items, nextCursor: next, hasMore: hasMore)
    }

    static func conversation(_ value: JSONValue) -> Conversation? {
        let id = value["id"]?.string ?? value["conversationId"]?.string
        guard let id else { return nil }
        let participants = (value["participants"]?.array ?? []).compactMap(participant)
        let last = value["lastMessage"].flatMap(preview)
        let updated = decodeDate(value["updatedAt"]?.string ?? value["updated_at"]?.string)
            ?? last?.sentAt
            ?? Date()
        return Conversation(
            id: id,
            kind: ConversationKind(parsing: value["kind"]?.string ?? value["type"]?.string),
            participants: participants,
            lastMessage: last,
            unreadCount: value["unreadCount"]?.int ?? value["unread_count"]?.int ?? 0,
            updatedAt: updated,
            titleOverride: emptyToNil(value["title"]?.string ?? value["name"]?.string)
        )
    }

    static func message(_ value: JSONValue, conversationID: ConversationID, viewerID: String?) -> Message? {
        let id = value["id"]?.string ?? value["messageId"]?.string
        guard let id else { return nil }
        let sender = value["sender"].flatMap(participant) ?? ConversationParticipant(
            id: value["senderId"]?.string ?? "unknown",
            handle: "",
            displayName: "Member",
            avatarURL: nil
        )
        let text = value["body"]?.string ?? value["text"]?.string ?? ""
        let sentAt = decodeDate(value["sentAt"]?.string ?? value["createdAt"]?.string) ?? Date()
        let own = value["isOwn"]?.bool ?? (viewerID != nil && sender.id == viewerID)
        return Message(
            id: id,
            conversationID: value["conversationId"]?.string ?? conversationID,
            sender: sender,
            body: .text(text),
            sentAt: sentAt,
            delivery: MessageDeliveryState(parsing: value["delivery"]?.string ?? value["status"]?.string),
            isOwn: own,
            localDraft: nil
        )
    }

    static func request(_ value: JSONValue) -> MessageRequest? {
        let id = value["id"]?.string
        let sender = value["sender"].flatMap(participant)
        guard let id, let sender else { return nil }
        return MessageRequest(
            id: id,
            conversationID: value["conversationId"]?.string,
            sender: sender,
            preview: value["preview"]?.string ?? value["body"]?.string ?? "Wants to send you a message.",
            createdAt: decodeDate(value["createdAt"]?.string) ?? Date()
        )
    }

    static func participant(_ value: JSONValue) -> ConversationParticipant? {
        let id = value["id"]?.string ?? value["accountId"]?.string
        guard let id else { return nil }
        let handle = value["handle"]?.string ?? ""
        let display = value["displayName"]?.string ?? value["name"]?.string ?? (handle.isEmpty ? "Member" : handle)
        return ConversationParticipant(
            id: id,
            handle: handle,
            displayName: display,
            avatarURL: (value["avatarUrl"]?.string ?? value["avatarUri"]?.string).flatMap(URL.init(string:))
        )
    }

    static func preview(_ value: JSONValue) -> MessagePreview? {
        let id = value["id"]?.string ?? "preview"
        let body = value["body"]?.string ?? value["text"]?.string ?? ""
        return MessagePreview(
            id: id,
            body: body,
            sentAt: decodeDate(value["sentAt"]?.string ?? value["createdAt"]?.string) ?? Date(),
            senderID: value["senderId"]?.string
        )
    }

    static func decodeDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MessagingOrdering {
    static func conversationsNewestFirst(_ items: [Conversation]) -> [Conversation] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func messagesChronological(_ items: [Message]) -> [Message] {
        items.sorted { $0.sentAt < $1.sentAt }
    }
}
