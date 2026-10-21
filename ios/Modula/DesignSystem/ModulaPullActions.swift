import SwiftUI
import UIKit

/// Directional pull-to-refresh: center refreshes, slide left opens Command Center, slide right opens Search, and a further slide right opens AI Mode.
enum ModulaPullDestination: String, CaseIterable, Equatable, Sendable {
    case command
    case refresh
    case search
    case ai

    var title: String {
        switch self {
        case .command: "Command"
        case .refresh: "Refresh"
        case .search: "Search"
        case .ai: "AI Mode"
        }
    }

    var symbol: String {
        switch self {
        case .command: "sparkles"
        case .refresh: "arrow.clockwise"
        case .search: "magnifyingglass"
        case .ai:
            UIImage(systemName: "pencil.and.scribble") == nil ? "square.and.pencil" : "pencil.and.scribble"
        }
    }

    static func resolve(horizontal: CGFloat, sideThreshold: CGFloat = 88, aiThreshold: CGFloat = 168) -> Self {
        if horizontal <= -sideThreshold { return .command }
        if horizontal >= aiThreshold { return .ai }
        if horizontal >= sideThreshold { return .search }
        return .refresh
    }
}

/// Live pull chrome so feed content can frost instead of leaving a dead void.
private struct ModulaPullProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct ModulaPullDistanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var modulaPullProgress: CGFloat {
        get { self[ModulaPullProgressKey.self] }
        set { self[ModulaPullProgressKey.self] = newValue }
    }

    var modulaPullDistance: CGFloat {
        get { self[ModulaPullDistanceKey.self] }
        set { self[ModulaPullDistanceKey.self] = newValue }
    }
}

