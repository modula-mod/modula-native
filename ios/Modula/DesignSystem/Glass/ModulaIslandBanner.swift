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
