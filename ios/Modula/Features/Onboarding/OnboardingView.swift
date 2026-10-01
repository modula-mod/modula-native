import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step: OnboardingStep = .world
    @State private var floatPhase: Bool = false
    /// Scales with Dynamic Type (including accessibility sizes) instead of a fixed point size.
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    var body: some View {
        ZStack {
            OnboardingHeroScene(floatPhase: floatPhase)
            heroScrim
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        brand
                        content
                        points
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .modulaSoftScrollEdge()
                .scrollBounceBehavior(.basedOnSize)
                cta
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.root")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                floatPhase = true
            }
        }
    }

    /// Keeps white copy legible over bright hero frames without dimming the
    /// whole scene: a light top band for the controls and a deeper bottom
    /// band behind the title, body and calls to action.
    private var heroScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.45), location: 0.35),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack {
            Button("Skip") {
                finishOnboarding(openLogin: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .accessibilityHint("Skips remaining introduction slides and opens sign in")
            .accessibilityIdentifier("onboarding.skip")
            Spacer()
            progress
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(Color.white.opacity(item == step ? 0.95 : 0.28))
                    .frame(width: item == step ? 22 : 8, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.accessibilityProgress)
        .accessibilityIdentifier("onboarding.progress")
    }

    private var brand: some View {
        Text("modula")
            .font(.system(.title2, design: app.appearance.fontDesign).weight(.bold))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.system(size: titleSize, weight: .bold, design: app.appearance.fontDesign))
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.8 : 1)
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.step.\(step.rawValue)")
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(step.points.prefix(3)), id: \.title) { point in
                HStack(spacing: 12) {
                    Image(systemName: point.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.title)
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                    // Informational rows: no chevron, because they don't navigate.
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .modulaMaterial(.control, in: RoundedRectangle(cornerRadius: ModulaRadius.medium + 2, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var cta: some View {
        VStack(spacing: 12) {
            if let next = step.next {
                Button {
                    advance(to: next)
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(hex: "#071C20"))
                .accessibilityIdentifier("onboarding.continue")
            } else {
                Button {
                    finishOnboarding(openRegister: true)
                } label: {
                    Text("Create Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(hex: "#071C20"))
                .accessibilityIdentifier("onboarding.create-account")

                Button("Sign In") {
                    finishOnboarding(openLogin: true)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("onboarding.sign-in")
            }

            if step.next != nil {
                Button("Create an account") {
                    finishOnboarding(openRegister: true)
                }
                .font(.subheadline.weight(.semibold))
                .underline()
                .foregroundStyle(.white)
                .accessibilityIdentifier("onboarding.create-account-link")
            }
        }
        .padding(.top, 4)
    }

    private func advance(to next: OnboardingStep) {
        HapticEngine.shared.play(.navigation)
        if reduceMotion {
            step = next
        } else {
            withAnimation(ModulaMotion.animation(.navigation, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                step = next
            }
        }
    }

    private func finishOnboarding(openLogin: Bool = false, openRegister: Bool = false) {
        app.gate.markOnboardingSeen()
        HapticEngine.shared.play(.confirmation)
        if openRegister {
            app.navigation.open(.auth(.register))
        } else if openLogin {
            app.navigation.open(.auth(.login))
        }
    }
}
