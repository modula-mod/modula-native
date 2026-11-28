import Foundation
import SwiftUI

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
    /// Manually marked unread by me (`markUnread` capability). Never moves read receipts.
    var markedUnread = false
    /// Messaging features 4 (all optional; nil / defaults on older servers).
    var serverPinnedAt: Date? = nil
    var serverPinned = false
    var notificationLevel: String? = nil
    var disappearingTtlSeconds: Int? = nil
    /// Shared chat theme preset id (`chatThemes`); nil = default.
    var theme: String? = nil

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

    var isUnread: Bool { unreadCount > 0 || markedUnread }
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
    /// Forwarded with attribution; `forwardedName == nil` + `isForwarded` = hidden by a block.
    var isForwarded = false
    var forwardedName: String? = nil
    /// Disappearing timer at send time; dropped locally once passed.
    var expiresAt: Date? = nil

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
    /// `POST /v1/conversations/:id/unread` (migration 092). Off unless the server says so.
    var markUnread = false
    /// Live comment updates over this socket (`liveComments.enabled`). Off unless advertised.
    var liveComments: LiveCommentsCapability = .disabled
    /// Messaging features 4 (migration 093). Every block off unless `enabled: true`.
    var features4 = MessagingFeatures4()

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
        static func markUnread(conversationID: String) -> String {
            "/v1/conversations/\(escape(conversationID))/unread"
        }
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
        static func messagePin(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/pin"
        }
        static func messageSaved(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/saved"
        }
        static func messageEdits(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/edits"
        }
        static func conversationPins(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/pins" }
        static func chatPin(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/pin" }
        static func notificationLevel(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/notifications" }
        static func disappearing(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/disappearing" }
        static func scheduled(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/scheduled" }
        static func scheduledItem(_ conversation: String, _ id: String) -> String {
            "/v1/conversations/\(escape(conversation))/scheduled/\(escape(id))"
        }
        static func scheduledSendNow(_ conversation: String, _ id: String) -> String { scheduledItem(conversation, id) + "/send-now" }
        static let folders = "/v1/messaging/folders"
        static func folder(_ id: String) -> String { "/v1/messaging/folders/\(escape(id))" }
        static let quickReplies = "/v1/messaging/quick-replies"
        static func quickReply(_ id: String) -> String { "/v1/messaging/quick-replies/\(escape(id))" }
        static func forward(_ conversation: String, _ message: String) -> String {
            "/v1/conversations/\(escape(conversation))/messages/\(escape(message))/forward"
        }
        static func theme(_ conversation: String) -> String { "/v1/conversations/\(escape(conversation))/theme" }
        static func savedMessages(cursor: String?) -> String {
            var path = "/v1/messages/saved?limit=30"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { path += "&cursor=\(encoded)" }
            return path
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
            group: value["group"].flatMap(groupSummary),
            markedUnread: value["markedUnread"]?.bool ?? false,
            serverPinnedAt: decodeDate(value["pinnedAt"]?.string),
            serverPinned: value["pinned"]?.bool ?? false,
            notificationLevel: value["notificationLevel"]?.string,
            disappearingTtlSeconds: value["disappearingTtlSeconds"]?.int,
            theme: value["theme"]?.string
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
            clientMessageId: value["clientMessageId"]?.string,
            isForwarded: { if case .object = value["forwardedFrom"] { return true } else { return false } }(),
            forwardedName: value["forwardedFrom"]?["sender"]?["displayName"]?.string,
            expiresAt: decodeDate(value["expiresAt"]?.string)
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
        return ModulaISODate.parse(raw)
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
        caps.markUnread = value["markUnread"]?.bool ?? false
        caps.liveComments = LiveCommentsCapability(value["liveComments"])
        caps.features4 = MessagingFeatures4(value)
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
        // Usually already in order (pages arrive sorted): skip the O(n log n) sort then.
        if zip(items, items.dropFirst()).allSatisfy({ $0.sentAt <= $1.sentAt }) { return items }
        return items.sorted { $0.sentAt < $1.sentAt }
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


/// `liveComments` block of `/v1/messaging/capabilities`. Frame names come from the server.
struct LiveCommentsCapability: Hashable, Sendable {
    var enabled = false
    var subscribeFrame = "post.subscribe"
    var unsubscribeFrame = "post.unsubscribe"
    var maxPostsPerSocket = 0

    static let disabled = LiveCommentsCapability()

    init() {}

    init(_ value: JSONValue?) {
        guard let value, value["enabled"]?.bool == true,
              let subscribe = value["subscribeFrame"]?.string, !subscribe.isEmpty,
              let unsubscribe = value["unsubscribeFrame"]?.string, !unsubscribe.isEmpty else { return }
        enabled = true
        subscribeFrame = subscribe
        unsubscribeFrame = unsubscribe
        maxPostsPerSocket = max(value["maxPostsPerSocket"]?.int ?? 1, 1)
    }
}

/// Messaging features 4 capability blocks (`/v1/messaging/capabilities`, additive keys).
struct MessagingFeatures4: Hashable, Sendable {
    var pinnedMessages = false
    var pinnedGroupAdminsOnly = true
    var savedMessages = false
    var editHistory = false
    var disappearing = false
    var disappearingOptions: [Int] = []
    var chatPins = false
    var chatPinsMax = 0
    var notificationLevels: [String] = []
    /// Parsed for later rounds (no UI yet): scheduled, folders, quick replies, forwarding, themes.
    var scheduled = false
    var scheduledMinLeadSeconds = 10
    var scheduledMaxLeadDays = 365
    var scheduledMaxPending = 50
    var chatFolders = false
    var chatFoldersMax = 20
    var quickReplies = false
    var quickRepliesMax = 50
    var forwarding = false
    var forwardingMaxTargets = 1
    var forwardingKinds: [String] = []
    var chatThemes: [String] = []

    init() {}

    init(_ value: JSONValue) {
        func on(_ key: String) -> JSONValue? { value[key]?["enabled"]?.bool == true ? value[key] : nil }
        if let block = on("pinnedMessages") {
            pinnedMessages = true
            pinnedGroupAdminsOnly = block["groupAdminsOnly"]?.bool ?? true
        }
        savedMessages = on("savedMessages") != nil
        editHistory = on("editHistory") != nil
        if let block = on("disappearingMessages") {
            disappearingOptions = (block["ttlOptionsSeconds"]?.array ?? []).compactMap(\.int).filter { $0 > 0 }
            disappearing = !disappearingOptions.isEmpty
        }
        if let block = on("chatPins") {
            chatPins = true
            chatPinsMax = block["max"]?.int ?? 10
        }
        if let block = on("notificationLevels") {
            notificationLevels = (block["levels"]?.array ?? []).compactMap(\.string)
        }
        if let block = on("scheduledMessages") {
            scheduled = true
            scheduledMinLeadSeconds = max(block["minLeadSeconds"]?.int ?? 10, 0)
            scheduledMaxLeadDays = max(block["maxLeadDays"]?.int ?? 365, 1)
            scheduledMaxPending = max(block["maxPending"]?.int ?? 50, 1)
        }
        if let block = on("chatFolders") {
            chatFolders = true
            chatFoldersMax = max(block["maxFolders"]?.int ?? 20, 1)
        }
        if let block = on("quickReplies") {
            quickReplies = true
            quickRepliesMax = max(block["max"]?.int ?? 50, 1)
        }
        if let block = on("forwarding") {
            forwardingKinds = (block["kinds"]?.array ?? []).compactMap(\.string)
            forwardingMaxTargets = max(block["maxTargets"]?.int ?? 1, 1)
            forwarding = !forwardingKinds.isEmpty
        }
        chatThemes = (on("chatThemes")?["themes"]?.array ?? []).compactMap(\.string)
    }

    static func ttlTitle(_ seconds: Int) -> String {
        switch seconds {
        case 3600: return "1 hour"
        case 86400: return "1 day"
        case 604800: return "1 week"
        case 7776000: return "90 days"
        default:
            let days = seconds / 86400
            let hours = max(seconds / 3600, 1)
            if days > 0 { return days == 1 ? "1 day" : "\(days) days" }
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
    }
}

struct MessageEditVersion: Hashable, Sendable, Identifiable {
    let text: String
    let at: Date?
    let current: Bool
    var id: String { "\(current)-\(at?.timeIntervalSince1970 ?? 0)-\(text)" }
}

// MARK: - Messaging features 4: DTOs and pure logic (decoders are covered by MessagingFeatures4UITests)

struct ScheduledMessage: Identifiable, Hashable, Sendable {
    enum State: String, Sendable { case pending, sending, sent, failed, cancelled }
    let id: String
    let conversationID: ConversationID
    var text: String
    var sendAt: Date
    var state: State
    var sentMessageID: MessageID?
    var failureReason: String?
    /// Still editable / cancellable from the list.
    var isOpen: Bool { state == .pending || state == .failed }
}

struct ChatFolder: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var emoji: String?
    var sortOrder: Int
    var conversationIDs: [ConversationID]
}

struct QuickReply: Identifiable, Hashable, Sendable {
    let id: String
    var shortcut: String
    var text: String
}

struct PinnedMessagePreview: Identifiable, Hashable, Sendable {
    let messageID: MessageID
    let text: String
    let senderName: String
    var id: MessageID { messageID }
}

struct SavedMessageItem: Identifiable, Hashable, Sendable {
    let messageID: MessageID
    let conversationID: ConversationID
    let savedAt: Date?
    let text: String
    let senderName: String
    let sentAt: Date?
    var id: MessageID { messageID }
}

struct ForwardResult: Identifiable, Hashable, Sendable {
    let conversationID: ConversationID
    let ok: Bool
    let reason: String?
    var id: ConversationID { conversationID }
}

struct MessagingSystemNote: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let at: Date
}

enum MessagingFeatures4Decoder {
    static func scheduled(_ value: JSONValue) -> ScheduledMessage? {
        guard let id = value["id"]?.string, let conversation = value["conversationId"]?.string,
              let sendAt = MessagingPayloadDecoder.decodeDate(value["sendAt"]?.string) else { return nil }
        return ScheduledMessage(id: id, conversationID: conversation, text: value["text"]?.string ?? "", sendAt: sendAt,
                                state: ScheduledMessage.State(rawValue: value["state"]?.string ?? "") ?? .pending,
                                sentMessageID: value["sentMessageId"]?.string, failureReason: value["failureReason"]?.string)
    }

    static func folder(_ value: JSONValue) -> ChatFolder? {
        guard let id = value["id"]?.string, let name = value["name"]?.string else { return nil }
        return ChatFolder(id: id, name: name, emoji: value["emoji"]?.string, sortOrder: value["sortOrder"]?.int ?? 0,
                          conversationIDs: (value["conversationIds"]?.array ?? []).compactMap(\.string))
    }

    static func quickReply(_ value: JSONValue) -> QuickReply? {
        guard let id = value["id"]?.string, let shortcut = value["shortcut"]?.string else { return nil }
        return QuickReply(id: id, shortcut: shortcut, text: value["text"]?.string ?? "")
    }

    static func pin(_ value: JSONValue) -> PinnedMessagePreview? {
        guard let id = value["messageId"]?.string else { return nil }
        return PinnedMessagePreview(messageID: id, text: value["message"]?["body"]?.string ?? "",
                                    senderName: value["message"]?["sender"]?["displayName"]?.string ?? "")
    }

    static func saved(_ value: JSONValue) -> SavedMessageItem? {
        guard let id = value["messageId"]?.string, let conversation = value["conversationId"]?.string else { return nil }
        let message = value["message"]
        return SavedMessageItem(messageID: id, conversationID: conversation,
                                savedAt: MessagingPayloadDecoder.decodeDate(value["savedAt"]?.string),
                                text: message?["body"]?.string ?? "",
                                senderName: message?["sender"]?["displayName"]?.string ?? "",
                                sentAt: MessagingPayloadDecoder.decodeDate(message?["sentAt"]?.string))
    }

    static func forwardResults(_ value: JSONValue) -> [ForwardResult] {
        (value["results"]?.array ?? []).compactMap { item in
            guard let id = item["conversationId"]?.string else { return nil }
            let ok = item["ok"]?.bool ?? false
            return ForwardResult(conversationID: id, ok: ok,
                                 reason: ok ? nil : (item["error"]?["reason"]?.string ?? item["error"]?["code"]?.string ?? "failed"))
        }
    }

    /// Folders sorted the way the server lists them (sortOrder, then name for ties).
    static func sorted(_ folders: [ChatFolder]) -> [ChatFolder] {
        folders.sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
    }
}

/// "/omw" in the composer: the typed shortcut prefix, or nil when the text isn't a shortcut query.
enum QuickReplyMatcher {
    static func query(in text: String) -> String? {
        guard text.hasPrefix("/"), !text.contains(" "), !text.contains("\n") else { return nil }
        let q = text.dropFirst().lowercased()
        guard q.count <= 24, q.allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "_" || $0 == "-" }) else { return nil }
        return String(q)
    }

    static func matches(_ replies: [QuickReply], text: String, limit: Int = 8) -> [QuickReply] {
        guard let q = query(in: text) else { return [] }
        let hits = replies.filter { q.isEmpty || $0.shortcut.hasPrefix(q) }
        return Array(hits.sorted { $0.shortcut < $1.shortcut }.prefix(limit))
    }

    static func isValidShortcut(_ s: String) -> Bool {
        let lower = s.lowercased()
        return (1...24).contains(lower.count)
            && lower.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
    }
}

/// Quick presets for "Schedule message", clamped to the server's lead window.
enum ScheduleSendPresets {
    struct Preset: Hashable, Identifiable { let title: String; let date: Date; var id: String { title } }

    static func presets(now: Date, calendar: Calendar = .current, minLead: Int = 10, maxLeadDays: Int = 365) -> [Preset] {
        var out: [Preset] = []
        if let hour = calendar.date(byAdding: .hour, value: 1, to: now) { out.append(.init(title: "In 1 hour", date: hour)) }
        if let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now), tonight.timeIntervalSince(now) > 3600 {
            out.append(.init(title: "Tonight, 8 PM", date: tonight))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            out.append(.init(title: "Tomorrow, 9 AM", date: morning))
        }
        if let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime),
           !out.contains(where: { calendar.isDate($0.date, equalTo: monday, toGranularity: .minute) }) {
            out.append(.init(title: "Monday, 9 AM", date: monday))
        }
        let range = window(now: now, minLead: minLead, maxLeadDays: maxLeadDays)
        return out.filter { range.contains($0.date) }
    }

    static func window(now: Date, minLead: Int, maxLeadDays: Int) -> ClosedRange<Date> {
        let start = now.addingTimeInterval(TimeInterval(max(minLead, 0) + 30))
        let end = now.addingTimeInterval(TimeInterval(max(maxLeadDays, 1)) * 86400)
        return start...max(end, start)
    }
}

enum DisappearingNote {
    static func text(ttlSeconds: Int?) -> String {
        guard let ttl = ttlSeconds, ttl > 0 else { return "Disappearing messages turned off" }
        return "Messages now disappear after \(MessagingFeatures4.ttlTitle(ttl))"
    }
}

/// Server chat theme ids -> native palettes (bubbles + background). Unknown ids fall back to default.
enum ChatThemePalette {
    static func accent(_ id: String?) -> Color? {
        switch id {
        case "coral": Color(red: 1.0, green: 0.45, blue: 0.40)
        case "ocean": Color(red: 0.10, green: 0.50, blue: 0.90)
        case "forest": Color(red: 0.16, green: 0.58, blue: 0.36)
        case "sunset": Color(red: 0.98, green: 0.55, blue: 0.18)
        case "midnight": Color(red: 0.22, green: 0.24, blue: 0.55)
        case "lavender": Color(red: 0.60, green: 0.48, blue: 0.90)
        case "mono": Color(white: 0.28)
        default: nil
        }
    }

    static func background(_ id: String?) -> [Color] {
        switch id {
        case "coral": [Color(red: 1.0, green: 0.62, blue: 0.55), Color(red: 1.0, green: 0.82, blue: 0.70)]
        case "ocean": [Color(red: 0.20, green: 0.60, blue: 0.95), Color(red: 0.40, green: 0.85, blue: 0.90)]
        case "forest": [Color(red: 0.20, green: 0.55, blue: 0.35), Color(red: 0.60, green: 0.80, blue: 0.45)]
        case "sunset": [Color(red: 1.0, green: 0.50, blue: 0.30), Color(red: 0.85, green: 0.35, blue: 0.60)]
        case "midnight": [Color(red: 0.10, green: 0.12, blue: 0.35), Color(red: 0.35, green: 0.25, blue: 0.60)]
        case "lavender": [Color(red: 0.70, green: 0.60, blue: 0.95), Color(red: 0.90, green: 0.75, blue: 0.95)]
        case "mono": [Color(white: 0.55), Color(white: 0.80)]
        default: []
        }
    }

    static func title(_ id: String) -> String { id == "default" ? "Default" : id.capitalized }
}

extension EnvironmentValues {
    /// Per-chat theme accent for own bubbles (nil = app accent).
    @Entry var chatThemeAccent: Color? = nil
}
