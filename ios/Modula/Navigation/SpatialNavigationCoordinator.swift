import Observation
import SwiftUI

// MARK: - Spatial navigation (Gesture Navigation System)
//
// Home is the anchor. Sidebar (from the left), Profile (from the right) and the Modules Dock
// (up from the in-app bottom bar) are temporary layers over it, never separate roots.
// This coordinator is the single owner of which layer is up, so only one primary sheet is
// ever open, every gesture has a button equivalent, and views never attach their own
// competing swipe handlers. Pure state + math: views read it and feed it drag values.

/// Debug: on by default. Release: off unless switched on (Settings → Labs), matching GUBIC.
enum SpatialNavigationFeature {
    static let enabledKey = "dev.spatialNavigation.enabled"

    static func enabled(defaults: UserDefaults = .standard) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--spatial-navigation-disabled") { return false }
        #if DEBUG
        return defaults.object(forKey: enabledKey) as? Bool ?? true
        #else
        return defaults.bool(forKey: enabledKey)
        #endif
    }
}

/// Whose profile the right-hand sheet shows.
struct SpatialProfileTarget: Hashable, Sendable {
    /// `nil` = the signed-in account (`.me`).
    var userID: String?
    var section: ProfileSection = .overview

    static let me = SpatialProfileTarget(userID: nil)

    var route: AppRoute {
        if let userID { return .profile(userID, section) }
        return .me(section)
    }

    /// Profile routes that open as the sheet. Edit and people lists stay pushed tasks.
    static func from(_ route: AppRoute) -> SpatialProfileTarget? {
        switch route {
        case .me(let section) where Self.sheetSections.contains(section):
            SpatialProfileTarget(userID: nil, section: section)
        case .profile(let id, let section) where Self.sheetSections.contains(section):
            SpatialProfileTarget(userID: id, section: section)
        default:
            nil
        }
    }

    static let sheetSections: Set<ProfileSection> = [.overview, .posts, .modules]
}

/// Modules Dock presentation. Collapsed = just the normal bottom bar.
enum SpatialDockState: Int, CaseIterable, Comparable, Sendable {
    case collapsed, half, expanded
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The one primary layer allowed over Home at a time.
enum SpatialSheet: Hashable, Sendable {
    case sidebar
    case profile(SpatialProfileTarget)
    case dock(SpatialDockState)

    enum Kind: Hashable, Sendable { case sidebar, profile, dock }

    var kind: Kind {
        switch self {
        case .sidebar: .sidebar
        case .profile: .profile
        case .dock: .dock
        }
    }
}

/// Where a drag started, for arbitration.
enum SpatialDragOrigin: Hashable, Sendable {
    case leadingEdge
    case trailingEdge
    case bottomBar
}

/// Last change, so views can animate a replace (e.g. Dock → Profile) as close-then-open.
struct SpatialTransition: Equatable, Sendable {
    var from: SpatialSheet?
    var to: SpatialSheet?
    var replaced: Bool { from != nil && to != nil && from?.kind != to?.kind }
}

@MainActor @Observable
final class SpatialNavigationCoordinator {
    /// The open layer; `nil` = Home (or whichever tab) with nothing over it.
    private(set) var activeSheet: SpatialSheet? {
        didSet {
            guard oldValue != activeSheet else { return }
            lastTransition = SpatialTransition(from: oldValue, to: activeSheet)
            sheetPath = []
            onTransition?(oldValue, activeSheet)
        }
    }
    private(set) var lastTransition = SpatialTransition(from: nil, to: nil)
    /// Screens pushed from inside the profile sheet stay inside it (own back stack).
    var sheetPath: [AppRoute] = []
    /// Called on every change (NavigationCoordinator mirrors the sidebar freeze flags).
    @ObservationIgnored var onTransition: (@MainActor (SpatialSheet?, SpatialSheet?) -> Void)?
    /// Global frames of inner horizontal galleries / module surfaces that own horizontal drags.
    /// Not observed: written from geometry callbacks while scrolling.
    @ObservationIgnored private(set) var exclusionRegions: [String: CGRect] = [:]

    // MARK: Queries

    var isHome: Bool { activeSheet == nil }
    var isSidebarOpen: Bool { activeSheet == .sidebar }
    var isProfileOpen: Bool { activeSheet?.kind == .profile }
    var profileTarget: SpatialProfileTarget? {
        if case .profile(let target) = activeSheet { return target }
        return nil
    }
    var dockState: SpatialDockState {
        if case .dock(let state) = activeSheet { return state }
        return .collapsed
    }
    var isDockOpen: Bool { dockState != .collapsed }

    // MARK: Transitions (one primary sheet at a time)

    /// Opens `sheet`, replacing whatever was up. Opening Profile while the Dock is open closes
    /// the Dock first: there is never more than one value, so that's structural.
    func open(_ sheet: SpatialSheet) {
        if case .dock(.collapsed) = sheet { close(); return }
        activeSheet = sheet
    }

    func openSidebar() { open(.sidebar) }
    func openProfile(_ target: SpatialProfileTarget = .me) { open(.profile(target)) }
    func openDock(_ state: SpatialDockState = .half) { open(.dock(state)) }

    /// Moves the dock between collapsed / half / expanded. Collapsing dismisses it.
    func setDock(_ state: SpatialDockState) {
        if state == .collapsed {
            if activeSheet?.kind == .dock { close() }
            return
        }
        open(.dock(state))
    }

