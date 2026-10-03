import SwiftUI

/// First screen a signed-out user sees: a floating cluster of glass bubbles (Modula's
/// modules) above a central "add" bubble, one headline, and a single "Let's go" pill.
///
/// Always rendered on a dark immersive canvas (like the onboarding hero), so it reads
/// the same in light and dark mode. Under Reduce Motion the cluster is static and
/// appears without the entrance animation; under Reduce Transparency the bubbles use
/// opaque fills instead of glass.
struct OnboardingLandingView: View {
    var onContinue: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    @State private var drag: CGSize = .zero
    @State private var continuing = false

    var body: some View {
        ZStack {
            LandingBackdrop()
            VStack(spacing: 0) {
                cluster
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)
                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 34) {
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
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: 1.1, bounce: 0.28).delay(0.1)) { appeared = true }
            }
        }
    }

    // MARK: Cluster

    private var cluster: some View {
        GeometryReader { proxy in
            let canvas = OnboardingLanding.canvasSize
            // Slightly larger than the canvas width: edge bubbles are allowed to kiss the screen edge.
            let scale = min(proxy.size.width / (canvas.width - 30), proxy.size.height / canvas.height, 1.3)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                ZStack {
                    ForEach(Array(OnboardingLanding.bubbles.enumerated()), id: \.element.id) { index, bubble in
                        let drift = reduceMotion ? .zero : OnboardingLanding.drift(for: bubble, at: t)
                        let parallax = OnboardingLanding.parallax(for: bubble, translation: drag)
                        LandingBubbleView(bubble: bubble, scale: scale)
                            .scaleEffect(appeared ? 1 : 0.35)
                            .opacity(appeared ? 1 : 0)
                            .position(
                                x: (bubble.center.x - canvas.width / 2) * scale * (appeared ? 1 : 0.55) + proxy.size.width / 2,
                                y: (bubble.center.y - canvas.height / 2) * scale * (appeared ? 1 : 0.55) + proxy.size.height / 2 + (appeared ? 0 : 40 * scale)
                            )
                            .offset(x: (drift.width + parallax.width) * scale, y: (drift.height + parallax.height) * scale)
                            .animation(
                                reduceMotion ? nil : .spring(duration: 1.0, bounce: 0.3).delay(Double(index) * 0.035),
                                value: appeared
                            )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingLanding.accessibilitySummary)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("onboarding.landing.cluster")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !reduceMotion else { return }
                drag = value.translation
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.42)) { drag = .zero }
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(0.45), value: appeared)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.65), value: appeared)
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
                colors: [app.appearance.accent.color.opacity(0.30), app.appearance.accent.color.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color(hex: "#4F6BFF").opacity(0.10), .clear],
                center: UnitPoint(x: 0.15, y: 0.12),
                startRadius: 0,
                endRadius: 260
            )
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Bubble

private struct LandingBubbleView: View {
    let bubble: OnboardingLanding.Bubble
    let scale: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var size: CGFloat { bubble.diameter * scale }
    private var tint: Color { Color(hex: bubble.tint) }

    var body: some View {
        ZStack {
            inner
                .padding(bubble.content == .droplet ? 0 : size * 0.075)
            specular
        }
        .frame(width: size, height: size)
        .background { glass }
        .overlay { rim }
        .shadow(color: shadowColor, radius: size * 0.22 * bubble.depth, y: size * 0.12 * bubble.depth)
        .compositingGroup()
    }

    private var shadowColor: Color {
        switch bubble.content {
        case .droplet: .clear
        case .add: Color.white.opacity(0.10)
        default: tint.opacity(0.35)
        }
    }

    @ViewBuilder
    private var glass: some View {
        if reduceTransparency {
            Circle().fill(Color(hex: "#1A2224"))
        } else if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(bubble.content == .droplet ? 0.02 : 0.10)), in: Circle())
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }

    private var rim: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.75, size * 0.014)
            )
            .allowsHitTesting(false)
    }

    /// Soft highlight that sells the curved glass.
    private var specular: some View {
        Ellipse()
            .fill(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size * 0.46, height: size * 0.22)
            .rotationEffect(.degrees(-28))
            .offset(x: -size * 0.16, y: -size * 0.24)
            .blur(radius: size * 0.03)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var inner: some View {
        switch bubble.content {
        case .droplet:
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
        case .add:
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
            }
        case .symbol(let symbol):
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.mix(with: .white, by: 0.45), tint, tint.mix(with: .black, by: 0.45)],
                            center: UnitPoint(x: 0.32, y: 0.26),
                            startRadius: 0,
                            endRadius: size * 0.62
                        )
                    )
                Image(systemName: symbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.02)
            }
        }
    }
}
