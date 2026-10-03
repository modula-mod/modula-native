import SwiftUI
import UIKit

/// First screen a signed-out user sees: a continuous stream of Liquid Glass bubbles
/// (Modula's modules) flowing out of a central glass "+" and floating up off the
/// screen over a slowly living mesh-gradient backdrop, one headline and a "Let's go"
/// button.
///
/// - Every bubble, the + and the tiny droplets are real Liquid Glass (`glassEffect`),
///   each its own lens, so they refract the backdrop and each other. Newborn bubbles
///   are first seen through the +'s glass, then pop out of its top. Module identity
///   (an SF Symbol, a faint tint) sits inside the glass.
/// - Motion comes from the stateless `OnboardingLanding.Emitter`; the backdrop from
///   `OnboardingLanding.Backdrop`. Both are pure functions of time driven by one
///   `TimelineView`.
/// - Reduce Motion: one composed, frozen frame. Reduce Transparency: solid bubbles.
///   Before iOS 26: material bubbles with a drawn glass rim.
/// - Always rendered dark, so it reads the same in light and dark mode.
struct OnboardingLandingView: View {
    var onContinue: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion
                ? OnboardingLanding.staticTime
                : context.date.timeIntervalSince(startDate) + OnboardingLanding.warmUp
            ZStack {
                LandingBackdrop(time: time)
                    .opacity(entrance.backdrop ? 1 : 0)
                VStack(spacing: 0) {
                    stage(time: time)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .top)
                    copy
                }
            }
        }
        .background(Color(hex: "#030608").ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.landing")
        .onAppear(perform: playEntrance)
    }

    private func playEntrance() {
        startDate = Date()
        if reduceMotion {
            entrance = Entrance(backdrop: true, plus: true, stream: true, headline: true, button: true)
            return
        }
        withAnimation(.easeOut(duration: 1.1)) { entrance.backdrop = true }
        withAnimation(.spring(duration: 0.75, bounce: 0.45).delay(0.15)) { entrance.plus = true }
        withAnimation(.easeOut(duration: 1.0).delay(0.35)) { entrance.stream = true }
        withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.55)) { entrance.headline = true }
        withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.75)) { entrance.button = true }
    }

    // MARK: Stage

    private func stage(time: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, 560) / 390
            let origin = CGPoint(x: size.width / 2, y: size.height - 86 * unit)
            let emitter = OnboardingLanding.Emitter(rise: Double(origin.y / unit) + 140)
            let pulse = reduceMotion ? 0 : emitter.emitPulse(at: time)
            let breath = reduceMotion ? 0 : OnboardingLanding.Emitter.breath(at: time)
            let bubbles = visibleBubbles(emitter: emitter, time: time, origin: origin, unit: unit)
            let plusDiameter = 108 * unit * (1 + 0.045 * pulse + 0.015 * breath)
            ZStack {
                // Light pooling behind the + for the glass to bend; flares with each emission.
                PlusGlow(diameter: 108 * unit, pulse: pulse, breath: breath)
                    .position(origin)
                    .opacity(entrance.plus ? 1 : 0)
                GlassStream(
                    bubbles: bubbles,
                    plusCenter: origin,
                    plusDiameter: plusDiameter * (entrance.plus ? 1 : 0.55),
                    plusOpacity: entrance.plus ? 1 : 0,
                    streamOpacity: entrance.stream ? 1 : 0,
                    unit: unit
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingLanding.accessibilitySummary)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("onboarding.landing.cluster")
    }

    /// Visible particles for this frame in screen space, far first so near bubbles draw on top.
    private func visibleBubbles(
        emitter: OnboardingLanding.Emitter,
        time: Double,
        origin: CGPoint,
        unit: CGFloat
    ) -> [Bubble] {
        var result: [Bubble] = []
        result.reserveCapacity(48)
        for index in emitter.liveRange(at: time) {
            let particle = emitter.particle(index)
            guard let state = emitter.state(of: particle, at: time), state.opacity > 0.005 else { continue }
            let parallax = 0.3 + 0.7 * particle.depth
            let center = CGPoint(
                x: origin.x + (state.position.x + band(drag.width) * parallax) * unit,
                y: origin.y + (state.position.y + band(drag.height) * parallax) * unit
            )
            guard center.y > -particle.diameter * unit else { continue }
            result.append(Bubble(
                particle: particle,
                state: state,
                age: time - particle.spawnTime,
                center: center,
                diameter: particle.diameter * unit
            ))
        }
        result.sort { $0.particle.depth < $1.particle.depth }
        return result
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
                withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.4)) { drag = .zero }
            }
    }

    // MARK: Copy and action

    private var copy: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 28) {
            Text(OnboardingLanding.headline)
                .font(.system(.largeTitle, design: app.appearance.fontDesign).weight(.light))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
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
                .foregroundStyle(Color(hex: "#071C20"))
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Capsule())
        }
        .modifier(LandingButtonStyle())
        .accessibilityHint("Continues to sign in")
        .accessibilityIdentifier("onboarding.landing.continue")
    }
}

