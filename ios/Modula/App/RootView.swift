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
        let policy = ShellChromePolicy.policy(for: navigation.currentRoute)
        shell(navigation: navigation, policy: policy)
        .fontDesign(appearance.fontDesign)
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
                .tabViewBottomAccessory(isEnabled: policy.bottomBarVisible) {
                    ModulaTabAccessory(route: navigation.currentRoute, nativeHosted: true)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 26.0, *) {
            tabs(navigation: navigation)
                .toolbar(policy.bottomBarVisible ? .visible : .hidden, for: .tabBar)
                .tabViewBottomAccessory {
                    if policy.bottomBarVisible {
                        ModulaTabAccessory(route: navigation.currentRoute, nativeHosted: true)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs(navigation: navigation)
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if policy.bottomBarVisible {
                        ModulaBottomChrome(route: navigation.currentRoute)
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
        case .auth: SignInView()
        case .home(let mode): HomeView(mode: mode)
        case .discover(let section): DiscoverView(section: section)
        case .search(let route): SearchFoundationView(route: route)
        case .post: DevelopmentRouteView(title: "Post", symbol: "text.bubble")
        case .compose(let route): ComposerFoundationView(route: route)
        case .activity(let mode): ActivityView(mode: mode)
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
        case .share: ShareLink(item: URL(string: "https://modula.digital")!) { Label("Share Modula", systemImage: "square.and.arrow.up") }.padding()
        case .filters: DevelopmentRouteView(title: "Filters", symbol: "line.3.horizontal.decrease.circle")
        case .modulePermissions: DevelopmentRouteView(title: "Module Permissions", symbol: "hand.raised")
        case .appearancePicker(let route): AppearanceSettingsView(focus: route)
        }
    }
}

struct DevelopmentRouteView: View {
    var title: String; var symbol: String
    var body: some View { ModulaEmptyState(title: title, message: "This route is ready for a later product phase.", symbol: symbol).navigationTitle(title) }
}
private enum ModulaSearchScope: String, CaseIterable, Identifiable {
    case all, people, posts, modules, topics
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct SearchFoundationView: View {
    let route: SearchRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query: String
    @State private var scope: ModulaSearchScope

    init(route: SearchRoute) {
        self.route = route
        switch route {
        case .root(let query):
            _query = State(initialValue: query ?? "")
            _scope = State(initialValue: .all)
        case .section(let section, let query):
            _query = State(initialValue: query ?? "")
            _scope = State(initialValue: ModulaSearchScope(rawValue: section.rawValue) ?? .all)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView {
                        Label("Search Modula", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search people, posts, modules, and topics from one native field. Only live catalogue-backed module results are shown in N2.")
                    }
                    .frame(minHeight: 300)
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaCanvas()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search Modula")
        .searchScopes($scope) {
            ForEach(ModulaSearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .modulaMinimizedSearchToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Browse Product Hub", systemImage: "shippingbox") {
                        app.navigation.open(.productHub(.featured))
                    }
                    Button("Search Settings", systemImage: "gearshape") {
                        app.navigation.open(.settings(.root))
                    }
                    Divider()
                    Button("Clear Search", systemImage: "xmark.circle") { query = "" }
                        .disabled(query.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Search menu")
            }
        }
        .accessibilityIdentifier("search.root")
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = moduleMatches
        if scope == .all || scope == .modules {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(minHeight: 260)
            } else {
                ModulaSection(title: scope == .all ? "Modules" : "Results") {
                    VStack(spacing: 12) {
                        ForEach(matches) { product in
                            ProductCard(product: product, installed: app.catalogue.installedIDs.contains(product.id)) {
                                app.navigation.open(.productHub(.module(product.id, .overview)))
                            }
                        }
                    }
                }
                if scope == .all {
                    Text("People, posts, and topics connect in N3; no placeholder results are invented here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ContentUnavailableView(
                "\(scope.title) search is ready",
                systemImage: "magnifyingglass",
                description: Text("This result source connects in N3. Modula will not fabricate matches in the meantime.")
            )
            .frame(minHeight: 280)
        }
    }

    private var moduleMatches: [CatalogueProduct] {
        app.catalogue.products.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
    }
}
struct ComposerFoundationView: View {
    let route: ComposeRoute
    var body: some View { DevelopmentRouteView(title: "Compose \(route.rawValue.capitalized)", symbol: "square.and.pencil") }
}
