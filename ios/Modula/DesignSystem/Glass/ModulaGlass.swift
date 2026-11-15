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
// MARK: - Shared button styles (t169u)
//
// Primary   = solid black (light) / solid white (dark), inverted label. Never the accent.
// Secondary = neutral Liquid Glass, primary-colour label.
// Coral is reserved for notification badges. `scripts/verify-boundaries.py` and
// `ModulaComponentUnificationTests` fail on accent-tinted buttons and bespoke segmented controls.

extension Color {
    /// Primary action fill: black in light mode, white in dark mode.
    static var modulaPrimaryFill: Color { Color(uiColor: .label) }
    /// Label on a primary fill (inverse of `modulaPrimaryFill`).
    static var modulaOnPrimary: Color { Color(uiColor: .systemBackground) }
}

enum ModulaButtonShape: Sendable {
    case capsule, circle, rounded(CGFloat)

    var shape: AnyShape {
        switch self {
        case .capsule: AnyShape(Capsule())
        case .circle: AnyShape(Circle())
        case .rounded(let r): AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }
}

struct ModulaPrimaryButtonStyle: ButtonStyle {
    var shape: ModulaButtonShape = .capsule
    var fullWidth = false
    var haptic: HapticSemantic? = .lightImpact

    func makeBody(configuration: Configuration) -> some View {
        ModulaPrimaryLabel(configuration: configuration, shape: shape, fullWidth: fullWidth, haptic: haptic)
    }
}

private struct ModulaPrimaryLabel: View {
    let configuration: ButtonStyleConfiguration
    let shape: ModulaButtonShape
    let fullWidth: Bool
    let haptic: HapticSemantic?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .modulaPrimaryCTA(in: shape.shape)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, isEnabled, let haptic { HapticEngine.shared.play(haptic) }
            }
    }
}

struct ModulaSecondaryButtonStyle: ButtonStyle {
    var shape: ModulaButtonShape = .capsule
    var fullWidth = false
    var haptic: HapticSemantic? = .selection

    func makeBody(configuration: Configuration) -> some View {
        ModulaSecondaryLabel(configuration: configuration, shape: shape, fullWidth: fullWidth, haptic: haptic)
    }
}

private struct ModulaSecondaryLabel: View {
    let configuration: ButtonStyleConfiguration
    let shape: ModulaButtonShape
    let fullWidth: Bool
    let haptic: HapticSemantic?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .tint(.primary)
            .padding(.horizontal, { if case .circle = shape { return 0 } else { return 16 } }())
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 36)
            .contentShape(shape.shape)
            .modulaGlass(in: shape.shape, interactive: true)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, isEnabled, let haptic { HapticEngine.shared.play(haptic) }
            }
    }
}

extension ButtonStyle where Self == ModulaPrimaryButtonStyle {
    static var modulaPrimary: ModulaPrimaryButtonStyle { ModulaPrimaryButtonStyle() }
    static var modulaPrimaryWide: ModulaPrimaryButtonStyle { ModulaPrimaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == ModulaSecondaryButtonStyle {
    static var modulaSecondary: ModulaSecondaryButtonStyle { ModulaSecondaryButtonStyle() }
    static var modulaSecondaryWide: ModulaSecondaryButtonStyle { ModulaSecondaryButtonStyle(fullWidth: true) }
}

/// Surface for a primary action drawn by hand (custom label layouts): solid label-colour fill,
/// inverted foreground. Disabled = neutral outline (never washed-out, never accent).
private struct ModulaPrimaryCTAModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if !isEnabled {
            content
                .foregroundStyle(Color.secondary)
                .tint(Color.secondary)
                .background(Color.primary.opacity(0.06), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(contrast == .increased ? 0.6 : 0.25), lineWidth: 1))
        } else {
            content
                .foregroundStyle(Color.modulaOnPrimary)
                .tint(Color.modulaOnPrimary)
                .background(shape.fill(Color.modulaPrimaryFill))
                .shadow(color: .black.opacity(0.12), radius: GeneratedDesignContract.Elevation.medium.radius, y: GeneratedDesignContract.Elevation.medium.y)
        }
    }
}

