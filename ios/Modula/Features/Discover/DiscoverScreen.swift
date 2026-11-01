import SwiftUI

struct DiscoverScreen: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Only flips at the threshold, so scrolling doesn't storm state every frame.
    @State private var collapsed = false
    /// Expanded header height, reserved in both states so collapsing never changes the
    /// scroll view's top inset (which used to shift the offset back across the threshold
    /// and flip collapsed on/off forever, hanging the main thread).
    @State private var expandedHeaderHeight: CGFloat = 0
    @Namespace private var glassNS

    private var section: DiscoverRoute {
        if case .discover(let route) = app.navigation.root(for: .discover) {
            return route
        }
        return .trending
    }

    var body: some View {
        Group {
            ZStack {
                ForEach(DiscoverRoute.allCases, id: \.self) { scope in
                    if app.discover.visitedScopes.contains(scope) {
                        scopeScroll(scope)
                            .opacity(scope == section ? 1 : 0)
                            .allowsHitTesting(scope == section)
                            .accessibilityHidden(scope != section)
                    }
                }
            }
        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .modulaSidebarTrigger()
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .overlay(alignment: .bottom) {
            if let message = app.discover.actionError {
                ModulaErrorBanner(message: message, identifier: "discover.banner") {
                    app.discover.clearActionError()
                }
            }
        }
        .task(id: section) {
            app.discover.markVisited(section)
            await app.discover.loadIfNeeded(section)
        }
        .onAppear { app.discover.markVisited(section) }
        .accessibilityIdentifier("discover.\(section.rawValue)")
        .accessibilityValue(RouteSerializer.serialize(.discover(section)))
    }

    private var searchEntry: some View {
        DiscoverSearchEntry(
            compact: collapsed,
            action: {
                app.navigation.open(.search(.root(nil)))
                HapticEngine.shared.play(.navigation)
            },
            onCustomise: section.hasFilters ? {
                PresentationCoordinator.present(.discoverFilter, in: app.navigation)
                HapticEngine.shared.play(.contextOpen)
            } : nil,
            onRefresh: {
                Task {
                    await app.discover.refresh(section)
                    HapticEngine.shared.play(.confirmation)
                }
            }
        )
    }

    private var chips: some View {
        DiscoverScopePicker(selection: section, compact: collapsed) { destination in
            app.discover.markVisited(destination)
            app.navigation.replaceContext(with: .discover(destination))
        }
    }

    /// Expanded: search row + chip row. Collapsed: one slim bar (chips + search icon + menu).
    private var header: some View {
        ModulaGlassGroup(spacing: 8) {
            Group {
                if collapsed {
                    HStack(spacing: 8) {
                        chips
                        searchEntry.modulaGlassID("discover.search", in: glassNS)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discover")
                                .font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text("People, posts, modules and topics.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        searchEntry.modulaGlassID("discover.search", in: glassNS)
                        chips
                    }
                }
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background {
            // Edge fade so cards dissolve under the header instead of clashing behind it.
            LinearGradient(stops: [
                .init(color: Color(uiColor: .systemBackground), location: 0),
                .init(color: Color(uiColor: .systemBackground).opacity(0.85), location: 0.6),
                .init(color: Color(uiColor: .systemBackground).opacity(0), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .padding(.bottom, -18)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { height in
            // Only the expanded layout defines the reserved height; ignore collapsed/animating sizes.
            if !collapsed, height > expandedHeaderHeight { expandedHeaderHeight = height }
        }
        .frame(minHeight: expandedHeaderHeight, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86), value: collapsed)
    }

    @ViewBuilder
    private func scopeScroll(_ scope: DiscoverRoute) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                content(for: scope)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 8)
            // Clear the floating Tools pill and the tab bar.
            .padding(.bottom, 140)
            .modulaPullContentEffects()
            .modulaScrollsToTopOnReselect(.discover)
        }
        .onScrollGeometryChange(for: Bool.self) { [collapsed] geo in
            DiscoverHeaderCollapse.isCollapsed(offset: geo.contentOffset.y + geo.contentInsets.top, current: collapsed)
        } action: { _, isCollapsed in
            guard scope == section, isCollapsed != collapsed else { return }
            collapsed = isCollapsed
        }
        .modulaSoftScrollEdge()
        .environment(\.modulaHeroScope, "discover.\(scope.rawValue)")
        .modulaShellPullActions(liftsAboveContent: false) {
            await app.discover.refresh(scope)
            HapticEngine.shared.play(.confirmation)
        }
    }

    @ViewBuilder
    private func content(for scope: DiscoverRoute) -> some View {
        switch scope {
        case .trending: trendingContent
        case .people: peopleContent
        case .topics: topicsContent
        case .posts: postsContent
        case .modules: modulesContent
        }
    }

    @ViewBuilder private var trendingContent: some View {
        let state = app.discover.trending
        switch state.loadState {
        case .loading where state.dashboard == nil:
            trendingSkeleton
        case .failed(let message) where state.dashboard == nil:
            ModulaErrorState(message: message) {
                Task { await app.discover.refresh(.trending) }
            }
            .padding(.top, 40)
            .accessibilityIdentifier("discover.error")
        case _ where state.dashboard == nil:
            ModulaEmptyState(title: "Nothing trending here yet.", message: "Check back soon.", symbol: "safari")
                .padding(.top, 28)
        default:
            if let dashboard = state.dashboard {
                DiscoverDashboardView(
                    dashboard: Self.personalised(dashboard),
                    previewPosts: state.previewPosts,
                    // Settings → Personalisation → Recommendations → "Suggested modules".
                    featuredProducts: ModulaPreferences.showsModuleSuggestions ? featuredProducts : [],
                    installedIDs: app.catalogue.installedIDs,
                    followBusyID: app.discover.followBusyID,
                    onTopic: openTopic,
                    onPerson: openPerson,
                    onFollow: handleFollow,
                    onSeePeople: { app.navigation.replaceContext(with: .discover(.people)) },
                    onPost: openPost,
                    onModule: openModule,
                    onSeeModules: { app.navigation.replaceContext(with: .discover(.modules)) },
                    onReel: { reel in
                        guard reel.attachment != nil else {
                            // Module-backed / non-video item: open its post instead of a blank player.
                            if let postID = reel.postID {
                                app.postActions.ingest(reel.asSocialPost())
                                app.navigation.push(.post(postID, .root))
                                HapticEngine.shared.play(.navigation)
                            }
                            return
                        }
                        app.reels.ingest(seed: dashboard.reels)
                        app.navigation.push(.reels(.reel(reel.id)))
                        HapticEngine.shared.play(.navigation)
                    }
                )
            }
        }
    }

    @ViewBuilder private var peopleContent: some View {
        let state = app.discover.people
        let items = app.discover.visiblePeople()
        switch state.loadState {
        case .loading where state.items.isEmpty:
            ForEach(0..<6, id: \.self) { _ in DiscoverSkeleton(kind: .person) }
        case .failed(let message) where state.items.isEmpty:
            ModulaErrorState(message: message) { Task { await app.discover.refresh(.people) } }
                .padding(.top, 40)
        case _ where items.isEmpty:
            ModulaEmptyState(title: "No people found.", message: "Try another filter.", symbol: "person.2")
                .padding(.top, 28)
        default:
            LazyVStack(spacing: 0) {
                ForEach(items) { person in
                    DiscoverPersonRow(
                        person: person,
                        followBusy: app.discover.followBusyID == person.id,
                        onOpen: { openPerson(person) },
                        onFollow: { handleFollow(person) }
                    )
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    /// Two columns normally; one column at accessibility text sizes so
    /// topic titles are not truncated to a couple of letters.
    private var topicColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder private var topicsContent: some View {
        let state = app.discover.topics
        switch state.loadState {
        case .loading where state.items.isEmpty:
            LazyVGrid(columns: topicColumns, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in DiscoverSkeleton(kind: .topic) }
            }
        case .failed(let message) where state.items.isEmpty:
            ModulaErrorState(message: message) { Task { await app.discover.refresh(.topics) } }
                .padding(.top, 40)
        case _ where state.items.isEmpty:
            ModulaEmptyState(title: "Nothing trending here yet.", message: "Check back soon.", symbol: "number")
                .padding(.top, 28)
        default:
            LazyVGrid(columns: topicColumns, spacing: 12) {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { item in
                    DiscoverTopicCard(topic: item.element, rank: item.offset + 1) { openTopic(item.element) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var postsContent: some View {
        let state = app.discover.posts
        let items = app.discover.visiblePosts()
        switch state.loadState {
        case .loading where state.items.isEmpty:
            ForEach(0..<3, id: \.self) { _ in DiscoverSkeleton(kind: .post) }
        case .failed(let message) where state.items.isEmpty:
            ModulaErrorState(message: message) { Task { await app.discover.refresh(.posts) } }
                .padding(.top, 40)
        case _ where items.isEmpty:
            ModulaEmptyState(title: "No posts match these filters.", message: "Try another filter or refresh.", symbol: "text.bubble")
                .padding(.top, 28)
        default:
            LazyVStack(spacing: 14) {
                ForEach(items) { post in
                    // Same shell as Home: reactions, repost, save, share and "…" menu.
                    SharedFeedPostCard(post: post.asSocialPost(), identifierPrefix: "discover")
                        .padding(.horizontal, -ModulaLayout.contentInset)
                        .padding(.horizontal, ModulaLayout.postBleedGutter)
                }
                if state.nextCursor != nil {
                    Button("Load more") {
                        Task { await app.discover.loadMore(.posts) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(state.loadState == .loadingMore)
                    .accessibilityIdentifier("discover.posts.load-more")
                }
            }
        }
    }

    @ViewBuilder private var modulesContent: some View {
        let state = app.discover.modules
        let items = app.discover.visibleModules(installedIDs: app.catalogue.installedIDs)
        switch state.loadState {
        case .loading where state.items.isEmpty:
            ForEach(0..<3, id: \.self) { _ in DiscoverSkeleton(kind: .module) }
        case .failed(let message) where state.items.isEmpty:
            ModulaErrorState(message: message) { Task { await app.discover.refresh(.modules) } }
                .padding(.top, 40)
        case _ where items.isEmpty:
            ModulaEmptyState(title: "No modules match this selection.", message: "Try another filter.", symbol: "shippingbox", illustration: .modules)
                .padding(.top, 28)
        default:
            VStack(alignment: .leading, spacing: 16) {
                if !state.featured.isEmpty, !app.discover.modules.filter.isActive {
                    ProductShelf(
                        title: "Featured",
                        subtitle: "Picked by the Modula team",
                        products: state.featured,
                        installedIDs: app.catalogue.installedIDs,
                        action: openModule
                    )
                }
                ProductShelf(
                    title: state.featured.isEmpty ? "From Modula" : "All Modules",
                    products: items,
                    installedIDs: app.catalogue.installedIDs,
                    action: openModule
                )
                if state.nextCursor != nil {
                    Button("Load more") {
                        Task { await app.discover.loadMore(.modules) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    private var trendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(0..<3, id: \.self) { _ in DiscoverSkeleton(kind: .topic) } }
            }
            ForEach(0..<3, id: \.self) { _ in DiscoverSkeleton(kind: .person) }
            DiscoverSkeleton(kind: .post)
            DiscoverSkeleton(kind: .module)
        }
    }

    /// Settings → Personalisation → Recommendations: drop suggested people / modules
    /// from Trending when switched off. Search and the People/Modules tabs still work.
    static func personalised(
        _ dashboard: DiscoverDashboard,
        suggestedPeople: Bool = ModulaPreferences.showsSuggestedPeople,
        moduleSuggestions: Bool = ModulaPreferences.showsModuleSuggestions
    ) -> DiscoverDashboard {
        var copy = dashboard
        if !suggestedPeople { copy.people = [] }
        if !moduleSuggestions { copy.featuredModules = [] }
        return copy
    }

    private var featuredProducts: [CatalogueProduct] {
        let featured = app.discover.trending.dashboard?.featuredModules ?? []
        let resolved = featured.compactMap { GreenfieldDiscoverRepository.resolve($0, in: app.catalogue.products) }
        if !resolved.isEmpty { return resolved }
        if !app.discover.modules.featured.isEmpty { return app.discover.modules.featured }
        return Array(app.catalogue.products.prefix(3))
    }

    private func openTopic(_ topic: DiscoverTopic) {
        app.navigation.open(.search(.section(.topics, topic.query)))
        HapticEngine.shared.play(.navigation)
    }

    private func openPerson(_ person: DiscoverPerson) {
        app.navigation.push(.profile(person.routeID, .overview))
        HapticEngine.shared.play(.navigation)
    }

    private func openPost(_ post: DiscoverPost) {
        let social = post.asSocialPost()
        // Discover keeps a compact preview; full interaction lives on canonical Post Detail.
        // Ingesting into PostStateStore keeps engagement consistent when returning.
        app.postActions.ingest(social)
        app.navigation.push(.post(post.id, .root))
        HapticEngine.shared.play(.navigation)
    }

    private func openModule(_ product: CatalogueProduct) {
        app.navigation.push(.productHub(.module(product.id, .overview)))
        HapticEngine.shared.play(.navigation)
    }

    private func handleFollow(_ person: DiscoverPerson) {
        if !app.auth.isSignedIn {
            app.navigation.requestAuthentication(returningTo: .profile(person.routeID, .overview))
            HapticEngine.shared.play(.navigation)
            return
        }
        Task {
            if person.isFollowing {
                await app.discover.unfollow(person)
            } else {
                _ = await app.discover.follow(person, signedIn: true)
            }
        }
    }
}

/// Collapse decision with a hysteresis band, so small offset shifts can't toggle the header.
enum DiscoverHeaderCollapse {
    static let collapseAbove: CGFloat = 60
    static let expandBelow: CGFloat = 20

    static func isCollapsed(offset: CGFloat, current: Bool) -> Bool {
        current ? offset >= expandBelow : offset > collapseAbove
    }
}
