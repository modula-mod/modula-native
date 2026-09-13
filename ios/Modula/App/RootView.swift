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
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: navigation.binding(for: tab)) {
                    RouteView(route: navigation.root(for: tab))
                        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
                }
                .tag(tab)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .fontDesign(appearance.fontDesign)
        .overlay(alignment: .trailing) {
            if ShellChromePolicy.policy(for: navigation.currentRoute).contextRailVisible {
                ModulaContextRail(route: navigation.currentRoute).padding(.trailing, -8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ShellChromePolicy.policy(for: navigation.currentRoute).bottomBarVisible { ModulaTabBar() }
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
struct SearchFoundationView: View {
    let route: SearchRoute; @State private var query = ""
    var body: some View { VStack { ModulaSearchField(text: $query, prompt: "Search Modula"); ModulaEmptyState(title: "Search is ready", message: "Results connect in a later phase.", symbol: "magnifyingglass") }.padding().navigationTitle("Search") }
}
struct ComposerFoundationView: View {
    let route: ComposeRoute
    var body: some View { DevelopmentRouteView(title: "Compose \(route.rawValue.capitalized)", symbol: "square.and.pencil") }
}
