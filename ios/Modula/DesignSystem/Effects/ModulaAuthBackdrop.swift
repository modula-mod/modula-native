import SwiftUI

/// Shared backdrop for every auth screen (sign in, create account, verify, forgot and
/// reset password). It is the welcome screen's world: the near-black base and the
/// dotted Spectral Drape particle wave, so moving from "Let's go" to the forms feels
/// like one continuous place. A soft top/bottom scrim keeps forms and copy legible.
/// Decorative only; the drape already pauses off-screen, in Low Power and with Reduce Motion.
struct ModulaAuthBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dark = scheme == .dark
        let ink = Color(hex: dark ? "#0A0A0A" : "#FAFAFC")
        ZStack {
            Color(hex: dark ? "#030608" : "#F6F8FF")
            SpectralDrapeView(interactive: false)
                .opacity(reduceTransparency ? 0.45 : 1)
            LinearGradient(
                colors: [ink.opacity(0.35), .clear, .clear, ink.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AuthBackdropHoistedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True under `PreShellAuthHost`, which draws one `ModulaAuthBackdrop` above the whole
    /// signed-out flow (landing, onboarding, every auth screen). Screens then stay clear so
    /// the wave keeps animating across navigation instead of restarting per screen.
    var authBackdropHoisted: Bool {
        get { self[AuthBackdropHoistedKey.self] }
        set { self[AuthBackdropHoistedKey.self] = newValue }
    }
}

private struct AuthBackdropModifier: ViewModifier {
    @Environment(\.authBackdropHoisted) private var hoisted

    func body(content: Content) -> some View {
        if hoisted {
            content
                .scrollContentBackground(.hidden)
                .containerBackground(.clear, for: .navigation)
        } else {
            content
                .scrollContentBackground(.hidden)
                .background { ModulaAuthBackdrop() }
        }
    }
}

extension View {
    /// Auth screen background: transparent over the hoisted backdrop, or its own
    /// `ModulaAuthBackdrop` when shown on its own (e.g. from Settings).
    func modulaAuthBackdrop() -> some View { modifier(AuthBackdropModifier()) }
}
