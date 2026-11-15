import SwiftUI
import UIKit

// MARK: - Shell accessory configuration

struct ShellAccessoryAction: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let enabled: Bool
    let accessibilityIdentifier: String
}

struct ShellAccessoryConfiguration: Equatable {
    var title: String
    var symbol: String
    var actions: [ShellAccessoryAction]
    var showsSearch: Bool
    var showsMore: Bool

    @MainActor
    static func configuration(for route: AppRoute, activity: ActivityStore?, signedIn: Bool) -> Self {
        switch route {
        case .activity(let mode):
            let state = activity?.state(for: mode)
            let hasUnread = (state?.events.contains { !$0.isRead } ?? false)
                || ((state?.unreadCount ?? 0) > 0)
            return Self(
                title: "Activity",
                symbol: "bell",
                actions: [
                    ShellAccessoryAction(id: "summary", title: "Summary", symbol: "sparkles", enabled: signedIn, accessibilityIdentifier: "accessory.summary"),
                    ShellAccessoryAction(id: "filter", title: "Options", symbol: "line.3.horizontal.decrease", enabled: signedIn, accessibilityIdentifier: "accessory.filter"),
                    ShellAccessoryAction(id: "mark-read", title: "Mark All Read", symbol: "checkmark.circle", enabled: signedIn && hasUnread, accessibilityIdentifier: "accessory.mark-read")
                ],
                showsSearch: false,
                showsMore: true
            )
        case .home:
            return Self(
                title: "Tools",
                symbol: "house",
                actions: [
                    ShellAccessoryAction(id: "feeds", title: "Feeds", symbol: "number", enabled: true, accessibilityIdentifier: "accessory.feeds"),
                    ShellAccessoryAction(id: "summary", title: "Summary", symbol: "sparkles", enabled: true, accessibilityIdentifier: "accessory.summary"),
                    // One-tap refresh; feed options + Manage following live once, in Feeds (was a duplicate "Tools" sheet).
                    ShellAccessoryAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", enabled: true, accessibilityIdentifier: "accessory.refresh")
                ],
                showsSearch: false,
                showsMore: false
            )
        case .discover(let scope):
            return Self(
                title: "Tools",
                symbol: "safari",
                actions: [
                    // Trending and Topics have no filters: never offer an empty Customise sheet.
                    ShellAccessoryAction(id: "customise", title: "Customise", symbol: "slider.horizontal.3", enabled: scope.hasFilters, accessibilityIdentifier: "accessory.customise"),
                    ShellAccessoryAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", enabled: true, accessibilityIdentifier: "accessory.refresh")
                ],
                showsSearch: false,
                showsMore: true
            )
        case .search:
            return Self(title: "Search", symbol: "magnifyingglass", actions: [], showsSearch: false, showsMore: false)
        case .productHub:
            return Self(title: "Modules", symbol: "shippingbox", actions: [], showsSearch: true, showsMore: true)
        case .profile, .me:
            return Self(
                title: "Tools",
                symbol: "person.crop.circle",
                actions: [
                    ShellAccessoryAction(id: "edit", title: "Edit", symbol: "pencil", enabled: true, accessibilityIdentifier: "accessory.edit"),
                    ShellAccessoryAction(id: "share", title: "Share", symbol: "square.and.arrow.up", enabled: true, accessibilityIdentifier: "accessory.share"),
                    ShellAccessoryAction(id: "more-profile", title: "More", symbol: "ellipsis", enabled: true, accessibilityIdentifier: "accessory.profile-more")
                ],
                showsSearch: false,
                showsMore: false
            )
        default:
            return Self(title: "Modula", symbol: "m.circle", actions: [], showsSearch: true, showsMore: true)
        }
    }
}

/// Quick tabs hosted by the bottom accessory (replaces the old "Tools" title row).
enum ShellQuickTab: String, CaseIterable, Identifiable {
    case following, forYou, discover, modules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .following: "Following"
        case .forYou: "For You"
        case .discover: "Discover"
        case .modules: "Modules"
        }
    }

    var symbol: String {
        switch self {
        case .following: "person.2"
        case .forYou: "sparkles"
        case .discover: "safari"
        case .modules: "square.grid.2x2"
        }
    }

    /// Next / previous quick tab in bar order (no wrap-around).
    func neighbour(_ step: Int) -> ShellQuickTab? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return nil }
        let target = index + step
        return all.indices.contains(target) ? all[target] : nil
    }

    static func current(_ route: AppRoute) -> ShellQuickTab? {
        switch route {
        case .home(.following): .following
        case .home(.forYou): .forYou
        case .discover: .discover
        case .productHub: .modules
        default: nil
        }
    }

    @MainActor
    func open(in navigation: NavigationCoordinator) {
        switch self {
        case .following, .forYou:
            navigation.select(.home)
            navigation.binding(for: .home).wrappedValue = []
            navigation.replaceContext(with: .home(self == .following ? .following : .forYou))
        case .discover:
            navigation.select(.discover)
        case .modules:
            navigation.select(.modules)
        }
    }
}

enum ShellIntelligenceChatMetrics {
    static let buttonSize: CGFloat = 48
    static let dockSpacing: CGFloat = 10
}

/// Detached circular AI control — same language as the Music-style side buttons.
struct ShellIntelligenceChatButton: View {
    var compact = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse = 0

    static var symbolName: String {
        UIImage(systemName: "pencil.and.scribble") == nil ? "square.and.pencil" : "pencil.and.scribble"
    }

    var body: some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let size: CGFloat = compact ? 28 : ShellIntelligenceChatMetrics.buttonSize
        Button {
            pulse += 1
            PresentationCoordinator.present(.intelligenceChat, in: app.navigation)
            HapticEngine.shared.play(.contextOpen)
        } label: {
            Image(systemName: Self.symbolName)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: pulse)
                .frame(width: size, height: size)
                .modifier(ShellIntelligenceChatChrome(compact: compact, opaque: opaque))
                .modifier(ShellIntelligenceShimmer(isActive: !compact && !opaque))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(IntelligenceChatIdentity.title)
        .accessibilityShowsLargeContentViewer {
            Label(IntelligenceChatIdentity.title, systemImage: Self.symbolName)
        }
        .accessibilityHint("Opens \(IntelligenceChatIdentity.subtitle.lowercased()) chat")
        .accessibilityIdentifier("accessory.intelligence.chat")
    }
}

