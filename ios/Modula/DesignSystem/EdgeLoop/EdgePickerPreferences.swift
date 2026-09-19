import Foundation

/// Persisted Edge Picker personalization. Nested under Appearance — not a separate store.
struct EdgePickerPreferences: Codable, Equatable, Sendable {
    var position: EdgePickerPosition
    var size: EdgePickerSize
    var side: EdgePickerSide
    var labelBehavior: EdgePickerLabelBehavior
    var glassIntensity: EdgePickerGlassIntensity
    var visibility: EdgePickerVisibility
    var motion: EdgePickerMotionPreference
    var haptics: EdgePickerHapticPreference

    static let `default` = EdgePickerPreferences(
        position: .middle,
        size: .standard,
        side: .right,
        labelBehavior: .onChange,
        glassIntensity: .standard,
        visibility: .always,
        motion: .followAppearance,
        haptics: .followAppearance
    )
}

enum EdgePickerPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case up, middle, down
    var id: Self { self }
    var title: String {
        switch self {
        case .up: "Up"
        case .middle: "Middle"
        case .down: "Down"
        }
    }
}

enum EdgePickerSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact, standard, large
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum EdgePickerSide: String, CaseIterable, Codable, Identifiable, Sendable {
    case left, right
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var loopPosition: EdgeLoopPosition {
        self == .left ? .leading : .trailing
    }
}

enum EdgePickerLabelBehavior: String, CaseIterable, Codable, Identifiable, Sendable {
    case onChange, always, iconsOnly
    var id: Self { self }
    var title: String {
        switch self {
        case .onChange: "On Change"
        case .always: "Always"
        case .iconsOnly: "Icons Only"
        }
    }
}

enum EdgePickerGlassIntensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case subtle, standard, strong
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum EdgePickerVisibility: String, CaseIterable, Codable, Identifiable, Sendable {
    case always, autoHide
    var id: Self { self }
    var title: String {
        switch self {
        case .always: "Always Visible"
        case .autoHide: "Auto-hide"
        }
    }
}

enum EdgePickerMotionPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case followAppearance, reduced, fluid
    var id: Self { self }
    var title: String {
        switch self {
        case .followAppearance: "Follow Appearance"
        case .reduced: "Reduced"
        case .fluid: "Fluid"
        }
    }
}

enum EdgePickerHapticPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case followAppearance, off, light, standard
    var id: Self { self }
    var title: String {
        switch self {
        case .followAppearance: "Follow Appearance"
        case .off: "Off"
        case .light: "Light"
        case .standard: "Standard"
        }
    }
}
