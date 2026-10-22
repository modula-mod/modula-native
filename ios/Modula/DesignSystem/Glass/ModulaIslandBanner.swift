import SwiftUI
import UIKit

// MARK: - Island-morph shell banner
//
// Single presenter for `NavigationCoordinator.banner` / `flash(...)`.
// Client-only gooey morph: black island material drips downward from a
// Dynamic Island–sized seed (or notch/status fallback), stays visually
// connected via a metaball neck, then collapses back. No ActivityKit.
//
// Technique: explicit dual-circle metaball Bézier bridges (crisp black
// silhouette matching banking-app drip refs). Canvas blur+threshold was too
// soft / detached on device. Reduce Motion: fade the settled toast only.

struct ModulaIslandBannerHost: View {
    var banner: ModulaBanner?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var displayed: ModulaBanner?
    /// 0 = island seed only · 1 = fully expanded toast hanging under the island.
    @State private var morph: CGFloat = 0
    @State private var calmVisible = false
    @State private var dismissGeneration = 0

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        GeometryReader { geo in
            let metrics = IslandBannerMetrics.resolve(
                safeAreaTop: geo.safeAreaInsets.top,
                containerWidth: geo.size.width
            )
            ZStack(alignment: .top) {
                if let displayed {
                    Group {
                        if calm {
                            calmToast(displayed, metrics: metrics, containerWidth: geo.size.width)
                        } else {
                            IslandGooeyToast(
                                banner: displayed,
                                metrics: metrics,
                                containerWidth: geo.size.width,
                                morph: morph
                            )
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("shell.islandBanner")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Ephemeral confirmations must never steal Edge Picker / tab / feed hits.
        .allowsHitTesting(false)
        .onAppear { sync(to: banner) }
        .onChange(of: banner?.id) { _, _ in sync(to: banner) }
    }

    @ViewBuilder
    private func calmToast(
        _ banner: ModulaBanner,
        metrics: IslandBannerMetrics,
        containerWidth: CGFloat
    ) -> some View {
        let settled = IslandGooeyLayout.resolve(metrics: metrics, morph: 1, containerWidth: containerWidth)
        ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.black)
                .frame(width: settled.bodyWidth, height: settled.bodyHeight)
                .padding(.top, settled.contentTop)
            labelRow(banner)
                .frame(width: settled.bodyWidth, height: settled.bodyHeight)
                .padding(.top, settled.contentTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, metrics.topPadding)
        .opacity(calmVisible ? 1 : 0)
        .ignoresSafeArea(edges: .top)
    }

    private func labelRow(_ banner: ModulaBanner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.symbol)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(banner.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
    }

    private func sync(to next: ModulaBanner?) {
        dismissGeneration += 1
        let generation = dismissGeneration

        if let next {
            let swapping = displayed != nil && displayed?.id != next.id
            displayed = next
            if calm {
                calmVisible = false
                withAnimation(.easeOut(duration: 0.16)) { calmVisible = true }
                return
            }
            if swapping, morph > 0.85 {
                // Already morph-expanded: soft content swap, no re-collapse.
                return
            }
            morph = 0
            withAnimation(expandAnimation) { morph = 1 }
            return
        }

        // Dismiss: collapse into the seed, then drop the view.
        guard displayed != nil else { return }
        if calm {
            withAnimation(.easeOut(duration: 0.14)) { calmVisible = false }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                guard generation == dismissGeneration, banner == nil else { return }
                displayed = nil
            }
            return
        }
        withAnimation(collapseAnimation) { morph = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard generation == dismissGeneration, banner == nil else { return }
            displayed = nil
        }
    }

    private var expandAnimation: Animation {
        // Slightly slower spring so the mid-morph drip reads clearly on device.
        ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.62, dampingFraction: 0.78)
    }

    private var collapseAnimation: Animation {
        ModulaMotion.animation(.dismissal, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.44, dampingFraction: 0.90)
    }
}

// MARK: - Animatable gooey toast (per-frame path + label)

private struct IslandGooeyToast: View, @MainActor Animatable {
    var banner: ModulaBanner
    var metrics: IslandBannerMetrics
    var containerWidth: CGFloat
    var morph: CGFloat

