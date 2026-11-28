import SwiftUI
import UIKit

/// Shared chrome for the secondary auth screens: hero mark, big expressive title, a
/// short subtitle and the content. The backdrop is hoisted above the auth navigation
/// (see `PreShellAuthHost`), so only this foreground slides when moving between screens.
struct AuthChrome<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                AuthBrandHeader(title: title, subtitle: subtitle)
                ModulaGlassGroup(spacing: ModulaSpacing.md) {
                    content
                }
            }
            .padding(.horizontal, ModulaSpacing.lg)
            .padding(.top, ModulaSpacing.sm)
            .padding(.bottom, ModulaSpacing.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .modulaSoftScrollEdge()
        .modulaAuthBackdrop()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Liquid Glass field

/// Liquid Glass text input for the auth flow: a capsule of real glass on iOS 26
/// (`glassEffect`, grouped by `ModulaGlassGroup`), and a solid fill before that and
/// under Reduce Transparency. Leading icon, floating label, an inner top
/// highlight, an accent glow and slight swell on focus, inline validation with a
/// gentle shake, and a reveal toggle for passwords. Content types (AutoFill, passkey
/// suggestions) are set by the caller with `.textContentType`.
struct AuthGlassField<Focus: Hashable>: View {
    enum Kind { case text, secure }

    let title: String
    let symbol: String
    @Binding var text: String
    var kind: Kind = .text
    var prompt: String? = nil
    var message: String? = nil
    var focus: FocusState<Focus?>.Binding
    var focusValue: Focus
    var identifier: String
    /// Bump to shake the field (e.g. a rejected submit).
    var shake: Int = 0

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var height = 58.0
    @ScaledMetric(relativeTo: .body) private var iconWidth = 22.0
    @State private var revealed = false
    @State private var ownShake = 0

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var floated: Bool { isFocused || !text.isEmpty }
    private var hasError: Bool { message != nil }
    private var accent: Color { app.appearance.liveAccent }
    private var opaque: Bool { reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: hasError ? "exclamationmark.circle" : symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(hasError ? Color.red : (isFocused ? accent : restingInk))
                    .frame(width: iconWidth)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    Text(title)
                        .font(floated ? .caption.weight(.semibold) : .body)
                        .foregroundStyle(hasError ? Color.red : (isFocused ? accent : restingInk))
                        .offset(y: floated ? -height * 0.2 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    input
                        .font(.body)
                        .offset(y: floated ? height * 0.11 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: max(ModulaLayout.minimumTouch, height), alignment: .leading)
                if kind == .secure {
                    Button {
                        let wasFocused = isFocused
                        revealed.toggle()
                        if wasFocused { DispatchQueue.main.async { focus.wrappedValue = focusValue } }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.body.weight(.medium))
                            .foregroundStyle(restingInk)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }
            }
            .padding(.leading, ModulaSpacing.md + 2)
            .padding(.trailing, kind == .secure ? ModulaSpacing.xs : ModulaSpacing.md + 2)
            .background { surface }
            .overlay { rim }
            .shadow(color: glowColor, radius: isFocused ? 16 : 0)
            .scaleEffect(isFocused && !reduceMotion ? 1.012 : 1)
            .contentShape(Capsule())
            .onTapGesture { focus.wrappedValue = focusValue }
            .modifier(AuthShakeEffect(travel: reduceMotion ? 0 : 7, animatableData: CGFloat(shake + ownShake)))

            if let message {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading, ModulaSpacing.md)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: isFocused)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: floated)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: message)
        .animation(reduceMotion ? nil : .linear(duration: 0.42), value: shake + ownShake)
        .onChange(of: message) { old, new in
            if old == nil, new != nil { ownShake += 1 }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var input: some View {
        Group {
            if kind == .secure && !revealed {
                SecureField("", text: $text, prompt: nil)
            } else {
                TextField("", text: $text, prompt: nil)
            }
        }
        .focused(focus, equals: focusValue)
        .accessibilityLabel(title)
        .accessibilityValue(message ?? "")
        .accessibilityHint(prompt ?? "")
        .accessibilityIdentifier(identifier)
    }

    /// Label/icon ink at rest: clearly readable on glass (system secondary washed out on light glass).
    private var restingInk: Color {
        Color.primary.opacity(contrast == .increased ? 0.85 : (scheme == .dark ? 0.68 : 0.62))
    }

    private var glowColor: Color {
        guard isFocused, !opaque else { return .clear }
        return (hasError ? Color.red : accent).opacity(scheme == .dark ? 0.38 : 0.24)
    }

    @ViewBuilder
    private var surface: some View {
        if opaque {
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        } else if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(isFocused ? accent.opacity(0.14) : .clear).interactive(), in: Capsule())
                .overlay { Capsule().fill(AuthFieldSurface.frost(scheme)).allowsHitTesting(false) }
        } else {
            // Below iOS 26 there is no system Liquid Glass: a solid fill, never a blur/material imitation.
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
                .overlay { Capsule().fill(accent.opacity(isFocused ? 0.10 : 0)).allowsHitTesting(false) }
        }
    }

    /// Focus/error ring plus an inner top highlight (the "lip" of the glass).
    private var rim: some View {
        ZStack {
            Capsule()
                .strokeBorder(
                    hasError ? Color.red.opacity(0.8)
                        : isFocused ? accent.opacity(0.9)
                        : Color.primary.opacity(contrast == .increased ? 0.35 : 0.14),
                    lineWidth: isFocused || hasError ? 1.5 : 0.75
                )
            if !opaque {
                Capsule()
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.32 : 0.6), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .padding(1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Horizontal damped shake; one full shake per whole step of `animatableData`.
struct AuthShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = animatableData - animatableData.rounded(.down)
        let x = travel * sin(phase * .pi * 6) * (1 - phase)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// Real system Liquid Glass capsule for small auth controls on iOS 26; a solid fill below
/// iOS 26 and under Reduce Transparency. Never a blur or material imitation.
struct AuthGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
        }
    }
}

