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
            let compact = proxy.size.height < 700 || dynamicTypeSize.isAccessibilitySize
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        brand(compact: compact)
                            .padding(.top, compact ? ModulaSpacing.sm : ModulaSpacing.xl)
                        Spacer(minLength: compact ? ModulaSpacing.lg : ModulaSpacing.xl)
                        form
                        Spacer(minLength: compact ? ModulaSpacing.lg : ModulaSpacing.xl)
                        footer
                    }
                    .padding(.horizontal, ModulaSpacing.lg)
                    .padding(.bottom, ModulaSpacing.md)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: focused) { _, field in
                    guard let field else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        reader.scrollTo(field, anchor: .center)
                    }
                    if field == .password { emailTouched = true }
                }
            }
        }
        .background {
            PerspectiveGridView()
                .ignoresSafeArea()
                .overlay {
                    // Legibility scrim over the grid for the form.
                    Color(uiColor: .systemBackground).opacity(0.35).ignoresSafeArea()
                }
        }
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
        VStack(spacing: compact ? ModulaSpacing.sm : ModulaSpacing.md) {
            SignInBrandMark(compact: compact)
            VStack(spacing: ModulaSpacing.xs) {
                ModulaWordmark(height: 20)
                    .accessibilityHidden(true)
                Text("Welcome back")
                    .font(.system(.largeTitle, design: app.appearance.fontDesign).weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Sign in to your digital world, your way.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.md) {
            ModulaFormField(
                title: "Email or username",
                symbol: "envelope",
                text: $email,
                prompt: "Email or username",
                message: emailMessage,
                focus: $focused,
                focusValue: Field.email,
                identifier: "auth.email"
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
                ModulaFormField(
                    title: "Password",
                    symbol: "lock",
                    text: $password,
                    kind: .secure,
                    prompt: "Password",
                    message: passwordMessage,
                    focus: $focused,
                    focusValue: Field.password,
                    identifier: "auth.password"
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

            ModulaButton(title: "Sign In", isLoading: app.auth.busy, loadingTitle: "Signing in…") {
                Task { await submit() }
            }
            .disabled(!canSubmit)
            .accessibilityIdentifier("auth.sign-in")
            .padding(.top, ModulaSpacing.xxs)
        }
        .padding(ModulaSpacing.lg)
        .modulaMaterial(.content, in: cardShape, depth: .floating)
        .overlay(cardShape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.07), lineWidth: 0.75))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: app.auth.error)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: emailMessage)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: passwordMessage)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: app.appearance.interfaceShape.radius(for: .contentCard) + 6, style: .continuous)
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: ModulaSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(error)
                    .accessibilityIdentifier("auth.error")
            }
            #if DEBUG
            if let diagnostic = app.auth.lastDiagnostic, diagnostic != error {
                Text(diagnostic)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("auth.error.diagnostic")
            }
            #endif
        }
        .padding(ModulaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(scheme == .dark ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: app.appearance.interfaceShape.radius(for: .control), style: .continuous))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
private struct SignInBrandMark: View {
    var compact = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var size = 76.0

    var body: some View {
        let side = min(size * (compact ? 0.82 : 1), compact ? 84 : 112)
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

/// Full-bleed canvas with a restrained accent wash at the top and a quieter
/// counter-glow at the bottom; flattens under Reduce Transparency.
private struct SignInBackdrop: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = ModulaPalette.resolve(app.appearance, scheme: scheme)
        let accent = app.appearance.liveAccent
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let strength = (scheme == .dark ? 0.34 : 0.22) * (opaque ? 0.5 : 1)
        ZStack {
            palette.canvas
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack {
                    RadialGradient(colors: [accent.opacity(strength), .clear], center: .top,
                                   startRadius: 0, endRadius: max(width, 320) * 0.95)
                    RadialGradient(colors: [accent.opacity(strength * 0.45), .clear], center: .bottomTrailing,
                                   startRadius: 0, endRadius: max(width, 320) * 0.8)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
        .modulaSoftScrollEdge()
        .navigationTitle("Create Account")
        .accessibilityIdentifier("auth.register")
    }
}

struct ForgotPasswordView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("auth.forgot.email")
            } footer: {
                Text("If an account exists for this email, we’ll send reset instructions.")
            }
            Section {
                Button {
                    Task {
                        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        sent = await app.auth.requestPasswordReset(email: trimmed)
                        if sent { HapticEngine.shared.play(.confirmation) }
                        else { HapticEngine.shared.play(.failure) }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if app.auth.busy { ProgressView() } else { Text("Send Reset Link") }
                        Spacer()
                    }
                }
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.auth.busy)
                .accessibilityIdentifier("auth.forgot.submit")

                Button("Back to Sign In") {
                    app.navigation.open(.auth(.login))
                }
            }
            if sent {
                Section {
                    Text("If that email is registered, a reset message is on its way.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("auth.forgot.sent")
                }
            }
            if let error = app.auth.error {
                Section {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.forgot.error")
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Forgot Password")
        .accessibilityIdentifier("auth.forgot")
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
