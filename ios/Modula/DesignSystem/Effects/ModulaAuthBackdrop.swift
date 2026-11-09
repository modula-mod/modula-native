import SwiftUI

/// Shared backdrop for every auth screen (sign in, create account, verify, forgot and
/// reset password). It is the welcome screen's world: the near-black base and the
/// dotted Spectral Drape particle wave, so moving from "Let's go" to the forms feels
/// like one continuous place. A soft top/bottom scrim keeps forms and copy legible.
/// Decorative only; the drape already pauses off-screen, in Low Power and with Reduce Motion.
struct ModulaAuthBackdrop: View {
    /// Forms sit on a quieter version of the same world: the wave dims and a soft veil
    /// settles over it. Only opacities change, so the wave keeps its clock (no reset).
    var calm = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        let ink = Color(hex: dark ? "#0A0A0A" : "#FAFAFC")
        let drape: Double = reduceTransparency ? 0.45 : (calm ? (dark ? 0.55 : 0.32) : 1)
        ZStack {
            // Light mode: a faintly tinted base instead of near-white, so glass fields read.
            LinearGradient(
                colors: dark ? [Color(hex: "#030608"), Color(hex: "#05090D")]
                             : [Color(hex: "#EEF1F8"), Color(hex: "#E4E9F3")],
                startPoint: .top,
                endPoint: .bottom
            )
            SpectralDrapeView(interactive: false)
                .opacity(drape)
            LinearGradient(
                colors: [ink.opacity(0.35), .clear, .clear, ink.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            ink.opacity(calm ? (dark ? 0.28 : 0.38) : 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: calm)
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
                .background { ModulaAuthBackdrop(calm: true) }
        }
    }
}

extension View {
    /// Auth screen background: transparent over the hoisted backdrop, or its own
    /// `ModulaAuthBackdrop` when shown on its own (e.g. from Settings).
    func modulaAuthBackdrop() -> some View { modifier(AuthBackdropModifier()) }
}