    var animatableData: CGFloat {
        get { morph }
        set { morph = newValue }
    }

    var body: some View {
        let layout = IslandGooeyLayout.resolve(
            metrics: metrics,
            morph: morph,
            containerWidth: containerWidth
        )
        let labelOpacity = Double(smoothstep(0.62, 0.90, morph))

        ZStack(alignment: .top) {
            IslandGooeyCanvas(layout: layout, fill: .black)
                .frame(width: containerWidth, height: layout.canvasHeight)

            HStack(spacing: 8) {
                Image(systemName: banner.symbol)
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(banner.message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(width: layout.bodyWidth, height: layout.bodyHeight)
            .opacity(layout.bodyVisible ? labelOpacity : 0)
            .padding(.top, layout.contentTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, metrics.topPadding)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Crisp metaball silhouette

struct IslandGooeyCanvas: View {
    var layout: IslandGooeyLayout
    var fill: Color = .black

    var body: some View {
        IslandMetaballShape(layout: layout)
            .fill(fill)
            .allowsHitTesting(false)
    }
}

/// Island capsule + drip circle + toast body, fused with classic 2-circle metaball bridges.
struct IslandMetaballShape: Shape {
    var layout: IslandGooeyLayout

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(Capsule(style: .continuous).path(in: layout.islandRect))

        if layout.dripVisible {
            path.addEllipse(in: layout.dripRect)
            if let bridge = MetaballBridge.path(
                c1: CGPoint(x: layout.islandRect.midX, y: layout.islandRect.maxY - layout.islandRect.height * 0.28),
                r1: layout.islandRect.height * 0.42,
                c2: CGPoint(x: layout.dripRect.midX, y: layout.dripRect.midY),
                r2: layout.dripRect.width * 0.5
            ) {
                path.addPath(bridge)
            }
        }

        if layout.bodyVisible {
            path.addPath(Capsule(style: .continuous).path(in: layout.bodyRect))
            // Prefer drip→body neck while the drip is mid-flight; otherwise island→body.
            if layout.dripVisible {
                if let bridge = MetaballBridge.path(
                    c1: CGPoint(x: layout.dripRect.midX, y: layout.dripRect.midY),
                    r1: layout.dripRect.width * 0.5,
                    c2: CGPoint(x: layout.bodyRect.midX, y: layout.bodyRect.minY + layout.bodyRect.height * 0.35),
                    r2: min(layout.bodyRect.height * 0.48, layout.bodyRect.width * 0.22)
                ) {
                    path.addPath(bridge)
                }
            } else if let bridge = MetaballBridge.path(
                c1: CGPoint(x: layout.islandRect.midX, y: layout.islandRect.maxY - layout.islandRect.height * 0.2),
                r1: layout.islandRect.height * 0.45,
                c2: CGPoint(x: layout.bodyRect.midX, y: layout.bodyRect.minY + layout.bodyRect.height * 0.28),
                r2: min(layout.bodyRect.height * 0.5, layout.bodyRect.width * 0.2)
            ) {
                path.addPath(bridge)
            }
            // Explicit neck blob keeps a concave fillet when the body is wide.
            if layout.neckVisible {
                path.addEllipse(in: layout.neckRect)
            }
        }

        return path
    }
}

/// Classic 2-circle metaball bridge (Tobias Ahlin / Paper.js-style handles).
enum MetaballBridge {
    static func path(
        c1: CGPoint,
        r1: CGFloat,
        c2: CGPoint,
        r2: CGFloat,
        handleSize: CGFloat = 2.35,
        v: CGFloat = 0.5
    ) -> Path? {
        let dx = c2.x - c1.x
        let dy = c2.y - c1.y
        let d = hypot(dx, dy)
        guard r1 > 0.5, r2 > 0.5, d > 0.5 else { return nil }

        let maxDist = r1 + r2 * 2.35
        guard d < maxDist, d > abs(r1 - r2) else { return nil }

        let u1: CGFloat
        let u2: CGFloat
        if d < r1 + r2 {
            u1 = acos(clampedCos(((r1 * r1) + (d * d) - (r2 * r2)) / (2 * r1 * d)))
            u2 = acos(clampedCos(((r2 * r2) + (d * d) - (r1 * r1)) / (2 * r2 * d)))
        } else {
            u1 = 0
            u2 = 0
        }

        let angleBetween = atan2(dy, dx)
        let maxSpread = acos(clampedCos((r1 - r2) / d))
        let angle1 = angleBetween + u1 + (maxSpread - u1) * v
        let angle2 = angleBetween - u1 - (maxSpread - u1) * v
        let angle3 = angleBetween + .pi - u2 - (.pi - u2) * v
        let angle4 = angleBetween - .pi + u2 + (.pi - u2) * v

        let p1 = point(on: c1, radius: r1, angle: angle1)
        let p2 = point(on: c1, radius: r1, angle: angle2)
        let p3 = point(on: c2, radius: r2, angle: angle3)
        let p4 = point(on: c2, radius: r2, angle: angle4)

        let totalRadius = r1 + r2
        let d2Base = min(v * handleSize, hypot(p1.x - p3.x, p1.y - p3.y) / totalRadius)
        let d2 = d2Base * min(1, (d * 2) / totalRadius)

        let h1 = r1 * d2
        let h2 = r2 * d2
        let leftAngle = atan2(p1.y - p4.y, p1.x - p4.x)
        let rightAngle = atan2(p2.y - p3.y, p2.x - p3.x)

        let hp1 = point(on: p1, radius: h1, angle: leftAngle + .pi / 2)
        let hp2 = point(on: p2, radius: h1, angle: rightAngle - .pi / 2)
        let hp3 = point(on: p3, radius: h2, angle: rightAngle - .pi / 2)
        let hp4 = point(on: p4, radius: h2, angle: leftAngle + .pi / 2)

        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: hp1, control2: hp3)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: hp4, control2: hp2)
        path.closeSubpath()
        return path
    }

    private static func point(on center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private static func clampedCos(_ value: CGFloat) -> CGFloat {
        min(1, max(-1, value))
    }
}

// MARK: - Layout / progress → geometry

struct IslandGooeyLayout: Equatable {
    var canvasHeight: CGFloat
    var islandRect: CGRect
    var dripRect: CGRect
    var bodyRect: CGRect
    var neckRect: CGRect
    var dripVisible: Bool
    var bodyVisible: Bool
    var neckVisible: Bool
    /// Top inset for label row (matches body capsule).
    var contentTop: CGFloat
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat

    /// Mid-morph drip should protrude below the island while still overlapping it.
    var isConnectedDrip: Bool {
        dripVisible && dripRect.maxY > islandRect.maxY && dripRect.minY < islandRect.maxY + 8
    }

    static func resolve(
        metrics: IslandBannerMetrics,
        morph: CGFloat,
        containerWidth: CGFloat
    ) -> Self {
        let t = morph.clamped(to: 0...1)
        let islandW = metrics.seedWidth
        let islandH = metrics.seedHeight
        let islandX = (containerWidth - islandW) / 2
        let islandRect = CGRect(x: islandX, y: 0, width: islandW, height: islandH)

        // Early phase: thick teardrop drip from island bottom-center (banking refs).
        let dripPhase = smoothstep(0.0, 0.42, t)
        let dripDiameter = lerp(12, min(islandW * 0.48, 52), dripPhase)
        let dripTravel = lerp(0, islandH * 0.85 + 18, dripPhase)
        let dripCenterY = islandRect.maxY - dripDiameter * 0.35 + dripTravel
        let dripRect = CGRect(
            x: containerWidth / 2 - dripDiameter / 2,
            y: dripCenterY - dripDiameter / 2,
            width: dripDiameter,
            height: dripDiameter
        )

        // Later phase: toast body grows from the drip while a neck stays attached.
        let bodyPhase = smoothstep(0.28, 1.0, t)
        let bodyW = lerp(max(dripDiameter * 1.05, 36), metrics.expandedWidth, bodyPhase)
        let bodyH = lerp(max(dripDiameter * 0.95, 28), metrics.expandedHeight, bodyPhase)
        // Short overlap under the island so the metaball neck stays concave, not a T-junction.
        let neckGap = lerp(-2, 4, bodyPhase)
        let bodyY = islandRect.maxY + neckGap + lerp(0, dripTravel * 0.35, 1 - bodyPhase)
        let bodyYSettled = islandRect.maxY + 5
        let bodyRect = CGRect(
            x: (containerWidth - bodyW) / 2,
            y: lerp(bodyY, bodyYSettled, bodyPhase),
            width: bodyW,
            height: bodyH
        )

        let neckW = lerp(dripDiameter * 0.55, min(36, bodyW * 0.22), bodyPhase)
        let neckH = lerp(dripDiameter * 0.45, 18, bodyPhase)
        let neckRect = CGRect(
            x: containerWidth / 2 - neckW / 2,
            y: islandRect.maxY - neckH * 0.35,
            width: neckW,
            height: neckH + 6
        )

        let dripVisible = t > 0.02 && t < 0.88
        let bodyVisible = t > 0.22
        let neckVisible = t > 0.12 && t < 0.98

        let canvasHeight = max(
            islandRect.maxY,
            bodyVisible ? bodyRect.maxY : dripRect.maxY,
            neckVisible ? neckRect.maxY : 0
        ) + 16

        return Self(
            canvasHeight: canvasHeight,
            islandRect: islandRect,
            dripRect: dripRect,
            bodyRect: bodyRect,
            neckRect: neckRect,
            dripVisible: dripVisible,
            bodyVisible: bodyVisible,
            neckVisible: neckVisible,
            contentTop: bodyRect.minY,
            bodyWidth: bodyW,
            bodyHeight: bodyH
        )
    }
}

// MARK: Metrics

struct IslandBannerMetrics: Equatable {
    enum Style: Equatable { case island, notch, bar }

    var style: Style
    var seedWidth: CGFloat
    var seedHeight: CGFloat
    var expandedWidth: CGFloat
    var expandedHeight: CGFloat
    /// Distance from the absolute top of the screen to the seed’s top edge.
    var topPadding: CGFloat

    static func resolve(safeAreaTop: CGFloat, containerWidth: CGFloat) -> Self {
        let expandedWidth = min(max(containerWidth - 48, 160), 300)
        // Tall enough for icon + label; still reads as island material, not a card.
        let expandedHeight: CGFloat = 44

        // Dynamic Island devices (14 Pro → current Pros / island phones): top inset ≥ 59.
        if safeAreaTop >= 59 {
            return Self(
                style: .island,
                seedWidth: 126,
                seedHeight: 37,
                expandedWidth: expandedWidth,
                expandedHeight: expandedHeight,
                // Hardware island sits just under the top bezel (~11pt).
                topPadding: 11
            )
        }

        // Notch / tall status cutout: morph from a centered top capsule.
        if safeAreaTop >= 44 {
            return Self(
                style: .notch,
                seedWidth: 168,
                seedHeight: 30,
                expandedWidth: expandedWidth,
                expandedHeight: expandedHeight,
                topPadding: max(safeAreaTop - 34, 8)
            )
        }

        // Home-button / thin status bar: grow from a slim top-center bar.
        return Self(
            style: .bar,
            seedWidth: 72,
            seedHeight: 6,
            expandedWidth: expandedWidth,
            expandedHeight: expandedHeight,
            topPadding: max(safeAreaTop - 2, 6)
        )
    }
}

// MARK: - Math

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
    return t * t * (3 - 2 * t)
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Unified toast system (PR K)
//
// One presenter for every confirmation in the app. Glass pill that grows out of
// (just below) the Dynamic Island, never over the status bar. Duplicates
// coalesce (×N + bump + timer reset), only one is visible, the rest queue.

enum ModulaToastTone: Sendable {
    case success, info, warning, error

    var tint: Color {
        switch self {
        case .success: .green
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    /// Infer tone from the SF Symbol legacy `flash` callers pass.
    static func infer(symbol: String) -> ModulaToastTone {
        if symbol.contains("xmark.octagon") || symbol.contains("exclamationmark.octagon") { return .error }
        if symbol.contains("exclamationmark") || symbol.contains("slash") && symbol.contains("wifi") { return .warning }
        if symbol.contains("checkmark") || symbol.contains("fill") { return .success }
        return .info
    }
}

struct ModulaToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String
    var tone: ModulaToastTone
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
    var count = 1
    var bump = 0

    static func == (a: ModulaToast, b: ModulaToast) -> Bool {
        a.id == b.id && a.count == b.count && a.bump == b.bump && a.message == b.message
    }
}

@MainActor
@Observable
final class ModulaToastCenter {
    static let shared = ModulaToastCenter()

    private(set) var current: ModulaToast?
    private var queue: [ModulaToast] = []
    private var timer: Task<Void, Never>?
    private(set) var paused = false

    func show(_ message: String, symbol: String, tone: ModulaToastTone? = nil,
              actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        ModulaToastWindow.installIfNeeded()
        let resolvedTone = tone ?? ModulaToastTone.infer(symbol: symbol)
        if var shown = current, shown.message == message {
            shown.count += 1
            shown.bump += 1
            if let action { shown.action = action; shown.actionTitle = actionTitle }
            current = shown
            HapticEngine.shared.play(.selection)
            restartTimer()
            return
        }
        let toast = ModulaToast(message: message, symbol: symbol, tone: resolvedTone, actionTitle: actionTitle, action: action)
        if current != nil {
            if !queue.contains(where: { $0.message == message }) {
                queue.append(toast)
                if queue.count > 3 { queue.removeFirst() }
            }
            return
        }
        present(toast)
    }

    private func present(_ toast: ModulaToast) {
        current = toast
        AccessibilityNotification.Announcement(toast.actionTitle.map { "\(toast.message). \($0) available" } ?? toast.message).post()
        switch toast.tone {
        case .error, .warning: HapticEngine.shared.play(.lightImpact)
        default: HapticEngine.shared.play(.selection)
        }
        restartTimer()
    }

    private func restartTimer() {
        timer?.cancel()
        guard !paused, let toast = current else { return }
        let hold: Double = toast.action != nil ? 4.0 : 2.0
        let id = toast.id
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.dismiss()
        }
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value { timer?.cancel() } else { restartTimer() }
    }

    func dismiss() {
        timer?.cancel()
        current = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard self?.current == nil else { self?.queue.insert(next, at: 0); return }
            self?.present(next)
        }
    }

    func performAction() {
        current?.action?()
        dismiss()
    }
}

struct ModulaToastHost: View {
    @State private var center = ModulaToastCenter.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var drag: CGFloat = 0
    @State private var bumpScale: CGFloat = 1

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        GeometryReader { geo in
            let metrics = IslandBannerMetrics.resolve(safeAreaTop: geo.safeAreaInsets.top, containerWidth: geo.size.width)
            ZStack {
                if metrics.style == .island && !calm {
                    IslandToastPresenter(center: center, metrics: metrics, containerWidth: geo.size.width)
                } else {
                    glassHost(geo)
                }
                IslandSendLayer(size: geo.size, safeTop: geo.safeAreaInsets.top, calm: calm)
            }
        }
    }

    @ViewBuilder
    private func glassHost(_ geo: GeometryProxy) -> some View {
        Group {
            // Just below the island / notch, inside the safe area.
            let top = max(geo.safeAreaInsets.top, 20) + 4
            ZStack(alignment: .top) {
                if let toast = center.current {
                    pill(toast)
                        .id(toast.id)
                        .scaleEffect(bumpScale)
                        .offset(y: min(drag, 0))
                        .padding(.top, top)
                        .padding(.horizontal, 24)
                        .transition(calm
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.35, anchor: .top).combined(with: .offset(y: -top * 0.6)).combined(with: .opacity),
                                removal: .scale(scale: 0.5, anchor: .top).combined(with: .offset(y: -top * 0.6)).combined(with: .opacity)
                            ))
                        .gesture(swipe)
                        .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 30, pressing: { center.setPaused($0) }, perform: {})
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .animation(calm ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.78), value: center.current?.id)
            .onChange(of: center.current?.bump) { _, _ in
                guard !calm else { return }
                bumpScale = 1.06
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { bumpScale = 1 }
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                if value.translation.height < -16 || value.predictedEndTranslation.height < -40 {
                    center.dismiss()
                }
            }
    }

