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
    /// Bumped by every refresh. A page that was requested under an older generation is
    /// dropped instead of overwriting the refreshed list (pull-to-refresh while the
    /// next page is still loading used to resurrect the stale feed).
    private var generations: [HomeMode: Int] = [:]
    private(set) var displayOptions: [String: HomeFeedDisplayOptions] = [:]
    private let displayOptionsKey = "modula.native.home.feed-display.v1"

    init(client: GreenfieldClient, posts: PostStateStore, postActions: PostActionController) {
        self.repository = GreenfieldHomeRepository(client: client)
        self.posts = posts
        self.postActions = postActions
        if let data = UserDefaults.standard.data(forKey: displayOptionsKey),
           let decoded = try? JSONDecoder().decode([String: HomeFeedDisplayOptions].self, from: data) {
            displayOptions = decoded
        }
    }

    func displayOptions(for mode: HomeMode) -> HomeFeedDisplayOptions {
        // Settings → Feed supplies the defaults; a per-mode choice made on Home wins.
        displayOptions[mode.rawValue] ?? HomeFeedDisplayOptions(
            mediaOnly: ModulaPreferences.feedMediaOnlyByDefault,
            hideModules: ModulaPreferences.feedHideModulePostsByDefault
        )
    }

    func setDisplayOptions(_ options: HomeFeedDisplayOptions, for mode: HomeMode) {
        displayOptions[mode.rawValue] = options
        if let data = try? JSONEncoder().encode(displayOptions) {
            UserDefaults.standard.set(data, forKey: displayOptionsKey)
        }
    }

    func visiblePosts(for mode: HomeMode) -> [SocialPost] {
        applyDisplay(visibleItems(state(for: mode).items), mode: mode)
    }

    func state(for mode: HomeMode) -> HomeModeState {
        modes[mode] ?? HomeModeState()
    }

    func summary(for mode: HomeMode) -> FeedSummary {
        let state = modes[mode] ?? HomeModeState()
        return .aggregate(from: visiblePosts(for: mode), rankingVersion: state.rankingVersion)
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
        generations[mode, default: 0] += 1
        let generation = generations[mode, default: 0]
        var state = self.state(for: mode)
        // Stale-while-revalidate: paint last launch's first page now, replace it when
        // the network answers (no "New posts" pill for that swap).
        var seededFromWarm = false
        if state.items.isEmpty, let warm = await repository.warmPage(mode: mode),
           generation == generations[mode, default: 0], self.state(for: mode).items.isEmpty {
            postActions.ingest(warm.items)
            state.items = warm.items.map(posts.resolved)
            state.nextCursor = nil
            state.hasMore = false
            state.rankingVersion = warm.rankingVersion
            seededFromWarm = true
        }
        let previousFirstID = seededFromWarm ? nil : state.items.first?.id
        let hasContent = !state.items.isEmpty
        state.loadState = hasContent ? .refreshing : .loading
        state.lastError = nil
        state.loadMoreError = nil
        state.newerAvailable = false
        modes[mode] = state
        do {
            let page = try await repository.refresh(mode: mode)
            guard generation == generations[mode, default: 0] else { return }
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
            guard generation == generations[mode, default: 0] else { return }
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
            guard generation == generations[mode, default: 0] else { return }
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
        state.loadMoreError = nil
        modes[mode] = state
        let generation = generations[mode, default: 0]
        do {
            let page = try await repository.page(mode: mode, cursor: cursor)
            // A refresh started meanwhile owns the list now; drop this stale page.
            guard generation == generations[mode, default: 0] else { return }
            state = self.state(for: mode)
            postActions.ingest(page.items)
            let existing = Set(state.items.map(\.id))
            state.items.append(contentsOf: page.items.filter { !existing.contains($0.id) }.map(posts.resolved))
            state.nextCursor = page.nextCursor
            state.hasMore = page.hasMore
            if let ranking = page.rankingVersion { state.rankingVersion = ranking }
            state.loadState = .loaded
            modes[mode] = state
        } catch {
            guard generation == generations[mode, default: 0] else { return }
            state = self.state(for: mode)
            state.loadState = .loaded
            state.loadMoreError = (error as? APIError)?.userFacingMessage ?? "Could not load more."
            modes[mode] = state
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

    private func applyDisplay(_ items: [SocialPost], mode: HomeMode) -> [SocialPost] {
        let options = displayOptions(for: mode)
        return items.filter { post in
            if options.hideModules, post.kind == .module { return false }
            if options.mediaOnly, !post.hasMedia, post.kind != .media, post.kind != .carousel, post.kind != .video {
                return false
            }
            return true
        }
    }
}
