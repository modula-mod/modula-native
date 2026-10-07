import SwiftUI
import UIKit

// MARK: - Modula Effect Kit
//
// Reusable motion + shader effects layered on the design system. Rules every
// effect follows:
// - Reduce Motion (system, or Settings → Battery & Data → Extra motion reduction)
//   freezes shaders on a static frame and removes positional/scale motion.
// - Reduce Transparency removes blur glows and translucent layers.
// - Animated shaders pause when scrolled off-screen or when the app is inactive.
// - Shaders are single-pass (see ModulaEffectKit.metal) to hold 60/120 fps.

enum ModulaEffectGate {
    /// System Reduce Motion or Modula's extra motion reduction.
    static func reduceMotion(_ system: Bool) -> Bool {
        system || ModulaPreferences.extraMotionReduction
    }
}

// MARK: Clock

/// Drives an animated effect. Pauses off-screen (scroll visibility), while the
/// scene is inactive, or when `isActive` is false; `staticTime` freezes it.
struct ModulaEffectClock<Content: View>: View {
    var isActive: Bool
    var fps: Double = 60
    var staticTime: Float? = nil
    @ViewBuilder var content: (Float) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = true

    var body: some View {
        let running = isActive && visible && scenePhase == .active && staticTime == nil
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !running)) { context in
            content(staticTime ?? ModulaSurfaceClock.seconds(context.date))
        }
        .onScrollVisibilityChange(threshold: 0.02) { visible = $0 }
    }
}

// MARK: Colour helpers

extension Color {
    /// Shift hue / saturation / brightness (used to derive a second aurora tint).
    func modulaAdjusted(hue: Double = 0, saturation: Double = 1, brightness: Double = 1) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        var nh = h + CGFloat(hue)
        nh -= floor(nh)
        return Color(
            hue: Double(nh),
            saturation: Double(min(max(s * CGFloat(saturation), 0), 1)),
            brightness: Double(min(max(b * CGFloat(brightness), 0), 1)),
            opacity: Double(a)
        )
    }
}

/// Dominant colour of an image (real avatar pixels), boosted so it reads as a tint.
enum ModulaImageTint {
    @MainActor private static var cache: [String: Color] = [:]

    @MainActor static func cached(_ key: String) -> Color? { cache[key] }

    /// Loads (through the shared image pipeline) and averages the image at `url`.
    @MainActor static func tint(for url: URL, cacheKey: String, client: GreenfieldClient) async -> Color? {
        if let hit = cache[cacheKey] { return hit }
        guard let data = try? await client.mediaData(from: url, maximumBytes: 8_000_000) else { return nil }
        let rgb = await Task.detached(priority: .utility) { () -> (Double, Double, Double)? in
            guard let image = ModulaRemoteImageDecoder.downsample(data: data, maximumPixelSize: 48),
                  let cg = image.cgImage else { return nil }
            return averageRGB(cg)
        }.value
        guard let rgb else { return nil }
        let colour = Color(red: rgb.0, green: rgb.1, blue: rgb.2).modulaAdjusted(saturation: 1.35, brightness: 1.1)
        cache[cacheKey] = colour
        return colour
    }

    nonisolated static func averageRGB(_ image: CGImage) -> (Double, Double, Double)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = max(Double(pixel[3]) / 255, 0.001)
        return (Double(pixel[0]) / 255 / alpha, Double(pixel[1]) / 255 / alpha, Double(pixel[2]) / 255 / alpha)
    }
}

// MARK: Aurora background (Metal)

