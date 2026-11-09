import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var password = ""
    @State private var emailTouched = false
    @State private var attemptedSubmit = false
    @State private var appeared = false
    @State private var shake = 0
    /// Tallest height seen: the layout keeps its rhythm when the keyboard shrinks the view.
    @State private var stableHeight: CGFloat = 0
    @FocusState private var focused: Field?
    #if DEBUG
    @State private var fixtureUnavailable = false
    #endif

    private enum Field: Hashable { case email, password }

    private var apiHost: String? {
        app.client.apiOriginHost
    }

    var body: some View {
        GeometryReader { proxy in
            // Compact heights (iPhone SE, keyboard up, large text) tighten the rhythm.
            let height = max(proxy.size.height, stableHeight)
            let compact = height < 700 || dynamicTypeSize.isAccessibilitySize
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        brand(compact: compact)
                            .padding(.top, ModulaSpacing.sm)
                        form
                            .padding(.top, compact ? ModulaSpacing.lg : ModulaSpacing.xl)
                        Spacer(minLength: compact ? ModulaSpacing.lg : ModulaSpacing.xl)
                        footer
                    }
                    .padding(.horizontal, ModulaSpacing.lg)
                    .padding(.bottom, ModulaSpacing.md)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: height)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .onAppear { stableHeight = max(stableHeight, proxy.size.height) }
                .onChange(of: proxy.size.width) { _, _ in stableHeight = proxy.size.height }
                .onChange(of: focused) { _, field in
                    guard let field else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        reader.scrollTo(field, anchor: .center)
                    }
                    if field == .password { emailTouched = true }
                }
            }
        }
        .modulaAuthBackdrop()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.login")
        .disabled(app.auth.busy)
        .onAppear {
            guard !appeared else { return }
            withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
        .onChange(of: email) { _, _ in clearStaleError() }
        .onChange(of: password) { _, value in if !value.isEmpty { clearStaleError() } }
        .onChange(of: app.auth.error) { _, error in
            guard let error else { return }
            AccessibilityNotification.Announcement(error).post()
        }
    }

    // MARK: Brand

    private func brand(compact: Bool) -> some View {
        AuthBrandHeader(title: "Welcome back", subtitle: "Sign in to your digital world, your way.", compact: compact) {
            if app.gate.pendingDestination != nil {
                Label("After you sign in, Modula opens the link you followed.", systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("auth.pendingLink")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Form

    private var form: some View {
        ModulaGlassGroup(spacing: ModulaSpacing.md) { formFields }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.md) {
            AuthGlassField(
                title: "Email or username",
                symbol: "envelope",
                text: $email,
                prompt: "Email or username",
                message: emailMessage,
                focus: $focused,
                focusValue: Field.email,
                identifier: "auth.email",
                shake: shake
            )
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit {
                emailTouched = true
                focused = .password
            }
            .id(Field.email)

            VStack(alignment: .trailing, spacing: ModulaSpacing.xxs) {
                AuthGlassField(
                    title: "Password",
                    symbol: "lock",
                    text: $password,
                    kind: .secure,
                    prompt: "Password",
                    message: passwordMessage,
                    focus: $focused,
                    focusValue: Field.password,
                    identifier: "auth.password",
                    shake: shake
                )
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
                .id(Field.password)

                Button("Forgot password?") {
                    app.navigation.open(.auth(.forgotPassword))
                    HapticEngine.shared.play(.navigation)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(minHeight: ModulaLayout.minimumTouch)
                .disabled(app.auth.busy)
                .accessibilityIdentifier("auth.forgot-password")
            }

            if let error = app.auth.error {
                errorBanner(error)
            }

            AuthPrimaryButton(title: "Sign In", busy: app.auth.busy, enabled: canSubmit) {
                Task { await submit() }
            }
            .accessibilityIdentifier("auth.sign-in")
            .padding(.top, ModulaSpacing.xxs)
        }
        // Fields are Liquid Glass themselves, so they float straight on the backdrop
        // (glass can't sample glass, so no card behind them).
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: app.auth.error)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: emailMessage)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: passwordMessage)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: app.appearance.interfaceShape.radius(for: .contentCard) + 6, style: .continuous)
    }

    private func errorBanner(_ error: String) -> some View {
        AuthNoticeBanner(message: error) {
            #if DEBUG
            if let diagnostic = app.auth.lastDiagnostic, diagnostic != error {
                Text(diagnostic)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("auth.error.diagnostic")
            }
            #endif
        }
        .accessibilityLabel(error)
        .accessibilityIdentifier("auth.error")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: ModulaSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ModulaSpacing.xxs) { createAccountPrompt }
                VStack(spacing: ModulaSpacing.xxs) { createAccountPrompt }
            }

            #if DEBUG
            if GreenfieldEnvironmentLabel.isIsolatedFixture(host: apiHost) {
                VStack(spacing: ModulaSpacing.xs) {
                    Button {
                        Task { await submitFixture() }
                    } label: {
                        Label("Sign in with N1 fixture", systemImage: "hammer")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, ModulaSpacing.md)
                            .frame(minHeight: ModulaLayout.minimumTouch)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modulaMaterial(.control, in: Capsule())
                    .disabled(app.auth.busy)
                    .accessibilityIdentifier("auth.sign-in-fixture")
                    if fixtureUnavailable {
                        Text("Could not read .env.n1.local. Run scripts/n1/fixture.mjs first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(GreenfieldEnvironmentLabel.describe(host: apiHost))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("auth.environment")
                }
            }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var createAccountPrompt: some View {
        Text("New to Modula?")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Button("Create account") {
            app.navigation.open(.auth(.register))
            HapticEngine.shared.play(.navigation)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(app.appearance.liveAccent)
        .frame(minHeight: ModulaLayout.minimumTouch)
        .disabled(app.auth.busy)
        .accessibilityIdentifier("auth.create-account")
    }

    // MARK: Validation

    /// A server error describes the last attempt; editing starts a new one.
    private func clearStaleError() {
        guard !app.auth.busy, app.auth.error != nil else { return }
        app.auth.error = nil
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailMessage: String? {
        guard emailTouched || attemptedSubmit else { return nil }
        if trimmedEmail.isEmpty { return "Enter your email or username." }
        if trimmedEmail.contains("@"), !Self.looksLikeEmail(trimmedEmail) {
            return "That email address looks incomplete."
        }
        return nil
    }

    private var passwordMessage: String? {
        guard attemptedSubmit, password.isEmpty, app.auth.error == nil else { return nil }
        return "Enter your password."
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        value.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty
            && !password.isEmpty
            && !app.auth.busy
    }

    private func submit() async {
        guard canSubmit else {
            attemptedSubmit = true
            focused = trimmedEmail.isEmpty ? .email : .password
            shake += 1
            HapticEngine.shared.play(.warning)
            return
        }
        attemptedSubmit = false
        focused = nil
        let trimmed = trimmedEmail
        let credential = password
        password = ""
        let ok = await app.auth.signIn(email: trimmed, password: credential)
        if ok {
            HapticEngine.shared.play(.success)
            app.refreshLaunchState()
        } else {
            shake += 1
            HapticEngine.shared.play(.failure)
            // Wait for the busy-disabled form to re-enable before moving focus.
            DispatchQueue.main.async { focused = .password }
        }
    }

    #if DEBUG
    private func submitFixture() async {
        guard let fixture = N1FixtureCredentials.load() else {
            fixtureUnavailable = true
            return
        }
        fixtureUnavailable = false
        email = fixture.email
        password = ""
        let ok = await app.auth.signIn(email: fixture.email, password: fixture.password)
        if ok {
            HapticEngine.shared.play(.success)
            app.refreshLaunchState()
        } else {
            HapticEngine.shared.play(.failure)
        }
    }
    #endif
}

/// App icon as the brand moment: a soft accent halo behind the real icon.
struct SignInBrandMark: View {
    var compact = false
    /// Fixed side length (e.g. the compact header lockup); nil scales with Dynamic Type.
    var side: CGFloat? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var size = 76.0

    var body: some View {
        let side = self.side ?? min(size * (compact ? 0.82 : 1), compact ? 84 : 112)
        ModulaUnitTile(variant: .teal)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            }
            .shadow(color: app.appearance.liveAccent.opacity(reduceTransparency ? 0.2 : 0.45), radius: side * 0.32, y: side * 0.12)
            .accessibilityHidden(true)
    }
}

struct RegisterPlaceholderView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section {
                Text("Create your account with your email address, then come back here to sign in.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Back to Sign In") {
                    app.navigation.open(.auth(.login))
                }
                .accessibilityIdentifier("auth.register.back")
            }
        }
        .scrollContentBackground(.hidden)
        .background { ModulaAuthBackdrop(calm: true) }
        .modulaSoftScrollEdge()
        .navigationTitle("Create Account")
        .accessibilityIdentifier("auth.register")
    }
}

