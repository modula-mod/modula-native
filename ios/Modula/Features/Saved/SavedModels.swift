import Foundation

struct SavedBackendCapabilities: Sendable, Equatable {
    /// Per-post save toggle exists (N4B).
    var toggleSave = true
    /// List of saved posts from Greenfield.
    var listSavedPosts = false
    var listSavedModules = false
    var listSavedLinks = false
    var pagination = false
    var unsaveFromList = true

    static let production = SavedBackendCapabilities()

    enum Paths {
        /// Provisional until VPS confirms.
        static func savedPosts(cursor: String?) -> String {
            var path = "/v1/saved/posts?limit=30"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&cursor=\(encoded)"
            }
            return path
        }
    }
}

enum SavedSection: String, CaseIterable, Codable, Hashable {
    case root
    case posts
    case modules
    case links
}

struct SavedPage: Sendable, Equatable {
    var posts: [SocialPost]
    var nextCursor: String?
    var hasMore: Bool
}

protocol SavedRepository: Sendable {
    var capabilities: SavedBackendCapabilities { get }
    func savedPosts(cursor: String?) async throws -> SavedPage
    func unsave(postID: SocialPostID) async throws
}

actor GreenfieldSavedRepository: SavedRepository {
    private let client: GreenfieldClient
    let capabilities: SavedBackendCapabilities
    private let posts: GreenfieldPostRepository

    init(
        client: GreenfieldClient,
        capabilities: SavedBackendCapabilities = .production
    ) {
        self.client = client
        self.capabilities = capabilities
        self.posts = GreenfieldPostRepository(client: client)
    }

    func savedPosts(cursor: String?) async throws -> SavedPage {
        guard capabilities.listSavedPosts else {
            throw APIError.unavailable("Saved list is not available yet.")
        }
        let value: JSONValue = try await client.authenticatedJSON(
            "GET",
            path: SavedBackendCapabilities.Paths.savedPosts(cursor: cursor),
            body: nil
        )
        let items = (value["items"]?.array ?? value["posts"]?.array ?? []).compactMap(SocialPayloadDecoder.post)
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        return SavedPage(
            posts: items,
            nextCursor: next,
            hasMore: value["hasMore"]?.bool ?? (next != nil)
        )
    }

    func unsave(postID: SocialPostID) async throws {
        guard capabilities.unsaveFromList || capabilities.toggleSave else {
            throw APIError.unavailable("Unsave is not available.")
        }
        try await posts.unsave(postID: postID)
    }
}