// MARK: - Password strength

/// Four-segment strength meter for new passwords (length, length 12+, mixed case,
/// digits and symbols). Advisory only; the server still enforces its own rules.
struct AuthPasswordStrengthMeter: View {
    let password: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func score(_ password: String) -> Int {
        guard !password.isEmpty else { return 0 }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        let hasLower = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUpper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        if hasLower && hasUpper { score += 1 }
        let hasDigit = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
        if hasDigit && hasSymbol { score += 1 }
        return max(1, min(4, score))
    }

    private var score: Int { Self.score(password) }
    private var label: String { ["", "Weak", "Fair", "Good", "Strong"][score] }
    private var color: Color { [Color.secondary, .red, .orange, .yellow, .green][score] }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? color : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            HStack {
                AuthPasswordRequirement(password: password)
                Spacer()
                if score > 0 {
                    Text(label).font(.footnote.weight(.semibold)).foregroundStyle(color)
                        .contentTransition(.opacity)
                }
            }
        }
        .padding(.horizontal, ModulaSpacing.xs)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: score)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score == 0 ? "Password strength" : "Password strength: \(label)")
    }
}

// MARK: - Success

/// Animated success mark: the ring draws, then the check, with a spring pop and a
/// success haptic. Static under Reduce Motion.
struct AuthSuccessCheckmark: View {
    var size: CGFloat = 88
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var pop = false

