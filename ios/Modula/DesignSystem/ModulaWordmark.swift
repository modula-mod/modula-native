import SwiftUI

/// The Modula wordmark: the supplied vector asset (`ModulaWordmark`, dark ink in Light, light ink in Dark).
/// Never typeset the brand name in its place. `onDark` forces the light-ink variant over dark artwork.
struct ModulaWordmark: View {
    var height: CGFloat = 22
    var onDark = false
    static let aspect: CGFloat = 2968.6 / 830

    var body: some View {
        Image("ModulaWordmark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: height * Self.aspect, height: height)
            .environment(\.colorScheme, onDark ? .dark : colorSchemeFallback)
            .accessibilityLabel("Modula")
            .accessibilityIdentifier("modula.wordmark")
    }

    @Environment(\.colorScheme) private var colorSchemeFallback
}
