import SwiftUI

/// The bubbly Moliboos logo, theme-aware. No Moliboos font ships in the app, so this draws the
/// original vector letterforms (`MoliboosLogo`) instead of retyping them:
/// - Dark: the original pastel artwork.
/// - Light: the same letterforms filled with the app accent (`.tint`) plus a soft top highlight,
///   so it stays readable on light surfaces and follows the user's accent.
struct MoliboosWordmark: View {
    var height: CGFloat = 28
    /// Force the pastel look over dark artwork (e.g. card backs, welcome sheet).
    var onDark = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// viewBox 4745 × 840 (SVG).
    static let aspect: CGFloat = 4745.0 / 840.0

    var body: some View {
        Group {
            if onDark || scheme == .dark {
                Image("MoliboosLogo").renderingMode(.original).resizable().scaledToFit()
            } else {
                let mark = Image("MoliboosLogo").renderingMode(.template).resizable().scaledToFit()
                mark
                    .foregroundStyle(.tint)
                    .overlay {
                        if !reduceTransparency {
                            LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center)
                                .mask(mark)
                        }
                    }
            }
        }
        .frame(width: height * Self.aspect, height: height)
        .accessibilityElement()
        .accessibilityLabel("Moliboos")
        .accessibilityIdentifier("moliboos.wordmark")
    }
}