    var body: some View {
        let accent = app.appearance.liveAccent
        ZStack {
            Circle().fill(accent.opacity(0.16))
            Circle()
                .trim(from: 0, to: ring)
                .stroke(accent, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(accent, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .scaleEffect(pop ? 1 : 0.85)
        .accessibilityHidden(true)
        .onAppear {
            HapticEngine.shared.play(.success)
            guard !reduceMotion else { ring = 1; check = 1; pop = true; return }
            withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) { check = 1 }
            withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.3)) { pop = true }
        }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}

/// Full success state used by forgot/reset/verify: checkmark, headline, body, one CTA.
struct AuthSuccessState: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: ModulaSpacing.md) {
            AuthSuccessCheckmark()
                .padding(.vertical, ModulaSpacing.sm)
            Text(title)
                .font(.system(.title, design: app.appearance.fontDesign).weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            AuthPrimaryButton(title: actionTitle, busy: false, enabled: true, action: action)
                .padding(.top, ModulaSpacing.sm)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(minHeight: ModulaLayout.minimumTouch)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Inline error banner shared by the auth screens.
struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        AuthNoticeBanner(message: message)
            .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}

/// Calm inline notice for auth: primary-coloured text on a quiet tinted surface with a
/// small coloured icon. A signed-out session reads as information, not an alarm.
struct AuthNoticeBanner<Accessory: View>: View {
    let message: String
    @ViewBuilder var accessory: Accessory
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(message: String, @ViewBuilder accessory: () -> Accessory) {
        self.message = message
        self.accessory = accessory()
    }

    static func isSessionNotice(_ message: String) -> Bool { message.hasPrefix("Your session ended") }

    private var informational: Bool { Self.isSessionNotice(message) }
    private var tint: Color { informational ? Color.orange : Color.red }