struct ModulaPullActionsChooser: View {
    var destination: ModulaPullDestination
    var refreshing: Bool
    var progress: CGFloat = 1
    var liftsAboveContent = true

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var settle: CGFloat {
        let t = min(max(progress, refreshing ? 1 : 0), 1)
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let frost = reduceMotion ? 0 : (1 - settle) * 12
        HStack(spacing: 2) {
            ForEach(ModulaPullDestination.allCases, id: \.self) { item in
                slot(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            if !opaque {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .blur(radius: reduceMotion ? 0 : 14)
                    .opacity(0.35 + (0.45 * settle))
                    .padding(.horizontal, -12)
                    .padding(.vertical, -8)
            }
        }
        .modulaChrome(in: Capsule(), opaque: opaque)
        .shadow(color: .black.opacity((opaque ? 0.04 : 0.10) * settle), radius: 12, y: 6)
        .blur(radius: frost)
        .opacity(0.18 + (0.82 * settle))
        .scaleEffect(reduceMotion ? 1 : 0.90 + (0.10 * settle), anchor: .top)
        .padding(.horizontal, 20)
        // Sit on the frosted feed, just under the nav — never floating in a black hole.
        .offset(y: liftsAboveContent ? 16 : 12)
        .allowsHitTesting(false)
        .accessibilityIdentifier("pull.actions")
        .accessibilityLabel(destination.title)
    }

    private func slot(_ item: ModulaPullDestination) -> some View {
        let selected = destination == item
        let accent = app.appearance.accent.color
        let appear = slotAppear(item)
        return VStack(spacing: 2) {
            if refreshing, item == .refresh {
                ProgressView()
                    .controlSize(.regular)
                    .tint(accent)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: selected ? .semibold : .medium))
                    .symbolEffect(.bounce, value: selected)
            }
            Text(item.title)
                .font(.caption2.weight(selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(selected ? accent : .secondary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
            if selected {
                Capsule()
                    .fill(accent.opacity(0.14 * appear))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
        }
        .blur(radius: reduceMotion ? 0 : (1 - appear) * 7)
        .opacity(0.12 + (0.88 * appear))
        .accessibilityHidden(true)
        .accessibilityIdentifier("pull.actions.\(item.rawValue)")
    }

    private func slotAppear(_ item: ModulaPullDestination) -> CGFloat {
        let delay: CGFloat = switch item {
        case .command: 0
        case .refresh: 0.08
        case .search: 0.16
        case .ai: 0.24
        }
        return min(max((settle - delay) / max(1 - delay, 0.01), 0), 1)
    }
}

struct ModulaPullActionsModifier: ViewModifier {
    var onRefresh: () async -> Void
    var onCommand: () -> Void
    var onSearch: () -> Void
    var onAI: () -> Void
    var liftsAboveContent = true

    @State private var pull: CGFloat = 0
    @State private var horizontal: CGFloat = 0
    @State private var armed = false
    @State private var destination: ModulaPullDestination = .refresh
    @State private var refreshing = false
    @State private var atTop = true
    @State private var interacting = false
    @State private var anchorY: CGFloat = 0
    @State private var ownerID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var app

    private let revealDistance: CGFloat = 48
    private let armDistance: CGFloat = 108
    private let commitDistance: CGFloat = 96
    private let cancelDistance: CGFloat = 52
    private let sideThreshold: CGFloat = 88

    private var progress: CGFloat {
        refreshing ? 1 : min(max(pull / armDistance, 0), 1)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.modulaPullProgress, progress)
            .environment(\.modulaPullDistance, pull)
            .onScrollGeometryChange(for: PullMetrics.self) { geometry in
                let overscroll = -(geometry.contentOffset.y + geometry.contentInsets.top)
                return PullMetrics(
                    pull: max(0, overscroll),
                    atTop: geometry.contentOffset.y + geometry.contentInsets.top <= 4
                )
            } action: { _, metrics in
                atTop = metrics.atTop
                if refreshing { return }
                pull = metrics.pull
                if pull >= armDistance {
                    armed = true
                } else if interacting, armed, pull < cancelDistance {
                    cancelArm()
                }
            }
            .onScrollPhaseChange { _, phase in
                let touching = phase == .interacting || phase == .tracking
                interacting = touching
                guard !refreshing else { return }
                if !touching {
                    if armed, pull >= commitDistance {
                        commit()
                    } else if armed {
                        reset()
                    }
                }
            }
            .simultaneousGesture(directionGesture)
            .scrollClipDisabled()
            // The frost + chooser render at the app root (ModulaPullOverlayHost) so the blur
            // covers the whole screen — header, tab bar, Tools bar and edge rail included.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { if !ShellChromeFreeze.isSidebarDragging { anchorY = $0 } }
            .onChange(of: overlayState) { _, state in publish(state) }
            .onDisappear { ModulaPullOverlayCenter.shared.clear(owner: ownerID) }
            .accessibilityAction(named: "Refresh") {
                Task { await runRefresh() }
            }
            .accessibilityAction(named: "Command Center") { onCommand() }
            .accessibilityAction(named: "Search") { onSearch() }
            .accessibilityAction(named: "AI Mode") { onAI() }
    }

    private var overlayState: ModulaPullOverlayState? {
        guard progress > 0.05 || refreshing else { return nil }
        return ModulaPullOverlayState(
            progress: progress,
            chooserVisible: pull >= revealDistance || refreshing,
            chooserProgress: refreshing ? 1 : min(max((pull - revealDistance) / max(armDistance - revealDistance, 1), 0), 1),
            destination: destination,
            refreshing: refreshing,
            interacting: interacting,
            anchorY: anchorY,
            liftsAboveContent: liftsAboveContent
        )
    }

    private func publish(_ state: ModulaPullOverlayState?) {
        let center = ModulaPullOverlayCenter.shared
        if let state {
            center.show(state, owner: ownerID) { reset() }
        } else {
            center.clear(owner: ownerID)
        }
    }

    private var directionGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onChanged { value in
                guard !refreshing else { return }
                guard atTop || pull > 24 else { return }
                guard value.translation.height > 36 || pull > 40 else { return }
                horizontal = value.translation.width
                let next = ModulaPullDestination.resolve(horizontal: horizontal, sideThreshold: sideThreshold)
                if next != destination {
                    destination = next
                    HapticEngine.shared.play(.selection)
                }
            }
            .onEnded { _ in
                if !interacting, armed, pull >= commitDistance {
                    commit()
                } else if !interacting {
                    reset()
                }
            }
    }

    private func commit() {
        guard armed, !refreshing else {
            reset()
            return
        }
        armed = false
        let chosen = destination
        horizontal = 0
        switch chosen {
        case .refresh:
            Task { await runRefresh() }
        case .command:
            reset()
            HapticEngine.shared.play(.contextOpen)
            onCommand()
        case .search:
            reset()
            HapticEngine.shared.play(.navigation)
            onSearch()
        case .ai:
            reset()
            HapticEngine.shared.play(.contextOpen)
            onAI()
        }
    }

    private func runRefresh() async {
        refreshing = true
        destination = .refresh
        HapticEngine.shared.play(.confirmation)
        await onRefresh()
        refreshing = false
        reset()
    }

    private func cancelArm() {
        armed = false
        horizontal = 0
        destination = .refresh
    }

    private func reset() {
        cancelArm()
        if !refreshing {
            pull = 0
        }
    }
}

private struct PullMetrics: Equatable {
    var pull: CGFloat
    var atTop: Bool
}

struct ModulaShellPullActionsModifier: ViewModifier {
    var onRefresh: () async -> Void
    var liftsAboveContent = true
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        content.modulaPullActions(
            onRefresh: onRefresh,
            onCommand: {
                CommandPaletteCenter.shared.present()
            },
            onSearch: {
                app.navigation.open(.search(.root(nil)))
            },
            onAI: {
                PresentationCoordinator.present(.intelligenceChat, in: app.navigation)
            },
            liftsAboveContent: liftsAboveContent
        )
    }
}

extension View {
    func modulaPullActions(
        onRefresh: @escaping () async -> Void,
        onCommand: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onAI: @escaping () -> Void,
        liftsAboveContent: Bool = true
    ) -> some View {
        modifier(ModulaPullActionsModifier(
            onRefresh: onRefresh,
            onCommand: onCommand,
            onSearch: onSearch,
            onAI: onAI,
            liftsAboveContent: liftsAboveContent
        ))
    }

