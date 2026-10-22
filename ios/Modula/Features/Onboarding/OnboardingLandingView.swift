import SwiftUI
import UIKit

/// First screen a signed-out user sees: a continuous stream of Liquid Glass bubbles
/// (Modula's modules) flowing out of a central glass "+" and floating up off the
/// screen over a slowly living mesh-gradient backdrop, one headline and a "Let's go"
/// button.
///
/// - Module bubbles and the + are real Liquid Glass (`glassEffect`), each its own lens,
///   so they refract the backdrop. Newborn bubbles are first seen through the +'s glass,
///   then pop out of its top. Tiny droplets, where glass refraction is invisible, are
///   drawn in one `Canvas` behind the glass (cheap, and the glass still bends them).
/// - Motion comes from the stateless `OnboardingLanding.Emitter`; the backdrop from
///   `OnboardingLanding.Backdrop`. Both are pure functions of time driven by
///   `TimelineView`, so motion is continuous and frame-rate independent.
/// - Bubbles live in a fixed pool of `Emitter.poolSize` slots (stable identity,
///   recycled in place, ordered with `zIndex`), so spawning and recycling never
///   insert or remove views.
/// - Follows the system appearance: a dark ink backdrop in dark mode, a bright airy one
///   in light mode.
/// - Reduce Motion: one composed, frozen frame. Reduce Transparency: solid bubbles.
///   Before iOS 26: material bubbles with a drawn glass rim.
struct OnboardingLandingView: View {
    var onContinue: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var startDate = Date()
    @State private var entrance = Entrance()
    @State private var drag: CGSize = .zero
    @State private var continuing = false

