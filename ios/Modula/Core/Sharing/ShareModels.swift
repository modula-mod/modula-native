import Foundation

/// Single source of truth for public share links. Every share surface
/// (post/profile models, share sheet, Product Hub, Reels) builds URLs here
/// so the format stays consistent and an odd id can never crash.
enum ModulaShareLink {
    static let base = URL(string: "https://modula.digital") ?? URL(fileURLWithPath: "/")

    static func link(_ components: String...) -> URL {
        components.reduce(base) { $0.appending(path: $1) }
    }

    static func profile(_ identity: String) -> URL { identity == "me" ? link("me") : link("profile", identity) }
    static func post(_ id: String) -> URL { link("post", id) }
    /// Product page (not `/module/:id`, which launches the module runtime).
    static func module(_ id: String) -> URL { link("product-hub", "module", id) }
    static func story(_ id: String) -> URL { link("stories", id) }
    static func reel(_ id: String) -> URL { link("reels", id) }
    static func conversation(_ id: String) -> URL { link("messages", id) }

    static func url(for route: AppRoute) -> URL {
        switch route {
        case .profile(let id, _): profile(id)
        case .me: link("me")
        case .post(let id, _): post(id)
        case .stories(.story(let id)): story(id)
        case .reels(.reel(let id)): reel(id)
        case .messages(.conversation(let id)): conversation(id)
        case .productHub(.module(let id, _)): module(id)
        default: base
        }
    }
}

/// Unified share payload. Profile / Post / Module / Link share one sheet architecture.
enum SharePayload: Hashable, Sendable {
    case profile(identity: String, displayName: String?, handle: String?, avatarURL: URL?)
    case post(id: String, authorName: String?, excerpt: String?, hasMedia: Bool)
    case module(id: String, name: String?, publisher: String?)
    case link(url: URL, title: String?)

    static func from(_ ref: SharePayloadRef) -> SharePayload {
        switch ref {
        case .profile(let id):
            return .profile(identity: id, displayName: nil, handle: nil, avatarURL: nil)
        case .post(let id):
            return .post(id: id, authorName: nil, excerpt: nil, hasMedia: false)
        case .module(let id):
            return .module(id: id, name: nil, publisher: nil)
        case .link(let raw):
            let url = URL(string: raw) ?? ModulaShareLink.base
            return .link(url: url, title: nil)
        }
    }

    var canonicalURL: URL {
        switch self {
        case .profile(let identity, _, _, _):
            return ModulaShareLink.profile(identity)
        case .post(let id, _, _, _):
            return ModulaShareLink.post(id)
        case .module(let id, _, _):
            return ModulaShareLink.module(id)
        case .link(let url, _):
            return url
        }
    }

    var title: String {
        switch self {
        case .profile(_, let name, let handle, _):
            return name ?? handle.map { "@\($0)" } ?? "Profile"
        case .post(_, let author, let excerpt, _):
            if let excerpt, !excerpt.isEmpty { return excerpt }
            return author.map { "Post by \($0)" } ?? "Post"
        case .module(_, let name, _):
            return name ?? "Module"
        case .link(_, let title):
            return title ?? "Link"
        }
    }
}

enum ShareDestinationKind: String, CaseIterable, Sendable, Hashable {
    case copyLink
    case messages
    case inMail
    case systemShare
    case saveToCollection
    case qr
}

struct ShareDestination: Identifiable, Sendable, Hashable {
    let kind: ShareDestinationKind
    let title: String
    let subtitle: String?
    let icon: SemanticIcon
    let availability: CommandAvailability

    var id: String { kind.rawValue }
}

enum ShareDestinationRegistry {
    static func destinations(
        for payload: SharePayload,
        messagingSend: Bool,
        inMailCompose: Bool,
        collectionsAvailable: Bool
    ) -> [ShareDestination] {
        var items: [ShareDestination] = [
            .init(
                kind: .copyLink,
                title: "Copy Link",
                subtitle: "Canonical Modula URL",
                icon: .init("link"),
                availability: .available
            ),
            .init(
                kind: .systemShare,
                title: "System Share",
                subtitle: "Share outside Modula",
                icon: .init("square.and.arrow.up"),
                availability: .available
            )
        ]

        items.append(.init(
            kind: .messages,
            title: "Messages",
            subtitle: "Share with a Modula conversation",
            icon: .init("bubble.left.and.bubble.right"),
            availability: messagingSend ? .available : .unavailable
        ))
        items.append(.init(
            kind: .inMail,
            title: "In-Mail",
            subtitle: "Prefill a private letter",
            icon: .init("envelope"),
            availability: inMailCompose ? .available : .unavailable
        ))

        switch payload {
        case .post, .link:
            items.append(.init(
                kind: .saveToCollection,
                title: "Save to Collection",
                subtitle: collectionsAvailable ? "On This Device" : nil,
                icon: .init("rectangle.stack.badge.plus"),
                availability: collectionsAvailable ? .available : .unavailable
            ))
        case .profile, .module:
            break
        }

        items.append(.init(
            kind: .qr,
            title: "QR Code",
            subtitle: "Show a scannable link",
            icon: .init("qrcode"),
            availability: .available
        ))

        return items.filter { $0.availability == .available }
    }
}