/// Animated aurora / mesh gradient tinted from one or two colours.
struct ModulaAuroraBackground: View {
    var tint: Color
    var secondary: Color? = nil
    var intensity: Double = 0.85
    var isActive = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let tintA = tint
        let tintB = secondary ?? tint.modulaAdjusted(hue: 0.11, saturation: 1.1, brightness: 0.95)
        let base: Color = scheme == .dark ? Color(red: 0.03, green: 0.03, blue: 0.045) : Color(red: 0.96, green: 0.96, blue: 0.975)
        let amount = Float(scheme == .dark ? intensity : intensity * 0.6)
        ModulaEffectClock(isActive: isActive && !reduce, fps: 30, staticTime: reduce ? 6.5 : nil) { time in
            Rectangle()
                .fill(Color.white)
                .visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.modulaAurora(
                            .float2(proxy.size),
                            .float(time),
                            .color(tintA),
                            .color(tintB),
                            .color(base),
                            .float(amount)
                        )
                    )
                }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: Shimmer (skeletons)

struct ModulaShimmerModifier: ViewModifier {
    var isActive: Bool
    var strength: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let amount = Float(strength * (scheme == .dark ? 0.10 : 0.22))
        if !isActive {
            content
        } else if reduce {
            // Static skeleton: no sweep, a single gentle opacity breath is still motion,
            // so stay fully static.
            content
        } else {
            ModulaEffectClock(isActive: true, fps: 60) { time in
                content.visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.modulaShimmer(.float2(proxy.size), .float(time), .float(amount))
                    )
                }
            }
        }
    }
}

// MARK: Press style (spring + haptic)

/// Spring press for tappable cards/buttons: scale, slight dim, haptic on touch-down.
struct ModulaPressStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    var haptic: HapticSemantic? = .selection
    var tilt: Bool = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduce ? scale : 1)
            .rotation3DEffect(
                .degrees(pressed && tilt && !reduce ? 4 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: 0.6
            )
            .brightness(pressed ? -0.035 : 0)
            .animation(reduce ? nil : .spring(response: 0.2, dampingFraction: 0.66), value: pressed)
            .onChange(of: pressed) { _, isPressed in
                if isPressed, let haptic { HapticEngine.shared.play(haptic) }
            }
    }
}

extension ButtonStyle where Self == ModulaPressStyle {
    static var modulaPress: ModulaPressStyle { ModulaPressStyle() }
    static var modulaPressTilt: ModulaPressStyle { ModulaPressStyle(scale: 0.975, tilt: true) }
}

// MARK: Scroll transitions

struct ModulaScrollRevealModifier: ViewModifier {
    var depth: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        if ModulaEffectGate.reduceMotion(systemReduceMotion) {
            content
        } else {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: phase.value < 0 ? .bottom : .top)
                    .rotation3DEffect(
                        .degrees(depth ? phase.value * -7 : 0),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.5
                    )
            }
        }
    }
}

struct ModulaCarouselRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        if ModulaEffectGate.reduceMotion(systemReduceMotion) {
            content
        } else {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view
                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                    .opacity(phase.isIdentity ? 1 : 0.7)
            }
        }
    }
}

// MARK: Specular highlight that follows the scroll position (shader)

struct ModulaScrollSpecularModifier: ViewModifier {
    var strength: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if ModulaEffectGate.reduceMotion(systemReduceMotion) || reduceTransparency {
            content
        } else {
            let amount = Float(strength)
            content.visualEffect { view, proxy in
                let frame = proxy.frame(in: .scrollView)
                let bounds = proxy.bounds(of: .scrollView) ?? CGRect(x: 0, y: 0, width: 1, height: 900)
                let progress = Float(min(max((frame.midY - bounds.minY) / max(bounds.height, 1), 0), 1))
                return view.colorEffect(
                    ShaderLibrary.modulaSpecular(
                        .float2(proxy.size),
                        .float2(0.2 + 0.6 * (1 - progress), 0.05 + 0.5 * progress),
                        .float(amount)
                    )
                )
            }
        }
    }
}

// MARK: Glow ring (avatar)