/// "Let's go": a bright, prominent glass capsule on iOS 26, a white pill before.
private struct LandingButtonStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .shadow(color: .white.opacity(0.14), radius: 22, y: 4)
        } else {
            content.buttonStyle(LandingPillButtonStyle())
        }
    }
}

private struct LandingPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(Color.white))
            .shadow(color: .white.opacity(0.12), radius: 18, y: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Backdrop

/// The living backdrop the glass refracts: a drifting dark mesh gradient in Modula's
/// palette, soft aurora light, slowly rising light motes and film grain. Kept dark at
/// the bottom for the headline and button.
private struct LandingBackdrop: View {
    var time: Double

    private static let colors: [Color] = OnboardingLanding.Backdrop.colors.map { Color(hex: $0) }

    var body: some View {
        ZStack {
            MeshGradient(
                width: OnboardingLanding.Backdrop.width,
                height: OnboardingLanding.Backdrop.height,
                points: OnboardingLanding.Backdrop.points(at: time),
                colors: Self.colors
            )
            Aurora(time: time)
                .blendMode(.screen)
            Motes(time: time)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.78), location: 0.86),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Grain()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Two soft, slowly swaying light fields.
private struct Aurora: View {
    var time: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: "#3BE3D0").opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: w * 0.55))
                    .frame(width: w * 1.3, height: h * 0.34)
                    .rotationEffect(.degrees(-24 + 7 * sin(time * 0.13)))
                    .position(x: w * (0.32 + 0.08 * sin(time * 0.07)), y: h * (0.36 + 0.04 * cos(time * 0.09)))
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: "#B05CFF").opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: w * 0.5))
                    .frame(width: w * 1.2, height: h * 0.3)
                    .rotationEffect(.degrees(28 + 6 * cos(time * 0.11)))
                    .position(x: w * (0.72 + 0.07 * cos(time * 0.06)), y: h * (0.2 + 0.05 * sin(time * 0.08)))
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: "#4F7BFF").opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: w * 0.45))
                    .frame(width: w * 1.1, height: h * 0.26)
                    .rotationEffect(.degrees(-8 + 5 * sin(time * 0.1)))
                    .position(x: w * (0.55 + 0.06 * sin(time * 0.05 + 1)), y: h * (0.55 + 0.03 * cos(time * 0.07)))
            }
            .blur(radius: 30)
        }
    }
}

/// Tiny drifting points of light; they give the glass detail to bend and lens.
private struct Motes: View {
    var time: Double

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: 0x6D6F_7465)
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
                let alpha = 0.55 * twinkle * fadeLow
                guard alpha > 0.02 else { continue }
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                if radius > 1.4 {
                    let halo = rect.insetBy(dx: -radius * 2.5, dy: -radius * 2.5)
                    context.fill(Path(ellipseIn: halo), with: .color(Color(hex: "#9FE8FF").opacity(alpha * 0.12)))
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

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(hex: "#7FF5E4").opacity(0.30 + 0.16 * pulse + 0.04 * breath), Color(hex: "#5B6CFF").opacity(0.12), .clear],
                center: .center,
                startRadius: diameter * 0.1,
                endRadius: diameter * 1.15
            ))
            .frame(width: diameter * 2.4, height: diameter * 2.4)
            .allowsHitTesting(false)
    }
}

