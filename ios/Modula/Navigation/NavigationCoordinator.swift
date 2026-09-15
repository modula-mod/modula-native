import Observation
import SwiftUI

@MainActor @Observable
final class NavigationCoordinator {
    var selectedTab: AppTab = .home
    private(set) var roots: [AppTab: AppRoute] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, $0.defaultRoute) })
    private(set) var paths: [AppTab: [AppRoute]] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    var presented: AppPresentation?
    var banner: ModulaBanner?
    /// Route to restore after a successful authentication challenge.
    private(set) var pendingReturnRoute: AppRoute?
    var currentRoute: AppRoute { paths[selectedTab]?.last ?? roots[selectedTab] ?? selectedTab.defaultRoute }
    var currentPath: String { RouteSerializer.serialize(currentRoute) }

    func root(for tab: AppTab) -> AppRoute { roots[tab] ?? tab.defaultRoute }
    func path(for tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }
    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }
    func select(_ tab: AppTab) { selectedTab = tab }
    func open(path: String) -> Bool {
        guard let route = RouteParser.parse(path) else { return false }
        open(route); return true
    }
    func open(_ route: AppRoute) {
        if let tab = route.tab {
            selectedTab = tab
            if isContextRoot(route) { roots[tab] = route; return }
        }
        paths[selectedTab, default: []].append(route)
    }
    func replaceContext(with route: AppRoute) {
        guard let tab = route.tab else { return }
        selectedTab = tab
        roots[tab] = route
    }
    func close() {
        if !paths[selectedTab, default: []].isEmpty { paths[selectedTab]?.removeLast() }
    }
    func home() { selectedTab = .home; paths[.home] = []; roots[.home] = .home(.following) }

    /// Authenticated destinations call this instead of opening login ad-hoc.
    func requestAuthentication(returningTo route: AppRoute) {
        pendingReturnRoute = route
        open(.auth(.login))
    }

    func completeAuthenticationReturn() {
        // Pop auth screens from the current stack, then open the intended destination.
        while let last = paths[selectedTab]?.last, case .auth = last {
            paths[selectedTab]?.removeLast()
        }
        if let pending = pendingReturnRoute {
            pendingReturnRoute = nil
            open(pending)
        } else {
            close()
        }
    }

    private func isContextRoot(_ route: AppRoute) -> Bool {
        switch route {
        case .home, .discover, .activity, .profile, .me: true
        case .productHub(.collection), .productHub(.search): true
        default: false
        }
    }
}

enum AppPresentation: Identifiable, Hashable {
    case composer(ComposeRoute), share(AppRoute), filters, modulePermissions(String), appearancePicker(AppearanceSettingsRoute)
    case activitySummary, activityFilter
    var id: String { String(describing: self) }
}
struct ModulaBanner: Identifiable, Hashable { let id = UUID(); var message: String; var symbol: String }
@MainActor enum PresentationCoordinator {
    static func present(_ presentation: AppPresentation, in navigation: NavigationCoordinator) { navigation.presented = presentation }
    static func dismiss(in navigation: NavigationCoordinator) { navigation.presented = nil }
}

struct ShellChromePolicy: Equatable {
    enum TopBarStyle: Equatable { case standard, floating, hidden }
    var bottomBarVisible: Bool
    var contextRailVisible: Bool
    var shellAccessoryVisible: Bool
    var topBarStyle: TopBarStyle
    var showsBack: Bool
    var showsClose: Bool
    var immersive: Bool
    var hidesForKeyboard: Bool

    static func policy(for route: AppRoute) -> Self {
        switch route {
        case .module:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: false,
                showsClose: true,
                immersive: true,
                hidesForKeyboard: true
            )
        case .productHub(.module):
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: true,
                topBarStyle: .floating,
                showsBack: true,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .home, .activity, .profile, .me:
            Self(
                bottomBarVisible: true,
                contextRailVisible: true,
                shellAccessoryVisible: true,
                topBarStyle: .standard,
                showsBack: false,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .auth, .settings(.account), .compose:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: true,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .settings:
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: true,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        default:
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: true,
                topBarStyle: .standard,
                showsBack: true,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        }
    }
}
