import SwiftUI

/// Single code-side source for the brand accent: values come from the generated design contract.
/// (Assets.xcassets/AccentColor mirrors the same value for system tinting.)
enum ModulaColor {
    static let accentHex = GeneratedDesignContract.accentDefault
    static let accent = GeneratedDesignContract.accentDefaultColor
    static let background = Color(uiColor: .systemBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
}
