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
                VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                    SignInBrandMark(compact: true)
                        .padding(.bottom, ModulaSpacing.xs)
                    Text(title)
                        .font(.system(.largeTitle, design: app.appearance.fontDesign).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ModulaGlassGroup(spacing: ModulaSpacing.md) {
                    content
                }
            }
            .padding(.horizontal, ModulaSpacing.lg)
            .padding(.vertical, ModulaSpacing.md)
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
/// (`glassEffect`, grouped by `ModulaGlassGroup`), `modulaGlass` before that and a
/// solid fill under Reduce Transparency. Leading icon, floating label, an inner top
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
                    .foregroundStyle(hasError ? Color.red : (isFocused ? accent : Color.secondary))
                    .frame(width: iconWidth)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    Text(title)
                        .font(floated ? .caption.weight(.semibold) : .body)
                        .foregroundStyle(hasError ? Color.red : (isFocused ? accent : Color.secondary))
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
                            .foregroundStyle(.secondary)
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
        } else {
            Color.clear
                .modulaGlass(in: Capsule(), interactive: false, tint: isFocused ? accent.opacity(0.14) : nil)
        }
    }

    /// Focus/error ring plus an inner top highlight (the "lip" of the glass).
    private var rim: some View {
        ZStack {
            Capsule()
                .strokeBorder(
                    hasError ? Color.red.opacity(0.8)
                        : isFocused ? accent.opacity(0.9)
                        : Color.primary.opacity(contrast == .increased ? 0.3 : 0.08),
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .padding(ModulaSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(scheme == .dark ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            .onAppear { AccessibilityNotification.Announcement(message).post() }
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
                AuthGlassField(title: "Display name", symbol: "person", text: $displayName,
                               focus: $focus, focusValue: Field.displayName, identifier: "auth.register.display-name")
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                    AuthGlassField(title: "Password", symbol: "lock", text: $password, kind: .secure,
                                   prompt: "At least 8 characters.", focus: $focus, focusValue: Field.password,
                                   identifier: "auth.register.password", shake: shake)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                    AuthPasswordStrengthMeter(password: password)
                }
                Toggle(isOn: $acceptedTerms) {
                    Text("I agree to the Modula terms").font(.subheadline)
                }
                .tint(app.appearance.liveAccent)
                .padding(.horizontal, ModulaSpacing.xs)
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
                AuthPrimaryButton(title: "Create Account", busy: busy, enabled: canSubmit) {
                    Task { await submit() }
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

    private var canSubmit: Bool {
        !email.isEmpty && !handle.isEmpty && password.count >= 8 && acceptedTerms && !busy
    }

    private func submit() async {
        guard !busy else { return }
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
            let result = try await app.client.register(payload: RegistrationPayload(
                email: trimmedEmail,
                password: password,
                handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.isEmpty ? nil : displayName,
                inviteCode: nil,
                acceptedTerms: acceptedTerms
            ))
            password = ""
            HapticEngine.shared.play(.success)
            if result.verificationRequired {
                app.navigation.open(.auth(.verify))
            } else {
                app.navigation.open(.auth(.login))
            }
        } catch let api as APIError {
            error = api.userFacingMessage
            #if DEBUG
            diagnostic = api.diagnosticDescription
            #endif
            shake += 1
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "Unable to create an account right now."
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

// MARK: - Verify

struct VerifyEmailView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var code = ""
    @State private var token = ""
    @State private var email = ""
    @State private var error: String?
    @State private var busy = false
    @State private var sent = false
    @State private var resending = false
    @State private var verified = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case code, token, email }

    var body: some View {
        AuthChrome(title: verified ? "You’re verified" : "Verify your email", subtitle: verified ? "Your email is confirmed." : "Enter the code we emailed you.") {
            if verified {
                AuthSuccessState(title: "Email verified", message: "Sign in to start building your Modula.", actionTitle: "Continue to Sign In") {
                    app.navigation.open(.auth(.login))
                }
            } else {
                VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                    AuthGlassField(title: "Verification code", symbol: "number", text: $code,
                                   focus: $focus, focusValue: Field.code, identifier: "auth.verify.code", shake: shake)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                    AuthGlassField(title: "Token (optional)", symbol: "key", text: $token,
                                   focus: $focus, focusValue: Field.token, identifier: "auth.verify.token")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    AuthGlassField(title: "Email for resend", symbol: "envelope", text: $email,
                                   focus: $focus, focusValue: Field.email, identifier: "auth.verify.email")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let error { AuthErrorBanner(message: error) }
                    AuthPrimaryButton(title: "Verify", busy: busy, enabled: !(code.isEmpty && token.isEmpty) && !busy) {
                        Task { await verify() }
                    }
                    Button {
                        Task { await resend() }
                    } label: {
                        HStack(spacing: 8) {
                            if resending { ProgressView().controlSize(.small) }
                            Text("Resend code")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                    }
                    .foregroundStyle(app.appearance.liveAccent)
                    .disabled(email.isEmpty || resending)
                    if sent {
                        Label("If that email is registered, a new code is on its way.", systemImage: "paperplane.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("auth.verify")
    }

    private func verify() async {
        guard !busy else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await app.client.verifyEmail(challengeID: nil, code: code.isEmpty ? nil : code, token: token.isEmpty ? nil : token)
            withAnimation(.snappy) { verified = true }
        } catch let api as APIError {
            error = api.userFacingMessage
            shake += 1
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "Verification didn’t succeed."
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }

    private func resend() async {
        guard !resending else { return }
        resending = true
        defer { resending = false }
        error = nil
        do {
            try await app.client.resendVerification(email: email)
            sent = true
            HapticEngine.shared.play(.confirmation)
        } catch let api as APIError {
            error = api.userFacingMessage
        } catch {
            self.error = "Unable to resend verification."
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
        !token.isEmpty && password.count >= 8 && password == confirm && !busy
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
            self.error = "Unable to reset the password."
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

/// Live 8+ character requirement shown under new-password fields.
struct AuthPasswordRequirement: View {
    let password: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let met = password.count >= 8
        Label("At least 8 characters", systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.footnote)
            .foregroundStyle(met ? app.appearance.liveAccent : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(met ? "Password meets the 8 character minimum" : "Password needs at least 8 characters")
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

    private static let height = 48.0

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
            // Every primary action wears the shared accent CTA (fill, rim, lift; outline when disabled).
            .modulaAccentCTA()
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
