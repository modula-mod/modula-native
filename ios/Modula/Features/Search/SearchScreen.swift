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
        case all, people, posts, modules, moliboos, topics
        var title: String {
            switch self {
            case .all: "All"
            case .people: "People"
            case .posts: "Posts"
            case .modules: "Modules"
            case .moliboos: "Moliboos"
            case .topics: "Topics"
            }
        }
        var section: SearchSection? {
            switch self {
            case .all, .moliboos: nil
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
                if chromeScope == .moliboos {
                    molibooResults(limit: nil)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chromeScope != .topics {
                    DiscoverSearchIdle(onPickRecent: { query = $0 }, onPickSuggestion: { query = $0 })
                } else {
                    if chromeScope == .all, !molibooMatches.isEmpty {
                        molibooResults(limit: 3)
                    }
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
        .searchable(text: $query, prompt: "Search people, posts, modules, Moliboos")
        .onSubmit(of: .search) { DiscoverSearchRecents.record(query) }
        .modulaMinimizedSearchToolbar()
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: chromeScope) { _, _ in
            // Scope is local state: replacing the route here re-created (popped + pushed) the
            // whole screen, which flashed the bar, dropped the tabs and looked like Search reopening.
            guard chromeScope != .moliboos else { return }
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
                ModulaEmptyState(title: "No results for “\(query)”", message: "Check the spelling or try a broader search.", symbol: "magnifyingglass")
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
        case .moliboos: return []
        }
    }

    /// Moliboos are an on-device catalogue (no search endpoint), so they are matched locally by
    /// name and personality. Premium kinds are listed but stay locked behind Premium.
    private var molibooMatches: [ModulaMascotKind] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = ModulaMascotKind.allCases
        guard !q.isEmpty else { return chromeScope == .moliboos ? all.filter { !$0.isPremium } : [] }
        return all.filter { $0.name.lowercased().contains(q) || $0.personality.lowercased().contains(q) }
            .sorted { a, b in
                let ap = a.name.lowercased().hasPrefix(q), bp = b.name.lowercased().hasPrefix(q)
                if ap != bp { return ap }
                return MascotEntitlements.canUse(a) && !MascotEntitlements.canUse(b)
            }
    }

    @ViewBuilder private func molibooResults(limit: Int?) -> some View {
        let matches = limit.map { Array(molibooMatches.prefix($0)) } ?? molibooMatches
        if matches.isEmpty {
            ModulaEmptyState(title: "No Moliboos match “\(query)”", message: "Try a name like Pip or a trait like sleepy.", symbol: "pawprint")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if limit != nil {
                    HStack {
                        ModulaSectionHeader(title: "Moliboos")
                        Button("See all") {
                            withAnimation(ModulaSurfaceMotion.animation(reduce: reduceMotion)) { chromeScope = .moliboos }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                    }
                }
                ForEach(matches) { kind in
                    SearchMolibooRow(kind: kind) {
                        HapticEngine.shared.play(.navigation)
                        app.navigation.open(.settings(.moliboo))
                    }
                }
            }
            .modulaSurfaceTransition()
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
            guard !Task.isCancelled, chromeScope != .moliboos else { return }
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


/// One Moliboo hit: glossy figure (never clipped), name, personality and a Premium lock when gated.
private struct SearchMolibooRow: View {
    let kind: ModulaMascotKind
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let usable = MascotEntitlements.canUse(kind)
        Button(action: action) {
            HStack(spacing: 12) {
                MolibooEmptyArt(kind: kind, mood: .happy, size: 26, animated: false)
                    .frame(width: 64, height: 56)
                    .opacity(usable ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.body.weight(.semibold))
                    Text(kind.personality).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if !usable {
                    Label("Premium", systemImage: "lock.fill")
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .accessibilityLabel("Premium Moliboo")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search.moliboo.\(kind.rawValue)")
    }
}
