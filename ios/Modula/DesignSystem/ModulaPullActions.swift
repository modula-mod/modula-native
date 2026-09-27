import SwiftUI

/// Directional pull-to-refresh: center refreshes, slide left opens Command Center, slide right opens Search.
enum ModulaPullDestination: String, CaseIterable, Equatable, Sendable {
    case command
    case refresh
    case search

    var title: String {
        switch self {
        case .command: "Command"
        case .refresh: "Refresh"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .command: "sparkles"
        case .refresh: "arrow.clockwise"
        case .search: "magnifyingglass"
        }
    }

    static func resolve(horizontal: CGFloat, sideThreshold: CGFloat = 88) -> Self {
        if horizontal <= -sideThreshold { return .command }
        if horizontal >= sideThreshold { return .search }
        return .refresh
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
        .offset(y: liftsAboveContent ? (-40 + (reduceMotion ? 0 : (1 - settle) * 14)) : 8)
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
        case .refresh: 0.1
        case .search: 0.2
        }
        return min(max((settle - delay) / max(1 - delay, 0.01), 0), 1)
    }
}

struct ModulaPullActionsModifier: ViewModifier {
    var onRefresh: () async -> Void
    var onCommand: () -> Void
    var onSearch: () -> Void
    var liftsAboveContent = true

    @State private var pull: CGFloat = 0
    @State private var horizontal: CGFloat = 0
    @State private var armed = false
    @State private var destination: ModulaPullDestination = .refresh
    @State private var refreshing = false
    @State private var atTop = true
    @State private var interacting = false

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
            .overlay(alignment: .top) {
                if pull >= revealDistance || refreshing {
                    ModulaPullActionsChooser(
                        destination: destination,
                        refreshing: refreshing,
                        progress: refreshing ? 1 : min(max((pull - revealDistance) / max(armDistance - revealDistance, 1), 0), 1),
                        liftsAboveContent: liftsAboveContent
                    )
                }
            }
            .accessibilityAction(named: "Refresh") {
                Task { await runRefresh() }
            }
            .accessibilityAction(named: "Command Center") { onCommand() }
            .accessibilityAction(named: "Search") { onSearch() }
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
                app.navigation.presented = .commandCenter
            },
            onSearch: {
                app.navigation.open(.search(.root(nil)))
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
        liftsAboveContent: Bool = true
    ) -> some View {
        modifier(ModulaPullActionsModifier(
            onRefresh: onRefresh,
            onCommand: onCommand,
            onSearch: onSearch,
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
        self
    }
}
