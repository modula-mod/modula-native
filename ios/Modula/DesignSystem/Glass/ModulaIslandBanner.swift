import SwiftUI
import UIKit

// MARK: - Island-morph shell banner
//
// Single presenter for `NavigationCoordinator.banner` / `flash(...)`.
// Client-only: expands from a Dynamic Island–sized seed (or notch/status
// fallback), then collapses back. No ActivityKit — ephemeral confirmations
// should not own a Live Activity.

struct ModulaIslandBannerHost: View {
    var banner: ModulaBanner?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var displayed: ModulaBanner?
    @State private var expanded = false
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
                    pill(displayed, metrics: metrics)
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
    private func pill(_ banner: ModulaBanner, metrics: IslandBannerMetrics) -> some View {
        let width = expanded ? metrics.expandedWidth : metrics.seedWidth
        let height = expanded ? metrics.expandedHeight : metrics.seedHeight

        HStack(spacing: 8) {
            Image(systemName: banner.symbol)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(banner.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, expanded ? 14 : 4)
        .opacity(contentOpacity)
        .frame(width: width, height: height)
        .modulaGlass(in: Capsule(), interactive: false, tint: seedTint(metrics), prominent: !expanded && metrics.style == .island)
        .overlay {
            // Collapsed seed reads as the hardware island / notch silhouette.
            if !expanded {
                Capsule()
                    .fill(seedFill(metrics))
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(expanded ? 0.22 : 0), radius: expanded ? 10 : 0, y: expanded ? 4 : 0)
        .padding(.top, metrics.topPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var contentOpacity: Double {
        if calm { return expanded ? 1 : 0 }
        return expanded ? 1 : 0
    }

    private func seedTint(_ metrics: IslandBannerMetrics) -> Color? {
        metrics.style == .island && !expanded ? Color.black : nil
    }

    private func seedFill(_ metrics: IslandBannerMetrics) -> Color {
        switch metrics.style {
        case .island: Color.black
        case .notch: Color.black.opacity(0.92)
        case .bar: Color.primary.opacity(0.55)
        }
    }

    private func sync(to next: ModulaBanner?) {
        dismissGeneration += 1
        let generation = dismissGeneration

        if let next {
            let swapping = displayed != nil && displayed?.id != next.id
            displayed = next
            if calm {
                expanded = true
                return
            }
            if swapping, expanded {
                // Already morph-expanded: soft content swap, no re-collapse.
                return
            }
            expanded = false
            withAnimation(expandAnimation) { expanded = true }
            return
        }

        // Dismiss: collapse into the seed, then drop the view.
        guard displayed != nil else { return }
        if calm {
            withAnimation(.easeOut(duration: 0.12)) { expanded = false }
            displayed = nil
            return
        }
        withAnimation(collapseAnimation) { expanded = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard generation == dismissGeneration, banner == nil else { return }
            displayed = nil
        }
    }

    private var expandAnimation: Animation {
        ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.42, dampingFraction: 0.78)
    }

    private var collapseAnimation: Animation {
        ModulaMotion.animation(.dismissal, personality: app.appearance.motion, reduceMotion: false)
            ?? .spring(response: 0.36, dampingFraction: 0.86)
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
        let expandedHeight: CGFloat = 40

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
