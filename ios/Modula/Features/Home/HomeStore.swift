import Foundation
import Observation

@MainActor @Observable
final class HomeStore {
    private let repository: GreenfieldHomeRepository
    private let posts: PostStateStore
    private let postActions: PostActionController
    private(set) var modes: [HomeMode: HomeModeState] = [
        .following: HomeModeState(),
        .forYou: HomeModeState(),
        .modules: HomeModeState()
    ]
    private(set) var actionError: String?
    var isOfflineHint = false

    init(client: GreenfieldClient, posts: PostStateStore, postActions: PostActionController) {
        self.repository = GreenfieldHomeRepository(client: client)
        self.posts = posts
        self.postActions = postActions
    }

    func state(for mode: HomeMode) -> HomeModeState {
        modes[mode] ?? HomeModeState()
    }

    func summary(for mode: HomeMode) -> FeedSummary {
        let state = modes[mode] ?? HomeModeState()
        return .aggregate(from: visibleItems(state.items), rankingVersion: state.rankingVersion)
    }

    func loadIfNeeded(_ mode: HomeMode, signedIn: Bool) async {
        if mode.requiresAuth && !signedIn {
            modes[mode] = HomeModeState(loadState: .loaded)
            return
        }
        let current = state(for: mode)
        guard current.loadState == .idle || current.items.isEmpty else { return }
        await refresh(mode, signedIn: signedIn)
    }

    func refresh(_ mode: HomeMode, signedIn: Bool) async {
        if mode.requiresAuth && !signedIn {
            modes[mode] = HomeModeState(loadState: .loaded)
            isOfflineHint = false
            return
        }
        var state = self.state(for: mode)
        let previousFirstID = state.items.first?.id
        let hasContent = !state.items.isEmpty
        state.loadState = hasContent ? .refreshing : .loading
        state.lastError = nil
        state.newerAvailable = false
        modes[mode] = state
        do {
            let page = try await repository.refresh(mode: mode)
            postActions.ingest(page.items)
            if hasContent, let previousFirstID, let freshFirst = page.items.first?.id, freshFirst != previousFirstID {
                state.newerAvailable = true
            }
            state.items = page.items.map(posts.resolved)
            state.nextCursor = page.nextCursor
            state.hasMore = page.hasMore
            state.rankingVersion = page.rankingVersion
            state.loadState = .loaded
            state.lastRefresh = Date()
            state.lastError = nil
            modes[mode] = state
            actionError = nil
            isOfflineHint = false
        } catch let api as APIError {
            if hasContent {
                state.loadState = .loaded
                state.lastError = api.userFacingMessage
                modes[mode] = state
                actionError = api.userFacingMessage
                isOfflineHint = api != .unauthenticated
            } else if let cached = await repository.cachedPage(mode: mode), !cached.items.isEmpty {
                postActions.ingest(cached.items)
                state.items = cached.items.map(posts.resolved)
                state.nextCursor = cached.nextCursor
                state.hasMore = cached.hasMore
                state.rankingVersion = cached.rankingVersion
                state.loadState = .loaded
                state.lastError = api.userFacingMessage
                modes[mode] = state
                isOfflineHint = true
            } else {
                state.loadState = .failed(api.userFacingMessage)
                state.lastError = api.userFacingMessage
                modes[mode] = state
                isOfflineHint = false
            }
            if api == .unauthenticated { isOfflineHint = false }
        } catch {
            let message = "Unable to load home feed."
            if hasContent {
                state.loadState = .loaded
                modes[mode] = state
                actionError = message
                isOfflineHint = true
            } else if let cached = await repository.cachedPage(mode: mode), !cached.items.isEmpty {
                postActions.ingest(cached.items)
                state.items = cached.items.map(posts.resolved)
                state.nextCursor = cached.nextCursor
                state.hasMore = cached.hasMore
                state.rankingVersion = cached.rankingVersion
                state.loadState = .loaded
                state.lastError = message
                modes[mode] = state
                isOfflineHint = true
            } else {
                state.loadState = .failed(message)
                modes[mode] = state
            }
        }
    }

    func loadMore(_ mode: HomeMode) async {
        var state = self.state(for: mode)
        guard state.hasMore || state.nextCursor != nil else { return }
        guard let cursor = state.nextCursor, state.loadState == .loaded else { return }
        state.loadState = .loadingMore
        modes[mode] = state
        do {
            let page = try await repository.page(mode: mode, cursor: cursor)
            postActions.ingest(page.items)
            let existing = Set(state.items.map(\.id))
            state.items.append(contentsOf: page.items.filter { !existing.contains($0.id) }.map(posts.resolved))
            state.nextCursor = page.nextCursor
            state.hasMore = page.hasMore
            if let ranking = page.rankingVersion { state.rankingVersion = ranking }
            state.loadState = .loaded
            modes[mode] = state
        } catch {
            state.loadState = .loaded
            modes[mode] = state
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not load more."
        }
    }

    func ingestPublished(_ post: SocialPost) {
        posts.upsert(post)
        let isPublic = post.visibility == .public || post.audience == "public" || post.audience == nil
        guard isPublic else { return }
        var state = self.state(for: .following)
        if let index = state.items.firstIndex(where: { $0.id == post.id }) {
            state.items[index] = post
        } else {
            state.items.insert(post, at: 0)
        }
        modes[.following] = state
    }

    func acknowledgeNewer(_ mode: HomeMode) {
        modes[mode]?.newerAvailable = false
    }

    func toggleLike(_ post: SocialPost, mode: HomeMode) async {
        postActions.ingest(post)
        await postActions.toggleLike(post)
        sync(postID: post.id, mode: mode)
        actionError = postActions.lastError
    }

    func toggleSave(_ post: SocialPost, mode: HomeMode) async {
        postActions.ingest(post)
        await postActions.toggleSave(post)
        sync(postID: post.id, mode: mode)
        actionError = postActions.lastError
    }

    func toggleRepost(_ post: SocialPost, mode: HomeMode) async {
        postActions.ingest(post)
        await postActions.toggleRepost(post)
        sync(postID: post.id, mode: mode)
        actionError = postActions.lastError
    }

    func clearActionError() {
        actionError = nil
        postActions.clearError()
    }

    /// Re-resolve feed rows from the shared post store (after engagement elsewhere).
    func syncVisibleEngagement() {
        for mode in HomeMode.allCases {
            guard var state = modes[mode] else { continue }
            state.items = visibleItems(state.items.map(posts.resolved))
            modes[mode] = state
        }
    }

    private func sync(postID: SocialPostID, mode: HomeMode) {
        guard var state = modes[mode] else { return }
        state.items = state.items.map { item in
            guard item.id == postID else { return item }
            return posts.resolved(item)
        }
        // Also sync other modes that show the same post.
        modes[mode] = state
        for other in HomeMode.allCases where other != mode {
            guard var otherState = modes[other] else { continue }
            otherState.items = otherState.items.map { item in
                guard item.id == postID else { return item }
                return posts.resolved(item)
            }
            modes[other] = otherState
        }
    }

    private func visibleItems(_ items: [SocialPost]) -> [SocialPost] {
        items.filter { !posts.isHidden($0.id) }.map(posts.resolved)
    }
}
