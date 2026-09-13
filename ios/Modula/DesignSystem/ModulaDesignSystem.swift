import SwiftUI
import UIKit

enum ModulaSpacing { static let xxs = 4.0; static let xs = 8.0; static let sm = 12.0; static let md = 16.0; static let lg = 24.0; static let xl = 32.0 }
enum ModulaRadius { static let small = 10.0; static let medium = 16.0; static let large = 24.0 }
enum ModulaLayout { static let minimumTouch = 44.0; static let contentInset = 18.0; static let railRestingWidth = 52.0; static let railRevealedWidth = 106.0 }
enum ModulaMotion {
    enum Role { case selection, navigation, morph, reveal, dismiss, railExpand, railCollapse, sheetPresent }
    static func animation(_ role: Role, personality: AppearanceStore.MotionPersonality, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.12) }
        switch personality {
        case .calm: return .easeOut(duration: role == .navigation ? 0.2 : 0.16)
        case .standard: return .spring(duration: 0.38, bounce: 0.16)
        case .expressive: return .spring(duration: 0.5, bounce: 0.28)
        }
    }
}

enum HapticSemantic { case selection, navigation, confirmation, warning, success, failure, impact }
@MainActor final class HapticEngine {
    static let shared = HapticEngine()
    var intensityProvider: () -> AppearanceStore.HapticIntensity = { .standard }
    func play(_ semantic: HapticSemantic) {
        let intensity = intensityProvider()
        guard intensity != .off else { return }
        switch semantic {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .navigation, .impact: UIImpactFeedbackGenerator(style: intensity == .strong ? .heavy : intensity == .light ? .light : .medium).impactOccurred()
        case .confirmation, .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failure: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

enum ModulaIconRole: String, CaseIterable { case home, discover, module, activity, profile, search, settings, share, like, comment, back, more }
enum ModulaIconRegistry {
    static func symbol(_ role: ModulaIconRole, style: AppearanceStore.IconStyle, selected: Bool = false) -> String {
        let base: String = switch role {
        case .home: "house"; case .discover: "safari"; case .module: "shippingbox"; case .activity: "bell"
        case .profile: "person.crop.circle"; case .search: "magnifyingglass"; case .settings: "gearshape"
        case .share: "square.and.arrow.up"; case .like: "heart"; case .comment: "bubble.right"; case .back: "chevron.left"; case .more: "ellipsis"
        }
        let canFill = [.home, .discover, .module, .activity, .profile, .like].contains(role)
        return canFill && (selected || style == .filled) ? base + ".fill" : base
    }
}

struct ModulaPalette {
    var canvas: Color; var surface: Color; var elevated: Color; var primary: Color; var secondary: Color; var separator: Color; var accent: Color
    @MainActor static func resolve(_ store: AppearanceStore, scheme: ColorScheme, increasedContrast: Bool = false) -> Self {
        let dark = scheme == .dark
        let accent = store.accent.color
        if dark && store.darkStyle == .oled {
            return Self(canvas: .black, surface: Color.white.opacity(0.055), elevated: Color.white.opacity(0.1), primary: .white,
                        secondary: Color.white.opacity(increasedContrast ? 0.78 : 0.66), separator: Color.white.opacity(0.14), accent: accent)
        }
        if dark && store.darkStyle == .dim {
            return Self(canvas: Color(red: 0.075, green: 0.085, blue: 0.10), surface: Color(red: 0.105, green: 0.12, blue: 0.14),
                        elevated: Color(red: 0.14, green: 0.155, blue: 0.18), primary: Color.white.opacity(0.92),
                        secondary: Color.white.opacity(increasedContrast ? 0.76 : 0.58), separator: Color.white.opacity(0.1), accent: accent)
        }
        if dark {
            return Self(canvas: Color(uiColor: .systemBackground), surface: Color(uiColor: .secondarySystemBackground), elevated: Color(uiColor: .tertiarySystemBackground),
                        primary: .primary, secondary: .secondary, separator: Color.white.opacity(0.12), accent: accent)
        }
        return Self(canvas: Color(red: 0.975, green: 0.982, blue: 0.988), surface: .white, elevated: Color(uiColor: .secondarySystemBackground),
                    primary: .primary, secondary: .secondary, separator: Color.black.opacity(increasedContrast ? 0.16 : 0.08), accent: accent)
    }
}

struct ModulaText: View {
    enum Role { case hero, title, headline, body, callout, caption, metric }
    let text: String; var role: Role = .body; var color: Color? = nil
    @Environment(AppEnvironment.self) private var app
    @ScaledMetric(relativeTo: .body) private var baseSize = 17.0
    var body: some View { Text(text).font(font).fontDesign(design).foregroundStyle(color ?? .primary).dynamicTypeSize(...DynamicTypeSize.accessibility5) }
    private var font: Font { .system(size: baseSize * multiplier * app.appearance.textSize.scale, weight: weight, design: design) }
    private var multiplier: Double { switch role { case .hero: 2; case .title: 1.35; case .headline: 1; case .body: 1; case .callout: 0.94; case .caption: 0.76; case .metric: 1.18 } }
    private var weight: Font.Weight { switch role { case .hero, .title: .bold; case .headline, .metric: .semibold; default: .regular } }
    private var design: Font.Design { switch app.appearance.fontFamily { case .rounded, .geometric: .rounded; case .editorial: .serif; case .mono: .monospaced; default: .default } }
}
struct ModulaIcon: View { var role: ModulaIconRole; var selected = false; @Environment(AppEnvironment.self) private var app; var body: some View { Image(systemName: ModulaIconRegistry.symbol(role, style: app.appearance.iconStyle, selected: selected)).imageScale(.large) } }
struct ModulaButton: View {
    let title: String; var symbol: String?; var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View { Button(action: action) { Label(title, systemImage: symbol ?? "arrow.right").frame(maxWidth: .infinity).frame(minHeight: ModulaLayout.minimumTouch).font(.headline) }.buttonStyle(.borderedProminent).tint(app.appearance.accent.color).buttonBorderShape(.capsule) }
}
struct ModulaIconButton: View { let title: String; let symbol: String; var action: () -> Void; var body: some View { Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(title) } }
struct ModulaAvatar: View { var initials: String; var size = 44.0; @Environment(AppEnvironment.self) private var app; var body: some View { Circle().fill(app.appearance.accent.color.gradient).frame(width: size, height: size).overlay(Text(initials).font(.headline).foregroundStyle(.white)).accessibilityLabel("Profile avatar") } }
struct ModulaBadge: View { var title: String; var symbol: String?; @Environment(AppEnvironment.self) private var app; var body: some View { Label(title, systemImage: symbol ?? "checkmark").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(app.appearance.accent.color.opacity(0.14), in: Capsule()).foregroundStyle(app.appearance.accent.color) } }
struct ModulaCard<Content: View>: View { @ViewBuilder var content: Content; @Environment(AppEnvironment.self) private var app; @Environment(\.colorScheme) private var scheme; var body: some View { content.padding(16 * app.appearance.density.spacingScale).frame(maxWidth: .infinity, alignment: .leading).background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous)).overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.07))).accessibilityElement(children: .contain) }; private var radius: Double { switch app.appearance.interfaceShape { case .soft: 24; case .balanced: 17; case .precise: 10 } } }

