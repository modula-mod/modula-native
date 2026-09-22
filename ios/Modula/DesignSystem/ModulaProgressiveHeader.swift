import SwiftUI

/// Clamps scroll-driven chrome progress into 0...1 for progressive headers.
enum ModulaScrollProgress {
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// Maps content offset into progress over a collapse distance (points).
    static func progress(offsetY: CGFloat, collapseDistance: CGFloat = 56) -> CGFloat {
        guard collapseDistance > 0 else { return 0 }
        return clamp(offsetY / collapseDistance)
    }

    /// Which top-edge dissolve path is active for acceptance recording.
    static var softEdgePathLabel: String {
        if #available(iOS 26.0, *) {
            return "native-soft-edge"
        }
        return "fallback-masked-material"
    }
}

private struct ModulaScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Progressive top chrome: large title dissolves into compact centered title without a hard material bar.
/// Blur/fade extends under the status bar so content softens from the top of the screen.
struct ModulaProgressiveHeader<Trailing: View>: View {
    let largeTitle: String
    let compactTitle: String
    var progress: CGFloat
    /// Optional compact identity (avatar + name cluster). When set, replaces the centered title.
    var compactInitials: String? = nil
    var compactAvatarURL: URL? = nil
    var compactSubtitle: String? = nil
    /// For full-bleed parents that ignore the top safe area — pad the content row so it
    /// shares the same band as `FloatingHeroControls` (status bar + floating top pad).
    var topChromeInset: CGFloat = 0
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var app

    private var clamped: CGFloat { ModulaScrollProgress.clamp(progress) }
    private var showsCompactIdentity: Bool { compactInitials != nil }
    private var immersive: Bool { topChromeInset > 0 }

    var body: some View {
        ZStack(alignment: immersive ? .top : .bottom) {
            fadeBackdrop
            contentRow
                .padding(.top, immersive ? topChromeInset + ModulaChromeMetrics.floatingTopPad : 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.progressiveHeader")
        .accessibilityValue(ModulaScrollProgress.softEdgePathLabel)
    }

    private var contentRow: some View {
        ZStack {
            if showsCompactIdentity {
                compactIdentity
                    .opacity(reduceMotion ? (clamped > 0.5 ? 1 : 0) : Double(clamped))
                    .offset(y: reduceMotion ? 0 : CGFloat(1 - clamped) * 8)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(clamped < 0.15)
            } else {
                // Compact centered title — keep clear of the shared top-trailing capsule.
                Text(compactTitle)
                    .font(.headline.weight(.semibold))
                    .opacity(reduceMotion ? (clamped > 0.5 ? 1 : 0) : Double(clamped))
                    .offset(y: reduceMotion ? 0 : CGFloat(1 - clamped) * 8)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, ModulaChromeMetrics.trailingCapsuleReserve)
                    .allowsHitTesting(false)
                    .accessibilityHidden(clamped < 0.15)
            }

            HStack(alignment: .center, spacing: 12) {
                if reduceMotion {
                    Text(clamped > 0.5 ? " " : largeTitle)
                        .font(.largeTitle.bold())
                        .opacity(clamped > 0.5 ? 0 : 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(largeTitle)
                        .font(.largeTitle.bold())
                        .opacity(Double(1 - clamped))
                        .scaleEffect(1 - (0.18 * clamped), anchor: .leading)
                        .offset(y: CGFloat(clamped) * -10)
                }
                Spacer(minLength: 8)
                trailing()
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 8)
        .padding(.top, immersive ? 0 : 4)
        .frame(height: ModulaLayout.minimumTouch)
    }

    private var compactIdentity: some View {
        HStack(alignment: .center, spacing: 10) {
            if let compactInitials {
                ModulaAvatar(initials: compactInitials, url: compactAvatarURL, size: 28)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(compactTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let compactSubtitle, !compactSubtitle.isEmpty {
                    Text(compactSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, ModulaChromeMetrics.trailingCapsuleReserve)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([compactTitle, compactSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    @ViewBuilder
    private var fadeBackdrop: some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let base = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        let strength = 0.12 + (0.78 * Double(clamped))
        let fadeHeight = 148 + max(0, topChromeInset)
        Group {
            if opaque {
                // Solid progressive veil — no material rectangle edge.
                LinearGradient(
                    stops: [
                        .init(color: base.opacity(0.97), location: 0),
                        .init(color: base.opacity(0.72), location: 0.35),
                        .init(color: base.opacity(0.28), location: 0.7),
                        .init(color: base.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                ZStack {
                    // Soft canvas tint from the very top (under status bar).
                    LinearGradient(
                        stops: [
                            .init(color: base.opacity(0.55 + 0.35 * Double(clamped)), location: 0),
                            .init(color: base.opacity(0.18 * Double(clamped)), location: 0.55),
                            .init(color: base.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.45 * Double(clamped)),
                                Color.black.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    // Masked material: dense at top, fully transparent at bottom — no slab edge.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(1.0), location: 0),
                                .init(color: .white.opacity(0.85), location: 0.22),
                                .init(color: .white.opacity(0.45), location: 0.5),
                                .init(color: .white.opacity(0.12), location: 0.78),
                                .init(color: .white.opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                // Always keep a light top dissolve so status-bar content never stays razor-sharp.
                .opacity(max(0.42, strength))
            }
        }
        .frame(maxWidth: .infinity)
        // Tall enough to cover status bar + large title row without a hard bottom edge.
        .frame(height: fadeHeight)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ModulaScrollProgressReader: View {
    var coordinateSpace: String = "modula.progressive"

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ModulaScrollOffsetKey.self,
                value: -proxy.frame(in: .named(coordinateSpace)).minY
            )
        }
        .frame(height: 0)
    }
}

extension View {
    /// Apply on the `ScrollView`; pair with `ModulaScrollProgressReader` at the top of content.
    func modulaScrollProgressTracking(
        coordinateSpace: String = "modula.progressive",
        collapseDistance: CGFloat = 56,
        progress: Binding<CGFloat>
    ) -> some View {
        self
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(ModulaScrollOffsetKey.self) { offset in
                progress.wrappedValue = ModulaScrollProgress.progress(offsetY: offset, collapseDistance: collapseDistance)
            }
    }

    /// Home’s progressive top blur. Apply on every page-level ScrollView / List / Form.
    @ViewBuilder
    func modulaSoftScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
