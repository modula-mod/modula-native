import Foundation
import Observation

@MainActor @Observable
final class SavedStore {
    private let repository: SavedRepository
    let capabilities: SavedBackendCapabilities
    private(set) var posts: [SocialPost] = []
    private(set) var nextCursor: String?
    private(set) var hasMore = false
    private(set) var loading = false
    private(set) var loaded = false
    var error: String?
    /// Backend list remains OPEN until VPS confirms.
    var backendListOpen: Bool { !capabilities.listSavedPosts }

    init(client: GreenfieldClient, capabilities: SavedBackendCapabilities = .production) {
        self.repository = GreenfieldSavedRepository(client: client, capabilities: capabilities)
        self.capabilities = capabilities
    }

    func load(force: Bool = false) async {
        guard capabilities.listSavedPosts else {
            loaded = true
            error = nil
            posts = []
            return
        }
        guard force || !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await repository.savedPosts(cursor: nil)
            posts = page.posts
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            loaded = true
            error = nil
        } catch {
            self.error = "Saved posts couldn’t be loaded."
            loaded = true
        }
    }

    func loadMore() async {
        guard capabilities.listSavedPosts, hasMore, let cursor = nextCursor, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await repository.savedPosts(cursor: cursor)
            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            self.error = "Couldn’t load more saved posts."
        }
    }

    func unsave(postID: SocialPostID, postActions: PostActionController) async {
        let previous = posts
        guard let post = posts.first(where: { $0.id == postID }) else { return }
        posts.removeAll { $0.id == postID }
        // Reuse N4B save toggle path so engagement state stays canonical.
        if post.saved {
            await postActions.toggleSave(post)
            if postActions.lastError != nil {
                posts = previous
                self.error = postActions.lastError
            }
            return
        }
        do {
            try await repository.unsave(postID: postID)
        } catch {
            posts = previous
            self.error = "Couldn’t unsave that post."
        }
    }
}