    /// Entrance choreography: backdrop, then the +, then the stream, then the copy.
    private struct Entrance {
        var backdrop = false
        var plus = false
        var stream = false
        var headline = false
        var button = false
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        // Only the drawn layers live inside the per-frame TimelineViews. The drag gesture, the
        // "Let's go" button and the accessibility tree sit outside them, so their closures are built
        // when state changes, not on every display-link tick. Rebuilding gesture/button closures at
        // frame rate (even while the landing is covered by another presentation) let SwiftUI destroy
        // a closure context that was already freed (MOL-02 stability track, EXC_BAD_ACCESS in
        // __swift_closure_destructor for `dragGesture` / `continueButton`).
        ZStack {
            TimelineView(.animation(paused: reduceMotion)) { context in
                LandingBackdrop(time: time(at: context.date), isDark: isDark)
                    .opacity(entrance.backdrop ? 1 : 0)
            }
            VStack(spacing: 0) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .top)
                copy
            }
        }
        .background(Color(hex: isDark ? "#030608" : "#F6F8FF").ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.landing")
        .onAppear {
            #if DEBUG
            LandingFrameProbe.startIfRequested()
            #endif
            playEntrance()
        }
    }

    private func time(at date: Date) -> Double {
        reduceMotion
            ? OnboardingLanding.staticTime
            : date.timeIntervalSince(startDate) + OnboardingLanding.warmUp
    }

    private func playEntrance() {
        startDate = Date()
        if reduceMotion {
            entrance = Entrance(backdrop: true, plus: true, stream: true, headline: true, button: true)
            return
        }
        withAnimation(.easeOut(duration: 0.8)) { entrance.backdrop = true }
        withAnimation(.spring(duration: 0.55, bounce: 0.45).delay(0.1)) { entrance.plus = true }
        withAnimation(.easeOut(duration: 0.7).delay(0.25)) { entrance.stream = true }
        withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.4)) { entrance.headline = true }
        withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.55)) { entrance.button = true }
    }

    // MARK: Stage

    private var stage: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            stageFrame(time: time(at: context.date))
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingLanding.accessibilitySummary)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("onboarding.landing.cluster")
    }

    private func stageFrame(time: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, 560) / 390
            let origin = CGPoint(x: size.width / 2, y: size.height - 86 * unit)
            let emitter = OnboardingLanding.Emitter(rise: Double(origin.y / unit) + 140)
            let pulse = reduceMotion ? 0 : emitter.emitPulse(at: time)
            let breath = reduceMotion ? 0 : OnboardingLanding.Emitter.breath(at: time)
            let frame = frameBubbles(emitter: emitter, time: time, origin: origin, unit: unit)
            let plusDiameter = 108 * unit * (1 + 0.05 * pulse + 0.015 * breath)
            ZStack {
                // Light pooling behind the + for the glass to bend; flares with each emission.
                PlusGlow(diameter: 108 * unit, pulse: pulse, breath: breath, isDark: isDark)
                    .position(origin)
                    .opacity(entrance.plus ? 1 : 0)
                GlassStream(
                    slots: frame.slots,
                    droplets: frame.droplets,
                    plusCenter: origin,
                    plusDiameter: plusDiameter * (entrance.plus ? 1 : 0.55),
                    plusOpacity: entrance.plus ? 1 : 0,
                    streamOpacity: entrance.stream ? 1 : 0,
                    isDark: isDark
                )
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// This frame's module bubbles in their fixed pool slots (nil = idle slot) and the
    /// visible droplets, all in screen space.
    private func frameBubbles(
        emitter: OnboardingLanding.Emitter,
        time: Double,
        origin: CGPoint,
        unit: CGFloat
    ) -> (slots: [Bubble?], droplets: [Bubble]) {
        var slots = [Bubble?](repeating: nil, count: OnboardingLanding.Emitter.poolSize)
        var droplets: [Bubble] = []
        droplets.reserveCapacity(16)
        let dragX = band(drag.width), dragY = band(drag.height)
        for index in emitter.liveRange(at: time) {
            let particle = emitter.particle(index)
            guard let state = emitter.state(of: particle, at: time), state.opacity > 0.005 else { continue }
            let parallax = 0.3 + 0.7 * particle.depth
            let center = CGPoint(
                x: origin.x + (state.position.x + dragX * parallax) * unit,
                y: origin.y + (state.position.y + dragY * parallax) * unit
            )
            guard center.y > -particle.diameter * unit else { continue }
            let bubble = Bubble(
                particle: particle,
                state: state,
                age: time - particle.spawnTime,
                center: center,
                diameter: particle.diameter * unit
            )
            if particle.kind == .droplet {
                droplets.append(bubble)
            } else {
                slots[OnboardingLanding.Emitter.slot(for: index)] = bubble
            }
        }
        return (slots, droplets)
    }

    /// Rubber-banded drag translation (reference points).
    private func band(_ value: CGFloat) -> Double {
        let limit = 50.0
        return limit * tanh(Double(value) / (limit * 2.4))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !reduceMotion else { return }
                drag = value.translation
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.4)) { drag = .zero }
            }
    }

    // MARK: Copy and action

    private var copy: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 28) {
            Text(OnboardingLanding.headline)
                .font(.system(.largeTitle, design: app.appearance.fontDesign).weight(isDark ? .light : .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: isDark ? "#FFFFFF" : "#0B1220"))
                .shadow(color: isDark ? .black.opacity(0.35) : .white.opacity(0.6), radius: 12, y: 2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.75 : 1)
                .opacity(entrance.headline ? 1 : 0)
                .offset(y: entrance.headline ? 0 : 18)
                .blur(radius: entrance.headline ? 0 : 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.landing.headline")
            continueButton
                .opacity(entrance.button ? 1 : 0)
                .offset(y: entrance.button ? 0 : 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .layoutPriority(1)
    }

    private var continueButton: some View {
        Button {
            guard !continuing else { return }
            continuing = true
            HapticEngine.shared.play(.confirmation)
            onContinue()
        } label: {
            Text(OnboardingLanding.continueTitle)
                .font(.system(.headline, design: app.appearance.fontDesign))
                .foregroundStyle(Color(hex: isDark ? "#071C20" : "#FFFFFF"))
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Capsule())
        }
        .modifier(LandingButtonStyle(isDark: isDark))
        .accessibilityHint("Continues to sign in")
        .accessibilityIdentifier("onboarding.landing.continue")
    }
}

/// "Let's go": a prominent glass capsule on iOS 26 (bright in dark mode, deep ink in
/// light mode), a solid pill before.
private struct LandingButtonStyle: ViewModifier {
    let isDark: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(LandingInk.button(isDark))
                .shadow(color: isDark ? .white.opacity(0.14) : Color(hex: "#3A3FA8").opacity(0.22), radius: 22, y: 6)
        } else {
            content.buttonStyle(LandingPillButtonStyle(isDark: isDark))
        }
    }
}

private enum LandingInk {
    static func button(_ isDark: Bool) -> Color { isDark ? .white : Color(hex: "#0F1630") }
}

