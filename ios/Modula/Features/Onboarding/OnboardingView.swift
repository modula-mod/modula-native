import SwiftUI

/// Signed-out onboarding: a short, expressive multi-step flow over the shared auth
/// backdrop (the wave keeps running; only this foreground moves).
///
/// Psychology: progress dots (goal-gradient), one question per screen with big type
/// (low cognitive load), tap-to-pick chips instead of typing (Hick's law, fast wins),
/// a name that comes back in Create Account (consistency + IKEA effect), a value-first
/// notification primer before iOS's one-shot alert (and only if the back-off allows it),
/// and a single accent action on every step.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step: OnboardingStep = .intro
    @State private var forward = true
    @State private var answers = OnboardingAnswers.load()
    @State private var name = OnboardingAnswers.load().name ?? ""
    @State private var primerAvailable = false
    @State private var requesting = false
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    private var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .notifications || primerAvailable }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                    header
                    stepContent
                }
                .padding(.horizontal, ModulaSpacing.lg)
                .padding(.top, ModulaSpacing.md)
                .padding(.bottom, ModulaSpacing.lg)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(stepTransition)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .modulaSoftScrollEdge()
            cta
                .padding(.horizontal, ModulaSpacing.lg)
                .padding(.bottom, ModulaSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .modulaAuthBackdrop()
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.root")
        .task {
            guard let push = PushNotificationController.current else { return }
            await push.refreshAuthorization()
            primerAvailable = push.offersOnboardingPrimer
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: ModulaSpacing.sm) {
            if let index = steps.firstIndex(of: step), index > 0 {
                Button {
                    go(to: steps[index - 1], forward: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            progress
            Spacer()
            if step != .finale {
                Button("Skip") { finishOnboarding(openLogin: true) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: ModulaLayout.minimumTouch)
                    .accessibilityHint("Skips the introduction and opens sign in")
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, ModulaSpacing.md)
        .padding(.top, ModulaSpacing.xs)
    }

    private var progress: some View {
        let current = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    .fill(index <= current ? app.appearance.liveAccent : Color.primary.opacity(0.2))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .padding(.leading, ModulaSpacing.xs)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(steps.count)")
        .accessibilityIdentifier("onboarding.progress")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            if step == .intro || step == .finale {
                SignInBrandMark()
                    .padding(.bottom, ModulaSpacing.sm)
            }
            Text(step.title)
                .font(.system(size: titleSize, weight: .heavy, design: app.appearance.fontDesign))
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.7 : 0.9)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(step.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.step.\(step.rawValue)")
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            ModulaGlassGroup(spacing: ModulaSpacing.sm) {
                VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                    ForEach(step.points, id: \.title) { point in
                        OnboardingChip(title: point.title, symbol: point.symbol, selected: false, action: nil)
                    }
                }
            }
        case .you:
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                TextField("", text: $name, prompt: Text("Your name").foregroundStyle(.tertiary))
                    .font(.system(size: titleSize * 1.1, weight: .bold, design: app.appearance.fontDesign))
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .accessibilityLabel("Your name")
                    .accessibilityIdentifier("onboarding.name")
                    .onChange(of: name) { _, value in
                        answers.name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        answers.save()
                    }
                VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                    Text("Your age").font(.headline)
                    OnboardingChipFlow(spacing: ModulaSpacing.xs) {
                        ForEach(OnboardingAnswers.ageRanges, id: \.self) { range in
                            OnboardingChip(title: range, symbol: nil, selected: answers.ageRange == range) {
                                answers.ageRange = answers.ageRange == range ? nil : range
                                answers.save()
                            }
                        }
                    }
                }
            }
            .onAppear { if name.isEmpty { nameFocused = true } }
        case .source:
            OnboardingChipFlow(spacing: ModulaSpacing.xs) {
                ForEach(OnboardingAnswers.sources, id: \.title) { source in
                    OnboardingChip(title: source.title, symbol: source.symbol, selected: answers.source == source.title) {
                        answers.source = answers.source == source.title ? nil : source.title
                        answers.save()
                    }
                }
            }
        case .moliboo:
            OnboardingMolibooPicker()
        case .notifications:
            OnboardingLockScreenPreview()
                .frame(maxWidth: .infinity)
        case .finale:
            EmptyView()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var cta: some View {
        VStack(spacing: ModulaSpacing.xs) {
            switch step {
            case .notifications:
                AuthPrimaryButton(title: "Turn on notifications", busy: requesting, enabled: true) {
                    Task {
                        requesting = true
                        await PushNotificationController.current?.requestPermission()
                        requesting = false
                        advance()
                    }
                }
                .accessibilityIdentifier("onboarding.notifications.allow")
                Button("Another time") {
                    // Counts toward the pre-prompt back-off (cool-down, max three asks).
                    PushNotificationController.current?.dismissPrePrompt()
                    advance()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                .accessibilityIdentifier("onboarding.notifications.later")
            case .finale:
                AuthPrimaryButton(title: "Create Account", busy: false, enabled: true) {
                    finishOnboarding(openRegister: true)
                }
                .accessibilityIdentifier("onboarding.create-account")
                Button("I already have an account") { finishOnboarding(openLogin: true) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                    .accessibilityIdentifier("onboarding.sign-in")
            default:
                AuthPrimaryButton(title: step == .you || step == .source ? "Done" : "Continue", busy: false, enabled: true) {
                    advance()
                }
                .accessibilityIdentifier("onboarding.continue")
            }
        }
    }

    private func advance() {
        nameFocused = false
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        go(to: steps[index + 1], forward: true)
    }

    private func go(to next: OnboardingStep, forward: Bool) {
        HapticEngine.shared.play(.navigation)
        self.forward = forward
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15)) {
            step = next
        }
    }

    private func finishOnboarding(openLogin: Bool = false, openRegister: Bool = false) {
        answers.save()
        app.gate.markOnboardingSeen()
        HapticEngine.shared.play(.confirmation)
        if openRegister {
            app.navigation.open(.auth(.register))
        } else if openLogin {
            app.navigation.open(.auth(.login))
        }
    }
}

// MARK: - Chips

/// Selectable pill. Selected wears the accent CTA; unselected is Liquid Glass
/// (solid under Reduce Transparency). `action == nil` renders a static info pill.
struct OnboardingChip: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let action: (() -> Void)?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button {
                HapticEngine.shared.play(.selection)
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.35)) { action() }
            } label: { label }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var label: some View {
        let content = HStack(spacing: ModulaSpacing.xs) {
            if let symbol { Image(systemName: symbol).font(.body.weight(.semibold)) }
            Text(title).font(.body.weight(.semibold))
        }
        .padding(.horizontal, ModulaSpacing.md)
        .frame(minHeight: 48)
        if selected {
            content.modulaAccentCTA().scaleEffect(reduceMotion ? 1 : 1.03)
        } else if reduceTransparency {
            content.background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.modulaGlass(in: Capsule(), interactive: false)
        }
    }
}

