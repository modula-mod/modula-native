import SwiftUI

struct SearchScreen: View {
    let route: SearchRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query: String
    @State private var chromeScope: ChromeScope
    @State private var searchTask: Task<Void, Never>?

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
                    ContentUnavailableView {
                        Label("Search Modula", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search people, posts, modules, and topics from one native field.")
                    }
                    .frame(minHeight: 280)
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
            }
        }
        .onDisappear { searchTask?.cancel() }
        .accessibilityIdentifier("search.root")
        .overlay(alignment: .bottom) {
            if let message = app.discover.search.lastError ?? app.discover.actionError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
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
        case _ where state.results.isEmpty:
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
        case .all: return results
        case .people: return results.filter { $0.entityType == "profile" }
        case .posts: return results.filter { $0.entityType == "post" }
        case .modules: return results.filter { $0.entityType == "module" || $0.entityType == "module-release" }
        case .topics: return results.filter { $0.entityType == "topic" }
        }
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
                HapticEngine.shared.play(.selection)
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
