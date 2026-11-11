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
    var kind: MessageKind = .text
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
    var isMuted = false
    var isArchived = false
    var group: ConversationGroupSummary? = nil

    var title: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        if let group, !group.title.isEmpty { return group.title }
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
    var reactions: [MessageReaction] = []
    var replyTo: MessageReplyPreview? = nil
    var editedAt: Date? = nil
    var isDeleted = false
    var kind: MessageKind = .text
    var attachments: [MessageAttachment] = []
    var mentions: [MessageMention] = []
    var clientMessageId: String? = nil

    var previewText: String {
        if kind == .voice { return body.text.isEmpty ? "Voice note" : body.text }
        return body.text
    }

    var voiceAttachment: MessageAttachment? { attachments.first(where: { $0.kind == .audio }) }
}

struct MessageDraft: Hashable, Sendable {
    var conversationID: ConversationID
    var text: String
    var replyToID: MessageID? = nil
    var kind: MessageKind = .text
    var clientMessageId: String? = nil
    var attachments: [MessageDraftAttachment] = []
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
    var kind: ConversationKind = .request
    var group: ConversationGroupSummary? = nil
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
    /// Messaging v2 (`PUT /v1/conversations/:id/messages/:messageId/reactions`). Probed at runtime.
    var reactions = false
    /// `POST /v1/profiles/:id/block` (live).
    var block = false

