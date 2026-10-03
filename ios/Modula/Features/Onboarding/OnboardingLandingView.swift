import SwiftUI

/// First screen a signed-out user sees: a continuous stream of glass bubbles (Modula's
/// modules) flowing out of a central "+" bubble and flying up off the screen, one
/// headline, and a single "Let's go" pill.
///
/// The stream is drawn in a `Canvas` driven by a `TimelineView`. Each bubble design is
/// rendered once as a Canvas symbol and then translated/scaled per frame, so a frame is
/// only a few dozen layer draws with no view diffing or allocations. Motion comes from
/// the stateless `OnboardingLanding.Emitter`.
///
/// Always rendered on a dark immersive canvas, so it reads the same in light and dark
/// mode. Under Reduce Motion the stream is one frozen frame and the + doesn't pulse.
struct OnboardingLandingView: View {
    var onContinue: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var startDate = Date()
    @State private var appeared = false
    @State private var drag: CGSize = .zero
    @State private var continuing = false

    var body: some View {
        ZStack {
            LandingBackdrop()
            VStack(spacing: 0) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .top)
                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 30) {
                    headline
                    continueButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: 560)
                .layoutPriority(1)
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.landing")
        .onAppear {
            startDate = Date()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.8)) { appeared = true }
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, 560) / 390
            let origin = CGPoint(x: size.width / 2, y: size.height - 92 * unit)
            let emitter = OnboardingLanding.Emitter(rise: Double(origin.y / unit) + 150)
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion
                    ? OnboardingLanding.staticTime
                    : context.date.timeIntervalSince(startDate) + OnboardingLanding.warmUp
                let pulse = reduceMotion ? 0 : emitter.emitPulse(at: time)
                ZStack {
                    PlusBubble(diameter: 112 * unit, pulse: pulse)
                        .position(origin)
                    Canvas { context, _ in
                        draw(in: &context, emitter: emitter, time: time, origin: origin, unit: unit)
                    } symbols: {
                        ForEach(OnboardingLanding.modules.indices, id: \.self) { index in
                            ModuleBubbleSymbol(module: OnboardingLanding.modules[index]).tag(index)
                        }
                        DropletSymbol().tag(BubbleSymbol.droplet)
                    }
                    .allowsHitTesting(false)
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingLanding.accessibilitySummary)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("onboarding.landing.cluster")
    }

    private func draw(
        in context: inout GraphicsContext,
        emitter: OnboardingLanding.Emitter,
        time: Double,
        origin: CGPoint,
        unit: CGFloat
    ) {
        let range = emitter.liveRange(at: time)
        // Two passes so far (soft, small) bubbles sit behind near ones without sorting.
        for pass in 0..<2 {
            for index in range {
                let particle = emitter.particle(index)
                let isNear = particle.depth >= 0.55
                guard isNear == (pass == 1), let state = emitter.state(of: particle, at: time) else { continue }
                let tag: Int
                switch particle.kind {
                case .module(let module): tag = module
                case .droplet: tag = BubbleSymbol.droplet
                }
                guard let symbol = context.resolveSymbol(id: tag) else { continue }
                let parallax = 0.3 + 0.7 * particle.depth
                let center = CGPoint(
                    x: origin.x + (state.position.x + band(drag.width) * parallax) * unit,
                    y: origin.y + (state.position.y + band(drag.height) * parallax) * unit
                )
                let scale = particle.diameter * state.scale * unit / BubbleSymbol.base
                context.drawLayer { layer in
                    layer.opacity = state.opacity
                    if state.blur > 0.15 { layer.addFilter(.blur(radius: state.blur * unit)) }
                    layer.translateBy(x: center.x, y: center.y)
                    layer.scaleBy(x: scale, y: scale)
                    layer.draw(symbol, at: .zero, anchor: .center)
                }
            }
        }
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

    private var headline: some View {
        Text(OnboardingLanding.headline)
            .font(.system(.largeTitle, design: app.appearance.fontDesign).weight(.light))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.75 : 1)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(0.3), value: appeared)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("onboarding.landing.headline")
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
        .buttonStyle(LandingPillButtonStyle())
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.5), value: appeared)
        .accessibilityHint("Continues to sign in")
        .accessibilityIdentifier("onboarding.landing.continue")
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