private struct ShellIntelligenceChatChrome: ViewModifier {
    var compact: Bool
    var opaque: Bool

    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            content.modulaChrome(in: Circle(), opaque: opaque)
        }
    }
}

private struct ShellIntelligenceShimmer: ViewModifier {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        if !isActive || reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                let period = app.appearance.motion == .calm ? 5.2 : 3.8
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                content.overlay {
                    Circle()
                        .stroke(
                            AngularGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.58),
                                    .init(color: Color.white.opacity(0.72), location: 0.74),
                                    .init(color: app.appearance.liveAccent.opacity(0.55), location: 0.84),
                                    .init(color: .clear, location: 0.96)
                                ],
                                center: .center,
                                angle: .degrees(phase * 360)
                            ),
                            lineWidth: 1.5
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Destination tools row. AI Mode lives in the pull-from-top actions.
struct ShellAccessoryDock: View {
    let route: AppRoute
    var toolsChrome = true

    var body: some View {
        ShellAccessoryHost(route: route, nativeHosted: !toolsChrome)
            .frame(maxWidth: .infinity, minHeight: ShellIntelligenceChatMetrics.buttonSize)
            .accessibilityElement(children: .contain)
    }
}

/// System accessory only — width stays with the tab view.
/// Inline vs expanded comes from `tabViewBottomAccessoryPlacement`.
@available(iOS 26.0, *)
struct ShellAccessorySystemSlot: View {
    let route: AppRoute
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if placement == .inline {
            inlineAccessory
        } else {
            ShellAccessoryDock(route: route, toolsChrome: false)
                .background {
                    TabAccessoryPlatterController(hidesExpandedPlatter: false)  // keep the system Liquid Glass platter
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }

    private var inlineAccessory: some View {
        let config = ShellAccessoryConfiguration.configuration(
            for: route,
            activity: app.activity,
            signedIn: app.auth.isSignedIn
        )
        let quick = ShellQuickTab.current(route)
        let title = quick?.title ?? config.title
        // Minimised on scroll: the accessory compacts into a single pill naming where you are.
        return HStack(spacing: 7) {
            Image(systemName: quick?.symbol ?? config.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(app.appearance.liveAccent.gradient, in: Circle())
                .symbolEffect(.bounce, value: config.symbol)
                .contentTransition(.symbolEffect(.replace))
            if title == "Modula" {
                ModulaWordmark(height: 14)
            } else {
                Text(title)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .transition(.blurReplace.combined(with: .scale(0.86)))
        .animation(.snappy(duration: 0.28), value: title)
        .contentShape(Capsule())
        .modifier(QuickTabSwipe(current: quick))
        .onLongPressGesture(minimumDuration: 0.5) { CommandPaletteCenter.shared.present() }
        .modifier(AccessoryModulesLift())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Swipe up for modules, swipe left or right to switch feeds")
        .accessibilityIdentifier("tab.accessory")
        .accessibilityAdjustableAction { direction in
            guard let quick else { return }
            switch direction {
            case .increment: quick.neighbour(1)?.open(in: app.navigation)
            case .decrement: quick.neighbour(-1)?.open(in: app.navigation)
            @unknown default: break
            }
        }
    }
}

/// Swipe sideways on the minimised accessory to move between Following / For You / Discover /
/// Modules. The pill follows the finger (rubber-banded at the ends) and settles without bounce.
private struct QuickTabSwipe: ViewModifier {
    let current: ShellQuickTab?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.26, bounce: 0)))
    private var drag: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : drag)
            .opacity(1 - min(abs(drag) / 240, 0.35))
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .updating($drag) { value, state, transaction in
                        guard current != nil, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        transaction.disablesAnimations = true
                        let dx = value.translation.width
                        let blocked = current?.neighbour(dx < 0 ? 1 : -1) == nil
                        state = blocked ? dx * 0.25 : dx * 0.6
                    }
                    .onEnded { value in
                        guard let current, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        let dx = abs(value.predictedEndTranslation.width) > abs(value.translation.width) * 1.5
                            ? value.predictedEndTranslation.width : value.translation.width
                        guard abs(dx) > 44, let next = current.neighbour(dx < 0 ? 1 : -1) else { return }
                        HapticEngine.shared.play(.selection)
                        withAnimation(.snappy(duration: 0.24)) { next.open(in: app.navigation) }
                    }
            )
    }
}

/// Main-thread flag the sidebar sets while its drag is live so UIKit chrome
/// hooks and Home observers stop writing during the interactive transform.
@MainActor
enum ShellChromeFreeze {
    /// Posted once the card has fully settled, so frozen writers can re-sync their latest value.
    static let cardSpace = "modula.shell.card"
    static let didThaw = Notification.Name("ShellChromeFreeze.didThaw")
    private static var liveDrag = false
    /// Mirrors `NavigationCoordinator.sidebarPresented`; while open the feed keeps its layout locked.
    static var sidebarPresented = false
    private static var settleUntil: CFTimeInterval = 0
    private static var thawScheduled = false

    /// True while the card is being dragged AND for the whole release / settle animation that
    /// follows. A fast flick ends the drag almost immediately, but the spring then moves the card
    /// for ~0.6s; geometry writers must stay frozen for all of it or they feed back into layout.
    static var isSidebarDragging: Bool {
        get { liveDrag || CACurrentMediaTime() < settleUntil }
        set {
            liveDrag = newValue
            holdForSettle()
        }
    }

    /// Keeps the freeze for the settle animation (spring settles in ~0.6s; padded).
    static func holdForSettle(_ duration: CFTimeInterval = 0.75) {
        settleUntil = max(settleUntil, CACurrentMediaTime() + duration)
        scheduleThaw()
    }

