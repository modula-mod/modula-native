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
    /// Custom navigation: bottom tab bar destinations, in order (Home always first, 2…5).
    var tabBar: [AppTab] { didSet { save() } }

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
        tabBar = AppTab.sanitizedBar((saved?.tabBar ?? []).compactMap(AppTab.init(rawValue:)))
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
        tabBar = AppTab.defaultBar
    }

    /// Custom navigation › Restore to default.
    func resetTabBar() {
        tabBar = AppTab.defaultBar
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
            brandWordmark: brandWordmark, customAccentHex: customAccentHex, edgePicker: edgePicker,
            tabBar: tabBar.map(\.rawValue)
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
        /// Optional so older blobs decode to the default bar.
        var tabBar: [String]?

        init(
            theme: Theme, darkStyle: DarkStyle, accent: Accent, fontFamily: FontFamily, textSize: TextSize,
            appIcon: AppIcon, density: Density, motion: MotionPersonality, haptics: HapticIntensity,
            contrastTransparency: ContrastTransparency, iconStyle: IconStyle, interfaceShape: InterfaceShape,
            moduleBranding: ModuleBranding, brandWordmark: BrandWordmark, customAccentHex: String?, edgePicker: EdgePickerPreferences,
            tabBar: [String]? = nil
        ) {
            self.theme = theme; self.darkStyle = darkStyle; self.accent = accent
            self.fontFamily = fontFamily; self.textSize = textSize; self.appIcon = appIcon
            self.density = density; self.motion = motion; self.haptics = haptics
            self.contrastTransparency = contrastTransparency; self.iconStyle = iconStyle
            self.interfaceShape = interfaceShape; self.moduleBranding = moduleBranding; self.brandWordmark = brandWordmark
            self.customAccentHex = customAccentHex
            self.edgePicker = edgePicker
            self.tabBar = tabBar
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


// MARK: - Custom navigation options (t226u/t227u)

enum TabIconTint: String, CaseIterable, Codable, Identifiable {
    case mono, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown
    var id: Self { self }
    var title: String { self == .mono ? "Monochrome" : rawValue.capitalized }
    var uiColor: UIColor? {
        switch self {
        case .mono: nil
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        }
    }
    var color: Color? { uiColor.map(Color.init(uiColor:)) }
}

enum TabIconStyle: String, CaseIterable, Codable, Identifiable {
    case automatic, filled, outline
    var id: Self { self }
    var title: String { switch self { case .automatic: "Auto"; case .filled: "Filled"; case .outline: "Outline" } }
}

enum TabBarSize: String, CaseIterable, Codable, Identifiable {
    case automatic, compact, regular
    var id: Self { self }
    var title: String { switch self { case .automatic: "Auto"; case .compact: "Compact"; case .regular: "Regular" } }
}

enum TabBadgeStyle: String, CaseIterable, Codable, Identifiable {
    case count, dot, off
    var id: Self { self }
    var title: String { switch self { case .count: "Count"; case .dot: "Dot"; case .off: "Off" } }
}

enum TabReselectAction: String, CaseIterable, Codable, Identifiable {
    case scrollToTop, refresh, backToStart, nothing
    var id: Self { self }
    var title: String {
        switch self {
        case .scrollToTop: "Scroll to top"
        case .refresh: "Refresh"
        case .backToStart: "Back to start"
        case .nothing: "Nothing"
        }
    }
}

struct TabIconChoice: Hashable {
    let outline: String
    let filled: String
}

extension AppTab {
    /// Index 0 is the default icon; the rest are alternates (Custom navigation › Icon).
    var iconChoices: [TabIconChoice] {
        let base = TabIconChoice(outline: icon, filled: selectedIcon)
        let extra: [(String, String)]
        switch self {
        case .home: extra = [("house.circle", "house.circle.fill"), ("square.grid.2x2", "square.grid.2x2.fill")]
        case .discover: extra = [("sparkles", "sparkles"), ("star", "star.fill")]
        case .modules: extra = [("square.stack.3d.up", "square.stack.3d.up.fill"), ("puzzlepiece", "puzzlepiece.fill")]
        case .activity: extra = [("heart", "heart.fill"), ("bolt", "bolt.fill")]
        case .profile: extra = [("person", "person.fill")]
        case .messages: extra = [("message", "message.fill"), ("bubble.left", "bubble.left.fill")]
        case .search: extra = [("magnifyingglass.circle", "magnifyingglass.circle.fill")]
        case .reels: extra = [("film", "film.fill"), ("play.circle", "play.circle.fill")]
        case .saved: extra = [("star", "star.fill"), ("folder", "folder.fill")]
        case .drafts: extra = [("square.and.pencil", "square.and.pencil"), ("pencil.line", "pencil.line")]
        case .communities: extra = [("person.2", "person.2.fill"), ("globe", "globe")]
        case .teams: extra = [("briefcase", "briefcase.fill"), ("building.2", "building.2.fill")]
        case .phone: extra = [("phone.circle", "phone.circle.fill"), ("phone.bubble", "phone.bubble.fill")]
        case .inMail: extra = [("tray", "tray.fill"), ("envelope.open", "envelope.open.fill")]
        case .moliboo: extra = [("face.smiling", "face.smiling.fill"), ("sparkles", "sparkles")]
        case .connect: extra = [("simcard", "simcard.fill"), ("network", "network")]
        }
        return [base] + extra.map { TabIconChoice(outline: $0.0, filled: $0.1) }
    }
}

/// One-tap tab bar presets (Custom navigation).
enum TabBarPreset: String, CaseIterable, Identifiable {
    case social, creator, messenger, minimal
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .social: "person.2"
        case .creator: "camera"
        case .messenger: "bubble.left.and.bubble.right"
        case .minimal: "circle.dashed"
        }
    }
    var tabs: [AppTab] {
        switch self {
        case .social: [.home, .discover, .reels, .messages, .activity]
        case .creator: [.home, .reels, .drafts, .modules, .activity]
        case .messenger: [.home, .messages, .phone, .inMail, .activity]
        case .minimal: [.home, .search, .activity]
        }
    }
}

