import Observation
import SwiftUI

@MainActor @Observable
final class NavigationCoordinator {
    var selectedTab: AppTab = .home
    private(set) var roots: [AppTab: AppRoute] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, $0.defaultRoute) })
    private(set) var paths: [AppTab: [AppRoute]] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    var presented: AppPresentation?
    var banner: ModulaBanner?
    /// Leading global sidebar. Not a sixth tab and not Edge Picker.
    var sidebarPresented = false {
        didSet {
            guard oldValue != sidebarPresented else { return }
            // Button / programmatic open+close take the same freeze-through-settle path as the swipe,
            // so feed geometry writers never feed back into layout while the card animates.
            ShellChromeFreeze.sidebarPresented = sidebarPresented
            ShellChromeFreeze.holdForSettle()
        }
    }
    /// Route to restore after a successful authentication challenge.
    private(set) var pendingReturnRoute: AppRoute?
    /// Settings control to scroll to and briefly emphasize after search.
    var settingsFocusAnchor: String?
    var currentRoute: AppRoute { paths[selectedTab]?.last ?? roots[selectedTab] ?? selectedTab.defaultRoute }
    var currentPath: String { RouteSerializer.serialize(currentRoute) }

    func root(for tab: AppTab) -> AppRoute { roots[tab] ?? tab.defaultRoute }
    func path(for tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }
    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }
    func select(_ tab: AppTab) {
        selectedTab = tab
        sidebarPresented = false
    }

    /// Short visible + VoiceOver confirmation (e.g. "Link copied").
    /// Uses the shell island-banner slot so features never build ad-hoc toasts.
    func flash(_ message: String, symbol: String = "checkmark.circle") {
        ModulaToastCenter.shared.show(message, symbol: symbol)
    }

    /// Toast with an action button (Undo / View); held longer.
    func flash(_ message: String, symbol: String, tone: ModulaToastTone? = nil, actionTitle: String, action: @escaping @MainActor () -> Void) {
        ModulaToastCenter.shared.show(message, symbol: symbol, tone: tone, actionTitle: actionTitle, action: action)
    }

    func presentSidebar() { sidebarPresented = true }
    func dismissSidebar() { sidebarPresented = false }
    func open(path: String) -> Bool {
        guard let route = RouteParser.parse(path) else { return false }
        open(route); return true
    }
    func open(_ route: AppRoute) {
        if let tab = route.tab {
            // A tab switch lands on another stack; the tapped card isn't there to morph from.
            if tab != selectedTab { ModulaHeroMorph.disarm() }
            selectedTab = tab
            if isContextRoot(route) { roots[tab] = route; return }
        }
        // A story viewer left on the stack (closed visually but never popped) made the next
        // destination — e.g. Saved from the sidebar — flash the Story Viewer first. Drop
        // stale story routes before pushing anything that isn't itself a story.
        if !Self.isStoryViewer(route), var path = paths[selectedTab] {
            while let last = path.last, Self.isStoryViewer(last) { path.removeLast() }
            paths[selectedTab] = path
        }
        appendDeduplicatingSearch(route)
    }

    private static func isStoryViewer(_ route: AppRoute) -> Bool {
        if case .stories(.story) = route { return true }
        return false
    }
    /// Search over Search replaces the top instead of stacking: two Search screens meant
    /// closing one revealed the other ("search opens again").
    private func appendDeduplicatingSearch(_ route: AppRoute) {
        if case .search = route, var path = paths[selectedTab], case .search? = path.last {
            path[path.count - 1] = route
            paths[selectedTab] = path
            return
        }
        paths[selectedTab, default: []].append(route)
    }
    /// True while the selected tab has pushed screens; the sidebar edge swipe yields to Back.
    var selectedStackHasPushedViews: Bool { !(paths[selectedTab] ?? []).isEmpty }
    /// Routes requested by a running module. Detail destinations (profile,
    /// post) are pushed on the current stack so Back returns to the module
    /// instead of replacing another tab's root (which also tore the module
    /// down). Top-level destinations keep the regular `open` behaviour.
    func openFromModule(_ route: AppRoute) {
        switch route {
        case .profile, .post: push(route)
        default: open(route)
        }
    }

    func replaceContext(with route: AppRoute) {
        guard let tab = route.tab else { return }
        selectedTab = tab
        roots[tab] = route
    }
    /// Context-rail selection: swap the tab root when at a context root; otherwise replace the pushed top so Profile/Home mode changes do not hijack another tab.
    func replaceContextOrTop(with route: AppRoute) {
        if var path = paths[selectedTab], !path.isEmpty, let current = path.last, Self.sameContextFamily(current, route) {
            path[path.count - 1] = route
            paths[selectedTab] = path
            return
        }
        if let current = roots[selectedTab], paths[selectedTab]?.isEmpty != false, Self.sameContextFamily(current, route) {
            roots[selectedTab] = route
            return
        }
        replaceContext(with: route)
    }
    private static func sameContextFamily(_ a: AppRoute, _ b: AppRoute) -> Bool {
        switch (a, b) {
        case (.home, .home), (.activity, .activity), (.me, .me): true
        case (.profile(let lhs, _), .profile(let rhs, _)): lhs == rhs
        default: false
        }
    }
    /// True when the selected tab has no pushed destinations (root context only).
    var isAtTabRoot: Bool { paths[selectedTab]?.isEmpty != false }
    /// Replace the top of the current stack (used by Search scope/query updates) without pushing.
    func replaceTop(with route: AppRoute) {
        if let tab = route.tab { selectedTab = tab }
        if var path = paths[selectedTab], !path.isEmpty {
            path[path.count - 1] = route
            paths[selectedTab] = path
            return
        }
        open(route)
    }
    /// Push onto the selected tab without stealing another tab’s root. Discover/Search use this for profile, post, and module detail so Back restores the current scope.
    func push(_ route: AppRoute) {
        appendDeduplicatingSearch(route)
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
    case activitySummary, activityFilter, discoverFilter
    case homeSummary, homeFeedTools, homeFeeds
    case installedModules
    case commandCenter
    case intelligenceChat
    case createPicker
    case universalShare(SharePayload)
    case collectionPicker(postID: String)
    case draftRestore
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

    static func policy(for route: AppRoute, isTabRoot: Bool = true) -> Self {
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
        case .activity:
            // Activity owns its filters (chip row) and Mark all read (nav bar): no rail, no Tools bar.
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: false,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .home:
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
        case .profile, .me:
            // Pushed profiles keep the originating tab selected in the bottom bar and hide
            // root-only accessories so chrome does not imply a global Profile switch.
            // Profile sections live in its sticky tab bar: no edge rail, no Tools bar.
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: !isTabRoot,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .discover:
            Self(
                bottomBarVisible: true,
                contextRailVisible: false,
                shellAccessoryVisible: true,
                topBarStyle: .standard,
                showsBack: false,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: true
            )
        case .search:
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
        case .auth, .settings(.account):
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
        case .compose:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .hidden,
                showsBack: false,
                showsClose: false,
                immersive: false,
                hidesForKeyboard: false
            )
        case .settings:
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
        case .post:
            // A focused conversation owns the bottom composer, not global shell chrome.
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
        case .developer(.components):
            // Catalog pages remain in the production shell but use a deliberate
            // inspection presentation without a floating accessory over the sample.
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
        case .messages:
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
        case .stories:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .hidden,
                showsBack: false,
                showsClose: true,
                immersive: true,
                hidesForKeyboard: true
            )
        case .reels:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .hidden,
                showsBack: true,
                showsClose: false,
                immersive: true,
                hidesForKeyboard: true
            )
        case .command:
            Self(
                bottomBarVisible: false,
                contextRailVisible: false,
                shellAccessoryVisible: false,
                topBarStyle: .standard,
                showsBack: false,
                showsClose: true,
                immersive: false,
                hidesForKeyboard: false
            )
        case .saved, .collections, .drafts:
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

/// One source of truth for content clearance around persistent shell chrome.
/// SwiftUI's TabView/safeAreaInset owns the occupied height; content adds only
/// this optical clearance rather than guessing per screen.
struct ShellChromeMetrics: Equatable, Sendable {
    let bottomBarHeight: CGFloat
    let accessoryHeight: CGFloat
    let containerReservesOccupiedRegion: Bool
    let opticalClearance: CGFloat

    var occupiedBottomHeight: CGFloat { bottomBarHeight + accessoryHeight }
    var contentBottomInset: CGFloat {
        containerReservesOccupiedRegion ? opticalClearance : occupiedBottomHeight + opticalClearance
    }

    static func resolve(policy: ShellChromePolicy, containerReservesOccupiedRegion: Bool = true) -> Self {
        Self(
            bottomBarHeight: policy.bottomBarVisible ? 49 : 0,
            accessoryHeight: policy.shellAccessoryVisible ? 52 : 0,
            containerReservesOccupiedRegion: containerReservesOccupiedRegion,
            opticalClearance: policy.bottomBarVisible ? 16 : 8
        )
    }
}