    // MARK: Messaging v3 (migration 089). All default off so production without 089 stays honest.
    var groups = false
    var maxGroupMembers = 0
    var mentions = false
    var voiceNotes = false
    var voiceNoteMaxMs = 0
    var voiceNoteMimeTypes: [String] = []
    /// Native photo/video sending stays off even if a server ever reports it.
    var photoVideo = false
    var maxAttachmentsPerMessage = 0
    var reactionDetails = false
    var groupReadReceipts = false
    var historySearch = false
    var presenceOnlineWindowMs = 0
    var privacyControls = false
    var idempotentSend = false
    var notificationReply = false
    var notificationMarkRead = false
    var realtimeSocketPath: String? = nil
    var realtimeHeartbeatMs = 0
    var realtimeSingleInstance = false
    /// 1:1 voice/video calls (`calls` block, migration 090). Off unless the server says enabled.
    var calls: CallsCapabilities = .disabled

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
        static let capabilities = "/v1/messaging/capabilities"
        static let privacy = "/v1/messaging/privacy"
        static let historySearch = "/v1/messages/search"
        static let presenceHeartbeat = "/v1/presence/heartbeat"
        static let presence = "/v1/presence"
        static let groups = "/v1/groups"
        static func group(_ id: String) -> String { "/v1/groups/\(escape(id))" }
        static func groupMembers(_ id: String) -> String { "/v1/groups/\(escape(id))/members" }
        static func groupMember(_ id: String, actor: String) -> String { "/v1/groups/\(escape(id))/members/\(escape(actor))" }
        static func groupMemberRole(_ id: String, actor: String) -> String { "/v1/groups/\(escape(id))/members/\(escape(actor))/role" }
        static func groupLeave(_ id: String) -> String { "/v1/groups/\(escape(id))/leave" }
        static func reactions(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/reactions"
        }
        static func receipts(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/receipts"
        }

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
            titleOverride: emptyToNil(value["title"]?.string ?? value["name"]?.string ?? value["group"]?["title"]?.string),
            isMuted: value["muted"]?.bool ?? false,
            isArchived: value["archived"]?.bool ?? false,
            group: value["group"].flatMap(groupSummary)
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
        let kind = MessageKind(parsing: value["kind"]?.string)
        return Message(
            id: id,
            conversationID: value["conversationId"]?.string ?? conversationID,
            sender: sender,
            body: kind == .text || !text.isEmpty ? .text(text) : .text(text),
            sentAt: sentAt,
            delivery: MessageDeliveryState(parsing: value["delivery"]?.string ?? value["status"]?.string),
            isOwn: own,
            localDraft: nil,
            reactions: (value["reactions"]?.array ?? []).compactMap { r in
                r["emoji"]?.string.map { MessageReaction(emoji: $0, count: r["count"]?.int ?? 1, mine: r["mine"]?.bool ?? false) }
            },
            replyTo: value["replyTo"].flatMap { r in
                r["id"]?.string.map {
                    MessageReplyPreview(id: $0, senderName: r["senderName"]?.string ?? "", body: r["body"]?.string ?? "", deleted: r["deleted"]?.bool ?? false)
                }
            },
            editedAt: decodeDate(value["editedAt"]?.string),
            isDeleted: value["deleted"]?.bool ?? false,
            kind: kind,
            attachments: (value["attachments"]?.array ?? []).compactMap(attachment),
            mentions: (value["mentions"]?.array ?? []).compactMap(mention),
            clientMessageId: value["clientMessageId"]?.string
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
            createdAt: decodeDate(value["createdAt"]?.string) ?? Date(),
            kind: ConversationKind(parsing: value["kind"]?.string ?? "request"),
            group: value["group"].flatMap(groupSummary)
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
            senderID: value["senderId"]?.string,
            kind: MessageKind(parsing: value["kind"]?.string)
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

    static func groupSummary(_ value: JSONValue) -> ConversationGroupSummary? {
        let title = value["title"]?.string ?? ""
        guard !title.isEmpty || value["memberCount"]?.int != nil || value["myRole"]?.string != nil else { return nil }
        return ConversationGroupSummary(
            title: title.isEmpty ? "Group" : title,
            description: emptyToNil(value["description"]?.string),
            memberCount: value["memberCount"]?.int ?? 0,
            myRole: GroupRole(parsing: value["myRole"]?.string)
        )
    }

    static func attachment(_ value: JSONValue) -> MessageAttachment? {
        guard let id = value["id"]?.string else { return nil }
        let kind: MessageAttachmentKind
        switch (value["kind"]?.string ?? "").lowercased() {
        case "audio": kind = .audio
        case "image": kind = .image
        case "video": kind = .video
        default: return nil
        }
        return MessageAttachment(
            id: id,
            kind: kind,
            mimeType: value["mimeType"]?.string ?? "",
            byteSize: value["byteSize"]?.int ?? 0,
            durationMs: value["durationMs"]?.int,
            waveform: (value["waveform"]?.array ?? []).compactMap(\.number),
            width: value["width"]?.int,
            height: value["height"]?.int,
            url: value["url"]?.string.flatMap(URL.init(string:))
        )
    }

    static func mention(_ value: JSONValue) -> MessageMention? {
        guard let actorId = value["actorId"]?.string ?? value["id"]?.string else { return nil }
        return MessageMention(actorId: actorId, handle: value["handle"]?.string ?? "")
    }

    static func capabilitiesV3(from value: JSONValue) -> MessagingBackendCapabilities? {
        let version = value["version"]?.int ?? 0
        guard version >= 3 else { return nil }
        var caps = MessagingBackendCapabilities.production
        caps.groups = value["groups"]?.bool ?? false
        caps.maxGroupMembers = value["maxGroupMembers"]?.int ?? 0
        caps.mentions = value["mentions"]?.bool ?? false
        caps.voiceNotes = value["voiceNotes"]?.bool ?? false
        caps.voiceNoteMaxMs = value["voiceNoteMaxMs"]?.int ?? 0
        caps.voiceNoteMimeTypes = (value["voiceNoteMimeTypes"]?.array ?? []).compactMap(\.string)
        caps.photoVideo = false
        caps.maxAttachmentsPerMessage = value["maxAttachmentsPerMessage"]?.int ?? 0
        caps.reactionDetails = value["reactionDetails"]?.bool ?? false
        caps.groupReadReceipts = value["groupReadReceipts"]?.bool ?? false
        caps.historySearch = value["historySearch"]?.bool ?? false
        caps.presence = value["presence"]?.bool ?? false
        caps.presenceOnlineWindowMs = value["presenceOnlineWindowMs"]?.int ?? 0
        let realtime = value["realtime"]
        caps.realtime = realtime != nil
        caps.realtimeSocketPath = realtime?["socketPath"]?.string
        caps.realtimeHeartbeatMs = realtime?["heartbeatMs"]?.int ?? 0
        caps.realtimeSingleInstance = realtime?["singleInstance"]?.bool ?? false
        caps.calls = CallPayloadDecoder.capabilities(value["calls"])
        caps.privacyControls = !(value["privacyControls"]?.array ?? []).isEmpty
        caps.idempotentSend = value["idempotentSend"]?.bool ?? false
        let actions = Set((value["notificationActions"]?.array ?? []).compactMap(\.string))
        caps.notificationReply = actions.contains("reply")
        caps.notificationMarkRead = actions.contains("markRead")
        caps.reactions = true
        caps.reply = true
        caps.edit = true
        caps.deleteOwn = true
        caps.typing = true
        caps.mute = true
        caps.archive = true
        caps.report = true
        caps.block = true
        return caps
    }

    static func privacy(_ value: JSONValue) -> MessagingPrivacy {
        MessagingPrivacy(
            readReceipts: value["readReceipts"]?.bool ?? true,
            typingIndicators: value["typingIndicators"]?.bool ?? true,
            presenceVisibility: PresenceVisibility(parsing: value["presenceVisibility"]?.string),
            notificationPreview: NotificationPreviewSetting(parsing: value["notificationPreview"]?.string),
            version: value["version"]?.int ?? 0
        )
    }

    static func groupDetail(_ value: JSONValue) -> GroupDetail? {
        guard let id = value["id"]?.string else { return nil }
        let members = (value["members"]?.array ?? []).compactMap(groupMember)
        return GroupDetail(
            id: id,
            title: value["title"]?.string ?? "Group",
            description: emptyToNil(value["description"]?.string),
            memberCount: value["memberCount"]?.int ?? members.filter { $0.state == "active" }.count,
            myRole: GroupRole(parsing: value["myRole"]?.string),
            myState: value["myState"]?.string ?? "active",
            maxMembers: value["maxMembers"]?.int ?? 0,
            members: members
        )
    }

    static func groupMember(_ value: JSONValue) -> GroupMember? {
        guard let person = value["participant"].flatMap(participant) else { return nil }
        return GroupMember(
            participant: person,
            role: GroupRole(parsing: value["role"]?.string),
            state: value["state"]?.string ?? "active",
            joinedAt: decodeDate(value["joinedAt"]?.string),
            isMe: value["isMe"]?.bool ?? false,
            blocked: value["blocked"]?.bool ?? false
        )
    }

    static func reactionDetails(_ value: JSONValue) -> [MessageReactionDetail] {
        (value["reactions"]?.array ?? value.array ?? []).compactMap { r in
            guard let emoji = r["emoji"]?.string else { return nil }
            return MessageReactionDetail(
                emoji: emoji,
                count: r["count"]?.int ?? 0,
                mine: r["mine"]?.bool ?? false,
                actors: (r["actors"]?.array ?? []).compactMap(participant)
            )
        }
    }

    static func receipts(_ value: JSONValue) -> MessageReceipts {
        MessageReceipts(
            readBy: (value["readBy"]?.array ?? []).compactMap { row in
                guard let person = row["participant"].flatMap(participant) else { return nil }
                return MessageReadReceipt(participant: person, readAt: decodeDate(row["readAt"]?.string))
            },
            notYet: (value["notYet"]?.array ?? []).compactMap(participant),
            hiddenCount: value["hiddenCount"]?.int ?? 0,
            receiptsDisabled: value["receiptsDisabled"]?.bool ?? false
        )
    }

    static func searchPage(from value: JSONValue) -> HistorySearchPage {
        let items = (value["items"]?.array ?? []).compactMap(searchHit)
        let next = value["nextCursor"]?.string
        return HistorySearchPage(items: items, nextCursor: next, hasMore: value["hasMore"]?.bool ?? (next != nil))
    }

    static func searchHit(_ value: JSONValue) -> HistorySearchHit? {
        guard let messageId = value["messageId"]?.string, let conversationId = value["conversationId"]?.string else { return nil }
        return HistorySearchHit(
            id: messageId,
            conversationID: conversationId,
            conversationKind: ConversationKind(parsing: value["conversationKind"]?.string),
            groupTitle: emptyToNil(value["groupTitle"]?.string),
            sender: value["sender"].flatMap(participant) ?? ConversationParticipant(id: "unknown", handle: "", displayName: "Member", avatarURL: nil),
            isOwn: value["isOwn"]?.bool ?? false,
            snippet: value["snippet"]?.string ?? "",
            kind: MessageKind(parsing: value["kind"]?.string),
            sentAt: decodeDate(value["sentAt"]?.string) ?? Date()
        )
    }

    static func presenceItems(_ value: JSONValue) -> [PresenceItem] {
        (value["items"]?.array ?? value.array ?? []).compactMap { row in
            guard let actorId = row["actorId"]?.string else { return nil }
            return PresenceItem(
                actorId: actorId,
                status: PresenceStatus(parsing: row["status"]?.string),
                lastActiveAt: decodeDate(row["lastActiveAt"]?.string)
            )
        }
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


struct MessageReaction: Hashable, Sendable {
    let emoji: String
    var count: Int
    var mine: Bool
}

struct MessageReplyPreview: Hashable, Sendable {
    let id: MessageID
    let senderName: String
    let body: String
    let deleted: Bool
}


enum MessageKind: String, Hashable, Sendable {
    case text, voice, media, unknown
    init(parsing raw: String?) {
        switch (raw ?? "text").lowercased() {
        case "text": self = .text
        case "voice": self = .voice
        case "media": self = .media
        default: self = .unknown
        }
    }
}

enum MessageAttachmentKind: String, Hashable, Sendable { case audio, image, video }

struct MessageAttachment: Hashable, Sendable, Identifiable {
    let id: String
    var kind: MessageAttachmentKind
    var mimeType: String
    var byteSize: Int
    var durationMs: Int?
    var waveform: [Double]
    var width: Int?
    var height: Int?
    var url: URL?

    var waveformPercents: [Int] { waveform.map { Int((min(1, max(0, $0)) * 100).rounded()) } }
}

struct MessageDraftAttachment: Hashable, Sendable {
    var attachmentId: String
    var durationMs: Int
    var waveform: [Double]
}

struct MessageMention: Hashable, Sendable {
    var actorId: String
    var handle: String
}

enum GroupRole: String, Hashable, Sendable {
    case owner, admin, member
    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "owner": self = .owner
        case "admin": self = .admin
        default: self = .member
        }
    }

    var title: String {
        switch self {
        case .owner: "Owner"
        case .admin: "Admin"
        case .member: "Member"
        }
    }
}

struct ConversationGroupSummary: Hashable, Sendable {
    var title: String
    var description: String?
    var memberCount: Int
    var myRole: GroupRole
}

struct GroupMember: Identifiable, Hashable, Sendable {
    var participant: ConversationParticipant
    var role: GroupRole
    var state: String
    var joinedAt: Date?
    var isMe: Bool
    var blocked: Bool
    var id: String { participant.id }
}

struct GroupDetail: Identifiable, Hashable, Sendable {
    var id: ConversationID
    var title: String
    var description: String?
    var memberCount: Int
    var myRole: GroupRole
    var myState: String
    var maxMembers: Int
    var members: [GroupMember]
    var canAdmin: Bool { myRole == .owner || myRole == .admin }
    var isOwner: Bool { myRole == .owner }
}

enum PresenceVisibility: String, Hashable, Sendable, CaseIterable, Identifiable {
    case contacts, nobody
    var id: String { rawValue }
    init(parsing raw: String?) { self = raw == "nobody" ? .nobody : .contacts }
    var title: String { self == .contacts ? "People I chat with" : "Nobody" }
}

enum NotificationPreviewSetting: String, Hashable, Sendable, CaseIterable, Identifiable {
    case full, nameOnly = "name_only", none
    var id: String { rawValue }
    init(parsing raw: String?) {
        switch raw {
        case "name_only": self = .nameOnly
        case "none": self = .none
        default: self = .full
        }
    }
    var title: String {
        switch self {
        case .full: "Name and message"
        case .nameOnly: "Name only"
        case .none: "No preview"
        }
    }
}

struct MessagingPrivacy: Hashable, Sendable, Equatable {
    var readReceipts = true
    var typingIndicators = true
    var presenceVisibility: PresenceVisibility = .contacts
    var notificationPreview: NotificationPreviewSetting = .full
    var version = 0
}

enum PresenceStatus: String, Hashable, Sendable {
    case online, offline, hidden
    init(parsing raw: String?) {
        switch raw {
        case "online": self = .online
        case "hidden": self = .hidden
        default: self = .offline
        }
    }
}

struct PresenceItem: Hashable, Sendable {
    var actorId: String
    var status: PresenceStatus
    var lastActiveAt: Date?
}

struct MessageReactionDetail: Hashable, Sendable, Identifiable {
    var emoji: String
    var count: Int
    var mine: Bool
    var actors: [ConversationParticipant]
    var id: String { emoji }
}

struct MessageReadReceipt: Hashable, Sendable, Identifiable {
    var participant: ConversationParticipant
    var readAt: Date?
    var id: String { participant.id }
}

struct MessageReceipts: Hashable, Sendable {
    var readBy: [MessageReadReceipt]
    var notYet: [ConversationParticipant]
    var hiddenCount: Int
    var receiptsDisabled: Bool
}

struct HistorySearchHit: Identifiable, Hashable, Sendable {
    var id: MessageID
    var conversationID: ConversationID
    var conversationKind: ConversationKind
    var groupTitle: String?
    var sender: ConversationParticipant
    var isOwn: Bool
    var snippet: String
    var kind: MessageKind
    var sentAt: Date
    var title: String { groupTitle ?? (isOwn ? "You" : sender.displayName) }
}

struct HistorySearchPage: Sendable, Equatable {
    var items: [HistorySearchHit]
    var nextCursor: String?
    var hasMore: Bool
}

