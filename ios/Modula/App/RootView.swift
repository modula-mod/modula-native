import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    var body: some View {
        @Bindable var navigation = app.navigation
        @Bindable var appearance = app.appearance
        let palette = ModulaPalette.resolve(appearance, scheme: scheme,
            increasedContrast: systemContrast == .increased || appearance.contrastTransparency == .higherContrast)
        let policy = ShellChromePolicy.policy(for: navigation.currentRoute, isTabRoot: navigation.isAtTabRoot)
        shell(navigation: navigation, policy: policy)
        .fontDesign(appearance.fontDesign)
        .environment(\.trailingInteractionInset, 0)
        .overlay(alignment: .trailing) {
            if policy.contextRailVisible {
                ModulaContextRail(route: navigation.currentRoute)
            }
        }
        .sheet(item: $navigation.presented) { presentation in
            ModulaSheet { PresentationView(presentation: presentation) }
        }
        .overlay(alignment: .top) {
            if let banner = navigation.banner { Label(banner.message, systemImage: banner.symbol).padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 8) }
        }
        .background(palette.canvas.ignoresSafeArea())
        .onOpenURL { _ = navigation.open(path: $0.absoluteString) }
        .onAppear { app.runtime.markNativeUsable() }
        .task { await app.auth.restore(); await app.catalogue.load() }
        .onChange(of: scenePhase) { previous, phase in
            if phase == .active { if previous == .background { app.runtime.lifecycle("foregrounded") }; app.runtime.lifecycle("active") }
            else { app.runtime.lifecycle(phase == .background ? "backgrounded" : "inactive") }
        }
        .onChange(of: appearance.contrastTransparency) { _, value in
            if value == .reduceTransparency || systemReduceTransparency { navigation.banner = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in app.runtime.lifecycle("memoryPressure") }
    }

    @ViewBuilder
    private func shell(navigation: NavigationCoordinator, policy: ShellChromePolicy) -> some View {
        if #available(iOS 26.1, *) {
            tabs(navigation: navigation)
                .toolbar(policy.bottomBarVisible ? .visible : .hidden, for: .tabBar)
                .tabViewBottomAccessory(isEnabled: policy.shellAccessoryVisible) {
                    ShellAccessoryHost(route: navigation.currentRoute, nativeHosted: true)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 26.0, *) {
            tabs(navigation: navigation)
                .toolbar(policy.bottomBarVisible ? .visible : .hidden, for: .tabBar)
                .tabViewBottomAccessory {
                    if policy.shellAccessoryVisible {
                        ShellAccessoryHost(route: navigation.currentRoute, nativeHosted: true)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs(navigation: navigation)
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if policy.bottomBarVisible {
                        ModulaBottomChrome(route: navigation.currentRoute, showsAccessory: policy.shellAccessoryVisible)
                    }
                }
        }
    }

    private func tabs(navigation: NavigationCoordinator) -> some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: navigation.binding(for: tab)) {
                    RouteView(route: navigation.root(for: tab))
                        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
                }
                .tabItem {
                    Label(tab.title, systemImage: navigation.selectedTab == tab ? tab.selectedIcon : tab.icon)
                }
                .tag(tab)
            }
        }
    }
}

private struct RouteView: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .boot: HomeView(mode: .following)
        case .auth(let route): AuthRouteView(route: route)
        case .home(let mode): HomeView(mode: mode)
        case .discover: DiscoverScreen()
        case .search(let route): SearchScreen(route: route)
        case .post(let id, let section): PostDetailView(postID: id, section: section)
        case .compose(let route): ComposerFoundationView(route: route)
        case .activity(let mode): ActivityScreen(mode: mode)
        case .notification: DevelopmentRouteView(title: "Notification", symbol: "bell")
        case .profile(let id, let section): ProfileView(userID: id, section: section)
        case .me(let section): ProfileView(userID: nil, section: section)
        case .productHub(.module(let id, let section)): ModuleDetailView(moduleID: id, section: section)
        case .productHub(let route): ProductHubView(route: route)
        case .module(let id, let localPath): ModuleHost(moduleID: id, initialLocalPath: localPath)
        case .settings(let route): SettingsRouteView(route: route)
        case .messages: DevelopmentRouteView(title: "Messages", symbol: "message")
        case .teams: DevelopmentRouteView(title: "Teams", symbol: "person.3")
        case .developer(.components):
            #if DEBUG
            ComponentCatalogView()
            #else
            DevelopmentRouteView(title: "Components", symbol: "square.grid.3x3")
            #endif
        case .developer(let route): DevelopmentRouteView(title: route.rawValue.capitalized, symbol: "hammer")
        }
    }
}

private struct PresentationView: View {
    let presentation: AppPresentation
    var body: some View {
        switch presentation {
        case .composer(let route): ComposerFoundationView(route: route)
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
        case .universalShare(let payload):
            ShareLink(item: payload.canonicalURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .padding()
            .accessibilityIdentifier("share.universal")
        case .collectionPicker:
            ContentUnavailableView(
                "Collections",
                systemImage: "folder",
                description: Text("Local collections arrive in a later phase.")
            )
            .padding()
            .accessibilityIdentifier("collections.picker.stub")
        }
    }

    private func shareURL(for route: AppRoute) -> URL {
        switch route {
        case .profile(let id, _):
            return URL(string: "https://modula.digital/profile/\(id)")!
        case .me:
            return URL(string: "https://modula.digital/me")!
        case .post(let id, _):
            return URL(string: "https://modula.digital/post/\(id)")!
        default:
            return URL(string: "https://modula.digital")!
        }
    }
}

struct DevelopmentRouteView: View {
    var title: String; var symbol: String
    var body: some View { ModulaEmptyState(title: title, message: "This route is ready for a later product phase.", symbol: symbol).navigationTitle(title) }
}
struct ComposerFoundationView: View {
    let route: ComposeRoute
    var body: some View { DevelopmentRouteView(title: "Compose \(route.rawValue.capitalized)", symbol: "square.and.pencil") }
}
