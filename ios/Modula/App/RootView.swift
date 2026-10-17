import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var routeTransitions
    // Device preferences that change the shell itself (re-render on change).
    @AppStorage(ModulaPreferences.Key.labsDebugOverlays) private var debugOverlays = false
    @AppStorage(ModulaPreferences.Key.labsExperimentalChrome) private var experimentalChrome = false
    @AppStorage(ModulaPreferences.Key.focusFilterActive) private var focusFilterActive = false
    @AppStorage(ModulaPreferences.Key.focusHideBadges) private var focusHideBadges = false
    @AppStorage(ModulaPreferences.Key.focusAllowMentions) private var focusAllowMentions = true
    var body: some View {
        @Bindable var navigation = app.navigation
        @Bindable var appearance = app.appearance
        let palette = ModulaPalette.resolve(appearance, scheme: scheme,
            increasedContrast: systemContrast == .increased || appearance.contrastTransparency == .higherContrast)
        let policy = ShellChromePolicy.policy(for: navigation.currentRoute, isTabRoot: navigation.isAtTabRoot)
        let edgeSide = appearance.edgePicker.side
        let clearance = EdgeInteractionSafeArea.contentClearance(
            side: edgeSide,
            pickerVisible: policy.contextRailVisible
        )
        shell(navigation: navigation, policy: policy)
        .fontDesign(appearance.fontDesign)
        .environment(\.trailingInteractionInset, clearance.trailing)
        .environment(\.leadingInteractionInset, clearance.leading)
        .environment(\.edgePickerSide, edgeSide)
        .environment(\.shellChromeMetrics, ShellChromeMetrics.resolve(policy: policy))
        .overlay(alignment: edgeSide == .right ? .trailing : .leading) {
            if policy.contextRailVisible, !navigation.sidebarPresented {
                ShellEdgeLoop(route: navigation.currentRoute)
                    .ignoresSafeArea(edges: edgeSide == .right ? .trailing : .leading)
                    .padding(.bottom, 80)
                    .padding(.top, 48)
            }
        }
        .modulaSidebarEdgeOpen()
        .overlay { ShellSidebarHost() }
        // Liquid Glass post menu: above tabs and chrome so it can blur the whole screen.
        .overlay { PostMenuHost() }
        .overlay { CommandPaletteHost() }
        .overlay { CelebrationHost() }
        .sheet(item: $navigation.presented) { presentation in
            ModulaSheet { PresentationView(presentation: presentation) }
        }
        .overlay {
            // Morphs from Dynamic Island (or notch/status fallback). Shared by every `flash`.
            ModulaIslandBannerHost(banner: navigation.banner)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) {
            if debugOverlays { ModulaDebugOverlay(route: navigation.currentRoute) }
        }
        // Ideas30 #18: offline banner. #27: one-time "What's new" sheet (opens the 30-ideas gallery).
        .overlay(alignment: .top) { Lab30OfflineBanner() }
        .modifier(Lab30WhatsNewPresenter())
        .background(palette.canvas.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            ModulaRuntimePreferences.apply()
        }
        .onAppear {
            ModulaRuntimePreferences.apply()
            app.runtime.markNativeUsable()
            if let delegate = UIApplication.shared.delegate as? ModulaAppDelegate {
                delegate.environment = app
                delegate.consumePendingShortcutIfNeeded()
            }
            app.refreshQuickActions()
        }
        .task {
            if app.catalogue.accountID == nil {
                app.catalogue.accountID = app.auth.account?.accountId
            }
            await app.catalogue.load()
            if app.auth.isSignedIn {
                await app.profile.loadIfNeeded(
                    .me,
                    handleHint: app.auth.account?.primaryHandle,
                    accountHandle: app.auth.account?.primaryHandle,
                    catalogue: app.catalogue.products
                )
            }
            await refreshTabAvatar()
            app.refreshQuickActions()
            let installed = app.catalogue.installedIDs.compactMap { id -> (id: String, name: String)? in
                guard let product = app.catalogue.product(id) else { return (id, id) }
                return (id, product.name)
            }
            SpotlightIndexPreparation.refresh(installedModules: installed)
        }
        .modulaCommandKeyboard(
            onCommandK: {
                CommandPaletteCenter.shared.present()
            },
            onCommandN: {
                app.navigation.presented = .createPicker
            },
            onCommandF: {
                app.navigation.open(.search(.root(nil)))
            }
        )
        .onChange(of: scenePhase) { previous, phase in
            if phase == .active {
                if previous == .background { app.runtime.lifecycle("foregrounded") }
                app.runtime.lifecycle("active")
                app.refreshQuickActions()
            } else if phase == .background {
                app.runtime.lifecycle("backgrounded")
            } else {
                app.runtime.lifecycle("inactive")
            }
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            Task {
                guard app.auth.isSignedIn else { return }
                await app.profile.loadIfNeeded(
                    .me,
                    handleHint: app.auth.account?.primaryHandle,
                    accountHandle: app.auth.account?.primaryHandle,
                    catalogue: app.catalogue.products
                )
                await refreshTabAvatar()
            }
        }
        .onChange(of: app.profile.ownProfile?.avatarURL) { _, _ in
            Task { await refreshTabAvatar() }
        }
        .onChange(of: appearance.contrastTransparency) { _, value in
            if value == .reduceTransparency || systemReduceTransparency { navigation.banner = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in app.runtime.lifecycle("memoryPressure") }
    }

    @ViewBuilder
    private func shell(navigation: NavigationCoordinator, policy: ShellChromePolicy) -> some View {
        if experimentalChrome {
            // Settings → Labs → "Experimental chrome": Modula's own floating bottom
            // chrome instead of the system tab bar, on every iOS version.
            tabs(navigation: navigation, hidesSystemTabBar: true)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if policy.bottomBarVisible {
                        ModulaBottomChrome(route: navigation.currentRoute, showsAccessory: policy.shellAccessoryVisible)
                    }
                }
        } else if #available(iOS 26.1, *) {
            tabs(navigation: navigation)
                .toolbar(policy.bottomBarVisible ? .visible : .hidden, for: .tabBar)
                .tabViewBottomAccessory(isEnabled: policy.shellAccessoryVisible) {
                    ShellAccessorySystemSlot(route: navigation.currentRoute)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 26.0, *) {
            tabs(navigation: navigation)
                .toolbar(policy.bottomBarVisible ? .visible : .hidden, for: .tabBar)
                .tabViewBottomAccessory {
                    if policy.shellAccessoryVisible {
                        ShellAccessorySystemSlot(route: navigation.currentRoute)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs(navigation: navigation, hidesSystemTabBar: true)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if policy.bottomBarVisible {
                        ModulaBottomChrome(route: navigation.currentRoute, showsAccessory: policy.shellAccessoryVisible)
                    }
                }
        }
    }

    /// `.toolbar(.hidden, for: .tabBar)` only hides the system bar when applied inside a
    /// tab's content; on the `TabView` itself iOS 26+ ignores it, which drew the system
    /// bar underneath Modula's own floating chrome (duplicate tab bar).
    private func tabs(navigation: NavigationCoordinator, hidesSystemTabBar: Bool = false) -> some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: navigation.binding(for: tab)) {
                    RouteView(route: navigation.root(for: tab))
                        .navigationDestination(for: AppRoute.self) {
                            RouteView(route: $0)
                                .modifier(SystemTabBarHidden(hidden: hidesSystemTabBar))
                        }
                        .background(EdgeSwipeBackConfigurator().frame(width: 0, height: 0).accessibilityHidden(true))
                        .modifier(SystemTabBarHidden(hidden: hidesSystemTabBar))
                }
                .environment(\.routeTransitionNamespace, routeTransitions)
                .modulaSoftScrollEdge()
                .tabItem {
                    if tab == .profile {
                        Image(uiImage: app.profile.tabBarAvatar ?? ProfileTabAvatarRenderer.fallback(
                            profile: app.profile.ownProfile,
                            account: app.auth.account,
                            accent: UIColor(app.appearance.accent.color)
                        ))
                        .renderingMode(.original)
                        Text(tab.title)
                    } else {
                        Label(tab.title, systemImage: navigation.selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .symbolEffect(.bounce, value: navigation.selectedTab == tab)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .badge(tab == .activity ? activityBadge : 0)
                .tag(tab)
            }
        }
        .overlay {
            ProfileTabBarAvatarApplicator(image: app.profile.tabBarAvatar)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            TabBarIconMotionApplicator(
                selectedTab: navigation.selectedTab,
                reduceMotion: reduceMotion
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Unread Activity, quietened by an iOS Focus filter per Settings → Focus.
    private var activityBadge: Int {
        _ = (focusFilterActive, focusHideBadges, focusAllowMentions)
        let events = app.activity.state(for: .all).events
        let unread = app.activity.state(for: .all).unreadCount ?? events.filter { !$0.isRead }.count
        let mentions = events.filter { !$0.isRead && $0.kind.isMention }.count
        return ModulaFocusState.activityBadge(unread: unread, unreadMentions: mentions)
    }

    private func refreshTabAvatar() async {
        await app.profile.refreshTabBarAvatar(
            account: app.auth.account,
            accent: UIColor(app.appearance.accent.color)
        )
    }
}

struct RouteView: View {
    let route: AppRoute
    /// Card the user tapped to get here (Activity / Discover / Product Hub), captured once.
    @State private var heroID: String?

    init(route: AppRoute) {
        self.route = route
        _heroID = State(initialValue: ModulaHeroMorph.consume(route))
    }

    var body: some View {
        destination
            .modulaSoftScrollEdge()
            .modifier(ModulaHeroDestinationModifier(heroID: heroID))
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .boot: BootSplashView()
        case .auth(let route): AuthRouteView(route: route)
        case .home(let mode): HomeView(mode: mode)
        case .discover: DiscoverScreen()
        case .search(let route): SearchScreen(route: route)
        case .post(let id, let section): PostDetailView(postID: id, section: section)
        case .compose(let route): CreationStudioView(route: route)
        case .activity(let mode): ActivityScreen(mode: mode)
        case .notification: DevelopmentRouteView(title: "Notification", symbol: "bell")
        case .profile(let id, let section): ProfileView(userID: id, section: section)
        case .me(let section): ProfileView(userID: nil, section: section)
        case .productHub(.module(let id, let section)): ModuleDetailV2View(moduleID: id, section: section)
        case .productHub(.publisher(let id)): PublisherView(publisherID: id)
        case .productHub(let route): ProductHubView(route: route)
        case .module(let id, let localPath): ModuleHost(moduleID: id, initialLocalPath: localPath)
        case .settings(let route): SettingsDestinationHost(route: route)
        case .messages(let route): MessagesRootView(route: route)
        case .stories(let route): StoriesRouteView(route: route)
        case .reels(let route): ReelsRouteView(route: route)
        case .teams: DevelopmentRouteView(title: "Teams", symbol: "person.3")
        case .developer(.components):
            #if DEBUG
            ComponentCatalogView()
            #else
            DevelopmentRouteView(title: "Components", symbol: "square.grid.3x3")
            #endif
        case .developer(.studio): DeveloperStudioView()
        case .developer(let route): DevelopmentRouteView(title: route.rawValue.capitalized, symbol: "hammer")
        case .command:
            CommandCenterView(context: .global)
        case .saved(let section):
            SavedView(section: {
                switch section {
                case .root: .root
                case .posts: .posts
                case .modules: .modules
                case .links: .links
                }
            }())
        case .collections(.root):
            CollectionsView()
        case .collections(.collection(let id)):
            CollectionDetailView(collectionID: id)
        case .drafts:
            DraftsView()
        }
    }
}

private struct PresentationView: View {
    let presentation: AppPresentation
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        destination.modulaSoftScrollEdge()
    }

    @ViewBuilder
    private var destination: some View {
        switch presentation {
        case .composer(let route): CreationStudioView(route: route)
        case .share(let route):
            let url = shareURL(for: route)
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .padding()
            .accessibilityIdentifier("share.sheet")
        case .filters: DevelopmentRouteView(title: "Filters", symbol: "line.3.horizontal.decrease.circle")
        case .modulePermissions: DevelopmentRouteView(title: "Module Permissions", symbol: "hand.raised")
        case .appearancePicker(let route): AppearanceSettingsView(focus: route)
        case .activitySummary: ActivitySummarySheet()
        case .activityFilter: ActivityFilterSheet()
        case .discoverFilter: DiscoverFilterSheet()
        case .homeSummary: HomeSummarySheet()
        case .homeFeedTools: HomeFeedToolsSheet()
        case .homeFeeds: HomeFeedsSheet()
        case .installedModules: InstalledModulesPanel()
        case .commandCenter: CommandCenterView(context: commandContext)
        case .intelligenceChat: IntelligenceChatView()
        case .createPicker: CreateActionPicker()
        case .universalShare(let payload): ModulaShareSheet(payload: payload)
        case .collectionPicker(let postID): CollectionPicker(postID: postID)
        case .draftRestore: DraftRestorePrompt(
            onContinue: {},
            onStartNew: {
                app.drafts.discardPost()
            }
        )
        }
    }

    private var commandContext: CommandContext {
        switch app.navigation.currentRoute {
        case .home: .home
        case .discover, .search: .discover
        case .productHub, .module: .modules
        case .activity: .activity
        case .profile, .me, .saved, .collections, .drafts: .profile
        case .settings: .settings
        case .messages: .messages
        default: .global
        }
    }

    private func shareURL(for route: AppRoute) -> URL {
        ModulaShareLink.url(for: route)
    }
}

struct DevelopmentRouteView: View {
    var title: String; var symbol: String
    var body: some View {
        ModulaEmptyState(title: title, message: "This destination isn’t part of the current product surface.", symbol: symbol)
            .modulaSoftScrollEdge()
            .navigationTitle(title)
    }
}
struct ComposerFoundationView: View {
    let route: ComposeRoute
    var body: some View { CreationStudioView(route: route) }
}

/// Hides the system tab bar for a tab's content when Modula draws its own bottom chrome.
/// Leaves per-route visibility (`.toolbar(... for: .tabBar)` in Reels, Messages, Post) alone
/// when Modula is using the system bar.
private struct SystemTabBarHidden: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if hidden {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}