    func modulaShellPullActions(
        liftsAboveContent: Bool = true,
        onRefresh: @escaping () async -> Void
    ) -> some View {
        modifier(ModulaShellPullActionsModifier(onRefresh: onRefresh, liftsAboveContent: liftsAboveContent))
    }

    func modulaPullContentEffects() -> some View {
        modifier(ModulaPullContentEffectsModifier())
    }
}

/// Blurs and lifts the live feed into the overscroll so Command/Refresh/Search/AI sit on content, not a hole.
private struct ModulaPullContentEffectsModifier: ViewModifier {
    @Environment(\.modulaPullProgress) private var progress
    @Environment(\.modulaPullDistance) private var pull
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let t = min(max(progress, 0), 1)
        content
            .opacity(1 - t * 0.06)
            .scaleEffect(reduceMotion ? 1 : 1 - t * 0.02, anchor: .top)
            .offset(y: reduceMotion ? 0 : -min(pull * 0.68, 88))
    }
}

struct ModulaPullOverlayState: Equatable {
    var progress: CGFloat
    var chooserVisible: Bool
    var chooserProgress: CGFloat
    var destination: ModulaPullDestination
    var refreshing: Bool
    var interacting: Bool
    var anchorY: CGFloat
    var liftsAboveContent: Bool
}

/// Shared pull-menu state so the frost can live above the whole shell.
@MainActor @Observable
final class ModulaPullOverlayCenter {
    static let shared = ModulaPullOverlayCenter()
    private(set) var state: ModulaPullOverlayState?
    /// Set when the user taps outside during a refresh; hides the chrome until the pull cycle ends.
    private(set) var dismissed = false
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var onDismiss: (() -> Void)?

    func show(_ state: ModulaPullOverlayState, owner: UUID, onDismiss: @escaping () -> Void) {
        if self.owner != owner { dismissed = false }
        self.owner = owner
        self.onDismiss = onDismiss
        if self.state != state { self.state = state }
    }

    func clear(owner: UUID) {
        guard self.owner == owner else { return }
        state = nil
        dismissed = false
        self.owner = nil
        onDismiss = nil
    }

    func dismiss() {
        dismissed = true
        onDismiss?()
    }
}

/// Full-screen frost + pull chooser, mounted at the app root above all chrome.
struct ModulaPullOverlayHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var center = ModulaPullOverlayCenter.shared

    var body: some View {
        if let state = center.state, !center.dismissed {
            let p = min(max(state.progress, 0), 1)
            let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
            ZStack(alignment: .top) {
                Group {
                    if opaque {
                        // No translucency: a solid-ish dim instead of a blur.
                        Color.black.opacity((colorScheme == .dark ? 0.55 : 0.28) * p)
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                // Reduce Motion: no progressive ramp, just present.
                                .opacity(reduceMotion ? 0.9 : Double(min(0.2 + p * 0.75, 0.95)))
                            Color.black.opacity((colorScheme == .dark ? 0.22 : 0.08) * (reduceMotion ? 1 : p))
                        }
                    }
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // While the finger drives the pull, let touches reach the scroll view; once released
                // (e.g. refreshing) the frost is a tap-to-dismiss surface.
                .allowsHitTesting(!state.interacting)
                .onTapGesture { center.dismiss() }
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(.isButton)

                if state.chooserVisible {
                    ModulaPullActionsChooser(
                        destination: state.destination,
                        refreshing: state.refreshing,
                        progress: state.chooserProgress,
                        liftsAboveContent: state.liftsAboveContent
                    )
                    .padding(.top, max(state.anchorY, 0) + 6)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}