    /// One step up (collapsed → half → expanded).
    func raiseDock() {
        switch dockState {
        case .collapsed: setDock(.half)
        case .half, .expanded: setDock(.expanded)
        }
    }

    /// One step down (expanded → half → collapsed).
    func lowerDock() {
        switch dockState {
        case .expanded: setDock(.half)
        case .half, .collapsed: setDock(.collapsed)
        }
    }

    func toggleSidebar() { isSidebarOpen ? close() : openSidebar() }

    /// Back to Home.
    func close() { activeSheet = nil }

    /// Closes only if `kind` is the open layer (stale gesture ends can't close a newer sheet).
    func close(_ kind: SpatialSheet.Kind) {
        if activeSheet?.kind == kind { close() }
    }

    /// Back inside the profile sheet: pops its stack, or dismisses at the root.
    func back() {
        if isProfileOpen, !sheetPath.isEmpty { sheetPath.removeLast(); return }
        close()
    }

    func pushInSheet(_ route: AppRoute) {
        guard isProfileOpen else { return }
        if sheetPath.last == route { return }
        if route == profileTarget?.route, sheetPath.isEmpty { return }
        sheetPath.append(route)
    }

    // MARK: Gesture arbitration

    func setExclusion(_ id: String, frame: CGRect?) {
        if let frame, !frame.isEmpty { exclusionRegions[id] = frame } else { exclusionRegions[id] = nil }
    }

    /// True when a drag starting at `point` (global) belongs to an inner gallery or module.
    func isExcluded(_ point: CGPoint) -> Bool {
        exclusionRegions.values.contains { $0.contains(point) }
    }

    /// Whether a drag from `origin` may start a layer. Inner galleries win; nothing opens over
    /// a system sheet; edge opens only happen with nothing else up and on a stack root (the
    /// leading edge on a pushed screen belongs to the system Back gesture).
    func canBegin(
        from origin: SpatialDragOrigin,
        at point: CGPoint,
        isAtStackRoot: Bool,
        systemSheetPresented: Bool,
        enabled: Bool
    ) -> Bool {
        guard !systemSheetPresented, !isExcluded(point) else { return false }
        switch origin {
        case .leadingEdge:
            return isHome && isAtStackRoot
        case .trailingEdge:
            return enabled && isHome && isAtStackRoot
        case .bottomBar:
            return enabled && (isHome || activeSheet?.kind == .dock)
        }
    }

    // MARK: Settle math (velocity-aware)

    /// Decides open/closed when a horizontal drag ends. `progress` and `predicted` are 0…1
    /// fractions of the sheet's travel; a strong flick beats raw distance.
    nonisolated static func settlesOpen(progress: CGFloat, predicted: CGFloat) -> Bool {
        if abs(predicted - progress) > 0.25 { return predicted > 0.5 }
        return progress > 0.5
    }

    /// Converts a horizontal drag into sheet progress. Sheets entering from the right open with
    /// negative translation; from the left with positive.
    nonisolated static func progress(
        translation: CGFloat,
        width: CGFloat,
        startOpen: Bool,
        fromTrailing: Bool
    ) -> CGFloat {
        guard width > 0 else { return startOpen ? 1 : 0 }
        let signed = fromTrailing ? -translation : translation
        let base: CGFloat = startOpen ? 1 : 0
        return min(max(base + signed / width, 0), 1)
    }

    /// Dock heights for a container height: half ≈ 46 %, expanded ≈ 88 %.
    nonisolated static func dockHeight(for state: SpatialDockState, container: CGFloat) -> CGFloat {
        switch state {
        case .collapsed: 0
        case .half: (container * 0.46).rounded()
        case .expanded: (container * 0.88).rounded()
        }
    }

    /// Picks the dock detent when a vertical drag ends. `translation` / `predicted` are the
    /// gesture's height values (negative = up).
    nonisolated static func settledDock(
        from state: SpatialDockState,
        translation: CGFloat,
        predicted: CGFloat,
        container: CGFloat
    ) -> SpatialDockState {
        let start = dockHeight(for: state, container: container)
        let current = start - translation
        let projected = start - predicted
        let target = abs(projected - current) > container * 0.18 ? projected : current
        return SpatialDockState.allCases.min {
            abs(dockHeight(for: $0, container: container) - target) < abs(dockHeight(for: $1, container: container) - target)
        } ?? state
    }
}

// MARK: - Layout tokens

/// Sheet geometry from the spec: ~97–98 % width, an 8–12 pt Home strip, 28–36 pt corners.
enum SpatialSheetMetrics {
    static let gutter: CGFloat = 10
    static let cornerRadius: CGFloat = 32
    /// Wide enough to catch a casual thumb swipe from the right bezel (20 pt missed often).
    static let edgeActivationWidth: CGFloat = 28
    static let travelPadding: CGFloat = 36

    nonisolated static func sheetWidth(for total: CGFloat) -> CGFloat {
        max(total - gutter, 0)
    }

    /// Quick and crisp, no bounce at rest; same curve as the sidebar so both sheets feel alike.
    static var settleSpring: Animation { .spring(duration: 0.3, bounce: 0) }
    static var reduceMotionFade: Animation { .easeInOut(duration: 0.2) }
}