private struct LandingPillButtonStyle: ButtonStyle {
    let isDark: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(LandingInk.button(isDark)))
            .shadow(color: isDark ? .white.opacity(0.12) : .black.opacity(0.15), radius: 18, y: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Backdrop

/// The living backdrop the glass refracts: a drifting mesh gradient in Modula's palette
/// (dark ink or bright and airy), soft aurora light, slowly rising motes and film grain.
/// The bottom is kept calm for the headline and button.
private struct LandingBackdrop: View {
    var time: Double
    var isDark: Bool

    private static let darkColors: [Color] = OnboardingLanding.Backdrop.colors.map { Color(hex: $0) }
    private static let lightColors: [Color] = OnboardingLanding.Backdrop.lightColors.map { Color(hex: $0) }

    var body: some View {
        ZStack {
            MeshGradient(
                width: OnboardingLanding.Backdrop.width,
                height: OnboardingLanding.Backdrop.height,
                points: OnboardingLanding.Backdrop.points(at: time),
                colors: isDark ? Self.darkColors : Self.lightColors
            )
            Aurora(time: time, isDark: isDark)
                .blendMode(isDark ? .screen : .normal)
            Motes(time: time, isDark: isDark)
            LinearGradient(stops: scrim, startPoint: .top, endPoint: .bottom)
            Grain()
                .opacity(isDark ? 1 : 0.6)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scrim: [Gradient.Stop] {
        let ink: Color = isDark ? .black : .white
        return [
            .init(color: ink.opacity(isDark ? 0.35 : 0.3), location: 0),
            .init(color: ink.opacity(0), location: 0.22),
            .init(color: ink.opacity(0), location: 0.58),
            .init(color: ink.opacity(isDark ? 0.78 : 0.62), location: 0.86),
            .init(color: ink.opacity(isDark ? 0.9 : 0.8), location: 1),
        ]
    }
}

/// Three soft, slowly swaying light fields. Each is a radial gradient that fades to
/// clear inside its own frame, squashed into an ellipse, so no per-frame blur is needed.
private struct Aurora: View {
    var time: Double
    var isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                field(isDark ? "#3BE3D0" : "#3CCFC0", isDark ? 0.30 : 0.30, radius: w * 0.62, squash: 0.42,
                      angle: -24 + 7 * sin(time * 0.13),
                      at: CGPoint(x: w * (0.32 + 0.08 * sin(time * 0.07)), y: h * (0.36 + 0.04 * cos(time * 0.09))))
                field(isDark ? "#B05CFF" : "#B47CFF", isDark ? 0.26 : 0.26, radius: w * 0.56, squash: 0.42,
                      angle: 28 + 6 * cos(time * 0.11),
                      at: CGPoint(x: w * (0.72 + 0.07 * cos(time * 0.06)), y: h * (0.2 + 0.05 * sin(time * 0.08))))
                field(isDark ? "#4F7BFF" : "#FF8FC7", isDark ? 0.22 : 0.2, radius: w * 0.5, squash: 0.45,
                      angle: -8 + 5 * sin(time * 0.1),
                      at: CGPoint(x: w * (0.55 + 0.06 * sin(time * 0.05 + 1)), y: h * (0.55 + 0.03 * cos(time * 0.07))))
            }
        }
    }

    private func field(_ hex: String, _ alpha: Double, radius: CGFloat, squash: CGFloat, angle: Double, at point: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: hex).opacity(alpha), Color(hex: hex).opacity(alpha * 0.35), .clear], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(x: 1, y: squash)
            .rotationEffect(.degrees(angle))
            .position(point)
    }
}

/// Tiny drifting points of light; they give the glass detail to bend and lens.
private struct Motes: View {
    var time: Double
    var isDark: Bool

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: 0x6D6F_7465)
            let core: Color = isDark ? .white : Color(hex: "#5A63D8")
            let haloColor = Color(hex: isDark ? "#9FE8FF" : "#8A7CFF")
            for _ in 0..<90 {
                let x0 = rng.unit(), y0 = rng.unit()
                let speed = 0.004 + 0.012 * rng.unit()
                let radius = 0.5 + 1.6 * pow(rng.unit(), 2)
                let phase = rng.unit() * 2 * .pi
                let twinkle = 0.55 + 0.45 * sin(time * (0.6 + rng.unit()) + phase)
                let y = (y0 - time * speed).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(
                    x: (x0 + 0.01 * sin(time * 0.3 + phase)) * size.width,
                    y: (y < 0 ? y + 1 : y) * size.height
                )
                let fadeLow = 1 - OnboardingLanding.smoothstep(0.62, 0.85, point.y / size.height)
                let alpha = (isDark ? 0.55 : 0.35) * twinkle * fadeLow
                guard alpha > 0.02 else { continue }
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(core.opacity(alpha)))
                if radius > 1.4 {
                    let halo = rect.insetBy(dx: -radius * 2.5, dy: -radius * 2.5)
                    context.fill(Path(ellipseIn: halo), with: .color(haloColor.opacity(alpha * 0.12)))
                }
            }
        }
    }
}