    var body: some View {
        HStack(alignment: .top, spacing: ModulaSpacing.sm) {
            Image(systemName: informational ? "clock.arrow.circlepath" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ModulaSpacing.md)
        .padding(.vertical, ModulaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuthFieldSurface.frost(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(scheme == .dark ? 0.35 : 0.25), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

/// Shared auth header: compact brand lockup (mark + wordmark) on the leading edge, then the
/// title and subtitle. Same position on every auth screen.
struct AuthBrandHeader<Extra: View>: View {
    let title: String
    let subtitle: String
    var compact = false
    @ViewBuilder var extra: Extra
    @Environment(AppEnvironment.self) private var app

    init(title: String, subtitle: String, compact: Bool = false, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
        self.extra = extra()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack(spacing: ModulaSpacing.sm) {
                SignInBrandMark(compact: true, side: 40)
                ModulaWordmark(height: 18)
            }
            .padding(.bottom, ModulaSpacing.xs)
            .accessibilityHidden(true)
            Text(title)
                .font(.system(compact ? .title : .largeTitle, design: app.appearance.fontDesign).weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Frosted fill laid over field glass so labels stay legible on bright backdrops.
enum AuthFieldSurface {
    static func frost(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62)
    }
}

// MARK: - Register

struct RegisterView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var handle = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var attempted = false
    @State private var error: String?
    @State private var diagnostic: String?
    @State private var busy = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, handle, displayName, password }

    var body: some View {
        AuthChrome(title: "Create your account", subtitle: "Pick a unique username and a password you don’t use anywhere else.") {
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                AuthGlassField(title: "Email", symbol: "envelope", text: $email, message: emailMessage,
                               focus: $focus, focusValue: Field.email, identifier: "auth.register.email", shake: shake)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .handle }
                AuthGlassField(title: "Username", symbol: "at", text: $handle, message: handleMessage,
                               focus: $focus, focusValue: Field.handle, identifier: "auth.register.handle")
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .displayName }
                AuthGlassField(title: "Display name", symbol: "person", text: $displayName, message: displayNameMessage,
                               focus: $focus, focusValue: Field.displayName, identifier: "auth.register.display-name")
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                    AuthGlassField(title: "Password", symbol: "lock", text: $password, kind: .secure,
                                   prompt: "At least 10 characters.", focus: $focus, focusValue: Field.password,
                                   identifier: "auth.register.password", shake: shake)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                    AuthPasswordStrengthMeter(password: password)
                }
                AuthTermsRow(accepted: $acceptedTerms)
                    .onChange(of: acceptedTerms) { _, _ in HapticEngine.shared.play(.selection) }
                if let error {
                    AuthErrorBanner(message: error)
                        .accessibilityIdentifier("auth.register.error")
                    #if DEBUG
                    if let diagnostic {
                        Text(diagnostic).font(.caption2).foregroundStyle(.secondary)
                    }
                    #endif
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = Int(app.auth.rateLimitWait(at: context.date).rounded(.up))
                    AuthPrimaryButton(title: wait > 0 ? "Try again in \(VerifyEmailView.clock(wait))" : "Create Account",
                                      busy: busy, enabled: canSubmit && wait == 0) {
                        Task { await submit() }
                    }
                }
                HStack(spacing: ModulaSpacing.xxs) {
                    Text("Already have an account?").foregroundStyle(.secondary)
                    Button("Sign In") {
                        HapticEngine.shared.play(.navigation)
                        app.navigation.open(.auth(.login))
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(app.appearance.liveAccent)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: error)
        }
        .accessibilityIdentifier("auth.register")
        .disabled(busy)
        .onAppear {
            // Name typed during onboarding (kept on device) pre-fills the display name.
            if displayName.isEmpty, let name = OnboardingAnswers.load().name, !name.isEmpty {
                displayName = name
            }
        }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailMessage: String? {
        guard attempted || (!trimmedEmail.isEmpty && focus != .email) else { return nil }
        if trimmedEmail.isEmpty { return "Enter your email." }
        if !SignInView.looksLikeEmail(trimmedEmail) { return "That email address looks incomplete." }
        return nil
    }

    private var handleMessage: String? {
        guard attempted else { return nil }
        return handle.trimmingCharacters(in: .whitespaces).isEmpty ? "Choose a username." : nil
    }

    private var trimmedDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Greenfield requires a display name of 2 to 80 characters.
    private var displayNameMessage: String? {
        guard attempted else { return nil }
        return (2...80).contains(trimmedDisplayName.count) ? nil : "Enter a display name of 2 to 80 characters."
    }

    private var canSubmit: Bool {
        SignInView.looksLikeEmail(trimmedEmail) && !handle.trimmingCharacters(in: .whitespaces).isEmpty
            && (2...80).contains(trimmedDisplayName.count)
            && password.count >= AuthPasswordRequirement.minimumLength && acceptedTerms && !busy
    }

    private func submit() async {
        guard !busy, app.auth.rateLimitWait() == 0 else { return }
        guard canSubmit else {
            attempted = true
            shake += 1
            HapticEngine.shared.play(.warning)
            return
        }
        focus = nil
        busy = true
        error = nil
        diagnostic = nil
        defer { busy = false }
        do {
            // The store keeps {email, account, challenge, expiry} in the Keychain; the
            // password is only sent here and never stored. Any 2xx (including 202) and
            // a legacy 409 EMAIL_TAKEN go to the code-entry screen.
            _ = try await app.auth.register(payload: RegistrationPayload(
                email: trimmedEmail,
                password: password,
                handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: trimmedDisplayName,
                inviteCode: nil,
                acceptedTerms: acceptedTerms
            ))
            password = ""
            HapticEngine.shared.play(.success)
            app.navigation.open(.auth(.verify))
        } catch let api as APIError {
            let details = await app.client.lastFailureDetails(path: "/v1/accounts/register")
            error = AuthenticationStore.isRateLimited(api)
                ? (app.auth.rateLimitNotice ?? AuthenticationStore.signupMessage(api, details: details))
                : AuthenticationStore.signupMessage(api, details: details)
            #if DEBUG
            diagnostic = api.diagnosticDescription
            #endif
            shake += 1
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = AuthenticationStore.offlineMessage
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

// MARK: - Verify

struct VerifyEmailView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code = ""
    @State private var email = ""
    @State private var attempted = false
    @State private var verified = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case code, email }

    /// Greenfield emails 6-digit codes (ChallengeService `codeDigits` default).
    static let codeLength = 6

    /// Neutral existing-account way out on the code-entry screen. Both routes are the
    /// live sign-in and forgot-password flows (no dead controls). Tests read these
    /// so the copy and destinations cannot drift from the buttons.
    enum AlternateActions {
        static let existingAccountCopy = "If you already have an account, you’ll get an email to sign in or reset your password instead."
        static let signInTitle = "Sign in"
        static let forgotPasswordTitle = "Forgot password"
        static let signInRoute: AppRoute = .auth(.login)
        static let forgotPasswordRoute: AppRoute = .auth(.forgotPassword)
    }

    private var pending: PendingSignup? { app.auth.pendingSignup }

    private var subtitle: String {
        if verified { return "Your email is confirmed." }
        if let pending { return "Enter the \(Self.codeLength)-digit code we sent to \(pending.recipient ?? pending.email). It can take a minute to arrive; check spam too." }
        return "Enter the email you signed up with and we’ll send a new code."
    }

    var body: some View {
        AuthChrome(title: verified ? "You’re verified" : "Verify your email", subtitle: subtitle) {
            if verified {
                AuthSuccessState(title: "Email verified", message: "Sign in to start building your Modula.", actionTitle: "Continue to Sign In") {
                    app.navigation.open(.auth(.login))
                }
                .accessibilityIdentifier("auth.verify.done")
            } else if let pending {
                codeStep(pending)
            } else {
                requestStep
            }
        }
        .accessibilityIdentifier("auth.verify")
        .onAppear {
            app.auth.restorePendingSignup()
            if app.auth.pendingSignup != nil { focus = .code }
        }
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(Self.codeLength))
            if digits != value { code = digits }
            if app.auth.signupError != nil, !app.auth.verifying { app.auth.signupError = nil }
        }
    }

    // MARK: Enter the code

    @ViewBuilder
    private func codeStep(_ pending: PendingSignup) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.md) {
            AuthGlassField(title: "Verification code", symbol: "number", text: $code,
                           prompt: "\(Self.codeLength) digits from the email", focus: $focus, focusValue: Field.code,
                           identifier: "auth.verify.code", shake: shake)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .submitLabel(.go)
                .onSubmit { Task { await verify() } }
            if let notice = app.auth.pendingNotice {
                AuthNoticeBanner(message: notice).accessibilityIdentifier("auth.verify.notice")
            }
            if let error = app.auth.signupError {
                AuthErrorBanner(message: error).accessibilityIdentifier("auth.verify.error")
            }
            AuthPrimaryButton(title: "Verify", busy: app.auth.verifying,
                              enabled: code.count == Self.codeLength && !pending.isLocked && !app.auth.verifying) {
                Task { await verify() }
            }
            .accessibilityIdentifier("auth.verify.submit")
            resendButton(pending)
            Text("This code works until \(pending.expiresAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("auth.verify.expiry")
            Text(AlternateActions.existingAccountCopy)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("auth.verify.existing-account")
            HStack(spacing: ModulaSpacing.md) {
                Button(AlternateActions.signInTitle) {
                    HapticEngine.shared.play(.navigation)
                    app.navigation.open(AlternateActions.signInRoute)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                .accessibilityIdentifier("auth.verify.sign-in")
                Button(AlternateActions.forgotPasswordTitle) {
                    HapticEngine.shared.play(.navigation)
                    app.navigation.open(AlternateActions.forgotPasswordRoute)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                .accessibilityIdentifier("auth.verify.forgot-password")
            }
            .disabled(app.auth.verifying || app.auth.resending)
            Button("Use a different account") {
                app.auth.abandonPendingSignup()
                app.auth.pendingNotice = nil
                app.auth.error = nil
                HapticEngine.shared.play(.navigation)
                app.navigation.open(.auth(.login))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(app.appearance.liveAccent)
            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
            .disabled(app.auth.verifying || app.auth.resending)
            .accessibilityHint("Forgets this sign-up on this device and returns to Sign In.")
            .accessibilityIdentifier("auth.verify.different-account")
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: app.auth.signupError)
    }

    private func resendButton(_ pending: PendingSignup) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = Int(pending.resendWait(at: context.date).rounded(.up))
            let label = wait > 0 ? "Resend code in \(Self.clock(wait))" : "Resend code"
            Button {
                Task { await resend() }
            } label: {
                HStack(spacing: 8) {
                    if app.auth.resending { ProgressView().controlSize(.small) }
                    Text(label).monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, ModulaSpacing.md)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                .modifier(AuthGlassCapsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(wait > 0 ? Color.secondary : app.appearance.liveAccent)
            .disabled(wait > 0 || app.auth.resending || app.auth.verifying)
            .accessibilityLabel(wait > 0 ? "Resend code, available in \(wait) seconds" : "Resend code")
            .accessibilityValue(app.auth.resending ? "Sending" : "")
            .accessibilityIdentifier("auth.verify.resend")
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Nothing pending on this device

    private var requestStep: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.md) {
            if let notice = app.auth.pendingNotice {
                AuthNoticeBanner(message: notice).accessibilityIdentifier("auth.verify.notice")
            }
            AuthGlassField(title: "Email", symbol: "envelope", text: $email,
                           message: attempted && !SignInView.looksLikeEmail(trimmedEmail) ? "Enter the email you signed up with." : nil,
                           focus: $focus, focusValue: Field.email, identifier: "auth.verify.email", shake: shake)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { Task { await requestCode() } }
            if let error = app.auth.signupError {
                AuthErrorBanner(message: error).accessibilityIdentifier("auth.verify.error")
            }
            AuthPrimaryButton(title: "Send a New Code", busy: app.auth.resending, enabled: !trimmedEmail.isEmpty) {
                Task { await requestCode() }
            }
            .accessibilityIdentifier("auth.verify.request")
            Button("Back to Sign In") {
                app.auth.pendingNotice = nil
                app.navigation.open(.auth(.login))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(app.appearance.liveAccent)
            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
        }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Actions

    private func verify() async {
        guard code.count == Self.codeLength, !app.auth.verifying else { return }
        focus = nil
        if await app.auth.verifyPendingCode(code) {
            withAnimation(reduceMotion ? nil : .snappy) { verified = true }
        } else {
            code = ""
            shake += 1
            HapticEngine.shared.play(.failure)
            if app.auth.pendingSignup != nil { DispatchQueue.main.async { focus = .code } }
        }
    }

    private func resend() async {
        if await app.auth.resendPendingCode() {
            code = ""
            HapticEngine.shared.play(.confirmation)
        } else if app.auth.signupError != nil {
            HapticEngine.shared.play(.failure)
        }
    }

    private func requestCode() async {
        guard SignInView.looksLikeEmail(trimmedEmail) else {
            attempted = true
            shake += 1
            HapticEngine.shared.play(.warning)
            return
        }
        focus = nil
        if await app.auth.requestCode(for: trimmedEmail) {
            HapticEngine.shared.play(.confirmation)
            focus = .code
        } else {
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

// MARK: - Reset

struct ResetPasswordView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var token = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var done = false
    @State private var busy = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case token, password, confirm }

    var body: some View {
        AuthChrome(title: done ? "All set" : "Reset password", subtitle: done ? "Your password has been updated." : "Use the token from your reset email. The new password is never stored on device.") {
            if done {
                AuthSuccessState(title: "Password updated", message: "Sign in with your new password.", actionTitle: "Back to Sign In") {
                    app.navigation.open(.auth(.login))
                }
            } else {
                VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                    AuthGlassField(title: "Reset token", symbol: "key", text: $token,
                                   focus: $focus, focusValue: Field.token, identifier: "auth.reset.token")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                        AuthGlassField(title: "New password", symbol: "lock", text: $password, kind: .secure,
                                       focus: $focus, focusValue: Field.password, identifier: "auth.reset.password", shake: shake)
                            .textContentType(.newPassword)
                            .submitLabel(.next)
                            .onSubmit { focus = .confirm }
                        AuthPasswordStrengthMeter(password: password)
                    }
                    AuthGlassField(title: "Confirm password", symbol: "lock.rotation", text: $confirm, kind: .secure,
                                   message: (!confirm.isEmpty && password != confirm) ? "Passwords don’t match." : nil,
                                   focus: $focus, focusValue: Field.confirm, identifier: "auth.reset.confirm")
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                        .accessibilityIdentifier("auth.reset.mismatch")
                    if let error { AuthErrorBanner(message: error) }
                    AuthPrimaryButton(title: "Update Password", busy: busy, enabled: canSubmit) {
                        Task { await submit() }
                    }
                    Button("Back to Sign In") { app.navigation.open(.auth(.login)) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                }
            }
        }
        .accessibilityIdentifier("auth.reset")
    }

    private var canSubmit: Bool {
        !token.isEmpty && password.count >= AuthPasswordRequirement.minimumLength && password == confirm && !busy
    }

    private func submit() async {
        guard !busy else { return }
        focus = nil
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.client.resetPassword(token: token, newPassword: password)
            password = ""
            confirm = ""
            withAnimation(.snappy) { done = true }
        } catch let api as APIError {
            error = api.userFacingMessage
            shake += 1
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = AuthenticationStore.offlineMessage
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

/// Live minimum-length requirement shown under new-password fields. Greenfield rejects
/// passwords under 10 characters on register, reset and change.
struct AuthPasswordRequirement: View {
    static let minimumLength = 10
    let password: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let minimum = Self.minimumLength
        let met = password.count >= minimum
        Label("At least \(minimum) characters", systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.footnote)
            .foregroundStyle(met ? app.appearance.liveAccent : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(met ? "Password meets the \(minimum) character minimum" : "Password needs at least \(minimum) characters")
    }
}

/// Primary auth action with an inline busy state and repeat-tap protection.
struct AuthPrimaryButton: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height = 52.0

    /// Full-width pill that contracts into a circular loader while busy.
    /// Under Reduce Motion the width stays fixed and only the content fades.
    var body: some View {
        let contracted = busy && !reduceMotion
        Button {
            guard !busy else { return }
            action()
        } label: {
            ZStack {
                if busy {
                    ProgressView()
                        .transition(.opacity)
                } else {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: contracted ? Self.height : .infinity)
            .frame(minHeight: Self.height)
            .modifier(AuthCTAStyle(active: enabled || busy))
            .contentShape(Capsule())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .animation(ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: reduceMotion), value: busy)
        .accessibilityLabel(title)
        .accessibilityValue(busy ? "In progress" : "")
    }
}

/// Auth primary CTA: a solid, high-contrast accent pill when it can be used (text colour picked
/// from the accent's luminance), and a neutral, clearly inert pill when it can't.
private struct AuthCTAStyle: ViewModifier {
    let active: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let accent = app.appearance.liveAccent
        if active {
            let ink = Self.ink(on: accent)
            content
                .foregroundStyle(ink)
                .tint(ink)
                .background {
                    Capsule().fill(accent)
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .black.opacity(0.10)], startPoint: .top, endPoint: .bottom)))
                }
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.75).allowsHitTesting(false))
                .shadow(color: accent.opacity(scheme == .dark ? 0.35 : 0.3), radius: 12, y: 5)
        } else {
            content
                .foregroundStyle(Color.primary.opacity(contrast == .increased ? 0.6 : 0.4))
                .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.1), lineWidth: 0.75))
        }
    }

    static func ink(on color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.62 ? .black : .white
    }
}

/// Terms consent as a field-height row aligned with the inputs above it.
struct AuthTermsRow: View {
    @Binding var accepted: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var height = 58.0

    var body: some View {
        Toggle(isOn: $accepted) {
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: "doc.text")
                    .font(.body.weight(.medium))
                    .foregroundStyle(accepted ? app.appearance.liveAccent : Color.primary.opacity(0.62))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("I agree to the Modula terms")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.primary)
        .padding(.leading, ModulaSpacing.md + 2)
        .padding(.trailing, ModulaSpacing.md)
        .frame(minHeight: height)
        .background(AuthFieldSurface.frost(scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
        .accessibilityIdentifier("auth.register.terms")
    }
}

extension AuthNoticeBanner where Accessory == EmptyView {
    init(message: String) { self.init(message: message) { EmptyView() } }
}

extension AuthBrandHeader where Extra == EmptyView {
    init(title: String, subtitle: String, compact: Bool = false) {
        self.init(title: title, subtitle: subtitle, compact: compact) { EmptyView() }
    }
}
