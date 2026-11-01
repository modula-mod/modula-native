import SwiftUI

struct SearchScreen: View {
    let route: SearchRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query: String
    @State private var chromeScope: ChromeScope
    @State private var searchTask: Task<Void, Never>?
    @State private var dismissedError: String?
    @State private var allCounts: [ChromeScope: Int] = [:]
    @Namespace private var scopeNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                scopeChips
                if !typeahead.isEmpty {
                    typeaheadRow
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chromeScope != .topics {
                    DiscoverSearchIdle(onPickRecent: { query = $0 }, onPickSuggestion: { query = $0 })
                } else {
                    results
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        // Enhancements-50: dragging results tucks the keyboard away; a tick confirms a submitted search.
        .scrollDismissesKeyboard(.immediately)
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search people, posts, modules")
        .onSubmit(of: .search) {
            DiscoverSearchRecents.record(query)
            HapticEngine.shared.play(.selection)
        }
        .modulaMinimizedSearchToolbar()
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: chromeScope) { _, _ in
            // Scope is local state: replacing the route here re-created (popped + pushed) the
            // whole screen, which flashed the bar, dropped the tabs and looked like Search reopening.
            Task { await app.discover.performSearch(query: query, section: chromeScope.section) }
        }
        .onChange(of: app.discover.search.results.count) { _, _ in
            if chromeScope == .all { allCounts = Self.counts(app.discover.search.results) }
        }
        .task {
            if !query.isEmpty || chromeScope == .topics {
                await app.discover.performSearch(query: query, section: chromeScope.section)
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
            VStack(spacing: 14) {
                ContentUnavailableView.search(text: query)
                    .frame(minHeight: 200)
                if chromeScope != .all {
                    Button("Search everything instead") {
                        withAnimation(reduceMotion ? nil : .snappy) { chromeScope = .all }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                DiscoverSearchIdle(onPickRecent: { query = $0 }, onPickSuggestion: { query = $0 })
            }
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
            SharedFeedPostCard(post: post.asSocialPost(), identifierPrefix: "search")
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
        DiscoverSearchRecents.record(query)
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
        }
    }

    private static func counts(_ results: [SearchHit]) -> [ChromeScope: Int] {
        var c: [ChromeScope: Int] = [:]
        for hit in results {
            switch hit.entityType {
            case "profile": c[.people, default: 0] += 1
            case "post": c[.posts, default: 0] += 1
            case "module", "module-release": c[.modules, default: 0] += 1
            case "topic": c[.topics, default: 0] += 1
            default: break
            }
        }
        c[.all] = results.count
        return c
    }

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Scope chips live in the content (not system search scopes), so they never vanish or
    /// jump when the search field gains focus. Counts come from the last All-scope results.
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChromeScope.allCases, id: \.self) { scope in
                    let selected = scope == chromeScope
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { chromeScope = scope }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack(spacing: 5) {
                            Text(scope.title)
                            if hasQuery, let n = allCounts[scope], n > 0 {
                                Text("\(n)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background {
                            if selected {
                                Capsule().fill(app.appearance.liveAccent.opacity(0.18))
                                    .matchedGeometryEffect(id: "scope", in: scopeNS)
                            }
                        }
                        .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("search.scope.\(scope.title.lowercased())")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// Typeahead: recent searches and trending topics that start with what you've typed.
    private var typeahead: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        let topics = app.discover.trending.dashboard?.topics.map(\.label) ?? []
        var seen = Set<String>()
        return (DiscoverSearchRecents.load() + topics)
            .filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(5)
            .map { $0 }
    }

    private var typeaheadRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(typeahead, id: \.self) { item in
                    Button {
                        query = item
                        DiscoverSearchRecents.record(item)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label(item, systemImage: "arrow.up.left")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).frame(height: 30)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
        .transition(.opacity)
    }
}