/// Local-only look and behaviour of the tab bar (Settings › Appearance › Custom navigation).
@MainActor @Observable
final class TabBarCustomization {
    static let shared = TabBarCustomization()
    private static let key = "modula.tabBarCustomization.v1"

    private struct Snapshot: Codable {
        var tints: [String: String] = [:]
        var icons: [String: Int] = [:]
        var showLabels = true
        var iconStyle: TabIconStyle = .automatic
        var size: TabBarSize = .automatic
        var badgeStyle: TabBadgeStyle = .count
        var reselect: TabReselectAction = .scrollToTop
        var longPressMenu = true
        var haptics = true
    }

    private var state: Snapshot { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            state = saved
        } else {
            state = Snapshot()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    var showLabels: Bool { get { state.showLabels } set { state.showLabels = newValue } }
    var iconStyle: TabIconStyle { get { state.iconStyle } set { state.iconStyle = newValue } }
    var size: TabBarSize { get { state.size } set { state.size = newValue } }
    var badgeStyle: TabBadgeStyle { get { state.badgeStyle } set { state.badgeStyle = newValue } }
    var reselect: TabReselectAction { get { state.reselect } set { state.reselect = newValue } }
    var longPressMenu: Bool { get { state.longPressMenu } set { state.longPressMenu = newValue } }
    var haptics: Bool { get { state.haptics } set { state.haptics = newValue } }

    func tint(for tab: AppTab) -> TabIconTint {
        state.tints[tab.rawValue].flatMap(TabIconTint.init(rawValue:)) ?? .mono
    }
    func setTint(_ tint: TabIconTint, for tab: AppTab) {
        state.tints[tab.rawValue] = tint == .mono ? nil : tint.rawValue
    }
    func iconIndex(for tab: AppTab) -> Int {
        let i = state.icons[tab.rawValue] ?? 0
        return tab.iconChoices.indices.contains(i) ? i : 0
    }
    func setIconIndex(_ index: Int, for tab: AppTab) {
        state.icons[tab.rawValue] = index == 0 ? nil : index
    }
    func symbol(for tab: AppTab, selected: Bool) -> String {
        let choice = tab.iconChoices[iconIndex(for: tab)]
        switch iconStyle {
        case .automatic: return selected ? choice.filled : choice.outline
        case .filled: return choice.filled
        case .outline: return choice.outline
        }
    }
    /// True when any per-tab or bar option differs from the defaults.
    var isCustomised: Bool {
        let d = Snapshot()
        return !state.tints.isEmpty || !state.icons.isEmpty || state.showLabels != d.showLabels
            || state.iconStyle != d.iconStyle || state.size != d.size || state.badgeStyle != d.badgeStyle
            || state.reselect != d.reselect || state.longPressMenu != d.longPressMenu || state.haptics != d.haptics
    }
    func reset() { state = Snapshot() }
    func applyPresetLook(_ preset: TabBarPreset) {
        state.showLabels = preset != .minimal
        if preset == .minimal { state.iconStyle = .outline } else if state.iconStyle == .outline { state.iconStyle = .automatic }
    }
}

/// Coloured tab icons: the system bar tints template images, so a coloured icon is rendered
/// once as an original-mode image and cached.
@MainActor
enum TabIconRenderer {
    private static var cache: [String: UIImage] = [:]
    static func image(_ symbol: String, color: UIColor, selected: Bool) -> UIImage {
        let key = "\(symbol)|\(color.hashValue)|\(selected)"
        if let hit = cache[key] { return hit }
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: selected ? .semibold : .regular)
        let base = UIImage(systemName: symbol, withConfiguration: config) ?? UIImage(systemName: "circle", withConfiguration: config) ?? UIImage()
        let out = base.withTintColor(color, renderingMode: .alwaysOriginal)
        cache[key] = out
        return out
    }
}