    private static func scheduleThaw() {
        guard !thawScheduled else { return }
        thawScheduled = true
        let delay = max(0.05, settleUntil - CACurrentMediaTime() + 0.02)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            thawScheduled = false
            if isSidebarDragging { scheduleThaw(); return }
            NotificationCenter.default.post(name: didThaw, object: nil)
        }
    }
}

@available(iOS 26.0, *)
private struct TabAccessoryPlatterController: UIViewRepresentable {
    var hidesExpandedPlatter: Bool

    func makeUIView(context: Context) -> TabAccessoryPlatterHook {
        let hook = TabAccessoryPlatterHook()
        hook.hidesExpandedPlatter = hidesExpandedPlatter
        return hook
    }

    func updateUIView(_ hook: TabAccessoryPlatterHook, context: Context) {
        hook.hidesExpandedPlatter = hidesExpandedPlatter
        hook.applySoon()
    }
}

/// Strips the system accessory glass capsule without touching our hosting content.
private final class TabAccessoryPlatterHook: UIView {
    var hidesExpandedPlatter = true
    private var hiddenViews: [UIView] = []
    private var clearedEffects: [(UIVisualEffectView, UIVisualEffect?)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
        NotificationCenter.default.addObserver(self, selector: #selector(thawed), name: ShellChromeFreeze.didThaw, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func thawed() { applySoon() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applySoon()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applySoon()
    }

    private var applyPending = false
    private var lastHidden: Bool?

    /// Coalesced: at most one queued pass. The old version ran apply three
    /// times per layoutSubviews, and apply itself dirtied layout, so any
    /// per-frame layout (sidebar drag transforms the whole TabView) flooded
    /// the main queue and hung the app.
    func applySoon() {
        guard !applyPending else { return }
        applyPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPending = false
            self.apply()
        }
    }

    func apply() {
        guard window != nil, !ShellChromeFreeze.isSidebarDragging else { return }
        let hide = shouldHidePlatter()
        // Idempotent: only touch UIKit when the decision actually changes.
        if lastHidden == hide, !hide { return }
        lastHidden = hide
        if hide {
            neutralize()
        } else {
            restore()
        }
    }

    private func shouldHidePlatter() -> Bool {
        if #available(iOS 26.0, *) {
            if traitCollection.tabAccessoryEnvironment == .inline { return false }
        }
        return hidesExpandedPlatter
    }

    private func neutralize() {
        let hosting = hostingAncestor()
        var current: UIView? = self
        var outsideHosting = hosting == nil
        while let view = current {
            if view is UITabBar || view is UIWindow { break }
            // Never climb past the tab bar controller's container into the
            // shell / sidebar card views.
            if view.next is UITabBarController { break }
            if let hosting, view === hosting {
                if view.backgroundColor != .clear { view.backgroundColor = .clear }
                if view.isOpaque { view.isOpaque = false }
                outsideHosting = true
                current = view.superview
                continue
            }
            guard outsideHosting else {
                current = view.superview
                continue
            }
            if view.backgroundColor != .clear { view.backgroundColor = .clear }
            if view.isOpaque { view.isOpaque = false }
            if let effectView = view as? UIVisualEffectView {
                clearEffect(effectView)
                for subview in effectView.subviews where subview !== effectView.contentView {
                    conceal(subview)
                }
            }
            if let parent = view.superview {
                for sibling in parent.subviews where sibling !== view {
                    concealChromeSibling(sibling)
                }
            }
            current = view.superview
        }
    }

    private func hostingAncestor() -> UIView? {
        var current: UIView? = self
        while let view = current {
            if String(describing: type(of: view)).localizedCaseInsensitiveContains("Hosting") {
                return view
            }
            current = view.superview
        }
        return nil
    }

    private func restore() {
        hiddenViews.forEach { $0.isHidden = false; $0.alpha = 1 }
        hiddenViews.removeAll()
        clearedEffects.forEach { $0.0.effect = $0.1 }
        clearedEffects.removeAll()
    }

    private func clearEffect(_ effectView: UIVisualEffectView) {
        guard effectView.effect != nil else { return }
        if !clearedEffects.contains(where: { $0.0 === effectView }) {
            clearedEffects.append((effectView, effectView.effect))
        }
        effectView.effect = nil
        effectView.backgroundColor = .clear
        effectView.isOpaque = false
    }

    private func concealChromeSibling(_ view: UIView) {
        if view is UITabBar { return }
        let name = String(describing: type(of: view))
        if name.localizedCaseInsensitiveContains("Hosting") { return }
        if name.localizedCaseInsensitiveContains("TabBar"),
           !name.localizedCaseInsensitiveContains("Accessory") {
            return
        }
        if isChrome(view) {
            conceal(view)
            return
        }
        view.subviews.forEach(concealChromeSibling)
    }

    private func isChrome(_ view: UIView) -> Bool {
        if view is UIVisualEffectView { return true }
        let name = String(describing: type(of: view)).lowercased()
        return ["glass", "effect", "platter", "backdrop", "material", "chrome", "visual"]
            .contains { name.contains($0) }
    }

    private func conceal(_ view: UIView) {
        guard !hiddenViews.contains(where: { $0 === view }) else { return }
        view.isHidden = true
        view.alpha = 0
        hiddenViews.append(view)
    }
}

/// Destination-scoped tool accessory. Modes stay on the context rail.
struct ShellAccessoryHost: View {
    let route: AppRoute
    var nativeHosted = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var iconPulse: [String: Int] = [:]
    /// Swipeable contexts: 0 = quick tabs (Following / For You / Discover / Modules),
    /// 1 = this route's tools, 2 = Modules, 3 = Quick actions.
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var quickTabSpace
    private static let pageTitles = ["Tabs", "Tools", "Modules", "Quick"]

    /// Feed-like routes open on the quick tabs; elsewhere (Activity, Profile…) the route's
    /// own tools come first so e.g. Mark All Read stays one tap away.
    static func defaultPage(for route: AppRoute) -> Int {
        ShellQuickTab.current(route) == nil ? 1 : 0
    }

