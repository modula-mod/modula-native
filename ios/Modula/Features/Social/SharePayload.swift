import Foundation

/// Minimal share payload for post/context surfaces. Full Universal Share lands in a later phase.
enum SharePayload: Hashable, Sendable {
    case profile(identity: String, displayName: String?, handle: String?, avatarURL: URL?)
    case post(id: String, authorName: String?, excerpt: String?, hasMedia: Bool)
    case module(id: String, name: String?, publisher: String?)
    case link(url: URL, title: String?)

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