/// Static film grain, tiled.
private struct Grain: View {
    private static let tile: UIImage = {
        let side = 128
        var rng = SplitMix64(seed: 0x6772_6169_6E)
        var pixels = [UInt8](repeating: 0, count: side * side)
        for i in pixels.indices { pixels[i] = UInt8(truncatingIfNeeded: rng.next() >> 56) }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(0.09)
    }
}

// MARK: - Bubbles

private struct Bubble {
    let particle: OnboardingLanding.Particle
    let state: OnboardingLanding.ParticleState
    let age: Double
    let center: CGPoint
    let diameter: CGFloat
}

/// Soft light behind the + that flares with each emission (the glass refracts it).
private struct PlusGlow: View {
    var diameter: CGFloat
    var pulse: Double
    var breath: Double
    var isDark: Bool

    var body: some View {
        let inner = Color(hex: isDark ? "#7FF5E4" : "#5FD9CC")
        let outer = Color(hex: isDark ? "#5B6CFF" : "#8C7CFF")
        Circle()
            .fill(RadialGradient(
                colors: [inner.opacity((isDark ? 0.30 : 0.34) + 0.18 * pulse + 0.04 * breath), outer.opacity(isDark ? 0.12 : 0.16), .clear],
                center: .center,
                startRadius: diameter * 0.1,
                endRadius: diameter * 1.15
            ))
            .frame(width: diameter * 2.4, height: diameter * 2.4)
            .allowsHitTesting(false)
    }
}

/// The + and the stream: real Liquid Glass on iOS 26, fallbacks otherwise.
///
/// The view tree is fixed: one droplet `Canvas`, `poolSize` bubble slots and the +.
/// Draw order comes from `zIndex` (newborns under the +, then far to near), so
/// recycling a slot or re-sorting never changes identity.
private struct GlassStream: View {
    var slots: [Bubble?]
    var droplets: [Bubble]
    var plusCenter: CGPoint
    var plusDiameter: CGFloat
    var plusOpacity: Double
    var streamOpacity: Double
    var isDark: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: BubbleStyle {
        if reduceTransparency { return .solid }
        if #available(iOS 26.0, *) { return .glass }
        return .material
    }

    var body: some View {
        let style = style
        ZStack {
            DropletLayer(droplets: droplets, style: style, isDark: isDark)
                .opacity(streamOpacity)
                .zIndex(-1)
            ForEach(0..<OnboardingLanding.Emitter.poolSize, id: \.self) { slot in
                let bubble = slots[slot]
                BubbleView(bubble: bubble, style: style, isDark: isDark)
                    .opacity(streamOpacity)
                    .zIndex(Self.order(of: bubble))
            }
            PlusView(diameter: plusDiameter, style: style, isDark: isDark)
                .opacity(plusOpacity)
                .position(plusCenter)
                .zIndex(0.95)
        }
        .allowsHitTesting(false)
    }

    /// Newborns (still inside the +) sit under it in 0…0.9; grown bubbles above it in 1…1.9.
    static func order(of bubble: Bubble?) -> Double {
        guard let bubble else { return -2 }
        let base = bubble.age < OnboardingLanding.Emitter.birthWindow ? 0.0 : 1.0
        return base + 0.9 * bubble.particle.depth
    }
}

private enum BubbleStyle {
    /// Liquid Glass (iOS 26).
    case glass
    /// Blurred material with a drawn rim (before iOS 26).
    case material
    /// Opaque (Reduce Transparency).
    case solid
}

/// Tiny clear droplets. At this size glass refraction is invisible, so they are drawn
/// as lit spheres in a single Canvas (behind the glass bubbles, which still bend them)
/// instead of costing a glass pass each.
private struct DropletLayer: View {
    let droplets: [Bubble]
    let style: BubbleStyle
    let isDark: Bool

