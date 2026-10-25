import Foundation

enum MessageContextActions {
    static func own(
        capabilities: MessagingBackendCapabilities,
        delivery: MessageDeliveryState
    ) -> [ModulaContextAction] {
        var items = [ModulaContextAction(id: "copy", title: "Copy", systemImage: "doc.on.doc")]
        if capabilities.reply {
            items.append(.init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left"))
        }
        if capabilities.edit {
            items.append(.init(id: "edit", title: "Edit", systemImage: "pencil"))
        }
        if capabilities.deleteOwn {
            items.append(.init(id: "delete", title: "Delete", systemImage: "trash", role: .destructive))
        }
        if delivery == .failed {
            items.append(.init(id: "retry", title: "Retry", systemImage: "arrow.clockwise"))
        }
        return items
    }

    static func other(capabilities: MessagingBackendCapabilities) -> [ModulaContextAction] {
        var items = [ModulaContextAction(id: "copy", title: "Copy", systemImage: "doc.on.doc")]
        if capabilities.reply {
            items.append(.init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left"))
        }
        if capabilities.report {
            items.append(.init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive))
        }
        return items
    }

    static func conversation(capabilities: MessagingBackendCapabilities) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = []
        if capabilities.mute {
            items.append(.init(id: "mute", title: "Mute", systemImage: "bell.slash"))
        }
        if capabilities.archive {
            items.append(.init(id: "archive", title: "Archive", systemImage: "archivebox"))
        }
        return items
    }
}

enum MessagingFixtures {
    static let now = Date(timeIntervalSince1970: 1_784_000_000)

    static let sophia = ConversationParticipant(
        id: "user-sophia",
        handle: "sophia.chen",
        displayName: "Sophia Chen",
        avatarURL: nil
    )
    static let marcus = ConversationParticipant(
        id: "user-marcus",
        handle: "marcus",
        displayName: "Marcus",
        avatarURL: nil
    )
    static let alex = ConversationParticipant(
        id: "user-alex",
        handle: "alex",
        displayName: "Alex",
        avatarURL: nil
    )
    static let me = ConversationParticipant(
        id: "user-me",
        handle: "me",
        displayName: "You",
        avatarURL: nil
    )

    static let unreadConversation = Conversation(
        id: "convo-sophia",
        kind: .direct,
        participants: [sophia],
        lastMessage: MessagePreview(
            id: "m-s-1",
            body: "Are you still working on the module SDK?",
            sentAt: now.addingTimeInterval(-120),
            senderID: sophia.id
        ),
        unreadCount: 2,
        updatedAt: now.addingTimeInterval(-120),
        titleOverride: nil
    )

    static let readConversation = Conversation(
        id: "convo-marcus",
        kind: .direct,
        participants: [marcus],
        lastMessage: MessagePreview(
            id: "m-m-1",
            body: "Sounds good.",
            sentAt: now.addingTimeInterval(-1260),
            senderID: marcus.id
        ),
        unreadCount: 0,
        updatedAt: now.addingTimeInterval(-1260),
        titleOverride: nil
    )

    static let request = MessageRequest(
        id: "req-alex",
        conversationID: "convo-alex",
        sender: alex,
        preview: "Wants to send you a message.",
        createdAt: now.addingTimeInterval(-3600)
    )

    static func thread(conversationID: ConversationID = "convo-sophia") -> [Message] {
        [
            Message(
                id: "m1",
                conversationID: conversationID,
                sender: sophia,
                body: .text("Are you still working on the module SDK?"),
                sentAt: now.addingTimeInterval(-3600),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m2",
                conversationID: conversationID,
                sender: me,
                body: .text("Yes — native messaging is next."),
                sentAt: now.addingTimeInterval(-3000),
                delivery: .sent,
                isOwn: true,
                localDraft: nil
            ),
            Message(
                id: "m3",
                conversationID: conversationID,
                sender: sophia,
                body: .text("Sounds good. See you tomorrow."),
                sentAt: now.addingTimeInterval(-120),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m-long",
                conversationID: conversationID,
                sender: sophia,
                body: .text(String(repeating: "This is a long message for Dynamic Type wrapping. ", count: 6)),
                sentAt: now.addingTimeInterval(-60),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m-fail",
                conversationID: conversationID,
                sender: me,
                body: .text("This send failed and must be retryable."),
                sentAt: now.addingTimeInterval(-30),
                delivery: .failed,
                isOwn: true,
                localDraft: "This send failed and must be retryable."
            )
        ]
    }
}