/// Rotating angular-gradient ring with a soft bloom, tinted. Static under Reduce
/// Motion; no blur bloom under Reduce Transparency.
struct ModulaGlowRing: View {
    var tint: Color
    var lineWidth: CGFloat = 3
    var glow: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let colours = [
            tint,
            tint.modulaAdjusted(hue: 0.08, brightness: 1.2),
            Color.white.opacity(0.85),
            tint.modulaAdjusted(hue: -0.07),
            tint
        ]
        ModulaEffectClock(isActive: !reduce, fps: 60, staticTime: reduce ? 0 : nil) { time in
            let angle = Angle.degrees(Double(time).truncatingRemainder(dividingBy: 6) * 60)
            ZStack {
                if glow && !reduceTransparency {
                    Circle()
                        .strokeBorder(AngularGradient(colors: colours, center: .center, angle: angle), lineWidth: lineWidth * 2.2)
                        .blur(radius: 10)
                        .opacity(0.75)
                }
                Circle()
                    .strokeBorder(AngularGradient(colors: colours, center: .center, angle: angle), lineWidth: lineWidth)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: Animated counter

/// Counts up from 0 to `value` on first appearance (digits roll via numericText),
/// then rolls to new values on change. Shows the final value under Reduce Motion.
struct ModulaCountUpText: View {
    var value: Int
    var format: (Int) -> String
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown: Int?

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let current = reduce ? value : (shown ?? 0)
        Text(format(current))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(current)))
            .task(id: value) {
                guard !reduce else { return }
                let start = shown ?? 0
                guard start != value else { shown = value; return }
                let steps = min(max(abs(value - start), 1), 18)
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    let eased = 1 - pow(1 - t, 3)
                    withAnimation(.snappy(duration: 0.12)) {
                        shown = start + Int((Double(value - start) * eased).rounded())
                    }
                    try? await Task.sleep(for: .milliseconds(40))
                    if Task.isCancelled { return }
                }
                shown = value
            }
    }
}

// MARK: Segmented tabs with matched-geometry indicator

struct ModulaEffectTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    var title: (Tab) -> String
    var symbol: (Tab) -> String
    var tint: Color
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var bounce = 0

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let selected = tab == selection
                Button {
                    guard tab != selection else { return }
                    withAnimation(reduce ? nil : .spring(response: 0.36, dampingFraction: 0.78)) { selection = tab }
                    bounce += 1
                    HapticEngine.shared.play(.selection)
                } label: {
                    Label(title(tab), systemImage: symbol(tab))
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .symbolEffect(.bounce, value: selected && !reduce ? bounce : 0)
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(tint.gradient)
                                    .shadow(color: reduceTransparency ? .clear : tint.opacity(0.45), radius: 10, y: 4)
                                    .matchedGeometryEffect(id: "modula.tab.indicator", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule().fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: Empty state with a living symbol

struct ModulaEffectSymbol: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 46
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        ZStack {
            if !reduceTransparency {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.32), tint.opacity(0)], center: .center, startRadius: 2, endRadius: size * 1.1))
                    .frame(width: size * 2.2, height: size * 2.2)
            }
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint.gradient)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.breathe.pulse, options: .repeating, isActive: !reduce)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Page entrance

struct ModulaPageEntranceModifier: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduce ? nil : .spring(response: 0.5, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

// MARK: Public modifiers

extension View {
    /// Shader shimmer for loading skeletons. Static under Reduce Motion.
    func modulaShimmer(_ isActive: Bool = true, strength: Double = 1) -> some View {
        modifier(ModulaShimmerModifier(isActive: isActive, strength: strength))
    }

    /// Cards ease in/out as they cross the scroll edges (.scrollTransition).
    func modulaScrollReveal(depth: Bool = false) -> some View {
        modifier(ModulaScrollRevealModifier(depth: depth))
    }

    /// Horizontal rails: items shrink slightly away from the centre.
    func modulaCarouselReveal() -> some View {
        modifier(ModulaCarouselRevealModifier())
    }

    /// Light spot that slides across the card as it scrolls (Metal).
    func modulaScrollSpecular(strength: Double = 1) -> some View {
        modifier(ModulaScrollSpecularModifier(strength: strength))
    }

    /// One-time fade + rise when a page or section first appears.
    func modulaPageEntrance(delay: Double = 0) -> some View {
        modifier(ModulaPageEntranceModifier(delay: delay))
    }
}