/// The + and the stream: real Liquid Glass on iOS 26, fallbacks otherwise.
private struct GlassStream: View {
    var bubbles: [Bubble]
    var plusCenter: CGPoint
    var plusDiameter: CGFloat
    var plusOpacity: Double
    var streamOpacity: Double
    var unit: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            // Each bubble is its own lens, so overlapping bubbles stay separate glass
            // instead of fusing into blobs (a shared GlassEffectContainer also lags
            // behind per-frame motion). Newborns sit *under* the + so they are first
            // seen magnified through its glass, then pop out of the top of it.
            ZStack {
                ForEach(bubbles.filter { $0.age < OnboardingLanding.Emitter.birthWindow }, id: \.particle.index) { bubble in
                    BubbleView(bubble: bubble, style: .glass).opacity(streamOpacity)
                }
                plus(style: .glass)
                ForEach(bubbles.filter { $0.age >= OnboardingLanding.Emitter.birthWindow }, id: \.particle.index) { bubble in
                    BubbleView(bubble: bubble, style: .glass).opacity(streamOpacity)
                }
            }
            .allowsHitTesting(false)
        } else {
            let style: BubbleStyle = reduceTransparency ? .solid : .material
            ZStack {
                ForEach(bubbles.filter { $0.age < OnboardingLanding.Emitter.birthWindow }, id: \.particle.index) { bubble in
                    BubbleView(bubble: bubble, style: style).opacity(streamOpacity)
                }
                plus(style: style)
                ForEach(bubbles.filter { $0.age >= OnboardingLanding.Emitter.birthWindow }, id: \.particle.index) { bubble in
                    BubbleView(bubble: bubble, style: style).opacity(streamOpacity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func plus(style: BubbleStyle) -> some View {
        PlusView(diameter: plusDiameter, style: style)
            .opacity(plusOpacity)
            .position(plusCenter)
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

private struct BubbleView: View {
    let bubble: Bubble
    let style: BubbleStyle

    var body: some View {
        let state = bubble.state
        let squash = sqrt(state.stretch)
        let d = bubble.diameter
        // Liquid Glass follows layout, not render transforms (a `scaleEffect` leaves the
        // glass at full size), so the glass is sized and squashed through its frame;
        // only the non-glass core and symbol use transforms.
        let width = d * state.scale / squash
        let height = d * state.scale * squash
        ZStack {
            // A coloured light core *behind* the glass: the glass refracts it, so module
            // bubbles glow with their colour while the glass itself stays clear.
            if style == .glass {
                core.scaleEffect(x: state.scale / squash, y: state.scale * squash)
            }
            Color.clear
                .frame(width: width, height: height)
                .modifier(BubbleSurface(kind: bubble.particle.kind, depth: bubble.particle.depth, style: style, blur: state.blur))
            if style != .glass {
                // A material or solid fill would hide the core, so it sits on top instead.
                core.scaleEffect(x: state.scale / squash, y: state.scale * squash).opacity(0.75)
            }
            // The symbol sits on the glass (outside the effect, so it keeps full vibrancy).
            symbol
                .scaleEffect(state.scale)
                .rotationEffect(.radians(state.tilt))
        }
        .frame(width: d, height: d)
        // Translucent glass turns muddy, so glass keeps full opacity except for its
        // birth/exit fades; depth reads through size, speed and symbol strength.
        .opacity(style == .glass ? state.opacity / (0.6 + 0.4 * bubble.particle.depth) : state.opacity)
        .position(bubble.center)
    }

    @ViewBuilder
    private var core: some View {
        if case .module(let index) = bubble.particle.kind {
            let module = OnboardingLanding.modules[index]
            let d = bubble.diameter
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: module.glow).opacity(0.55), Color(hex: module.tint).opacity(0.5), Color(hex: module.tint).opacity(0)],
                    center: UnitPoint(x: 0.45, y: 0.6),
                    startRadius: 0,
                    endRadius: d * 0.42
                ))
                .frame(width: d * 0.86, height: d * 0.86)
                .opacity(0.55 + 0.45 * bubble.particle.depth)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        if case .module(let index) = bubble.particle.kind {
            let module = OnboardingLanding.modules[index]
            let d = bubble.diameter
            Image(systemName: module.symbol)
                .font(.system(size: d * 0.36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(LinearGradient(colors: [.white, Color(hex: module.glow)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: module.tint).opacity(0.9), radius: d * 0.08)
                .opacity(0.75 + 0.25 * bubble.particle.depth)
        }
    }
}

/// The bubble's body for each style.
private struct BubbleSurface: ViewModifier {
    let kind: OnboardingLanding.Kind
    let depth: Double
    let style: BubbleStyle
    let blur: Double

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(iOS 26.0, *) {
                content.glassEffect(glass, in: Ellipse())
            } else {
                content
            }
        case .material:
            content
                .background(Ellipse().fill(.ultraThinMaterial))
                .overlay(GlassRim())
                .blur(radius: blur)
        case .solid:
            content
                .background(Ellipse().fill(solidFill))
                .overlay(Ellipse().strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        switch kind {
        case .module(let index):
            let tint = Color(hex: OnboardingLanding.modules[index].tint)
            return .clear.tint(tint.opacity(0.10 + 0.14 * depth))
        case .droplet:
            return .clear
        }
    }

    private var solidFill: Color {
        switch kind {
        case .module(let index): Color(hex: OnboardingLanding.modules[index].tint).mix(with: .black, by: 0.55)
        case .droplet: Color(hex: "#2A3338")
        }
    }
}

/// Drawn glass rim and highlight for the pre-iOS 26 fallback.
private struct GlassRim: View {
    var body: some View {
        GeometryReader { proxy in
            let d = proxy.size.width
            ZStack {
                Ellipse()
                    .strokeBorder(
                        AngularGradient(
                            colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.7)],
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

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: diameter * 0.3, weight: .light))
            .foregroundStyle(.white.opacity(0.95))
            .frame(width: diameter, height: diameter)
            .modifier(PlusSurface(style: style))
            .accessibilityHidden(true)
    }
}

private struct PlusSurface: ViewModifier {
    let style: BubbleStyle

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(iOS 26.0, *) {
                content.glassEffect(.clear.tint(.white.opacity(0.04)), in: Circle())
            } else {
                content
            }
        case .material:
            content
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(GlassRim())
        case .solid:
            content
                .background(Circle().fill(Color(hex: "#1A2224")))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
    }
}
