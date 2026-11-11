import SwiftUI

// MARK: - Shared Liquid Glass primitives
//
// One place decides how a floating control is drawn:
// - iOS 26+: real Liquid Glass (`glassEffect`), interactive, morphing inside a
//   `ModulaGlassGroup` (GlassEffectContainer) via `modulaGlassID`.
// - Reduce Transparency, or iOS 18–25: an opaque-enough material with a hairline,
//   so text stays legible and nothing pretends to be glass.

/// Appearance → Glass Intensity. Reduce Transparency always wins (opaque fallback).
enum ModulaGlassIntensity: String, CaseIterable, Identifiable {
    case clear, standard, frosted
    static let storageKey = "modula.appearance.glassIntensity"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clear: "Clear"
        case .standard: "Standard"
        case .frosted: "Frosted"
        }
    }
}

struct ModulaGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

private struct ModulaGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool
    var tint: Color?
    var prominent = false
    var specular = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // One shared observable: an @AppStorage per glass view subscribed every capsule
    // in every feed row to UserDefaults.
    private var intensity: ModulaGlassIntensity { ModulaGlassSettings.shared.intensity }

    func body(content: Content) -> some View {
        if ModulaGlassSettings.shared.lighter {
            // Lighter effects: an opaque fill, no glass sampling, no shadow pass.
            content
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.94), in: shape)
                .background((tint ?? .clear).opacity(prominent ? 0.9 : 0.18), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
        } else if #available(iOS 26.0, *), !reduceTransparency {
            content
                .background {
                    if intensity == .frosted { shape.fill(.thinMaterial) }
                }
                .glassEffect(glass, in: shape)
                .overlay {
                    if specular {
                        // Subtle specular rim: bright top edge fading out, faint shade at the bottom.
                        shape.stroke(
                            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .black.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.8
                        )
                        .allowsHitTesting(false)
                    }
                }
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: shape)
                .background((tint ?? .clear).opacity(prominent ? 0.9 : 0.18), in: shape)
                .overlay(
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(reduceTransparency ? 0 : 0.5), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.7
                    )
                )
                .shadow(color: .black.opacity(prominent ? 0.14 : 0.06), radius: prominent ? 6 : 4, y: 2)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var value = intensity == .clear ? Glass.clear : Glass.regular
        if let tint { value = value.tint(prominent ? tint : tint.opacity(0.55)) }
        return interactive ? value.interactive() : value
    }
}

private struct ModulaGlassIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: true)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 (material fallback when unavailable or with Reduce Transparency).
    func modulaGlass<S: Shape>(in shape: S, interactive: Bool = true, tint: Color? = nil, prominent: Bool = false, specular: Bool = false) -> some View {
        modifier(ModulaGlassModifier(shape: shape, interactive: interactive, tint: tint, prominent: prominent, specular: specular))
    }

    /// Identity for glass morphing between states inside a `ModulaGlassGroup`.
    func modulaGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(ModulaGlassIDModifier(id: id, namespace: namespace))
    }
}

/// Round Liquid Glass icon button (attach, mic, close, reload…).
struct ModulaGlassIconButton: View {
    let title: String
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color? = nil
    var foreground: Color = .primary
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), tint: tint, specular: true)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }
}

/// Tinted, interactive Liquid Glass send button. Prominent (full accent tint, white glyph) when
/// `ready`; plain glass otherwise. Pair with `modulaGlassID` inside a `ModulaGlassGroup` to morph.
struct ModulaGlassSendButton: View {
    var title = "Send"
    var systemImage = "arrow.up"
    var ready: Bool
    var busy = false
    var size: CGFloat = 44
    var tint: Color = .accentColor
    var action: () -> Void

    var body: some View {
        // Visible disc is smaller than the 44pt touch target; no glow ring or scale-up.
        let disc = min(size, 44) * 0.8
        let active = ready || busy
        let ink = active ? Self.ink(on: tint) : Color.secondary
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .frame(width: disc, height: disc)
                if busy {
                    ProgressView().controlSize(.small).tint(ink)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: disc * 0.46, weight: .bold))
                        .foregroundStyle(ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!ready && !busy)
        .animation(.snappy(duration: 0.18), value: active)
        .accessibilityLabel(busy ? "Sending" : title)
    }

    private static func ink(on color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.62 ? .black : .white
    }
}

/// Liquid Glass search field used by every custom search bar.
struct ModulaGlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .modulaGlass(in: Capsule())
    }
}

// MARK: - Shared filled accent CTA
//
// One style for every primary/filled call to action: a solid fill in the user's live accent
// (custom or preset) with white text, so the single strongest action on a screen always looks
// the same (Von Restorff). On iOS 26 the fill stays fully opaque with a thin specular glass rim
// (tinted Liquid Glass over the fill read as a washed-out, disabled-looking pastel on device);
// with Reduce Transparency or on iOS 18–25 it is a plain solid capsule.
private struct ModulaAccentCTAModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(AppEnvironment.self) private var app
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let accent = app.appearance.liveAccent
        let styled = content
            .foregroundStyle(isEnabled ? Color.white : accent)
            .tint(isEnabled ? .white : accent)
        if !isEnabled {
            // Inactive (e.g. "You're on Horizon"): accent outline, never a washed-out fill.
            styled
                .background(accent.opacity(0.10), in: shape)
                .overlay(shape.strokeBorder(accent.opacity(contrast == .increased ? 1 : 0.6), lineWidth: 1.2))
        } else if !reduceTransparency {
            styled
                .background(shape.fill(accent))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8
                    )
                    .allowsHitTesting(false)
                )
                .shadow(color: accent.opacity(0.28), radius: GeneratedDesignContract.Elevation.medium.radius, y: GeneratedDesignContract.Elevation.medium.y)
        } else {
            styled
                .background(shape.fill(accent))
                .shadow(color: accent.opacity(0.28), radius: GeneratedDesignContract.Elevation.medium.radius, y: GeneratedDesignContract.Elevation.medium.y)
        }
    }
}

extension View {
    /// The one filled accent CTA used app-wide.
    func modulaAccentCTA() -> some View { modifier(ModulaAccentCTAModifier(shape: Capsule())) }
    func modulaAccentCTA<S: InsettableShape>(in shape: S) -> some View { modifier(ModulaAccentCTAModifier(shape: shape)) }
}


/// Glass intensity + Lighter effects, read once and shared by every glass surface.
@MainActor @Observable
final class ModulaGlassSettings {
    static let shared = ModulaGlassSettings()
    private(set) var intensity: ModulaGlassIntensity = .standard
    private(set) var lighter = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        read()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ModulaGlassSettings.shared.read() }
        }
    }

    func read() {
        let defaults = UserDefaults.standard
        let nextIntensity = ModulaGlassIntensity(rawValue: defaults.string(forKey: ModulaGlassIntensity.storageKey) ?? "") ?? .standard
        if nextIntensity != intensity { intensity = nextIntensity }
        let nextLighter = defaults.bool(forKey: "settings.battery.reduceMotionExtra")
        if nextLighter != lighter { lighter = nextLighter }
    }
}
