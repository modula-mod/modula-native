import SwiftUI
import UIKit
import Observation

@MainActor @Observable
final class AppearanceStore {
    enum Theme: String, CaseIterable, Codable, Identifiable { case system, light, dark; var id: Self { self } }
    enum DarkStyle: String, CaseIterable, Codable, Identifiable { case standard, dim, oled; var id: Self { self } }
    enum Accent: String, CaseIterable, Codable, Identifiable {
        case modulaTeal, ocean, violet, coral, moss, graphite
        var id: Self { self }
        var title: String { switch self { case .modulaTeal: "Modula Teal"; default: rawValue.capitalized } }
        var hex: String { switch self { case .modulaTeal: "#369CAA"; case .ocean: "#3478F6"; case .violet: "#7656D6"; case .coral: "#D66056"; case .moss: "#4E8B67"; case .graphite: "#667085" } }
        var color: Color { Color(hex: hex) }
    }
    enum FontFamily: String, CaseIterable, Codable, Identifiable { case system, rounded, humanist, geometric, editorial, mono; var id: Self { self } }
    enum TextSize: String, CaseIterable, Codable, Identifiable { case compact, standard, large; var id: Self { self }; var scale: Double { switch self { case .compact: 0.94; case .standard: 1; case .large: 1.12 } } }
    enum AppIcon: String, CaseIterable, Codable, Identifiable { case `default`; var id: Self { self } }
    enum Density: String, CaseIterable, Codable, Identifiable { case compact, standard, comfortable; var id: Self { self }; var spacingScale: Double { switch self { case .compact: 0.84; case .standard: 1; case .comfortable: 1.18 } } }
    enum MotionPersonality: String, CaseIterable, Codable, Identifiable { case calm, standard, expressive; var id: Self { self } }
    enum HapticIntensity: String, CaseIterable, Codable, Identifiable { case off, light, standard, strong; var id: Self { self } }
    enum ContrastTransparency: String, CaseIterable, Codable, Identifiable { case standard, higherContrast, reduceTransparency; var id: Self { self } }
    enum IconStyle: String, CaseIterable, Codable, Identifiable { case outline, balanced, filled; var id: Self { self } }
    enum InterfaceShape: String, CaseIterable, Codable, Identifiable { case soft, balanced, precise; var id: Self { self } }
    enum ModuleBranding: String, CaseIterable, Codable, Identifiable { case moduleIdentity, blend, preferUserAccent; var id: Self { self } }
    /// Home / chrome wordmark. Modula (default) or the Moliboos bubbly mark.
    enum BrandWordmark: String, CaseIterable, Codable, Identifiable {
        case modula, moliboos
        var id: Self { self }
        var title: String { switch self { case .modula: "Modula"; case .moliboos: "Moliboos" } }
    }

    private let defaults: UserDefaults
    private let key = "modula.native.appearance.v2"
    var theme: Theme { didSet { save() } }
    var darkStyle: DarkStyle { didSet { save() } }
    var accent: Accent { didSet { save() } }
    var fontFamily: FontFamily { didSet { save() } }
    var textSize: TextSize { didSet { save() } }
    var appIcon: AppIcon { didSet { save() } }
    var density: Density { didSet { save() } }
    var motion: MotionPersonality { didSet { save() } }
    var haptics: HapticIntensity { didSet { save() } }
    var contrastTransparency: ContrastTransparency { didSet { save() } }
    var iconStyle: IconStyle { didSet { save() } }
    var interfaceShape: InterfaceShape { didSet { save() } }
    var moduleBranding: ModuleBranding { didSet { save() } }
    var brandWordmark: BrandWordmark { didSet { save() } }
    /// A colour chosen from the wheel. Nil means the named `accent` swatch is in use.
    /// Stored on this iPhone only: `PATCH /v1/accounts/me/appearance` has no declared body.
    var customAccentHex: String? { didSet { save() } }
    /// Edge Picker personalization. Nested under Appearance; reset separately via `resetEdgePicker()`.
    var edgePicker: EdgePickerPreferences { didSet { save() } }

    var colorScheme: ColorScheme? { switch theme { case .system: nil; case .light: .light; case .dark: .dark } }
    /// Named swatch, or the wheel colour when one is stored.
    var liveAccent: Color {
        if let customAccentHex, let normalized = Self.normalizedHex(customAccentHex) {
            return Color(hex: normalized)
        }
        return accent.color
    }
    var accentTitle: String { customAccentHex == nil ? accent.title : "Custom" }

    func selectNamedAccent(_ value: Accent) {
        if customAccentHex != nil { customAccentHex = nil }
        accent = value
    }

    func selectCustomAccent(hex: String) {
        guard let normalized = Self.normalizedHex(hex) else { return }
        customAccentHex = normalized
    }