private struct ModulaCanvasModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.scrollContentBackground(.hidden).background(ModulaPalette.resolve(app.appearance, scheme: scheme).canvas) }
}
extension View { func modulaCanvas() -> some View { modifier(ModulaCanvasModifier()) } }
struct ModulaListRow: View { var title: String; var subtitle: String?; var symbol: String; var action: (() -> Void)?; var body: some View { Button { action?() } label: { HStack(spacing: 14) { Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint); VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.medium)); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }; Spacer(); if action != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }.frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(action == nil).accessibilityLabel(title).accessibilityValue(subtitle ?? "") } }
struct ModulaSection<Content: View>: View { var title: String; @ViewBuilder var content: Content; var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content }.frame(maxWidth: .infinity, alignment: .leading) } }
struct ModulaSearchField: View { @Binding var text: String; var prompt = "Search"; var body: some View { TextField(prompt, text: $text).textFieldStyle(.plain).padding(.horizontal, 14).frame(minHeight: 44).background(.thinMaterial, in: Capsule()).accessibilityLabel(prompt) } }
struct ModulaMetric: View { var value: String; var label: String; var body: some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.title3.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.accessibilityElement(children: .combine) } }
struct ModulaMetricPicker<Value: Hashable, Content: View>: View { @Binding var selection: Value; var values: [Value]; @ViewBuilder var label: (Value) -> Content; var body: some View { Picker("Selection", selection: $selection) { ForEach(values, id: \.self) { label($0).tag($0) } }.pickerStyle(.segmented) } }
struct ModulaChip: View { var title: String; var selected = false; var action: () -> Void; var body: some View { Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(selected ? .accentColor : .secondary).frame(minHeight: 44) } }
struct ModulaToolbar<Content: View>: View { @ViewBuilder var content: Content; var body: some View { HStack(spacing: 8) { content }.padding(6).background(.regularMaterial, in: Capsule()) } }
struct ModulaTopBar: View { var title: String; var trailing: (() -> Void)?; var body: some View { HStack { Text(title).font(.largeTitle.bold()); Spacer(); if let trailing { ModulaIconButton(title: "Settings", symbol: "gearshape", action: trailing) } }.padding(.horizontal, ModulaLayout.contentInset) } }
struct ModulaSheet<Content: View>: View { @ViewBuilder var content: Content; var body: some View { NavigationStack { content }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) } }
struct ModulaMenu<Content: View>: View { var title: String; @ViewBuilder var content: Content; var body: some View { Menu(title, content: { content }) } }
struct ModulaEmptyState: View { var title: String; var message: String; var symbol: String; var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) } }
struct ModulaLoadingState: View { var title = "Loading…"; var body: some View { ProgressView(title).frame(maxWidth: .infinity, minHeight: 180) } }
struct ModulaErrorState: View { var message: String; var retry: (() -> Void)?; var body: some View { ContentUnavailableView { Label("Something went wrong", systemImage: "exclamationmark.triangle") } description: { Text(message) } actions: { if let retry { Button("Try Again", action: retry) } } } }
struct ModulaHero<Content: View>: View { var title: String; var subtitle: String; @ViewBuilder var artwork: Content; var body: some View { ZStack(alignment: .bottomLeading) { artwork.frame(maxWidth: .infinity).frame(height: 260).clipped(); LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom); VStack(alignment: .leading) { Text(title).font(.largeTitle.bold()); Text(subtitle) }.foregroundStyle(.white).padding(20) }.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)) } }
struct ModulaMetadataRail: View { var values: [(String, String)]; var body: some View { HStack { ForEach(Array(values.enumerated()), id: \.offset) { _, value in ModulaMetric(value: value.0, label: value.1); Spacer() } }.padding(.vertical, 8) } }