    var body: some View {
        Canvas { context, _ in
            let rim: Color = isDark ? .white : Color(hex: "#4E5AC8")
            for droplet in droplets {
                let s = droplet.state
                let squash = sqrt(s.stretch)
                let w = droplet.diameter * s.scale / squash
                let h = droplet.diameter * s.scale * squash
                let rect = CGRect(x: droplet.center.x - w / 2, y: droplet.center.y - h / 2, width: w, height: h)
                let alpha = s.opacity
                let body = Path(ellipseIn: rect)
                switch style {
                case .solid:
                    context.fill(body, with: .color(Color(hex: isDark ? "#2A3338" : "#C9D2EE").opacity(alpha)))
                default:
                    context.fill(body, with: .radialGradient(
                        Gradient(colors: [rim.opacity(0.02 * alpha), rim.opacity((isDark ? 0.16 : 0.12) * alpha), rim.opacity((isDark ? 0.5 : 0.38) * alpha)]),
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: 0,
                        endRadius: max(w, h) / 2
                    ))
                    context.stroke(body, with: .color(rim.opacity((isDark ? 0.45 : 0.4) * alpha)), lineWidth: 0.6)
                    let spec = CGRect(x: rect.minX + w * 0.2, y: rect.minY + h * 0.14, width: w * 0.32, height: h * 0.22)
                    context.fill(Path(ellipseIn: spec), with: .color(.white.opacity(0.8 * alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One pooled bubble slot. An idle slot keeps its views but collapses to nothing and
/// goes fully transparent, so the tree never changes shape.
private struct BubbleView: View {
    let bubble: Bubble?
    let style: BubbleStyle
    let isDark: Bool

    var body: some View {
        let state = bubble?.state
        let scale = state?.scale ?? 0
        let squash = sqrt(state?.stretch ?? 1)
        let d = bubble?.diameter ?? 0
        let depth = bubble?.particle.depth ?? 0
        let module = OnboardingLanding.modules[moduleIndex]
        // Liquid Glass follows layout, not render transforms (a `scaleEffect` leaves the
        // glass at full size), so the glass is sized and squashed through its frame;
        // only the non-glass core and symbol use transforms.
        let width = d * scale / squash
        let height = d * scale * squash
        ZStack {
            // A coloured light core *behind* the glass: the glass refracts it, so module
            // bubbles glow with their colour while the glass itself stays clear. For
            // material/solid it sits on top (a fill would hide it).
            core(module: module, d: d, depth: depth)
                .scaleEffect(x: scale / squash, y: scale * squash)
                .opacity(style == .glass ? 1 : 0.75)
                .zIndex(style == .glass ? 0 : 1)
            Color.clear
                .frame(width: width, height: height)
                .modifier(BubbleSurface(tint: module.tint, depth: depth, style: style, blur: state?.blur ?? 0, isDark: isDark))
                .zIndex(0.5)
            // The symbol sits on the glass (outside the effect, so it keeps full vibrancy).
            Image(systemName: module.symbol)
                .font(.system(size: max(1, d * 0.36), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolStyle(module))
                .opacity(0.8 + 0.2 * depth)
                .scaleEffect(scale)
                .rotationEffect(.radians(state?.tilt ?? 0))
                .zIndex(2)
        }
        .frame(width: d, height: d)
        // Translucent glass turns muddy, so glass keeps full opacity except for its
        // birth/exit fades; depth reads through size, speed and symbol strength.
        .opacity(opacity(state: state, depth: depth))
        .position(bubble?.center ?? .zero)
    }

    private var moduleIndex: Int {
        if case .module(let index)? = bubble?.particle.kind { return index }
        return 0
    }

    private func opacity(state: OnboardingLanding.ParticleState?, depth: Double) -> Double {
        guard let state else { return 0 }
        return style == .glass ? state.opacity / (0.6 + 0.4 * depth) : state.opacity
    }

    private func symbolStyle(_ module: OnboardingLanding.Module) -> LinearGradient {
        isDark
            ? LinearGradient(colors: [.white, Color(hex: module.glow)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: module.tint).mix(with: .black, by: 0.25), Color(hex: module.tint)], startPoint: .top, endPoint: .bottom)
    }

    private func core(module: OnboardingLanding.Module, d: CGFloat, depth: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [
                    Color(hex: module.glow).opacity(isDark ? 0.55 : 0.5),
                    Color(hex: module.tint).opacity(isDark ? 0.5 : 0.26),
                    Color(hex: module.tint).opacity(0),
                ],
                center: UnitPoint(x: 0.45, y: 0.6),
                startRadius: 0,
                endRadius: max(1, d * 0.42)
            ))
            .frame(width: d * 0.86, height: d * 0.86)
            .opacity(0.55 + 0.45 * depth)
    }
}

/// The bubble's body for each style.
private struct BubbleSurface: ViewModifier {
    let tint: String
    let depth: Double
    let style: BubbleStyle
    let blur: Double
    let isDark: Bool

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(iOS 26.0, *) {
                content.glassEffect(.clear.tint(Color(hex: tint).opacity((isDark ? 0.10 : 0.14) + 0.14 * depth)), in: Ellipse())
            } else {
                content
            }
        case .material:
            content
                .background(Ellipse().fill(isDark ? .ultraThinMaterial : .thinMaterial))
                .overlay(GlassRim(isDark: isDark))
                .blur(radius: blur)
        case .solid:
            content
                .background(Ellipse().fill(Color(hex: tint).mix(with: isDark ? .black : .white, by: isDark ? 0.55 : 0.7)))
                .overlay(Ellipse().strokeBorder(isDark ? .white.opacity(0.22) : .black.opacity(0.12), lineWidth: 1))
        }
    }
}

/// Drawn glass rim and highlight for the pre-iOS 26 fallback.
private struct GlassRim: View {
    var isDark: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let d = proxy.size.width
            let edge: Color = isDark ? .white : Color(hex: "#3E4AA8")
            ZStack {
                Ellipse()
                    .strokeBorder(
                        AngularGradient(
                            colors: [.white.opacity(0.7), edge.opacity(0.08), edge.opacity(0.35), edge.opacity(0.05), .white.opacity(0.7)],
                            center: .center,
                            angle: .degrees(-130)
                        ),
                        lineWidth: max(0.8, d * 0.02)
                    )
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.42, height: d * 0.18)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -d * 0.16, y: -d * 0.25)
            }
        }
    }
}

