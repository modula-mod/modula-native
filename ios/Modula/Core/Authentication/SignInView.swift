import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    #if DEBUG
    @State private var fixtureUnavailable = false
    #endif

    private enum Field { case email, password }

    private var apiHost: String? {
        Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL")
            .flatMap { $0 as? String }
            .flatMap(URL.init(string:))?
            .host
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Environment", value: GreenfieldEnvironmentLabel.describe(host: apiHost))
                    .accessibilityIdentifier("auth.environment")
            } footer: {
                if GreenfieldEnvironmentLabel.isIsolatedFixture(host: apiHost) {
                    Text("This Debug build talks to the isolated N1 Greenfield fixture, not production. Use the N1 fixture account.")
                }
            }

            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .accessibilityIdentifier("auth.email")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .accessibilityIdentifier("auth.password")
            } header: {
                Text("Sign in")
            } footer: {
                Text("Your session is stored securely on this device. Modules never receive your account credentials.")
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if app.auth.busy { ProgressView() } else { Text("Sign In") }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("auth.sign-in")

                #if DEBUG
                if GreenfieldEnvironmentLabel.isIsolatedFixture(host: apiHost) {
                    Button("Sign in with N1 fixture") {
                        Task { await submitFixture() }
                    }
                    .disabled(app.auth.busy)
                    .accessibilityIdentifier("auth.sign-in-fixture")
                    if fixtureUnavailable {
                        Text("Could not read .env.n1.local. Run scripts/n1/fixture.mjs first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Button("Forgot Password") {
                    app.navigation.open(.auth(.forgotPassword))
                    HapticEngine.shared.play(.navigation)
                }
                .disabled(app.auth.busy)
                .accessibilityIdentifier("auth.forgot-password")

                Button("Create Account") {
                    app.navigation.open(.auth(.register))
                    HapticEngine.shared.play(.navigation)
                }
                .disabled(app.auth.busy)
                .accessibilityIdentifier("auth.create-account")
            }

            if let error = app.auth.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityLabel(error)
                        .accessibilityIdentifier("auth.error")
                    #if DEBUG
                    if let diagnostic = app.auth.lastDiagnostic, diagnostic != error {
                        Text(diagnostic)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("auth.error.diagnostic")
                    }
                    #endif
                }
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.login")
        .disabled(app.auth.busy)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !app.auth.busy
    }

    private func submit() async {
        guard canSubmit else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = password
        password = ""
        let ok = await app.auth.signIn(email: trimmed, password: credential)
        if ok {
            HapticEngine.shared.play(.success)
            app.navigation.completeAuthenticationReturn()
        } else {
            HapticEngine.shared.play(.failure)
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
            app.navigation.completeAuthenticationReturn()
        } else {
            HapticEngine.shared.play(.failure)
        }
    }
    #endif
}

struct RegisterPlaceholderView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section {
                Text("Account registration uses Greenfield’s verified email flow. Complete it on a supported surface, then return here to sign in.")
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
                Text("If an account exists for this email, Greenfield sends reset instructions.")
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
        .navigationTitle("Forgot Password")
        .accessibilityIdentifier("auth.forgot")
    }
}

struct AuthRouteView: View {
    let route: AuthRoute

    var body: some View {
        switch route {
        case .login, .root, .welcome:
            SignInView()
        case .register, .verify:
            RegisterPlaceholderView()
        case .forgotPassword, .resetPassword:
            ForgotPasswordView()
        }
    }
}