    private func pill(_ toast: ModulaToast) -> some View {
        HStack(spacing: 9) {
            Image(systemName: toast.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toast.tone.tint)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if toast.count > 1 {
                Text("×\(toast.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if let title = toast.actionTitle, toast.action != nil {
                Button(title) { center.performAction() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous).fill(Color(uiColor: .secondarySystemBackground))
            }
        }
        .modulaGlass(in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("shell.toast")
        .accessibilityAction(named: "Dismiss") { center.dismiss() }
    }
}


// MARK: - Island toast: emerges from and melts back into the Dynamic Island

/// Same metaball technique as Settings' Telegram avatar merge (`IslandAvatarMerge`):
/// black shapes drawn in a Canvas layer with blur + alpha threshold so the island
/// capsule and the growing toast body fuse with a gooey neck. Only used on Dynamic
/// Island devices with motion allowed; everything else uses the glass pill.
private struct IslandToastPresenter: View {
    var center: ModulaToastCenter
    var metrics: IslandBannerMetrics
    var containerWidth: CGFloat

    @State private var displayed: ModulaToast?
    @State private var morph: CGFloat = 0
    @State private var contentSize = CGSize(width: 200, height: 44)
    @State private var generation = 0
    @State private var bumpScale: CGFloat = 1
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        // Swiping up pulls the toast back toward the island.
        let pull = drag < 0 ? max(0, 1 + drag / 140) : 1
        let m = morph * pull
        ZStack(alignment: .top) {
            if let toast = displayed {
                IslandToastMorph(metrics: metrics, containerWidth: containerWidth,
                                 bodySize: contentSize, morph: m, bump: bumpScale)
                    .allowsHitTesting(false)
                content(toast)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
                    .opacity(Double(smoothstepToast(0.6, 0.92, m)))
                    .blur(radius: (1 - smoothstepToast(0.6, 0.95, m)) * 6)
                    .scaleEffect(bumpScale * (0.88 + 0.12 * smoothstepToast(0.5, 1, m)), anchor: .top)
                    .padding(.top, bodyTop(m))
                    .gesture(swipe)
                    .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 30, pressing: { center.setPaused($0) }, perform: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .onAppear { sync(center.current) }
        .onChange(of: center.current?.id) { _, _ in sync(center.current) }
        .onChange(of: center.current?.bump) { _, _ in
            if let c = center.current, c.id == displayed?.id { displayed = c }
            bumpScale = 1.05
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { bumpScale = 1 }
        }
    }

    /// Top of the toast body: tucked into the island at 0, hanging below it at 1.
    private func bodyTop(_ m: CGFloat) -> CGFloat {
        let islandBottom = metrics.topPadding + metrics.seedHeight
        return metrics.topPadding + (islandBottom + 8 - metrics.topPadding) * m
    }

    private func sync(_ next: ModulaToast?) {
        generation += 1
        let gen = generation
        if let next {
            if displayed != nil, morph > 0.85 {
                // Already open: swap content in place.
                withAnimation(.easeInOut(duration: 0.2)) { displayed = next }
                return
            }
            displayed = next
            morph = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) { morph = 1 }
            return
        }
        guard displayed != nil else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) { morph = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(460))
            guard gen == generation, center.current == nil else { return }
            displayed = nil
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                if value.translation.height < -16 || value.predictedEndTranslation.height < -40 {
                    // Continue from the pulled position so it keeps melting upward.
                    morph = max(0, 1 + value.translation.height / 140)
                    center.dismiss()
                }
            }
    }

