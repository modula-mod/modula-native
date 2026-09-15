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
            case .personalInformation, .username, .email, .deleteAccount:
                DevelopmentRouteView(title: title, symbol: "person.crop.circle")
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
                    NavigationLink("Password") {
                        AccountPasswordView()
                    }
                    NavigationLink("Sessions") {
                        AccountSessionsView()
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        app.runtime.revokeAll()
                        Task {
                            await app.auth.signOut()
                            HapticEngine.shared.play(.warning)
                        }
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
    var body: some View {
        Form {
            Section {
                Text("Use Forgot Password from Sign In to reset credentials through Greenfield. Direct password change will land with the account security surface.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Password")
    }
}

private struct AccountSessionsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section("This device") {
                LabeledContent("Session", value: app.auth.account == nil ? "Signed out" : "Active")
                LabeledContent("Storage", value: "Keychain (this device only)")
                if let host = Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String,
                   let url = URL(string: host), let name = url.host {
                    LabeledContent("API", value: name)
                }
            }
        }
        .navigationTitle("Sessions")
    }
}
