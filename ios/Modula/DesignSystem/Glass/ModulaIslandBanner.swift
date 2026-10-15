import SwiftUI
import UIKit

// MARK: - Island-morph shell banner
//
// Single presenter for `NavigationCoordinator.banner` / `flash(...)`.
// Client-only gooey morph: a black metaball drip grows downward out of a
// Dynamic Island–sized seed (or notch/status fallback), stays visually
// connected, then collapses back. No ActivityKit — ephemeral confirmations
// should not own a Live Activity.
//
// Technique: SwiftUI `Canvas` with blur + `alphaThreshold` (classic metaball /
// SDF-blob look) driven by an animatable progress. Reduce Motion skips travel
// and fades the settled toast.

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
            try? await Task.sleep(for: .milliseconds(420))
            guard generation == dismissGeneration, banner == nil else { return }
            displayed = nil
        }
    }

    private var expandAnimation: Animation {
        ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.52, dampingFraction: 0.82)
    }

    private var collapseAnimation: Animation {
        ModulaMotion.animation(.dismissal, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.40, dampingFraction: 0.88)
    }
}

// MARK: - Animatable gooey toast (per-frame Canvas + label)

private struct IslandGooeyToast: View, Animatable {
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
        let labelOpacity = Double(smoothstep(0.58, 0.88, morph))

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

// MARK: - Gooey canvas (blur + alpha threshold metaball)

struct IslandGooeyCanvas: View {
    var layout: IslandGooeyLayout
    var fill: Color = .black

    var body: some View {
        Canvas { context, size in
            // Order: threshold after blur → overlapping soft blobs fuse into one
            // liquid mass (the drip fillets in the banking-app references).
            context.addFilter(.alphaThreshold(min: 0.42, color: fill))
            context.addFilter(.blur(radius: layout.blurRadius))

            context.drawLayer { layer in
                let island = Capsule(style: .continuous).path(in: layout.islandRect)
                layer.fill(island, with: .color(fill))

                if layout.dripVisible {
                    let drip = Circle().path(in: layout.dripRect)
                    layer.fill(drip, with: .color(fill))
                }

                if layout.bodyVisible {
                    let body = Capsule(style: .continuous).path(in: layout.bodyRect)
                    layer.fill(body, with: .color(fill))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Layout / progress → geometry

struct IslandGooeyLayout: Equatable {
    var canvasHeight: CGFloat
    var islandRect: CGRect
    var dripRect: CGRect
    var bodyRect: CGRect
    var dripVisible: Bool
    var bodyVisible: Bool
    var blurRadius: CGFloat
    /// Top inset for label row (matches body capsule).
    var contentTop: CGFloat
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat

    /// Mid-morph drip should protrude below the island while still overlapping it.
    var isConnectedDrip: Bool {
        dripVisible && dripRect.maxY > islandRect.maxY && dripRect.minY < islandRect.maxY + blurRadius
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

        // Early phase: teardrop drip from island bottom-center (refs 1–2).
        let dripPhase = smoothstep(0.02, 0.38, t)
        let dripDiameter = lerp(10, min(islandW * 0.42, 48), dripPhase)
        let dripTravel = lerp(0, islandH * 0.55 + 10, dripPhase)
        let dripCenterY = islandRect.maxY - dripDiameter * 0.22 + dripTravel
        let dripRect = CGRect(
            x: containerWidth / 2 - dripDiameter / 2,
            y: dripCenterY - dripDiameter / 2,
            width: dripDiameter,
            height: dripDiameter
        )

        // Later phase: toast body grows downward while staying close enough for
        // the metaball neck to stay connected to the island / drip.
        let bodyPhase = smoothstep(0.22, 1.0, t)
        let bodyW = lerp(max(dripDiameter, 28), metrics.expandedWidth, bodyPhase)
        let bodyH = lerp(max(dripDiameter * 0.9, 22), metrics.expandedHeight, bodyPhase)
        // Keep a short gap under the island so blur forms concave fillets, not a hard T-junction.
        let neckGap = lerp(2, 7, bodyPhase)
        let bodyY = islandRect.maxY + neckGap + lerp(0, 4, bodyPhase)
        // As the body widens, pull it slightly up so the neck stays gooey.
        let bodyYLift = bodyPhase * 2
        let bodyRect = CGRect(
            x: (containerWidth - bodyW) / 2,
            y: bodyY - bodyYLift,
            width: bodyW,
            height: bodyH
        )

        let dripVisible = t > 0.02 && t < 0.92
        let bodyVisible = t > 0.18
        // Slightly tighter blur once settled so the silhouette stays crisp.
        let blurRadius = lerp(11, 8, smoothstep(0.55, 1.0, t))

        let canvasHeight = max(islandRect.maxY, bodyVisible ? bodyRect.maxY : dripRect.maxY) + blurRadius * 2 + 8

        return Self(
            canvasHeight: canvasHeight,
            islandRect: islandRect,
            dripRect: dripRect,
            bodyRect: bodyRect,
            dripVisible: dripVisible,
            bodyVisible: bodyVisible,
            blurRadius: blurRadius,
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
                seedHeight: 36,
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