private struct LandingBackdrop: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            Color(hex: "#030708")
            RadialGradient(
                colors: [app.appearance.accent.color.opacity(0.32), app.appearance.accent.color.opacity(0.07), .clear],
                center: UnitPoint(x: 0.5, y: 0.55),
                startRadius: 10,
                endRadius: 440
            )
            RadialGradient(
                colors: [Color(hex: "#4F6BFF").opacity(0.10), .clear],
                center: UnitPoint(x: 0.2, y: 0.08),
                startRadius: 0,
                endRadius: 280
            )
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: UnitPoint(x: 0.5, y: 0.62), endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Bubbles

private enum BubbleSymbol {
    /// Symbols are rendered at this diameter and only ever scaled down.
    static let base: CGFloat = 150
    static let droplet = -1
}

/// Glass rim, curved highlight and soft inner light shared by every bubble.
private struct GlassShell: View {
    var diameter: CGFloat
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.10), tint.opacity(0.08), .white.opacity(0.03)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.6))
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0.08), .white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.75)],
                        center: .center,
                        angle: .degrees(-130)
                    ),
                    lineWidth: diameter * 0.018
                )
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.44, height: diameter * 0.2)
                .rotationEffect(.degrees(-30))
                .offset(x: -diameter * 0.17, y: -diameter * 0.26)
                .blur(radius: diameter * 0.025)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct ModuleBubbleSymbol: View {
    let module: OnboardingLanding.Module
    private let d = BubbleSymbol.base

    var body: some View {
        let tint = Color(hex: module.tint)
        let glow = Color(hex: module.glow)
        ZStack {
            // Soft coloured halo.
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.45), .clear], center: .center, startRadius: d * 0.3, endRadius: d * 0.62))
                .frame(width: d * 1.25, height: d * 1.25)
            // Sphere: a mesh of light, tint and shade for a 3D, art-like fill.
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.42, 0.4], [1, 0.55],
                    [0, 1], [0.6, 1], [1, 1]
                ],
                colors: [
                    glow, glow.mix(with: tint, by: 0.5), tint,
                    tint.mix(with: glow, by: 0.3), tint, tint.mix(with: .black, by: 0.35),
                    tint.mix(with: .black, by: 0.25), tint.mix(with: .black, by: 0.5), tint.mix(with: .black, by: 0.65)
                ]
            )
            .clipShape(Circle())
            .overlay {
                Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.35)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: d * 0.2, endRadius: d * 0.48))
            }
            .frame(width: d * 0.84, height: d * 0.84)
            Image(systemName: module.symbol)
                .font(.system(size: d * 0.3, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: d * 0.025, y: d * 0.02)
            GlassShell(diameter: d, tint: tint)
        }
        .frame(width: d * 1.25, height: d * 1.25)
    }
}

private struct DropletSymbol: View {
    private let d = BubbleSymbol.base

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.14), .white.opacity(0.015)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.6))
            GlassShell(diameter: d, tint: .white)
        }
        .frame(width: d * 1.25, height: d * 1.25)
    }
}

/// The real-glass "+" the stream flows out of. Breathes slightly with each emission.
private struct PlusBubble: View {
    var diameter: CGFloat
    var pulse: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.10 + 0.10 * pulse), .clear], center: .center, startRadius: diameter * 0.3, endRadius: diameter * 0.85))
                .frame(width: diameter * 1.7, height: diameter * 1.7)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.6))
                    .padding(diameter * 0.075)
                Image(systemName: "plus")
                    .font(.system(size: diameter * 0.32, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
                GlassShell(diameter: diameter, tint: .white)
            }
            .frame(width: diameter, height: diameter)
            .background { glass }
            .scaleEffect(1 + 0.035 * pulse)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glass: some View {
        if reduceTransparency {
            Circle().fill(Color(hex: "#1A2224"))
        } else if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.white.opacity(0.04)), in: Circle())
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }
}
