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
}

private struct ModulaScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Progressive top chrome: large title dissolves into compact title without a hard material bar.
struct ModulaProgressiveHeader<Trailing: View>: View {
    let largeTitle: String
    let compactTitle: String
    var progress: CGFloat
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var app

    private var clamped: CGFloat { ModulaScrollProgress.clamp(progress) }

    var body: some View {
        ZStack(alignment: .bottom) {
            fadeBackdrop
            HStack(alignment: .center, spacing: 12) {
                titleStack
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var titleStack: some View {
        if reduceMotion {
            Text(clamped > 0.5 ? compactTitle : largeTitle)
                .font(clamped > 0.5 ? .headline.weight(.bold) : .largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .animation(.easeInOut(duration: 0.15), value: clamped > 0.5)
        } else {
            ZStack(alignment: .leading) {
                Text(largeTitle)
                    .font(.largeTitle.bold())
                    .opacity(Double(1 - clamped))
                    .offset(y: CGFloat(clamped) * -6)
                Text(compactTitle)
                    .font(.headline.weight(.bold))
                    .opacity(Double(clamped))
                    .offset(y: CGFloat(1 - clamped) * 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
        }
    }

    @ViewBuilder
    private var fadeBackdrop: some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let base = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        if opaque {
            LinearGradient(
                colors: [base.opacity(0.98), base.opacity(0.55), base.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .allowsHitTesting(false)
        } else {
            ZStack {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55 * Double(clamped)), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.95),
                                .white.opacity(0.55),
                                .white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(height: 88)
            .opacity(0.35 + (0.55 * Double(clamped)))
            .allowsHitTesting(false)
        }
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

    @ViewBuilder
    func modulaSoftScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
