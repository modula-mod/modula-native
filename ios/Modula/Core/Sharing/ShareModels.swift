import Foundation

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
            let url = URL(string: raw) ?? URL(string: "https://modula.digital")!
            return .link(url: url, title: nil)
        }
    }

    var canonicalURL: URL {
        switch self {
        case .profile(let identity, _, _, _):
            if identity == "me" {
                return URL(string: "https://modula.digital/me")!
            }
            return URL(string: "https://modula.digital/profile/\(identity)")!
        case .post(let id, _, _, _):
            return URL(string: "https://modula.digital/post/\(id)")!
        case .module(let id, _, _):
            return URL(string: "https://modula.digital/product-hub/module/\(id)")!
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

    static func messageBodyFallback(for payload: SharePayload) -> String {
        payload.canonicalURL.absoluteString
    }
}
