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
