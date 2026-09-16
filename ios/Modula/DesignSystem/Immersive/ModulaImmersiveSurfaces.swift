import SwiftUI

/// Full-bleed identity surface: media starts at the physical top edge, chrome floats over it.
/// Minimal N4E subset — AvatarPocket / OnboardingHeroScene polish deferred to N4G.
struct FullBleedHero<Media: View, Overlay: View>: View {
    var height: CGFloat
    var scrollProgress: CGFloat = 0
    var bottomFade: Bool = true
    @ViewBuilder var media: () -> Media
    @ViewBuilder var overlay: () -> Overlay

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dissolve = ModulaScrollProgress.clamp(scrollProgress)
        ZStack(alignment: .top) {
            media()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .offset(y: reduceMotion ? 0 : -CGFloat(dissolve) * 16)
                .opacity(1 - (0.28 * Double(dissolve)))

            if bottomFade {
                LinearGradient(
                    colors: [
                        .clear,
                        canvas.opacity(0.18 + (0.4 * Double(dissolve))),
                        canvas.opacity(0.72 + (0.2 * Double(dissolve)))
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            overlay()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var canvas: Color {
        ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
    }
}

/// Floating Back / Share / More cluster for immersive heroes.
struct FloatingHeroControls<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

struct FloatingHeroButton: View {
    let title: String
    let symbol: String
    var action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaChrome(in: Circle(), opaque: reduceTransparency)
        .accessibilityLabel(title)
    }
}

/// Module artwork sit-in for full-bleed heroes (AvatarPocket carve deferred to N4G).
struct ArtworkPocket<Artwork: View>: View {
    var size: CGFloat
    var leadingInset: CGFloat = ModulaLayout.contentInset
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        artwork()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .padding(.leading, leadingInset)
            .offset(y: size * 0.42)
            .accessibilityElement(children: .contain)
    }
}

/// Lightweight onboarding atmosphere (full N4G hero polish deferred).
struct OnboardingHeroScene: View {
    var floatPhase: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: scheme == .dark ? "#041416" : "#082F34"),
                    app.appearance.accent.color.opacity(scheme == .dark ? 0.42 : 0.62),
                    Color(hex: scheme == .dark ? "#02080A" : "#071C20")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.08 : 0.16),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            orbs
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var orbs: some View {
        let drift: CGFloat = reduceMotion ? 0 : (floatPhase ? 10 : -10)
        return ZStack {
            moduleTile(symbol: "square.stack.3d.up", x: -118, y: -86, size: 78, drift: drift)
            moduleTile(symbol: "link", x: 126, y: -40, size: 62, drift: -drift)
            moduleTile(symbol: "lock.shield", x: -72, y: 108, size: 68, drift: drift * 0.6)
            moduleTile(symbol: "person.2", x: 96, y: 148, size: 54, drift: -drift * 0.5)
            Circle()
                .fill(Color.white.opacity(reduceTransparency ? 0.06 : 0.1))
                .frame(width: 168, height: 168)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .offset(y: drift * 0.35)
        }
        .opacity(reduceTransparency ? 0.34 : 0.72)
    }

    private func moduleTile(symbol: String, x: CGFloat, y: CGFloat, size: CGFloat, drift: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color.white.opacity(reduceTransparency ? 0.16 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .offset(x: x, y: y + drift)
    }
}
