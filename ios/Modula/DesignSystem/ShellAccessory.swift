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
                    ShellAccessoryAction(id: "tools", title: "Tools", symbol: "slider.horizontal.3", enabled: true, accessibilityIdentifier: "accessory.tools")
                ],
                showsSearch: false,
                showsMore: false
            )
        case .discover:
            return Self(
                title: "Tools",
                symbol: "safari",
                actions: [
                    ShellAccessoryAction(id: "customise", title: "Customise", symbol: "slider.horizontal.3", enabled: true, accessibilityIdentifier: "accessory.customise"),
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
                .foregroundStyle(app.appearance.accent.color)
                .symbolEffect(.bounce, value: pulse)
                .frame(width: size, height: size)
                .modifier(ShellIntelligenceChatChrome(compact: compact, opaque: opaque))
                .modifier(ShellIntelligenceShimmer(isActive: !compact && !opaque))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Chat")
        .accessibilityHint("Opens on-device intelligence chat")
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
                                    .init(color: app.appearance.accent.color.opacity(0.55), location: 0.84),
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

/// Tools row + detached AI circle.
struct ShellAccessoryDock: View {
    let route: AppRoute
    var toolsChrome = true

    var body: some View {
        HStack(spacing: ShellIntelligenceChatMetrics.dockSpacing) {
            ShellAccessoryHost(route: route, nativeHosted: !toolsChrome)
                .frame(maxWidth: .infinity, minHeight: ShellIntelligenceChatMetrics.buttonSize)
            ShellIntelligenceChatButton()
        }
        .padding(.horizontal, 14)
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
                    TabAccessoryPlatterController(hidesExpandedPlatter: true)
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
        return HStack(spacing: 8) {
            Image(systemName: config.symbol)
            Text(config.title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(config.title)
        .accessibilityIdentifier("tab.accessory")
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
    }

    required init?(coder: NSCoder) { nil }

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

    func applySoon() {
        apply()
        DispatchQueue.main.async { [weak self] in self?.apply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.apply() }
    }

    func apply() {
        if shouldHidePlatter() {
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
            if let hosting, view === hosting {
                view.backgroundColor = .clear
                view.isOpaque = false
                outsideHosting = true
                current = view.superview
                continue
            }
            guard outsideHosting else {
                current = view.superview
                continue
            }
            view.backgroundColor = .clear
            view.isOpaque = false
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

    var body: some View {
        let config = ShellAccessoryConfiguration.configuration(
            for: route,
            activity: app.activity,
            signedIn: app.auth.isSignedIn
        )
        HStack(spacing: 8) {
            Image(systemName: config.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(app.appearance.accent.color)
                .frame(width: 24, height: 24)
                .background(app.appearance.accent.color.opacity(0.12), in: Circle())
                .symbolEffect(.bounce, value: config.symbol)
                .contentTransition(.symbolEffect(.replace))
            Text(config.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
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
                .accessibilityIdentifier("accessory.search")
            }
            if config.showsMore {
                moreMenu
            }
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
        .animation(.snappy(duration: 0.28), value: config.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tab.accessory")
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
                                .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
                        }
                        Text(tab.title)
                            .font(.caption2.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if selected {
                            Capsule()
                                .fill(app.appearance.accent.color.opacity(0.14))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, embedded ? 2 : 4)
        .padding(.vertical, embedded ? 2 : 3)
        .frame(maxWidth: 560)
        .modifier(TabBarChrome(embedded: embedded, opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency))
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global navigation")
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

/// Compatibility alias — prefer `ShellAccessoryHost`.
typealias ModulaTabAccessory = ShellAccessoryHost