@MainActor
enum ShareCoordinator {
    static func copyLink(_ payload: SharePayload) -> String {
        payload.canonicalURL.absoluteString
    }

    static func systemShareItems(for payload: SharePayload) -> [Any] {
        [payload.canonicalURL]
    }

    static func inMailPrefill(for payload: SharePayload) -> InMailDraft {
        var draft = InMailDraft()
        draft.subject = payload.title
        draft.body = payload.canonicalURL.absoluteString
        return draft
    }

    nonisolated static func messageBodyFallback(for payload: SharePayload) -> String {
        payload.canonicalURL.absoluteString
    }
}

/// Text actually posted to a DM. The note is the person's words; the link is the canonical share URL.
enum ShareOutboundMessage {
    static func text(note: String, payload: SharePayload) -> String {
        let link = ShareCoordinator.messageBodyFallback(for: payload)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return link }
        return trimmed + "\n" + link
    }
}

/// One person on the share sheet. `conversationID` is set only when a direct chat already exists.
struct ShareRecipient: Identifiable, Hashable, Sendable {
    let personID: String
    let handle: String
    let displayName: String
    let avatarURL: URL?
    let conversationID: ConversationID?

    var id: String { key }

    var key: String {
        let handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handle.isEmpty { return handle.lowercased() }
        return personID.lowercased()
    }

    var hasDirectChat: Bool { conversationID != nil }

    var subtitle: String {
        let who = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = who.isEmpty ? displayName : "@\(who)"
        return hasDirectChat ? label : "\(label) · No chat yet"
    }
}

enum ShareAudience {
    /// Direct chats first (they can take a message), then other real people who are not already listed.
    static func recipients(
        conversations: [Conversation],
        suggestions: [DiscoverPerson],
        ownID: String?,
        ownHandle: String?
    ) -> [ShareRecipient] {
        var ordered: [ShareRecipient] = []
        var seen = Set<String>()

        for conversation in conversations where isDirectMessage(conversation) {
            let others = others(in: conversation, ownID: ownID, ownHandle: ownHandle)
            for person in others {
                guard !ModulaFixtureFilter.isFixture(name: person.displayName, handle: person.handle) else { continue }
                let recipient = ShareRecipient(
                    personID: person.id,
                    handle: person.handle,
                    displayName: person.displayName.isEmpty ? conversation.title : person.displayName,
                    avatarURL: person.avatarURL,
                    conversationID: conversation.id
                )
                append(recipient, to: &ordered, seen: &seen)
            }
        }

        for person in suggestions {
            guard !isOwn(id: person.id, handle: person.handle, ownID: ownID, ownHandle: ownHandle) else { continue }
            guard !ModulaFixtureFilter.isFixture(name: person.displayName, handle: person.handle) else { continue }
            let match = directConversationID(matching: person.handle.isEmpty ? person.id : person.handle, in: conversations)
            let recipient = ShareRecipient(
                personID: person.id,
                handle: person.handle,
                displayName: person.displayName,
                avatarURL: person.avatarURL,
                conversationID: match
            )
            append(recipient, to: &ordered, seen: &seen)
        }
        return ordered
    }

    /// The 1:1 thread for a handle or id, using the same match the inbox already uses for direct chats.
    static func directConversationID(matching token: String, in conversations: [Conversation]) -> ConversationID? {
        let key = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !key.isEmpty else { return nil }
        return conversations.first { conversation in
            isDirectMessage(conversation) && conversation.participants.contains {
                $0.handle.lowercased() == key || $0.id.lowercased() == key
            }
        }?.id
    }

    static func isDirectMessage(_ conversation: Conversation) -> Bool {
        switch conversation.kind {
        case .group, .request:
            return false
        case .direct:
            return conversation.participants.count <= 2
        case .unknown:
            return conversation.participants.count <= 2 && !conversation.participants.isEmpty
        }
    }

    private static func others(in conversation: Conversation, ownID: String?, ownHandle: String?) -> [ConversationParticipant] {
        conversation.participants.filter {
            !isOwn(id: $0.id, handle: $0.handle, ownID: ownID, ownHandle: ownHandle)
        }
    }

    private static func isOwn(id: String, handle: String, ownID: String?, ownHandle: String?) -> Bool {
        if let ownID, !ownID.isEmpty, id.caseInsensitiveCompare(ownID) == .orderedSame { return true }
        let own = ownHandle?.trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
        if !own.isEmpty, handle.caseInsensitiveCompare(own) == .orderedSame { return true }
        return false
    }

    private static func append(_ recipient: ShareRecipient, to ordered: inout [ShareRecipient], seen: inout Set<String>) {
        guard !recipient.key.isEmpty, seen.insert(recipient.key).inserted else { return }
        if !recipient.personID.isEmpty { seen.insert(recipient.personID.lowercased()) }
        ordered.append(recipient)
    }
}
