import Foundation

typealias InMailThreadID = String
typealias InMailMessageID = String

struct InMailThread: Identifiable, Hashable, Sendable {
    let id: InMailThreadID
    let subject: String
    let participants: [ConversationParticipant]
    let preview: String
    let unread: Bool
    let updatedAt: Date
}

struct InMailMessage: Identifiable, Hashable, Sendable {
    let id: InMailMessageID
    let subject: String?
    let body: String
    let sender: ConversationParticipant
    let createdAt: Date
    let isOwn: Bool
}

struct InMailDraft: Equatable, Sendable {
    var toHandle: String = ""
    var subject: String = ""
    var body: String = ""
}

struct InMailPage: Sendable, Equatable {
    var items: [InMailThread]
    var nextCursor: String?
    var hasMore: Bool
}

struct InMailBackendCapabilities: Sendable, Equatable {
    var list = false
    var thread = false
    var send = false
    var reply = false
    var attachments = false
    var privacySettings = false
    var unread = false
    var serverSearch = false

    /// Live on api.modula.digital since backend migration 075_greenfield_messaging.
    static let production = InMailBackendCapabilities(list: true, thread: true, send: true, reply: true, unread: true)

    enum Paths {
        static func inbox(cursor: String?) -> String {
            var path = "/v1/in-mail?limit=30"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&cursor=\(encoded)"
            }
            return path
        }
        static func thread(_ id: String) -> String { "/v1/in-mail/\(escape(id))" }
        static let compose = "/v1/in-mail"
        static func reply(_ id: String) -> String { "/v1/in-mail/\(escape(id))/replies" }

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}

enum InMailPayloadDecoder {
    static func page(from value: JSONValue) -> InMailPage {
        let items = (value["items"]?.array ?? value["threads"]?.array ?? []).compactMap(thread)
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        return InMailPage(
            items: items,
            nextCursor: next,
            hasMore: value["hasMore"]?.bool ?? (next != nil)
        )
    }

    static func thread(_ value: JSONValue) -> InMailThread? {
        let id = value["id"]?.string ?? value["threadId"]?.string
        guard let id else { return nil }
        let participants = (value["participants"]?.array ?? []).compactMap(MessagingPayloadDecoder.participant)
        return InMailThread(
            id: id,
            subject: value["subject"]?.string ?? "(No subject)",
            participants: participants,
            preview: value["preview"]?.string ?? value["snippet"]?.string ?? "",
            unread: value["unread"]?.bool ?? false,
            updatedAt: MessagingPayloadDecoder.decodeDate(value["updatedAt"]?.string) ?? Date()
        )
    }

    static func messages(from value: JSONValue, viewerID: String?) -> [InMailMessage] {
        let items = value["messages"]?.array ?? value["items"]?.array ?? []
        return items.compactMap { message($0, viewerID: viewerID) }
    }

    static func message(_ value: JSONValue, viewerID: String?) -> InMailMessage? {
        let id = value["id"]?.string
        let body = value["body"]?.string ?? value["text"]?.string
        guard let id, let body else { return nil }
        let sender = value["sender"].flatMap(MessagingPayloadDecoder.participant) ?? ConversationParticipant(
            id: "unknown", handle: "", displayName: "Member", avatarURL: nil
        )
        return InMailMessage(
            id: id,
            subject: value["subject"]?.string,
            body: body,
            sender: sender,
            createdAt: MessagingPayloadDecoder.decodeDate(value["createdAt"]?.string) ?? Date(),
            isOwn: viewerID != nil && sender.id == viewerID
        )
    }
}

enum InMailValidation {
    static func subject(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add a subject." }
        if trimmed.count > 180 { return "Subject is too long." }
        return nil
    }

    static func recipient(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add a recipient." }
        if trimmed.count > 80 { return "Recipient isn’t valid." }
        return nil
    }

    static func body(_ value: String) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write a message." }
        return nil
    }
}

enum InMailFixtures {
    static let now = Date(timeIntervalSince1970: 1_784_000_000)

    static let unread = InMailThread(
        id: "mail-sophia",
        subject: "Partnership idea",
        participants: [MessagingFixtures.sophia],
        preview: "I wanted to ask whether we could collaborate on the module SDK.",
        unread: true,
        updatedAt: now.addingTimeInterval(-7200)
    )

    static let read = InMailThread(
        id: "mail-marcus",
        subject: "Re: Module SDK",
        participants: [MessagingFixtures.marcus],
        preview: "Sounds good — I’ll send the notes tomorrow.",
        unread: false,
        updatedAt: now.addingTimeInterval(-86_400)
    )

    static let longSubject = InMailThread(
        id: "mail-long",
        subject: "A substantially longer subject line that must wrap for Dynamic Type and still remain readable in the In-Mail list",
        participants: [MessagingFixtures.sophia],
        preview: String(repeating: "Long body preview. ", count: 8),
        unread: true,
        updatedAt: now.addingTimeInterval(-400)
    )

    static func chain(threadID: InMailThreadID = "mail-sophia") -> [InMailMessage] {
        [
            InMailMessage(
                id: "im1",
                subject: "Partnership idea",
                body: "I wanted to ask whether we could collaborate on the module SDK.",
                sender: MessagingFixtures.sophia,
                createdAt: now.addingTimeInterval(-8_000),
                isOwn: false
            ),
            InMailMessage(
                id: "im2",
                subject: "Re: Partnership idea",
                body: "Yes — let’s keep this in In-Mail rather than chat.",
                sender: MessagingFixtures.me,
                createdAt: now.addingTimeInterval(-7_200),
                isOwn: true
            )
        ]
    }

    static let newDraft = InMailDraft(toHandle: "sophia.chen", subject: "", body: "")
}