#if DEBUG
/// DEBUG-only screenshot seed (`--debug-messages-fixture`). Never compiled into Release,
/// never sent to the server. Times are relative to launch so labels read naturally.
enum MessagingDebugFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-messages-fixture") }
    static let viewerID = "uitest-local-modules"

    static let sophia = ConversationParticipant(id: "fx-sophia", handle: "sophia.chen", displayName: "Sophia Chen", avatarURL: nil)
    static let marcus = ConversationParticipant(id: "fx-marcus", handle: "marcus", displayName: "Marcus Lee", avatarURL: nil)
    static let noor = ConversationParticipant(id: "fx-noor", handle: "noor", displayName: "Noor Haddad", avatarURL: nil)
    static let kai = ConversationParticipant(id: "fx-kai", handle: "kaij", displayName: "Kai Jensen", avatarURL: nil)
    static let me = ConversationParticipant(id: viewerID, handle: "modules", displayName: "You", avatarURL: nil)

    static func requests(now: Date = Date()) -> [MessageRequest] {
        let zoe = ConversationParticipant(id: "fx-zoe", handle: "zoe.adler", displayName: "Zoe Adler", avatarURL: nil)
        let ravi = ConversationParticipant(id: "fx-ravi", handle: "ravi", displayName: "Ravi Patel", avatarURL: nil)
        return [
            MessageRequest(id: "fx-req-zoe", conversationID: nil, sender: zoe,
                           preview: "Hi! Loved your Vault Notes module. Could I ask a couple of questions about the sync?",
                           createdAt: now.addingTimeInterval(-15 * 60)),
            MessageRequest(id: "fx-req-ravi", conversationID: nil, sender: ravi,
                           preview: "Hey, are you open to collaborating on a Moliboo outfit pack?",
                           createdAt: now.addingTimeInterval(-3 * 3600)),
        ]
    }

    static func inbox(now: Date = Date()) -> [Conversation] {
        func c(_ id: String, _ kind: ConversationKind, _ people: [ConversationParticipant], _ body: String, from: String?,
               minutes: Double, unread: Int, title: String? = nil) -> Conversation {
            let at = now.addingTimeInterval(-minutes * 60)
            return Conversation(id: id, kind: kind, participants: people,
                                lastMessage: MessagePreview(id: "\(id)-last", body: body, sentAt: at, senderID: from),
                                unreadCount: unread, updatedAt: at, titleOverride: title)
        }
        return [
            c("fx-sophia", .direct, [sophia], "Are you still working on the module SDK? I have a few ideas for the bridge.", from: sophia.id, minutes: 2, unread: 2),
            c("fx-crew", .group, [marcus, noor, kai], "Shipping the glass header tonight 🚀", from: marcus.id, minutes: 24, unread: 5, title: "Design crew"),
            c("fx-marcus", .direct, [marcus], "Sounds good, see you tomorrow.", from: viewerID, minutes: 70, unread: 0),
            c("fx-noor", .direct, [noor], "Sent you the Vault Notes build notes.", from: noor.id, minutes: 60 * 26, unread: 0),
            c("fx-kai", .direct, [kai], "Haha that Moliboo is adorable", from: kai.id, minutes: 60 * 24 * 4, unread: 0),
        ]
    }

    static func thread(_ id: ConversationID, now: Date = Date()) -> [Message] {
        func m(_ mid: String, _ who: ConversationParticipant, _ text: String, minutes: Double, _ state: MessageDeliveryState = .sent) -> Message {
            Message(id: mid, conversationID: id, sender: who, body: .text(text), sentAt: now.addingTimeInterval(-minutes * 60),
                    delivery: state, isOwn: who.id == viewerID, localDraft: state == .failed ? text : nil)
        }
        return [
            m("t1", sophia, "Hey! Did you see the new Activity tab?", minutes: 60 * 25),
            m("t2", me, "Yes, the glass chips came out really nice.", minutes: 60 * 25 - 2, .read),
            m("t3", sophia, "Are you still working on the module SDK?", minutes: 6),
            m("t4", sophia, "I have a few ideas for the bridge — mostly around permissions.", minutes: 5),
            m("t5", me, "Always. Send them over and I'll take a look tonight.", minutes: 4, .read),
            m("t6", me, "Also: https://modula.digital", minutes: 3, .delivered),
            m("t7", sophia, "Perfect, writing it up now", minutes: 2),
            m("t8", me, "This one didn't go through.", minutes: 1, .failed),
        ]
    }
}
#endif
