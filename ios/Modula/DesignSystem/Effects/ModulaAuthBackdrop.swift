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
                colors: [ink.opacity(0.55), .clear, .clear, ink.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