    private func content(_ toast: ModulaToast) -> some View {
        HStack(spacing: 9) {
            Image(systemName: toast.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toast.tone.tint)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if toast.count > 1 {
                Text("×\(toast.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
            }
            if let title = toast.actionTitle, toast.action != nil {
                Button(title) { center.performAction() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 46)
        .frame(maxWidth: containerWidth - 32)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("shell.toast")
        .accessibilityAction(named: "Dismiss") { center.dismiss() }
    }
}

/// The black island + toast silhouette, fused with blur + alpha threshold.
private struct IslandToastMorph: View, @MainActor Animatable {
    var metrics: IslandBannerMetrics
    var containerWidth: CGFloat
    var bodySize: CGSize
    var morph: CGFloat
    var bump: CGFloat

    var animatableData: CGFloat {
        get { morph }
        set { morph = newValue }
    }

    var body: some View {
        let island = CGRect(x: (containerWidth - metrics.seedWidth) / 2, y: metrics.topPadding,
                            width: metrics.seedWidth, height: metrics.seedHeight)
        let m = max(0, morph)
        // Body starts as the island itself, then stretches down and widens into the toast.
        let stretch = smoothstepToast(0, 0.55, m)
        let widen = smoothstepToast(0.3, 1, m)
        let w = (island.width + (bodySize.width - island.width) * widen) * bump
        let h = island.height + (bodySize.height - island.height) * widen
        let top = island.minY + (island.maxY + 8 - island.minY) * m
        let body = CGRect(x: (containerWidth - w) / 2, y: top, width: w, height: h)
        // Neck blob sits in the gap so the two stay fused until the toast settles.
        let neckW = island.width * (0.55 - 0.25 * widen)
        let neckH = max(0, (body.minY - island.maxY) + 18) * (1 - smoothstepToast(0.85, 1, m) * 0.6)
        let neck = CGRect(x: (containerWidth - neckW) / 2, y: island.maxY - 12, width: neckW, height: neckH)
        Canvas { ctx, _ in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
            ctx.addFilter(.blur(radius: 6 + 4 * stretch * (1 - widen)))
            ctx.drawLayer { layer in
                layer.fill(Path(roundedRect: island, cornerRadius: island.height / 2), with: .color(.black))
                if m > 0.01 {
                    layer.fill(Path(roundedRect: body, cornerRadius: min(body.height, body.width) / 2), with: .color(.black))
                    if neckH > 0 { layer.fill(Path(ellipseIn: neck), with: .color(.black)) }
                }
            }
        }
        .frame(width: containerWidth, height: max(body.maxY + 30, island.maxY + 30))
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

private func smoothstepToast(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Passthrough overlay window so toasts sit above sheets and full-screen covers.
@MainActor
enum ModulaToastWindow {
    private static var window: UIWindow?

    static func installIfNeeded() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let w = PassthroughToastWindow(windowScene: scene)
        let host = UIHostingController(rootView: ModulaToastHost())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.isHidden = false
        window = w
    }
}

private final class PassthroughToastWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Only the pill itself takes touches; everything else falls through.
        return hit === rootViewController?.view ? nil : hit
    }
}


// MARK: - Send into the Dynamic Island (AirDrop-style)

/// Fire-and-forget visual for "sent": a floating card rises with an iridescent edge glow,
/// genie-squeezes into the Dynamic Island (top-centre pill without one), and a ripple
/// ring + accent flash mark the absorption. Purely decorative and non-blocking.
@MainActor @Observable
final class IslandSendEffect {
    static let shared = IslandSendEffect()
    private(set) var token = 0
    private(set) var title = "Sent"
    private(set) var symbol = "paperplane.fill"
    var accent: Color = .accentColor

    func fire(_ title: String = "Sent", symbol: String = "paperplane.fill", accent: Color? = nil) {
        ModulaToastWindow.installIfNeeded()
        self.title = title
        self.symbol = symbol
        if let accent { self.accent = accent }
        token &+= 1
        HapticEngine.shared.play(.lightImpact)
    }
}

struct IslandSendLayer: View {
    var size: CGSize
    var safeTop: CGFloat
    var calm: Bool
    @State private var effect = IslandSendEffect.shared
    @State private var start: Date?
    @State private var run = 0

    private let duration: Double = 1.2
    private var hasIsland: Bool { safeTop >= 58 }
    private var island: CGRect {
        let w: CGFloat = hasIsland ? 125 : 110, h: CGFloat = hasIsland ? 37 : 30
        let y = hasIsland ? max(safeTop - 48, 9) : max(safeTop, 20) + 4
        return CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
    }

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation) { ctx in
                    let t = min(1, ctx.date.timeIntervalSince(start) / (calm ? 0.45 : duration))
                    if calm { calmFrame(t) } else { frame(t, time: ctx.date.timeIntervalSince(start)) }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: effect.token) { _, _ in
            run &+= 1
            let mine = run
            start = Date()
            Task { @MainActor in
                if calm {
                    ModulaToastCenter.shared.show(effect.title, symbol: "checkmark.circle")
                    try? await Task.sleep(for: .milliseconds(480))
                } else {
                    try? await Task.sleep(for: .milliseconds(Int(duration * 0.82 * 1000)))
                    guard mine == run else { return }
                    HapticEngine.shared.play(.success)
                    try? await Task.sleep(for: .milliseconds(Int(duration * 0.2 * 1000)))
                }
                if mine == run { start = nil }
            }
        }
    }

    private func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    @ViewBuilder
    private func frame(_ t: Double, time: Double) -> some View {
        // 0–0.15 detach (scale into card) · 0.15–0.72 rise · 0.72–0.86 genie squeeze · 0.86–1 ripple.
        let detach = ease(clamp(t / 0.15))
        let rise = ease(clamp((t - 0.15) / 0.57))
        let squeeze = ease(clamp((t - 0.72) / 0.14))
        let ripple = clamp((t - 0.84) / 0.16)
        let startW = min(size.width - 48, 340), startH: CGFloat = 132
        let cardW = startW * (1 - 0.12 * detach) * (1 - 0.35 * rise)
        let cardH = startH * (1 - 0.12 * detach) * (1 - 0.35 * rise)
        let w = cardW + (island.width - cardW) * squeeze
        let h = cardH + (island.height - cardH) * squeeze
        let startY = size.height - 150
        let cy = startY + (island.midY + cardH * 0.35 - startY) * rise + (island.midY - (island.midY + cardH * 0.35)) * squeeze
        let radius = 26 + (h / 2 - 26) * squeeze
        let intensity = 0.25 + 0.75 * rise
        ZStack {
            if squeeze < 1 {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(squeeze > 0.4 ? AnyShapeStyle(Color.black) : AnyShapeStyle(.regularMaterial))
                    if squeeze < 0.5 {
                        HStack(spacing: 10) {
                            Image(systemName: effect.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(effect.accent)
                            Text(effect.title)
                                .font(.headline)
                        }
                        .opacity(1 - squeeze * 2)
                        .scaleEffect(1 - 0.3 * squeeze)
                    }
                    Rectangle()
                        .fill(.white)
                        .colorEffect(ShaderLibrary.islandSendGlow(.float2(w + 40, h + 40), .float(time), .float(intensity), .float(radius)))
                        .frame(width: w + 40, height: h + 40)
                        .blendMode(.plusLighter)
                        .opacity(1 - squeeze)
                }
                .frame(width: w, height: h)
                // Genie: the bottom pinches harder than the top as it is sucked upward.
                .scaleEffect(x: 1 - 0.25 * squeeze * (1 - squeeze) * 4, y: 1, anchor: .top)
                .shadow(color: effect.accent.opacity(0.35 * intensity), radius: 18)
                .position(x: size.width / 2, y: cy)
            }
            if ripple > 0 {
                Capsule(style: .continuous)
                    .strokeBorder(effect.accent.opacity(0.9 * (1 - ripple)), lineWidth: 2.5)
                    .frame(width: island.width + 70 * ripple, height: island.height + 40 * ripple)
                    .position(x: island.midX, y: island.midY)
                Capsule(style: .continuous)
                    .fill(effect.accent.opacity(0.55 * (1 - ripple)))
                    .frame(width: island.width, height: island.height)
                    .blur(radius: 6)
                    .position(x: island.midX, y: island.midY)
                    .blendMode(.plusLighter)
            }
        }
    }

    @ViewBuilder
    private func calmFrame(_ t: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: effect.symbol).foregroundStyle(effect.accent)
            Text(effect.title).font(.headline)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(1 - t)
        .position(x: size.width / 2, y: size.height - 150)
    }
}
