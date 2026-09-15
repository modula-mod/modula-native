import Foundation
import Observation

struct DiscoverPeopleState: Equatable {
    var items: [DiscoverPerson] = []
    var nextCursor: String?
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
    var filter = PeopleFilters()
}

struct DiscoverTopicsState: Equatable {
    var items: [DiscoverTopic] = []
    var nextCursor: String?
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
    var filter = TopicFilters()
}

struct DiscoverPostsState: Equatable {
    var items: [DiscoverPost] = []
    var nextCursor: String?
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
    var filter = PostFilters()
}

struct DiscoverModulesState: Equatable {
    var items: [CatalogueProduct] = []
    var featured: [CatalogueProduct] = []
    var nextCursor: String?
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
    var filter = ModuleFilters()
}

struct DiscoverTrendingState: Equatable {
    var dashboard: DiscoverDashboard?
    var previewPosts: [DiscoverPost] = []
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
}

struct DiscoverSearchState: Equatable {
    var query = ""
    var results: [SearchHit] = []
    var nextCursor: String?
    var loadState: DiscoverLoadState = .idle
    var lastError: String?
}

@MainActor @Observable
final class DiscoverStore {
    private let repository: GreenfieldDiscoverRepository
    private(set) var trending = DiscoverTrendingState()
    private(set) var people = DiscoverPeopleState()
    private(set) var topics = DiscoverTopicsState()
    private(set) var posts = DiscoverPostsState()
    private(set) var modules = DiscoverModulesState()
    private(set) var search = DiscoverSearchState()
    private(set) var actionError: String?
    private(set) var visitedScopes: Set<DiscoverRoute> = [.trending]
    var followBusyID: String?

    init(client: GreenfieldClient) {
        self.repository = GreenfieldDiscoverRepository(client: client)
    }

    func markVisited(_ scope: DiscoverRoute) {
        visitedScopes.insert(scope)
    }

    func loadIfNeeded(_ scope: DiscoverRoute) async {
        switch scope {
        case .trending:
            if trending.dashboard == nil { await refresh(.trending) }
        case .people:
            if people.items.isEmpty { await refresh(.people) }
        case .topics:
            if topics.items.isEmpty { await refresh(.topics) }
        case .posts:
            if posts.items.isEmpty { await refresh(.posts) }
        case .modules:
            if modules.items.isEmpty { await refresh(.modules) }
        }
    }

    func refresh(_ scope: DiscoverRoute) async {
        switch scope {
        case .trending: await refreshTrending()
        case .people: await refreshPeople()
        case .topics: await refreshTopics()
        case .posts: await refreshPosts()
        case .modules: await refreshModules()
        }
    }

    func loadMore(_ scope: DiscoverRoute) async {
        switch scope {
        case .posts:
            guard let cursor = posts.nextCursor, posts.loadState == .loaded else { return }
            posts.loadState = .loadingMore
            do {
                let page = try await repository.posts(cursor: cursor)
                let existing = Set(posts.items.map(\.id))
                posts.items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                posts.nextCursor = page.nextCursor
                posts.loadState = .loaded
            } catch {
                posts.loadState = .loaded
                actionError = (error as? APIError)?.userFacingMessage ?? "Could not load more posts."
            }
        case .modules:
            guard let cursor = modules.nextCursor, modules.loadState == .loaded else { return }
            modules.loadState = .loadingMore
            do {
                let page = try await repository.modules(cursor: cursor)
                let existing = Set(modules.items.map(\.id))
                modules.items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                modules.nextCursor = page.nextCursor
                modules.loadState = .loaded
            } catch {
                modules.loadState = .loaded
                actionError = (error as? APIError)?.userFacingMessage ?? "Could not load more modules."
            }
        default:
            break
        }
    }

    func setPeopleFilter(_ filter: PeopleFilters) {
        people.filter = filter
    }

    func setPostFilter(_ filter: PostFilters) {
        posts.filter = filter
    }

    func setModuleFilter(_ filter: ModuleFilters) {
        modules.filter = filter
    }