/// The glass "+" the stream flows out of.
private struct PlusView: View {
    let diameter: CGFloat
    let style: BubbleStyle
    let isDark: Bool

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: diameter * 0.3, weight: .light))
            .foregroundStyle(isDark ? Color.white.opacity(0.95) : Color(hex: "#0F1630").opacity(0.85))
            .frame(width: diameter, height: diameter)
            .modifier(PlusSurface(style: style, isDark: isDark))
            .accessibilityHidden(true)
    }
}

private struct PlusSurface: ViewModifier {
    let style: BubbleStyle
    let isDark: Bool

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(iOS 26.0, *) {
                content.glassEffect(.clear.tint(.white.opacity(isDark ? 0.04 : 0.12)), in: Circle())
            } else {
                content
            }
        case .material:
            content
                .background(Circle().fill(isDark ? .ultraThinMaterial : .thinMaterial))
                .overlay(GlassRim(isDark: isDark))
        case .solid:
            content
                .background(Circle().fill(Color(hex: isDark ? "#1A2224" : "#E6EAF6")))
                .overlay(Circle().strokeBorder(isDark ? .white.opacity(0.25) : .black.opacity(0.12), lineWidth: 1))
        }
    }
}

#if DEBUG
/// Debug-only frame pacing probe (`--debug-frame-probe`): logs frame rate, hitches
/// (frames longer than 1.5× the target) and the worst frame every 5 seconds.
@MainActor
final class LandingFrameProbe: NSObject {
    static let shared = LandingFrameProbe()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var hitches = 0
    private var worst: CFTimeInterval = 0

    static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--debug-frame-probe"), shared.link == nil else { return }
        let link = CADisplayLink(target: shared, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        shared.link = link
    }

    /// Appends to the file named by `FRAME_PROBE_LOG` (falls back to stderr).
    private static func append(_ line: String) {
        let data = Data(line.utf8)
        if let path = ProcessInfo.processInfo.environment["FRAME_PROBE_LOG"] {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let handle = FileHandle(forWritingAtPath: path) { handle.seekToEndOfFile(); handle.write(data); try? handle.close(); return }
        }
        FileHandle.standardError.write(data)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard last > 0 else { windowStart = now; return }
        let dt = now - last
        let target = max(1.0 / 120, link.targetTimestamp - link.timestamp)
        frames += 1
        if dt > target * 1.5 { hitches += 1 }
        worst = max(worst, dt)
        if now - windowStart >= 5 {
            let fps = Double(frames) / (now - windowStart)
            let line = String(format: "[frame-probe] fps=%.1f hitches=%d worstMs=%.1f targetMs=%.2f", fps, hitches, worst * 1000, target * 1000) + "\n"
            Self.append(line)
            frames = 0; hitches = 0; worst = 0; windowStart = now
        }
    }
}
#endif