extension View {
    /// The one filled primary CTA (black / white). Replaces the retired accent CTA.
    func modulaPrimaryCTA() -> some View { modifier(ModulaPrimaryCTAModifier(shape: Capsule())) }
    func modulaPrimaryCTA<S: Shape>(in shape: S) -> some View { modifier(ModulaPrimaryCTAModifier(shape: shape)) }
}


/// Glass intensity + Lighter effects, read once and shared by every glass surface.
@MainActor @Observable
final class ModulaGlassSettings {
    static let shared = ModulaGlassSettings()
    private(set) var intensity: ModulaGlassIntensity = .standard
    private(set) var lighter = false
    private(set) var glassBubbles = false
    static let glassBubblesKey = "messages.glassBubbles"
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []

    private init() {
        read()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ModulaGlassSettings.shared.read() }
        }
        // Speed: Low Power Mode or a serious/critical thermal state switch glass to the opaque
        // "lighter" path automatically (live blur is the most expensive thing we draw while scrolling).
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            systemObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ModulaGlassSettings.shared.read() }
            })
        }
    }

    /// Glass is thinned by the system, not the user: Low Power Mode or thermal pressure.
    var systemConstrained: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    func read() {
        let defaults = UserDefaults.standard
        let nextIntensity = ModulaGlassIntensity(rawValue: defaults.string(forKey: ModulaGlassIntensity.storageKey) ?? "") ?? .standard
        if nextIntensity != intensity { intensity = nextIntensity }
        let nextLighter = defaults.bool(forKey: "settings.battery.reduceMotionExtra") || systemConstrained
        if nextLighter != lighter { lighter = nextLighter }
        let nextBubbles = defaults.bool(forKey: Self.glassBubblesKey)
        if nextBubbles != glassBubbles { glassBubbles = nextBubbles }
    }
}


// MARK: - Sheets

/// Sheet background: on iOS 26 leave the system Liquid Glass sheet alone (partial detents float as glass,
/// large detents go opaque on their own). Reduce Transparency or older systems get `fallback`.
private struct ModulaGlassPresentation: ViewModifier {
    var fallback: AnyShapeStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, !ModulaGlassSettings.shared.lighter {
            content
        } else if reduceTransparency {
            content.presentationBackground(Color(uiColor: .systemBackground))
        } else {
            content.presentationBackground(fallback)
        }
    }
}

/// t169u — the ONE drawer/sheet style. Every bottom sheet uses the system (concentric) corner radius,
/// a visible grabber, scroll-first content interaction and the shared Liquid Glass background
/// (opaque under Reduce Transparency). Do not set `presentationCornerRadius` / `presentationBackground`
/// / `presentationDragIndicator` at call sites; `verify-boundaries.py` flags them.
struct ModulaSheetChrome: ViewModifier {
    var dragIndicator: Visibility = .visible

    func body(content: Content) -> some View {
        content
            .presentationDragIndicator(dragIndicator)
            .presentationContentInteraction(.scrolls)
            .modulaGlassPresentation()
            // Instruments: SheetOpen = the presenting tap's "Mark"/hitch → this event; see PERF_PLAN.md.
            .onAppear { ModulaSignpost.event("SheetOpen") }
            .onDisappear { ModulaSignpost.event("SheetClose") }
    }
}

extension View {
    /// Apply after `.presentationDetents(...)` on any sheet root.
    func modulaSheetStyle(dragIndicator: Visibility = .visible) -> some View {
        modifier(ModulaSheetChrome(dragIndicator: dragIndicator))
    }
}

extension View {
    func modulaGlassPresentation(fallback: some ShapeStyle = .regularMaterial) -> some View {
        modifier(ModulaGlassPresentation(fallback: AnyShapeStyle(fallback)))
    }
}
