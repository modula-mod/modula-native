import Foundation
import Observation

@MainActor @Observable
final class HomeStore {
    private let repository: GreenfieldHomeRepository
    private(set) var modes: [HomeMode: HomeModeState] = [
        .following: HomeModeState(),
        .forYou: HomeModeState(),
        .modules: HomeModeState()
    ]
    private(set) var actionError: String?
    var isOfflineHint = false

    init(client: GreenfieldClient) {
        self.repository = GreenfieldHomeRepository(client: client)
    }

    func state(for mode: HomeMode) -> HomeModeState {
        modes[mode] ?? HomeModeState()
    }

    func summary(for mode: HomeMode) -> FeedSummary {
        let state = modes[mode] ?? HomeModeState()
        return .aggregate(from: state.items, rankingVersion: state.rankingVersion)
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
            if hasContent, let previousFirstID, let freshFirst = page.items.first?.id, freshFirst != previousFirstID {
                state.newerAvailable = true
            }
            state.items = page.items
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
                state.items = cached.items
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
                state.items = cached.items
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
            let existing = Set(state.items.map(\.id))
            state.items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
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

    func acknowledgeNewer(_ mode: HomeMode) {
        modes[mode]?.newerAvailable = false
    }

    func toggleLike(_ post: SocialPost, mode: HomeMode) async {
        let nextLiked = !post.liked
        applyEngagement(postID: post.id, mode: mode) { item in
            item.liked = nextLiked
            item.likeCount = max(0, item.likeCount + (nextLiked ? 1 : -1))
            if nextLiked { item.viewerReaction = .like }
            else if item.viewerReaction == .like { item.viewerReaction = nil }
        }
        do {
            if nextLiked {
                try await repository.like(postID: post.id)
            } else {
                try await repository.unlike(postID: post.id)
            }
            HapticEngine.shared.play(.selection)
        } catch {
            applyEngagement(postID: post.id, mode: mode) { item in
                item.liked = post.liked
                item.likeCount = post.likeCount
                item.viewerReaction = post.viewerReaction
            }
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not update like."
            HapticEngine.shared.play(.failure)
        }
    }

    func toggleSave(_ post: SocialPost, mode: HomeMode) async {
        let nextSaved = !post.saved
        applyEngagement(postID: post.id, mode: mode) { item in
            item.saved = nextSaved
        }
        do {
            if nextSaved {
                try await repository.save(postID: post.id)
            } else {
                try await repository.unsave(postID: post.id)
            }
            HapticEngine.shared.play(.selection)
        } catch {
            applyEngagement(postID: post.id, mode: mode) { item in
                item.saved = post.saved
            }
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not update save."
            HapticEngine.shared.play(.failure)
        }
    }

    func toggleRepost(_ post: SocialPost, mode: HomeMode) async {
        let nextReposted = !post.reposted
        applyEngagement(postID: post.id, mode: mode) { item in
            item.reposted = nextReposted
            item.repostCount = max(0, item.repostCount + (nextReposted ? 1 : -1))
        }
        do {
            if nextReposted {
                try await repository.repost(postID: post.id)
            } else {
                try await repository.unrepost(postID: post.id)
            }
            HapticEngine.shared.play(.confirmation)
        } catch {
            applyEngagement(postID: post.id, mode: mode) { item in
                item.reposted = post.reposted
                item.repostCount = post.repostCount
            }
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not update repost."
            HapticEngine.shared.play(.failure)
        }
    }

    func clearActionError() { actionError = nil }

    private func applyEngagement(postID: SocialPostID, mode: HomeMode, mutate: (inout SocialPost) -> Void) {
        guard var state = modes[mode] else { return }
        state.items = state.items.map { item in
            guard item.id == postID else { return item }
            var copy = item
            mutate(&copy)
            return copy
        }
        modes[mode] = state
    }
}
