import SwiftUI

struct SearchScreen: View {
    let route: SearchRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query: String
    @State private var chromeScope: ChromeScope
    @State private var searchTask: Task<Void, Never>?
    @State private var dismissedError: String?

    private enum ChromeScope: Hashable, CaseIterable {
        case all, people, posts, modules, topics
        var title: String {
            switch self {
            case .all: "All"
            case .people: "People"
            case .posts: "Posts"
            case .modules: "Modules"
            case .topics: "Topics"
            }
        }
        var section: SearchSection? {
            switch self {
            case .all: nil
            case .people: .people
            case .posts: .posts
            case .modules: .modules
            case .topics: .topics
            }
        }
        init(section: SearchSection?) {
            switch section {
            case .people: self = .people
            case .posts: self = .posts
            case .modules: self = .modules
            case .topics: self = .topics
            case nil: self = .all
            }
        }
    }

    init(route: SearchRoute) {
        self.route = route
        switch route {
        case .root(let query):
            _query = State(initialValue: query ?? "")
            _chromeScope = State(initialValue: .all)
        case .section(let section, let query):
            _query = State(initialValue: query ?? "")
            _chromeScope = State(initialValue: ChromeScope(section: section))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chromeScope != .topics {
                    DiscoverSearchIdle(onPickRecent: { query = $0 }, onPickSuggestion: { query = $0 })
                } else {
                    results
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search Modula")
        .searchScopes($chromeScope) {
            ForEach(ChromeScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .modulaMinimizedSearchToolbar()
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: chromeScope) { _, _ in
            syncRoute()
            Task { await app.discover.performSearch(query: query, section: chromeScope.section) }
        }
        .task {
            if !query.isEmpty || chromeScope == .topics {
                await app.discover.performSearch(query: query, section: chromeScope.section)
                DiscoverSearchRecents.record(query)
            }
        }
        .onDisappear { searchTask?.cancel() }
        .accessibilityIdentifier("search.root")
        .overlay(alignment: .bottom) {
            if let message = app.discover.search.lastError ?? app.discover.actionError, message != dismissedError {
                ModulaErrorBanner(message: message, identifier: "search.banner") {
                    dismissedError = message
                    app.discover.clearActionError()
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        let state = app.discover.search
        switch state.loadState {
        case .loading where state.results.isEmpty:
            ProgressView("Searching…").frame(maxWidth: .infinity, minHeight: 180)
        case .failed(let message) where state.results.isEmpty:
            ModulaErrorState(message: message) {
                Task { await app.discover.performSearch(query: query, section: chromeScope.section) }
            }
        case _ where visibleResults.isEmpty:
            ContentUnavailableView.search(text: query)
                .frame(minHeight: 240)
        default:
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(visibleResults) { hit in
                    searchRow(hit)
                }
                if state.nextCursor != nil {
                    Button("Load more") {
                        Task { await app.discover.loadMoreSearch(section: chromeScope.section) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("search.load-more")
                }
            }
        }
    }

    private var visibleResults: [SearchHit] {
        let results = app.discover.search.results
        switch chromeScope {
        case .all: return Self.orderAll(results)
        case .people: return results.filter { $0.entityType == "profile" }
        case .posts: return results.filter { $0.entityType == "post" }
        case .modules: return results.filter { $0.entityType == "module" || $0.entityType == "module-release" }
        case .topics: return results.filter { $0.entityType == "topic" }
        }
    }

    /// Settings → Search: "Include modules in results" (All scope only — the Modules
    /// scope always shows modules) and "Prefer people first" (stable re-order).
    static func orderAll(
        _ results: [SearchHit],
        includeModules: Bool = ModulaPreferences.searchIncludesModules,
        peopleFirst: Bool = ModulaPreferences.searchPeopleFirst
    ) -> [SearchHit] {
        var visible = results
        if !includeModules {
            visible.removeAll { $0.entityType == "module" || $0.entityType == "module-release" }
        }
        if peopleFirst {
            let people = visible.filter { $0.entityType == "profile" }
            let others = visible.filter { $0.entityType != "profile" }
            visible = people + others
        }
        return visible
    }

    @ViewBuilder private func searchRow(_ hit: SearchHit) -> some View {
        if hit.entityType == "profile", let person = hit.person {
            DiscoverPersonRow(
                person: person,
                followBusy: app.discover.followBusyID == person.id,
                onOpen: { open(hit) },
                onFollow: {
                    if !app.auth.isSignedIn {
                        app.navigation.requestAuthentication(returningTo: .profile(person.routeID, .overview))
                    } else if person.isFollowing {
                        Task { await app.discover.unfollow(person) }
                    } else {
                        Task { _ = await app.discover.follow(person, signedIn: true) }
                    }
                }
            )
        } else if hit.entityType == "post", let post = hit.post {
            DiscoverPostCard(post: post) { open(hit) }
        } else if hit.entityType == "topic", let topic = hit.topic {
            DiscoverTopicCard(topic: topic) {
                // Open a search for the topic instead of a haptic-only tap.
                app.navigation.push(.search(.root(topic.query)))
                HapticEngine.shared.play(.navigation)
            }
        } else if (hit.entityType == "module" || hit.entityType == "module-release"),
                  let id = hit.moduleID,
                  let product = app.catalogue.product(id) {
            ProductCard(product: product, installed: app.catalogue.installedIDs.contains(id)) { open(hit) }
        } else {
            Button { open(hit) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.title).font(.body.weight(.semibold))
                    if let excerpt = hit.excerpt {
                        Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(hit.entityType.capitalized).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.hit.\(hit.id)")
        }
    }

    private func open(_ hit: SearchHit) {
        if let destination = hit.destination {
            app.navigation.push(destination)
            HapticEngine.shared.play(.navigation)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await app.discover.performSearch(query: query, section: chromeScope.section)
            DiscoverSearchRecents.record(query)
        }
    }

    private func syncRoute() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let next: AppRoute
        if let section = chromeScope.section {
            next = .search(.section(section, trimmed.isEmpty ? nil : trimmed))
        } else {
            next = .search(.root(trimmed.isEmpty ? nil : trimmed))
        }
        app.navigation.replaceTop(with: next)
    }
}
