import SwiftUI

/// Signed-in account surface for `/settings/account`. Never shows the login form while authenticated.
struct AccountSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    let route: AccountSettingsRoute

    var body: some View {
        Group {
            switch route {
            case .root: AccountRootView()
            case .password: AccountPasswordView()
            case .sessions: AccountSessionsView()
            case .personalInformation: AccountPersonalInformationView()
            case .username: AccountUsernameView()
            case .email: AccountEmailView()
            case .deleteAccount: AccountDeleteView()
            }
        }
        .accessibilityIdentifier("settings.account.\(route.rawValue)")
    }

    private var title: String {
        route.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct AccountRootView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let account = app.auth.account {
            SettingsScrollCanvas {
                AccountIdentityGraphic(
                    name: account.displayName?.isEmpty == false ? account.displayName! : account.primaryHandle,
                    handle: "@\(account.primaryHandle)",
                    status: account.status.capitalized,
                    avatarURL: app.profile.ownProfile?.avatarURL
                )
                SettingsGroup(title: "This account") {
                    VStack(spacing: 0) {
                        accountFact("Handle", "@\(account.primaryHandle)", "at")
                        SettingsDivider()
                        accountFact("Status", account.status.capitalized, "checkmark.seal")
                        SettingsDivider()
                        accountFact("Account ID", redact(account.accountId), "number")
                        if let email = account.email, !email.isEmpty {
                            SettingsDivider()
                            accountFact("Email", email, "envelope")
                        }
                    }
                }
                SettingsGroup(title: "Security") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Personal Information", subtitle: "Private account details", symbol: "person.text.rectangle") {
                            app.navigation.open(.settings(.account(.personalInformation)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Username", subtitle: "@\(account.primaryHandle)", symbol: "at") {
                            app.navigation.open(.settings(.account(.username)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Email", subtitle: account.email ?? "Not provided on this session", symbol: "envelope") {
                            app.navigation.open(.settings(.account(.email)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Password", subtitle: "Reset by email", symbol: "key") {
                            app.navigation.open(.settings(.account(.password)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Sessions", subtitle: "Devices signed into this account", symbol: "laptopcomputer.and.iphone") {
                            app.navigation.open(.settings(.account(.sessions)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Delete Account", subtitle: "Close this Modula account", symbol: "trash") {
                            app.navigation.open(.settings(.account(.deleteAccount)))
                        }
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task { await app.performSignOut(resetAppLock: true) }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .disabled(app.auth.busy)
                .accessibilityIdentifier("account.sign-out")
                SettingsAPIFootnote(text: "Signing out clears the Keychain session on this device. Modules never receive account credentials.")
                if let error = app.auth.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if app.auth.busy { ProgressView() } }
        } else {
            ContentUnavailableView {
                Label("Sign in required", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Sign in to manage your Modula account.")
            } actions: {
                Button("Sign In") {
                    app.navigation.requestAuthentication(returningTo: .settings(.account(.root)))
                }
                .accessibilityIdentifier("account.sign-in-cta")
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Account")
        }
    }

    private func accountFact(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func redact(_ id: String) -> String {
        guard id.count > 8 else { return "••••" }
        return String(id.prefix(4)) + "…" + String(id.suffix(4))
    }
}

private struct AccountIdentityGraphic: View {
    var name: String
    var handle: String
    var status: String
    var avatarURL: URL?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        SettingsGraphicFrame(caption: "\(status) session on this device") {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(app.appearance.accent.color.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 108, height: 108)
                        .scaleEffect(appeared && !reduceMotion ? 1 : 0.86)
                    Circle()
                        .stroke(app.appearance.accent.color.opacity(0.7), lineWidth: 2)
                        .frame(width: 92, height: 92)
                    ModulaAvatar(initials: String(name.prefix(1)), url: avatarURL, size: 72)
                        .scaleEffect(appeared ? 1 : 0.9)
                }
                VStack(spacing: 2) {
                    Text(name).font(.title3.weight(.semibold))
                    Text(handle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(handle), \(status)")
    }
}

private struct AccountPasswordView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section {
                Text("We’ll email you a link to reset your password. Your password is never stored on this device.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Forgot Password") {
                    app.navigation.open(.auth(.forgotPassword))
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Password")
    }
}

private struct AccountSessionsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var sessions: [GreenfieldSessionInfo] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section("This device") {
                LabeledContent("Session", value: app.auth.account == nil ? "Signed out" : "Active")
                LabeledContent("Storage", value: "Keychain (this device only)")
            }
            Section("Other sessions") {
                if !loaded {
                    ProgressView()
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else if sessions.isEmpty {
                    Text("No other signed-in devices.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.current ? "This session" : (session.platform ?? "Session"))
                                .font(.headline)
                            if let agent = session.userAgent { Text(agent).font(.caption).foregroundStyle(.secondary) }
                            if let last = session.lastActive { Text(last).font(.caption).foregroundStyle(.secondary) }
                            if let location = session.location { Text(location).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Sign Out All Other Sessions", role: .destructive) {
                        Task {
                            do {
                                try await app.client.revokeOtherSessions()
                                await load()
                            } catch let api as APIError {
                                error = api.userFacingMessage
                            } catch {
                                self.error = "Could not revoke other sessions."
                            }
                        }
                    }
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Sessions")
        .task { await load() }
    }

    private func load() async {
        do {
            sessions = try await app.client.listSessions()
            loaded = true
            error = nil
        } catch let api as APIError {
            loaded = true
            error = api.userFacingMessage
        } catch {
            loaded = true
            self.error = "Session list isn’t available right now."
        }
    }
}

private struct AccountPersonalInformationView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Form {
            if let account = app.auth.account {
                LabeledContent("Name", value: account.displayName ?? "—")
                LabeledContent("Email", value: account.email ?? "Not provided on this session")
                LabeledContent("Account ID", value: redact(account.accountId))
                Text("These details are private account metadata. They never appear on Profile.")
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Personal Information")
    }

    private func redact(_ id: String) -> String {
        guard id.count > 8 else { return "••••" }
        return String(id.prefix(4)) + "…" + String(id.suffix(4))
    }
}

private struct AccountUsernameView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let dest = SettingsRegistry.destination(for: .account(.username))
        Form {
            LabeledContent("Current username", value: app.auth.account.map { "@\($0.primaryHandle)" } ?? "—")
            Text(dest?.unavailableReason ?? "Username cannot be changed in this client.")
                .foregroundStyle(.secondary)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Username")
    }
}

private struct AccountEmailView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let dest = SettingsRegistry.destination(for: .account(.email))
        Form {
            LabeledContent("Current email", value: app.auth.account?.email ?? "Not provided")
            Text(dest?.unavailableReason ?? "Email cannot be changed in this client.")
                .foregroundStyle(.secondary)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Email")
    }
}

private struct AccountDeleteView: View {
    @State private var confirmation = ""
    var body: some View {
        let dest = SettingsRegistry.destination(for: .account(.deleteAccount))
        Form {
            Text(dest?.unavailableReason ?? "Account deletion isn’t available.")
                .foregroundStyle(.secondary)
            TextField("Type DELETE to confirm", text: $confirmation)
                .textInputAutocapitalization(.characters)
                .disabled(true)
            Button("Delete Account", role: .destructive) {}
                .disabled(true)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Delete Account")
    }
}