    var body: some View {
        let config = ShellAccessoryConfiguration.configuration(
            for: route,
            activity: app.activity,
            signedIn: app.auth.isSignedIn
        )
        HStack(spacing: 8) {
            switch page {
            case 0: quickTabsRow
            case 1: toolsRow(config)
            default: contextRow(page)
            }
            pageDots
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, minHeight: ShellIntelligenceChatMetrics.buttonSize)
        .modulaAccessorySurface(
            nativeHosted: nativeHosted,
            opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        )
        .dynamicTypeSize(...DynamicTypeSize.large)
        .contentTransition(.interpolate)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: page)
        .animation(.snappy(duration: 0.28), value: config.title)
        .contentShape(Rectangle())
        // Horizontal swipe pages between contexts (Tools / Modules / Quick).
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                  abs(value.translation.width) > 40 else { return }
            let next = value.translation.width < 0 ? page + 1 : page - 1
            page = (next + Self.pageTitles.count) % Self.pageTitles.count
            HapticEngine.shared.play(.selection)
        })
        // Long-press anywhere on the Tools accessory: glass command palette.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            CommandPaletteCenter.shared.present()
        })
        .modifier(AccessoryModulesLift())
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next context") { page = (page + 1) % Self.pageTitles.count }
        .accessibilityAction(named: "Installed modules") {
            app.navigation.openModulesDock()
        }
        .accessibilityAction(named: "Command palette") { CommandPaletteCenter.shared.present() }
        .accessibilityIdentifier("tab.accessory")
        .onChange(of: route) { _, next in page = Self.defaultPage(for: next) }
        .onAppear { page = Self.defaultPage(for: route) }
    }

    /// Quick tabs: one tap between the main feeds without reaching for the tab bar.
    private var quickTabsRow: some View {
        let current = ShellQuickTab.current(route)
        // Optional ID: off-feed routes show no thumb instead of a wrong one.
        return ModulaSegmentedControl("Feeds", selection: Binding<ShellQuickTab?>(get: { current }, set: { $0?.open(in: app.navigation) }),
                                      options: ShellQuickTab.allCases.map { Optional($0) }, compact: true,
                                      identifier: { "accessory.quick.\($0?.rawValue ?? "none")" }) { $0?.title ?? "" }
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.pageTitles.count, id: \.self) { i in
                Circle()
                    .fill(i == page ? app.appearance.liveAccent : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }

    private struct ContextItem: Identifiable { let id: String; let title: String; let symbol: String; let run: () -> Void }

    private func contextItems(_ page: Int) -> [ContextItem] {
        if page == 2 {
            return [
                ContextItem(id: "hub", title: "Product Hub", symbol: "shippingbox") { app.navigation.open(.productHub(.featured)) },
                ContextItem(id: "installed", title: "Installed", symbol: "checkmark.circle") { app.navigation.open(.productHub(.collection(.installed))) },
                ContextItem(id: "updates", title: "Updates", symbol: "arrow.triangle.2.circlepath") { app.navigation.open(.productHub(.collection(.updates))) }
            ]
        }
        return [
            ContextItem(id: "search", title: "Search", symbol: "magnifyingglass") { app.navigation.open(.search(.root(nil))) },
            ContextItem(id: "command", title: "Command Center", symbol: "command") { PresentationCoordinator.present(.commandCenter, in: app.navigation) },
            ContextItem(id: "saved", title: "Saved", symbol: "bookmark") { app.navigation.open(.saved(.root)) },
            ContextItem(id: "drafts", title: "Drafts", symbol: "doc.text") { app.navigation.open(.drafts(.root)) }
        ]
    }

    @ViewBuilder
    private func contextRow(_ page: Int) -> some View {
        Text(Self.pageTitles[page])
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
        Spacer(minLength: 6)
        ForEach(contextItems(page)) { item in
            Button {
                iconPulse[item.id, default: 0] += 1
                HapticEngine.shared.play(.navigation)
                item.run()
            } label: {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.bounce, value: iconPulse[item.id, default: 0])
                    .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityIdentifier("accessory.\(item.id)")
        }
    }

    @ViewBuilder
    private func toolsRow(_ config: ShellAccessoryConfiguration) -> some View {
            Image(systemName: config.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(app.appearance.liveAccent.opacity(0.12), in: Circle())
                .symbolEffect(.bounce, value: config.symbol)
                .contentTransition(.symbolEffect(.replace))
            if config.title == "Modula" {
                ModulaWordmark(height: 13)
            } else {
                Text(config.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            ForEach(config.actions) { action in
                if action.enabled {
                    Button {
                        iconPulse[action.id, default: 0] += 1
                        perform(action)
                    } label: {
                        Image(systemName: action.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: iconPulse[action.id, default: 0])
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityShowsLargeContentViewer {
                        Label(action.title, systemImage: action.symbol)
                    }
                    .accessibilityIdentifier(action.accessibilityIdentifier)
                }
            }
            if config.showsSearch {
                Button {
                    iconPulse["search", default: 0] += 1
                    app.navigation.open(.search(.root(nil)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolEffect(.bounce, value: iconPulse["search", default: 0])
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search Modula")
                .accessibilityShowsLargeContentViewer {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("accessory.search")
            }
            if config.showsMore {
                moreMenu
            }
    }

    private var moreMenu: some View {
        Menu {
            if case .activity = route {
                Section("Activity") {
                    Button("Notification Settings", systemImage: "bell.badge") {
                        app.navigation.open(.settings(.notifications(.root)))
                    }
                }
            }
            Section("Quick Access") {
                Button("Command Center", systemImage: "command") {
                    PresentationCoordinator.present(.commandCenter, in: app.navigation)
                    HapticEngine.shared.play(.contextOpen)
                }
                Button("Settings", systemImage: "gearshape") { app.navigation.open(.settings(.root)) }
                Button("Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
                Button("Account", systemImage: "person.crop.circle") {
                    if app.auth.account == nil {
                        app.navigation.requestAuthentication(returningTo: .settings(.account(.root)))
                    } else {
                        app.navigation.open(.settings(.account(.root)))
                    }
                }
                Button("Saved", systemImage: "bookmark") { app.navigation.open(.saved(.root)) }
                Button("Drafts", systemImage: "doc.text") { app.navigation.open(.drafts(.root)) }
            }
            Section("Modules") {
                Button("Product Hub", systemImage: "shippingbox") { app.navigation.open(.productHub(.featured)) }
                Button("Installed Modules", systemImage: "checkmark.circle") {
                    app.navigation.open(.productHub(.collection(.installed)))
                }
                Button("Updates", systemImage: "arrow.triangle.2.circlepath") {
                    app.navigation.open(.productHub(.collection(.updates)))
                }
            }
            Section("Privacy & Information") {
                Button("Privacy & Security", systemImage: "lock.shield") { app.navigation.open(.settings(.privacy(.root))) }
                Button("About Modula", systemImage: "info.circle") { app.navigation.open(.settings(.about(.root))) }
                Button("Share Modula", systemImage: "square.and.arrow.up") {
                    PresentationCoordinator.present(.share(route), in: app.navigation)
                }
            }
            #if DEBUG
            Divider()
            Button("Component Catalog", systemImage: "square.grid.3x3") { app.navigation.open(.developer(.components)) }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .symbolEffect(.bounce, value: iconPulse["more", default: 0])
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded {
            iconPulse["more", default: 0] += 1
        })
        .accessibilityLabel("More")
        .accessibilityIdentifier("accessory.more")
    }

    private func perform(_ action: ShellAccessoryAction) {
        HapticEngine.shared.play(.selection)
        switch action.id {
        case "feeds":
            PresentationCoordinator.present(.homeFeeds, in: app.navigation)
        case "customise":
            PresentationCoordinator.present(.discoverFilter, in: app.navigation)
        case "summary":
            if case .home = route {
                PresentationCoordinator.present(.homeSummary, in: app.navigation)
            } else {
                PresentationCoordinator.present(.activitySummary, in: app.navigation)
            }
        case "tools":
            PresentationCoordinator.present(.homeFeedTools, in: app.navigation)
        case "filter":
            if case .activity = route {
                PresentationCoordinator.present(.activityFilter, in: app.navigation)
            } else {
                PresentationCoordinator.present(.discoverFilter, in: app.navigation)
            }
        case "mark-read":
            if case .activity(let mode) = route {
                Task { await app.activity.markAllRead(mode: mode) }
            }
        case "search":
            app.navigation.open(.search(.root(nil)))
            HapticEngine.shared.play(.navigation)
        case "refresh":
            if case .discover(let scope) = route {
                Task {
                    await app.discover.refresh(scope)
                    HapticEngine.shared.play(.confirmation)
                }
            } else if case .home(let mode) = route {
                Task {
                    await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                    HapticEngine.shared.play(.confirmation)
                }
            }
        case "edit":
            switch route {
            case .me:
                app.navigation.replaceContextOrTop(with: .me(.edit))
            case .profile(let id, _):
                app.navigation.replaceContextOrTop(with: .profile(id, .edit))
            default:
                app.navigation.open(.me(.edit))
            }
            HapticEngine.shared.play(.navigation)
        case "share":
            PresentationCoordinator.present(.share(route), in: app.navigation)
            HapticEngine.shared.play(.lightImpact)
        case "more-profile":
            PresentationCoordinator.present(.share(route), in: app.navigation)
            HapticEngine.shared.play(.contextOpen)
        default:
            break
        }
    }
}

/// Shell-owned bottom chrome for iOS versions without system tab accessories.
struct ModulaBottomChrome: View {
    let route: AppRoute
    var showsAccessory = true
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if showsAccessory {
                ShellAccessoryDock(route: route)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            ModulaTabBar(embedded: true)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .padding(.top, 2)
        .modulaMaterial(
            .control,
            in: RoundedRectangle(cornerRadius: app.appearance.interfaceShape.radius(for: .control) + 10, style: .continuous),
            depth: .floating
        )
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

struct ModulaTabBar: View {
    var embedded = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Blob edges in tab units. The leading edge of travel moves first and the
    /// trailing edge follows, so the glass stretches across and settles (liquid morph).
    @State private var blobLead: CGFloat = -1
    @State private var blobTrail: CGFloat = -1

    var body: some View {
        @Bindable var navigation = app.navigation
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = navigation.selectedTab == tab
                Button {
                    navigation.select(tab)
                    HapticEngine.shared.play(.navigation)
                } label: {
                    VStack(spacing: 2) {
                        if tab == .profile {
                            ProfileTabIcon(selected: selected, size: 26)
                                .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
                                .animation(.spring(duration: 0.34, bounce: 0.28), value: selected)
                        } else {
                            Image(systemName: selected ? tab.selectedIcon : tab.icon)
                                .font(.system(size: 16, weight: selected ? .semibold : .medium))
                                .symbolEffect(.bounce, value: selected)
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(selected ? app.appearance.liveAccent : .secondary)
                        }
                        Text(tab.title)
                            .font(.caption2.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? app.appearance.liveAccent : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .background { tabBlob(selectedIndex: tabIndex(navigation.selectedTab)) }
        .padding(.horizontal, embedded ? 2 : 4)
        .padding(.vertical, embedded ? 2 : 3)
        .frame(maxWidth: 560)
        .onAppear {
            let index = tabIndex(navigation.selectedTab)
            blobLead = index
            blobTrail = index
        }
        .onChange(of: navigation.selectedTab) { old, new in
            morphBlob(from: tabIndex(old), to: tabIndex(new))
        }
        .modifier(TabBarChrome(embedded: embedded, opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency))
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global navigation")
    }
}

extension ModulaTabBar {
    fileprivate func tabIndex(_ tab: AppTab) -> CGFloat {
        CGFloat(AppTab.allCases.firstIndex(of: tab) ?? 0)
    }

    fileprivate func morphBlob(from: CGFloat, to: CGFloat) {
        guard from != to else { return }
        if reduceMotion || ModulaPreferences.extraMotionReduction {
            withAnimation(.easeOut(duration: 0.15)) { blobLead = to; blobTrail = to }
            return
        }
        // Front edge snaps toward the new tab, back edge follows a beat later: stretch → settle.
        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
            if to > from { blobTrail = to } else { blobLead = to }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.7)) {
                blobLead = to
                blobTrail = to
            }
        }
    }

    @ViewBuilder
    fileprivate func tabBlob(selectedIndex: CGFloat) -> some View {
        let lead = blobLead < 0 ? selectedIndex : blobLead
        let trail = blobTrail < 0 ? selectedIndex : blobTrail
        let accent = app.appearance.liveAccent
        ModulaTabBlobShape(lead: lead, trail: trail, count: CGFloat(AppTab.allCases.count))
            .fill(accent.opacity(0.15))
            .overlay {
                ModulaTabBlobShape(lead: lead, trail: trail, count: CGFloat(AppTab.allCases.count))
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: accent.opacity(0.18), radius: 8, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Capsule spanning tab `lead`…`trail` (fractional while animating). Squeezes a little
/// vertically while stretched so the glass reads as liquid rather than a sliding pill.
struct ModulaTabBlobShape: Shape {
    var lead: CGFloat
    var trail: CGFloat
    var count: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lead, trail) }
        set { lead = newValue.first; trail = newValue.second }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let slot = rect.width / count
        let low = min(lead, trail), high = max(lead, trail)
        let stretch = min(high - low, 1.5)
        let inset: CGFloat = 5
        let squeeze = stretch * 2.5
        let frame = CGRect(
            x: rect.minX + low * slot + inset,
            y: rect.minY + 3 + squeeze,
            width: max((high - low + 1) * slot - inset * 2, 1),
            height: max(rect.height - 6 - squeeze * 2, 1)
        )
        return Capsule(style: .continuous).path(in: frame)
    }
}

private struct TabBarChrome: ViewModifier {
    var embedded: Bool
    var opaque: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .modulaChrome(in: Capsule(), opaque: opaque)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
    }
}

/// Swipe-up on the Tools accessory opens installed Product Hub modules. Vertical-only
/// so tab taps, accessory buttons, Edge Picker, and feed scroll keep ownership.
private struct AccessoryModulesLift: ViewModifier {
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        let dy = value.translation.height
                        let dx = value.translation.width
                        guard dy < -PostGestureThresholds.commentSheetThreshold else { return }
                        guard abs(dy) > abs(dx) * PostGestureThresholds.verticalDominanceRatio else { return }
                        present()
                    }
            )
            .accessibilityAction(named: "Installed modules", present)
    }

    private func present() {
        HapticEngine.shared.play(.contextOpen)
        app.navigation.openModulesDock()
    }
}

/// Sheet of modules the signed-in account actually has installed. Opens `/module/:id`.
/// Generic host: only catalogue metadata (name, publisher, kind, icon) — never a module's own UI.
struct InstalledModulesPanel: View {
    /// Set when hosted by the spatial Modules Dock instead of a system sheet.
    var dockState: SpatialDockState? = nil
    var onClose: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var filter: InstalledModulesFilter = .all
    @AppStorage(ModulesDockPrefs.sortKey) private var sortRaw = ModulesDockSort.standard.rawValue
    @AppStorage(ModulesDockPrefs.pinnedKey) private var pinnedRaw = ""
    @AppStorage(ModulesDockPrefs.orderKey) private var orderRaw = ""
    @AppStorage(ModulesDockPrefs.foldersKey) private var foldersRaw = ""
    @State private var newFolderFor: String?
    @State private var newFolderName = ""
    private var folders: [ModulesDockFolder] { ModulesDockPrefs.decodeFolders(foldersRaw) }
    /// Drag-to-arrange only where the order on screen is the custom order.
    private var canArrange: Bool {
        !isHalfDock && sort == .standard && query.isEmpty && {
            if case .folder = filter { return true }
            return filter == .all
        }()
    }
    @FocusState private var searchFocused: Bool

    private var isHalfDock: Bool { dockState == .half }
    private var pinned: [String] { ModulesDockPrefs.decode(pinnedRaw) }
    private var sort: ModulesDockSort { ModulesDockSort(rawValue: sortRaw) ?? .standard }

    private func closePanel() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var installed: [CatalogueProduct] {
        app.catalogue.products.filter { app.catalogue.installedIDs.contains($0.moduleId) }
    }

    /// Chips only for facets the data actually has (no empty "Favorites").
    private var filters: [InstalledModulesFilter] {
        let all = installed
        var chips: [InstalledModulesFilter] = [.all]
        let ids = Set(all.map(\.moduleId))
        if ProductHubRecents.load().contains(where: ids.contains) { chips.append(.recent) }
        if all.contains(where: { app.catalogue.installations[$0.moduleId]?.status == "updateAvailable" }) {
            chips.append(.updates)
        }
        let kinds = Array(Set(all.map(\.productKind))).sorted()
        if kinds.count > 1 { chips.append(contentsOf: kinds.map { .kind($0) }) }
        // Folders that hold at least one installed module.
        for folder in folders where folder.moduleIDs.contains(where: ids.contains) {
            chips.append(.folder(id: folder.id, name: folder.name))
        }
        return chips
    }

    private var shown: [CatalogueProduct] {
        var list = installed
        switch filter {
        case .all:
            break
        case .recent:
            let order = ProductHubRecents.load()
            list = order.compactMap { id in list.first { $0.moduleId == id } }
        case .updates:
            list = list.filter { app.catalogue.installations[$0.moduleId]?.status == "updateAvailable" }
        case .kind(let kind):
            list = list.filter { $0.productKind == kind }
        case .folder(let id, _):
            let members = folders.first { $0.id == id }?.moduleIDs ?? []
            list = list.filter { members.contains($0.moduleId) }
        }
        if filter != .recent {
            switch sort {
            case .standard:
                let order = ModulesDockPrefs.decode(orderRaw)
                if !order.isEmpty { list = ModulesDockPrefs.pinnedFirst(list, pins: order, id: \.moduleId) }
            case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .recent:
                let order = ProductHubRecents.load()
                list.sort { (order.firstIndex(of: $0.moduleId) ?? .max) < (order.firstIndex(of: $1.moduleId) ?? .max) }
            }
        }
        // Pinned first, in the order they were pinned (Move earlier/later rearranges).
        let pins = pinned
        if !pins.isEmpty {
            list = ModulesDockPrefs.pinnedFirst(list, pins: pins, id: \.moduleId)
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHalfDock {
            // Half detent: favourites (pinned) + recently used only; drag up for everything.
            let recents = Set(ProductHubRecents.load())
            let quick = list.filter { pins.contains($0.moduleId) || recents.contains($0.moduleId) }
            return Array((quick.isEmpty ? list : quick).prefix(8))
        }
        guard !needle.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.publisherName.localizedCaseInsensitiveContains(needle)
        }
    }

    private func togglePin(_ id: String) {
        var pins = pinned
        if let index = pins.firstIndex(of: id) { pins.remove(at: index) } else { pins.append(id) }
        pinnedRaw = ModulesDockPrefs.encode(pins)
        HapticEngine.shared.play(.selection)
    }

    /// Drop `dragged` onto `target`: it takes the target's place in the custom order.
    private func arrange(_ dragged: String, onto target: String) {
        guard dragged != target else { return }
        let visible = shown.map(\.moduleId)
        var order = ModulesDockPrefs.decode(orderRaw).filter { !visible.contains($0) }
        var ids = visible
        guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(dragged, at: to)
        order = ids + order
        orderRaw = ModulesDockPrefs.encode(order)
        // Pins keep their own order but follow a drag between pinned modules.
        let pins = pinned
        if pins.contains(dragged), pins.contains(target) {
            pinnedRaw = ModulesDockPrefs.encode(ids.filter(pins.contains))
        }
        HapticEngine.shared.play(.selection)
    }

    private func addToFolder(_ moduleID: String, folderID: String) {
        var all = folders
        guard let index = all.firstIndex(where: { $0.id == folderID }) else { return }
        if !all[index].moduleIDs.contains(moduleID) { all[index].moduleIDs.append(moduleID) }
        foldersRaw = ModulesDockPrefs.encodeFolders(all)
        HapticEngine.shared.play(.selection)
    }

    private func removeFromFolder(_ moduleID: String, folderID: String) {
        var all = folders
        guard let index = all.firstIndex(where: { $0.id == folderID }) else { return }
        all[index].moduleIDs.removeAll { $0 == moduleID }
        if all[index].moduleIDs.isEmpty { all.remove(at: index) }
        foldersRaw = ModulesDockPrefs.encodeFolders(all)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let moduleID = newFolderFor, !name.isEmpty else { return }
        var all = folders
        all.append(ModulesDockFolder(id: UUID().uuidString, name: String(name.prefix(30)), moduleIDs: [moduleID]))
        foldersRaw = ModulesDockPrefs.encodeFolders(all)
        newFolderFor = nil
        newFolderName = ""
        HapticEngine.shared.play(.success)
    }

    private func movePin(_ id: String, by delta: Int) {
        pinnedRaw = ModulesDockPrefs.encode(ModulesDockPrefs.move(pinned, id: id, by: delta))
        HapticEngine.shared.play(.selection)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !isHalfDock {
                        searchField
                        if app.auth.isSignedIn, installed.count > 0 { chipRow }
                    }
                    content
                    if !isHalfDock { exploreBanner }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { closePanel() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                if !isHalfDock {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Sort", selection: $sortRaw) {
                                ForEach(ModulesDockSort.allCases, id: \.rawValue) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Sort modules")
                        .accessibilityIdentifier("accessory.modules.sort")
                    }
                }
            }
            .toolbar(dockState == nil ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .task { await app.catalogue.load() }
            .onChange(of: filters) { _, chips in
                if !chips.contains(filter) { filter = .all }
            }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
        .modulaGlassPresentation()
        .alert("New Folder", isPresented: Binding(get: { newFolderFor != nil }, set: { if !$0 { newFolderFor = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Create", action: createFolder)
            Button("Cancel", role: .cancel) { newFolderFor = nil; newFolderName = "" }
        }
        .accessibilityIdentifier("accessory.modules.panel")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modules")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if dockState != nil {
                Button { closePanel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Modules Dock")
                .accessibilityIdentifier("spatial.dock.close")
            }
            Button {
                openHub()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .modulaGlass(in: Circle(), interactive: true, tint: Color(red: 0.93, green: 0.30, blue: 0.34), prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get more modules")
            .accessibilityIdentifier("accessory.modules.hub")
        }
    }

    private var subtitle: String {
        guard app.auth.isSignedIn else { return "Your installed modules, one tap away." }
        switch installed.count {
        case 0: return "Nothing installed yet."
        case 1: return "1 installed module"
        default: return "\(installed.count) installed modules"
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your modules", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .modulaGlass(in: Capsule(), interactive: true)
        .accessibilityIdentifier("accessory.modules.search")
    }

    private var chipRow: some View {
        ModulaSegmentedControl(segments: filters.map { .init(id: $0, title: $0.title) },
                               selection: $filter, accessibilityLabel: "Installed filter",
                               identifier: { "accessory.installed.filter.\($0.title)" })
            .modulaEdgeToEdgeRail()
    }

    @ViewBuilder
    private var content: some View {
        // Computed once per render (it reads recents from disk and sorts); it was evaluated
        // three times per body before.
        let shown = self.shown
        let installed = self.installed
        if let error = app.catalogue.error, installed.isEmpty {
            ModulaErrorState(message: error) {
                Task { await app.catalogue.load() }
            }
        } else if !app.auth.isSignedIn {
            ModulaEmptyState(
                title: "Sign in to see modules",
                message: "Installed Product Hub modules appear here for your account.",
                symbol: "shippingbox"
            )
        } else if installed.isEmpty, app.catalogue.loaded {
            ModulaEmptyState(
                title: "No modules installed",
                message: "Install something from Product Hub and it will show up here.",
                symbol: "shippingbox"
            )
        } else if installed.isEmpty {
            ProgressView("Loading modules…")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if shown.isEmpty {
            Text("No modules match “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4), spacing: 18) {
                ForEach(shown) { product in
                    Button {
                        closePanel()
                        app.navigation.open(.module(product.moduleId, localPath: nil))
                        HapticEngine.shared.play(.navigation)
                    } label: {
                        VStack(spacing: 6) {
                            ProductArtwork(product: product, size: 58)
                                .overlay(alignment: .topTrailing) {
                                    if app.catalogue.installations[product.moduleId]?.status == "updateAvailable" {
                                        Circle().fill(app.appearance.liveAccent)
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                                            .offset(x: 3, y: -3)
                                            .accessibilityHidden(true)
                                    }
                                }
                            Text(product.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                    .accessibilityLabel(product.name)
                    .accessibilityHint("Opens \(product.name)")
                    .accessibilityIdentifier("accessory.module.\(product.moduleId)")
                    // Long-press: pin / arrange, with a card preview (registry metadata only).
                    .contextMenu {
                        let isPinned = pinned.contains(product.moduleId)
                        Button(isPinned ? "Unpin from Dock" : "Pin to Dock",
                               systemImage: isPinned ? "pin.slash" : "pin") { togglePin(product.moduleId) }
                        if isPinned {
                            Button("Move Earlier", systemImage: "arrow.left") { movePin(product.moduleId, by: -1) }
                            Button("Move Later", systemImage: "arrow.right") { movePin(product.moduleId, by: 1) }
                        }
                        Menu("Add to Folder", systemImage: "folder.badge.plus") {
                            ForEach(folders) { folder in
                                Button(folder.name) { addToFolder(product.moduleId, folderID: folder.id) }
                            }
                            Button("New Folder…", systemImage: "plus") { newFolderFor = product.moduleId }
                        }
                        if case .folder(let id, let name) = filter {
                            Button("Remove from \(name)", systemImage: "folder.badge.minus") {
                                removeFromFolder(product.moduleId, folderID: id)
                            }
                        }
                        Button("Open", systemImage: "arrow.up.forward.app") {
                            closePanel()
                            app.navigation.open(.module(product.moduleId, localPath: nil))
                        }
                    } preview: {
                        HStack(spacing: 12) {
                            ProductArtwork(product: product, size: 58)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name).font(.headline)
                                Text(product.publisherName).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(width: 280, alignment: .leading)
                    }
                    // Expanded launcher: drag a module onto another to arrange (persisted order).
                    .draggable(product.moduleId) {
                        ProductArtwork(product: product, size: 58)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard canArrange, let dragged = items.first else { return false }
                        withAnimation(.snappy(duration: 0.22)) { arrange(dragged, onto: product.moduleId) }
                        return true
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var exploreBanner: some View {
        let accent = app.appearance.liveAccent
        return Button(action: openHub) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore Modules")
                        .font(.headline)
                    Text("Find new modules and games in Product Hub.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [accent.opacity(0.16), accent.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
        .accessibilityIdentifier("accessory.modules.explore")
    }

    private func openHub() {
        closePanel()
        app.navigation.open(.productHub(.featured))
        HapticEngine.shared.play(.navigation)
    }
}

/// A user folder in the Modules Dock: a name and registry module IDs (no module special cases).
struct ModulesDockFolder: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var moduleIDs: [String]
}

/// Modules Dock sort order (expanded detent).
enum ModulesDockSort: String, CaseIterable {
    case standard, name, recent
    var title: String {
        switch self {
        case .standard: return "Default"
        case .name: return "Name"
        case .recent: return "Recently Used"
        }
    }
}

/// Pinned dock modules: an ordered list of registry module IDs (no module special cases).
enum ModulesDockPrefs {
    static let pinnedKey = "modules.dock.pinned.v1"
    static let sortKey = "modules.dock.sort.v1"
    static let orderKey = "modules.dock.order.v1"
    static let foldersKey = "modules.dock.folders.v1"

    static func decodeFolders(_ raw: String) -> [ModulesDockFolder] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let folders = try? JSONDecoder().decode([ModulesDockFolder].self, from: data) else { return [] }
        return folders
    }

    static func encodeFolders(_ folders: [ModulesDockFolder]) -> String {
        guard let data = try? JSONEncoder().encode(folders) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func encode(_ ids: [String]) -> String {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    static func move(_ ids: [String], id: String, by delta: Int) -> [String] {
        guard let index = ids.firstIndex(of: id) else { return ids }
        let target = min(max(index + delta, 0), ids.count - 1)
        guard target != index else { return ids }
        var copy = ids
        copy.remove(at: index)
        copy.insert(id, at: target)
        return copy
    }

    static func pinnedFirst<T>(_ items: [T], pins: [String], id: (T) -> String) -> [T] {
        let rank = Dictionary(pins.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let head = items.filter { rank[id($0)] != nil }.sorted { (rank[id($0)] ?? 0) < (rank[id($1)] ?? 0) }
        let tail = items.filter { rank[id($0)] == nil }
        return head + tail
    }
}

enum InstalledModulesFilter: Hashable {
    case all, recent, updates, kind(String)
    case folder(id: String, name: String)

    var title: String {
        switch self {
        case .all: return "All"
        case .recent: return "Recent"
        case .updates: return "Updates"
        case .folder(_, let name):
            return name
        case .kind(let kind):
            if kind == "module" { return "Modules" }
            if kind == "game" { return "Games" }
            return kind.prefix(1).uppercased() + String(kind.dropFirst())
        }
    }
}

/// Compatibility alias — prefer `ShellAccessoryHost`.
typealias ModulaTabAccessory = ShellAccessoryHost