    func visiblePeople() -> [DiscoverPerson] {
        var items = people.items
        if people.filter.followingOnly { items = items.filter(\.isFollowing) }
        if people.filter.newestFirst {
            items.sort { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
        }
        return items
    }

    func visiblePosts() -> [DiscoverPost] {
        posts.items.filter { post in
            switch posts.filter.kind {
            case .all: true
            case .text: post.kind == .text
            case .media: post.kind == .media || post.kind == .image || post.kind == .video
            case .links: post.kind == .link
            }
        }
    }

    func visibleModules(installedIDs: Set<String>) -> [CatalogueProduct] {
        modules.items.filter { product in
            if modules.filter.installedOnly && !installedIDs.contains(product.id) { return false }
            if modules.filter.compatibleOnly && !product.installable { return false }
            if modules.filter.firstPartyOnly && !Self.isFirstParty(product) { return false }
            return true
        }
    }

    func follow(_ person: DiscoverPerson, signedIn: Bool) async -> Bool {
        guard signedIn else { return false }
        applyFollow(id: person.id, handle: person.handle, following: true)
        followBusyID = person.id
        defer { followBusyID = nil }
        do {
            try await repository.follow(person: person)
            HapticEngine.shared.play(.success)
            return true
        } catch {
            applyFollow(id: person.id, handle: person.handle, following: false)
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not follow."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    func unfollow(_ person: DiscoverPerson) async {
        applyFollow(id: person.id, handle: person.handle, following: false)
        followBusyID = person.id
        defer { followBusyID = nil }
        do {
            try await repository.unfollow(person: person)
            HapticEngine.shared.play(.confirmation)
        } catch {
            applyFollow(id: person.id, handle: person.handle, following: true)
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not unfollow."
            HapticEngine.shared.play(.failure)
        }
    }

    func performSearch(query: String, section: SearchSection?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        search.query = trimmed
        if section == .topics {
            await searchTopics(query: trimmed)
            return
        }
        guard !trimmed.isEmpty else {
            search.results = []
            search.nextCursor = nil
            search.loadState = .idle
            search.lastError = nil
            return
        }
        let hasContent = !search.results.isEmpty
        search.loadState = hasContent ? .refreshing : .loading
        search.lastError = nil
        do {
            let page = try await repository.search(query: trimmed, entityType: Self.entityType(section), cursor: nil)
            search.results = page.results
            search.nextCursor = page.nextCursor
            search.loadState = .loaded
        } catch let api as APIError {
            if hasContent {
                search.loadState = .loaded
                search.lastError = api.userFacingMessage
                actionError = api.userFacingMessage
            } else {
                search.loadState = .failed(api.userFacingMessage)
                search.lastError = api.userFacingMessage
            }
        } catch {
            let message = "Unable to search."
            search.loadState = hasContent ? .loaded : .failed(message)
            if !hasContent { search.lastError = message }
        }
    }

    func loadMoreSearch(section: SearchSection?) async {
        guard let cursor = search.nextCursor, search.loadState == .loaded, !search.query.isEmpty else { return }
        search.loadState = .loadingMore
        do {
            let page = try await repository.search(query: search.query, entityType: Self.entityType(section), cursor: cursor)
            let existing = Set(search.results.map(\.id))
            search.results.append(contentsOf: page.results.filter { !existing.contains($0.id) })
            search.nextCursor = page.nextCursor
            search.loadState = .loaded
        } catch {
            search.loadState = .loaded
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not load more results."
        }
    }

    func clearActionError() { actionError = nil }

    static func isFirstParty(_ product: CatalogueProduct) -> Bool {
        product.publisherId.lowercased().contains("modula")
            || product.publisherName.lowercased().contains("modula")
            || product.moduleId.hasPrefix("digital.modula.")
    }

    // MARK: - Private

    private func refreshTrending() async {
        let hasContent = trending.dashboard != nil
        trending.loadState = hasContent ? .refreshing : .loading
        trending.lastError = nil
        do {
            let dash = try await repository.dashboard()
            trending.dashboard = dash
            trending.loadState = .loaded
            trending.lastRefresh = Date()
            people.items = dash.people.sorted { $0.usefulness > $1.usefulness }
            people.loadState = .loaded
            people.lastRefresh = Date()
            topics.items = dash.topics
            topics.loadState = .loaded
            topics.lastRefresh = Date()
            if posts.items.isEmpty {
                await hydratePreviewPosts()
            } else {
                trending.previewPosts = Array(posts.items.prefix(2))
            }
            actionError = nil
        } catch let api as APIError {
            failTrending(api.userFacingMessage, keep: hasContent)
        } catch {
            failTrending("Unable to load Discover.", keep: hasContent)
        }
    }

    private func hydratePreviewPosts() async {
        do {
            let page = try await repository.posts(cursor: nil)
            posts.items = page.items
            posts.nextCursor = page.nextCursor
            posts.loadState = .loaded
            posts.lastRefresh = Date()
            trending.previewPosts = Array(page.items.prefix(2))
        } catch {
            trending.previewPosts = []
        }
    }

    private func refreshPeople() async {
        let hasContent = !people.items.isEmpty
        people.loadState = hasContent ? .refreshing : .loading
        people.lastError = nil
        do {
            let page = try await repository.people(cursor: nil)
            people.items = page.items
            people.nextCursor = page.nextCursor
            people.loadState = .loaded
            people.lastRefresh = Date()
            actionError = nil
        } catch let api as APIError {
            failPeople(api.userFacingMessage, keep: hasContent)
        } catch {
            failPeople("Unable to load people.", keep: hasContent)
        }
    }

    private func refreshTopics() async {
        let hasContent = !topics.items.isEmpty
        topics.loadState = hasContent ? .refreshing : .loading
        topics.lastError = nil
        do {
            let page = try await repository.topics(cursor: nil)
            topics.items = page.items
            topics.nextCursor = page.nextCursor
            topics.loadState = .loaded
            topics.lastRefresh = Date()
            actionError = nil
        } catch let api as APIError {
            failTopics(api.userFacingMessage, keep: hasContent)
        } catch {
            failTopics("Unable to load topics.", keep: hasContent)
        }
    }

    private func refreshPosts() async {
        let hasContent = !posts.items.isEmpty
        posts.loadState = hasContent ? .refreshing : .loading
        posts.lastError = nil
        do {
            let page = try await repository.posts(cursor: nil)
            posts.items = page.items
            posts.nextCursor = page.nextCursor
            posts.loadState = .loaded
            posts.lastRefresh = Date()
            trending.previewPosts = Array(page.items.prefix(2))
            actionError = nil
        } catch let api as APIError {
            failPosts(api.userFacingMessage, keep: hasContent)
        } catch {
            failPosts("Unable to load posts.", keep: hasContent)
        }
    }

    private func refreshModules() async {
        let hasContent = !modules.items.isEmpty
        modules.loadState = hasContent ? .refreshing : .loading
        modules.lastError = nil
        do {
            let page = try await repository.modules(cursor: nil)
            let featured = (try? await repository.dashboard())?.featuredModules ?? []
            modules.items = page.items
            modules.nextCursor = page.nextCursor
            modules.featured = featured.compactMap { GreenfieldDiscoverRepository.resolve($0, in: page.items) }
            modules.loadState = .loaded
            modules.lastRefresh = Date()
            actionError = nil
        } catch let api as APIError {
            failModules(api.userFacingMessage, keep: hasContent)
        } catch {
            failModules("Unable to load modules.", keep: hasContent)
        }
    }

    private func applyFollow(id: String, handle: String, following: Bool) {
        func update(_ person: DiscoverPerson) -> DiscoverPerson {
            guard person.id == id || person.handle == handle else { return person }
            return DiscoverPerson(
                id: person.id, handle: person.handle, displayName: person.displayName, kind: person.kind,
                bio: person.bio, avatarURL: person.avatarURL, followerCount: person.followerCount,
                followingCount: person.followingCount, postCount: person.postCount,
                isFollowing: following, followsViewer: person.followsViewer, isVerified: person.isVerified,
                joinedAt: person.joinedAt
            )
        }
        people.items = people.items.map(update)
        if var dash = trending.dashboard {
            dash.people = dash.people.map(update)
            trending.dashboard = dash
        }
    }

    private func failTrending(_ message: String, keep: Bool) {
        if keep {
            trending.loadState = .loaded
            trending.lastError = message
            actionError = message
        } else {
            trending.loadState = .failed(message)
            trending.lastError = message
        }
    }

    private func failPeople(_ message: String, keep: Bool) {
        if keep { people.loadState = .loaded; people.lastError = message; actionError = message }
        else { people.loadState = .failed(message); people.lastError = message }
    }

    private func failTopics(_ message: String, keep: Bool) {
        if keep { topics.loadState = .loaded; topics.lastError = message; actionError = message }
        else { topics.loadState = .failed(message); topics.lastError = message }
    }

    private func failPosts(_ message: String, keep: Bool) {
        if keep { posts.loadState = .loaded; posts.lastError = message; actionError = message }
        else { posts.loadState = .failed(message); posts.lastError = message }
    }

    private func failModules(_ message: String, keep: Bool) {
        if keep { modules.loadState = .loaded; modules.lastError = message; actionError = message }
        else { modules.loadState = .failed(message); modules.lastError = message }
    }

    private static func entityType(_ section: SearchSection?) -> String? {
        switch section {
        case .people: "profile"
        case .posts: "post"
        case .modules: "module"
        case .topics: nil
        case nil: nil
        }
    }

    private func searchTopics(query: String) async {
        await loadIfNeeded(.topics)
        let matches: [DiscoverTopic]
        if query.isEmpty {
            matches = topics.items
        } else {
            matches = topics.items.filter {
                $0.label.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
            }
        }
        search.results = matches.map(SearchHit.from(topic:))
        search.nextCursor = nil
        search.loadState = .loaded
        search.lastError = nil
    }
}