    static func normalizedHex(_ raw: String) -> String? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(hex)"
    }

    static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return formatHex(red, green, blue)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let resolved = ui.cgColor.converted(to: space, intent: .defaultIntent, options: nil) ?? ui.cgColor
        if let components = resolved.components, components.count >= 3 {
            return formatHex(components[0], components[1], components[2])
        }
        return "#369CAA"
    }

    private static func formatHex(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    var fontDesign: Font.Design { switch fontFamily { case .rounded, .geometric: .rounded; case .editorial: .serif; case .mono: .monospaced; default: .default } }
    var appearance: LegacyAppearance {
        get { if theme == .system { .system } else if theme == .light { .light } else if darkStyle == .oled { .oled } else { .dark } }
        set {
            switch newValue {
            case .system: theme = .system
            case .light: theme = .light
            case .dark: theme = .dark; darkStyle = .standard
            case .oled: theme = .dark; darkStyle = .oled
            }
        }
    }
    enum LegacyAppearance: String, CaseIterable, Codable { case system, light, dark, oled }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        theme = saved?.theme ?? .system
        darkStyle = saved?.darkStyle ?? .standard
        accent = saved?.accent ?? .modulaTeal
        fontFamily = saved?.fontFamily ?? .system
        textSize = saved?.textSize ?? .standard
        appIcon = saved?.appIcon ?? .default
        density = saved?.density ?? .standard
        motion = saved?.motion ?? .standard
        haptics = saved?.haptics ?? .standard
        contrastTransparency = saved?.contrastTransparency ?? .standard
        iconStyle = saved?.iconStyle ?? .balanced
        interfaceShape = saved?.interfaceShape ?? .balanced
        moduleBranding = saved?.moduleBranding ?? .blend
        brandWordmark = saved?.brandWordmark ?? .modula
        customAccentHex = saved?.customAccentHex.flatMap(Self.normalizedHex)
        edgePicker = saved?.edgePicker ?? .default
        if saved == nil, let legacy = LegacyAppearance(rawValue: defaults.string(forKey: "modula.native.appearance.v1") ?? "") { appearance = legacy }
    }

    /// Full Appearance reset — includes Edge Picker defaults.
    func reset() {
        theme = .system; darkStyle = .standard; accent = .modulaTeal; fontFamily = .system; textSize = .standard
        appIcon = .default; density = .standard; motion = .standard; haptics = .standard
        contrastTransparency = .standard; iconStyle = .balanced; interfaceShape = .balanced; moduleBranding = .blend
        brandWordmark = .modula
        customAccentHex = nil
        edgePicker = .default
    }

    /// Resets only Edge Picker preferences to canonical defaults.
    func resetEdgePicker() {
        edgePicker = .default
    }

    private func save() {
        let value = Snapshot(
            theme: theme, darkStyle: darkStyle, accent: accent, fontFamily: fontFamily, textSize: textSize,
            appIcon: appIcon, density: density, motion: motion, haptics: haptics,
            contrastTransparency: contrastTransparency, iconStyle: iconStyle,
            interfaceShape: interfaceShape, moduleBranding: moduleBranding,
            brandWordmark: brandWordmark, customAccentHex: customAccentHex, edgePicker: edgePicker
        )
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private struct Snapshot: Codable {
        var theme: Theme; var darkStyle: DarkStyle; var accent: Accent; var fontFamily: FontFamily; var textSize: TextSize
        var appIcon: AppIcon; var density: Density; var motion: MotionPersonality; var haptics: HapticIntensity
        var contrastTransparency: ContrastTransparency; var iconStyle: IconStyle; var interfaceShape: InterfaceShape
        var moduleBranding: ModuleBranding
        var brandWordmark: BrandWordmark?
        /// Optional so existing v2 blobs without this field decode to defaults.
        var customAccentHex: String?
        /// Optional so existing v2 blobs without this field decode to defaults.
        var edgePicker: EdgePickerPreferences?

        init(
            theme: Theme, darkStyle: DarkStyle, accent: Accent, fontFamily: FontFamily, textSize: TextSize,
            appIcon: AppIcon, density: Density, motion: MotionPersonality, haptics: HapticIntensity,
            contrastTransparency: ContrastTransparency, iconStyle: IconStyle, interfaceShape: InterfaceShape,
            moduleBranding: ModuleBranding, brandWordmark: BrandWordmark, customAccentHex: String?, edgePicker: EdgePickerPreferences
        ) {
            self.theme = theme; self.darkStyle = darkStyle; self.accent = accent
            self.fontFamily = fontFamily; self.textSize = textSize; self.appIcon = appIcon
            self.density = density; self.motion = motion; self.haptics = haptics
            self.contrastTransparency = contrastTransparency; self.iconStyle = iconStyle
            self.interfaceShape = interfaceShape; self.moduleBranding = moduleBranding; self.brandWordmark = brandWordmark
            self.customAccentHex = customAccentHex
            self.edgePicker = edgePicker
        }
    }
}

typealias SettingsStore = AppearanceStore

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
