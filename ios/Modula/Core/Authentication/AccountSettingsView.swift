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
            Form {
                Section("Identity") {
                    LabeledContent("Handle", value: "@\(account.primaryHandle)")
                    if let name = account.displayName, !name.isEmpty {
                        LabeledContent("Name", value: name)
                    }
                    if let email = account.email, !email.isEmpty {
                        LabeledContent("Email", value: email)
                    }
                    LabeledContent("Status", value: account.status.capitalized)
                    LabeledContent("Account ID", value: redact(account.accountId))
                }
                Section("Security") {
                    Button("Personal Information") { app.navigation.open(.settings(.account(.personalInformation))) }
                    Button("Username") { app.navigation.open(.settings(.account(.username))) }
                    Button("Email") { app.navigation.open(.settings(.account(.email))) }
                    Button("Password") { app.navigation.open(.settings(.account(.password))) }
                    Button("Sessions") { app.navigation.open(.settings(.account(.sessions))) }
                    Button("Delete Account") { app.navigation.open(.settings(.account(.deleteAccount))) }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await app.performSignOut(resetAppLock: true) }
                    }
                    .disabled(app.auth.busy)
                    .accessibilityIdentifier("account.sign-out")
                } footer: {
                    Text("Signing out clears the Keychain session on this device. Modules never receive account credentials.")
                }
                if let error = app.auth.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Account")
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
            .navigationTitle("Account")
        }
    }

    private func redact(_ id: String) -> String {
        guard id.count > 8 else { return "••••" }
        return String(id.prefix(4)) + "…" + String(id.suffix(4))
    }
}

private struct AccountPasswordView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section {
                Text("Greenfield resets passwords through email, not an in-app current-password form. Your password is never stored on this device.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Forgot Password") {
                    app.navigation.open(.auth(.forgotPassword))
                }
            }
        }
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
                    Text("No additional sessions were returned by Greenfield.")
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
        .navigationTitle("Delete Account")
    }
}