/// Wrapping row layout for chips.
struct OnboardingChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (points, maxX, y + rowHeight)
    }
}

// MARK: - Notification primer

/// Mock lock screen that previews the kinds of notifications Modula sends. The rows
/// are the app's real notification categories, labelled as examples (no invented people).
struct OnboardingLockScreenPreview: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var shown = false

    private let samples: [(symbol: String, title: String, body: String)] = [
        ("paperplane.fill", "Messages", "New message from a friend"),
        ("person.badge.plus", "Follows & requests", "Someone wants to connect"),
        ("leaf.fill", "Moliboo care", "Your Moliboo misses you"),
    ]

    private let tints = ["#7FF5E4", "#8C7CFF", "#FF8FB1", "#FFC56B", "#6BB8FF"]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        VStack(spacing: ModulaSpacing.sm) {
            avatarCluster
                .padding(.bottom, ModulaSpacing.xs)
            Text(Date(), format: .dateTime.hour().minute())
                .font(.system(size: 52, weight: .bold, design: app.appearance.fontDesign))
                .monospacedDigit()
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, ModulaSpacing.xs)
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                notification(sample)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 14)
                    .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25).delay(0.15 * Double(index)), value: shown)
            }
            Text("Example notifications")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(ModulaSpacing.md)
        .frame(maxWidth: 340)
        .background {
            if reduceTransparency {
                shape.fill(Color(uiColor: .secondarySystemBackground))
            } else {
                shape.fill(LinearGradient(colors: [app.appearance.liveAccent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a lock screen with example Modula notifications for messages, follow requests and Moliboo care.")
        .onAppear { shown = true }
    }

    private var avatarCluster: some View {
        HStack(spacing: -12) {
            ForEach(Array(tints.enumerated()), id: \.offset) { index, hex in
                Circle()
                    .fill(Color(hex: hex).gradient)
                    .frame(width: index == 2 ? 52 : 40, height: index == 2 ? 52 : 40)
                    .overlay(Image(systemName: "person.fill").font(.system(size: index == 2 ? 22 : 16)).foregroundStyle(.white.opacity(0.9)))
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 2))
                    .zIndex(index == 2 ? 1 : 0)
            }
        }
    }

    private func notification(_ sample: (symbol: String, title: String, body: String)) -> some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: sample.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(app.appearance.liveAccent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Modula · \(sample.title)").font(.footnote.weight(.semibold))
                    Spacer()
                    Text("now").font(.caption).foregroundStyle(.secondary)
                }
                Text(sample.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(ModulaSpacing.sm)
        .background {
            let card = RoundedRectangle(cornerRadius: 20, style: .continuous)
            if reduceTransparency {
                card.fill(Color(uiColor: .tertiarySystemBackground))
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: card)
            } else {
                Color.clear.modulaGlass(in: card, interactive: false)
            }
        }
    }
}