struct ForgotPasswordView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var sent = false
    @State private var attempted = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email }

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        AuthChrome(
            title: sent ? "Check your email" : "Forgot password?",
            subtitle: sent ? "We’ve sent reset instructions if an account exists." : "Enter your email and we’ll send you a link to reset it."
        ) {
            if sent {
                AuthSuccessState(
                    title: "Reset link sent",
                    message: "If \(trimmed) is registered, a reset message is on its way. It can take a minute; check spam too.",
                    actionTitle: "Back to Sign In",
                    action: { app.navigation.open(.auth(.login)) },
                    secondaryTitle: "Use a different email",
                    secondaryAction: { withAnimation(reduceMotion ? nil : .snappy) { sent = false } }
                )
                .accessibilityIdentifier("auth.forgot.sent")
            } else {
                VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                    AuthGlassField(
                        title: "Email", symbol: "envelope", text: $email,
                        message: attempted && !SignInView.looksLikeEmail(trimmed) ? "Enter the email you signed up with." : nil,
                        focus: $focus, focusValue: Field.email, identifier: "auth.forgot.email", shake: shake
                    )
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                    if let error = app.auth.error {
                        AuthErrorBanner(message: error).accessibilityIdentifier("auth.forgot.error")
                    }
                    AuthPrimaryButton(title: "Send Reset Link", busy: app.auth.busy, enabled: !trimmed.isEmpty) {
                        Task { await send() }
                    }
                    .accessibilityIdentifier("auth.forgot.submit")
                    Button("Back to Sign In") { app.navigation.open(.auth(.login)) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                }
            }
        }
        .accessibilityIdentifier("auth.forgot")
        .onAppear { focus = .email }
    }

    private func send() async {
        guard SignInView.looksLikeEmail(trimmed) else {
            attempted = true
            shake += 1
            HapticEngine.shared.play(.warning)
            return
        }
        focus = nil
        if await app.auth.requestPasswordReset(email: trimmed) {
            withAnimation(reduceMotion ? nil : .snappy) { sent = true }
        } else {
            shake += 1
            HapticEngine.shared.play(.failure)
        }
    }
}

struct AuthRouteView: View {
    let route: AuthRoute

    var body: some View {
        switch route {
        case .welcome:
            OnboardingView()
        case .login, .root:
            SignInView()
        case .register:
            RegisterView()
        case .verify:
            VerifyEmailView()
        case .forgotPassword:
            ForgotPasswordView()
        case .resetPassword:
            ResetPasswordView()
        }
    }
}
