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
            // Personal Information was a thin duplicate of the Account page.
            case .personalInformation: AccountRootView()
            case .username: UsernameChangeView()
            case .email: AccountEmailView()
            case .deleteAccount: DeleteAccountView()
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
                // Identity lives in the Settings header row; this page lists each fact once.
                SettingsGroup(title: "Account") {
                    SettingsTileRow(title: "Name", value: account.displayName ?? "—", symbol: "person.fill", showsChevron: false) {}
                        .disabled(true)
                    SettingsDivider()
                    SettingsTileRow(title: "Username", value: "@\(account.primaryHandle)", symbol: "at") {
                        app.navigation.open(.settings(.account(.username)))
                    }
                    SettingsDivider()
                    SettingsTileRow(title: "Email", value: account.email ?? "Not provided", symbol: "envelope.fill") {
                        app.navigation.open(.settings(.account(.email)))
                    }
                    SettingsDivider()
                    SettingsTileRow(title: "Status", value: account.status.capitalized, symbol: "checkmark.seal.fill", showsChevron: false) {}
                        .disabled(true)
                }
                SettingsGroup(title: "Security") {
                    SettingsTileRow(title: "Password", value: "Reset by email", symbol: "key.fill") {
                        app.navigation.open(.settings(.account(.password)))
                    }
                    SettingsDivider()
                    SettingsTileRow(title: "Sessions", symbol: "laptopcomputer.and.iphone") {
                        app.navigation.open(.settings(.account(.sessions)))
                    }
                    SettingsDivider()
                    SettingsTileRow(title: "App Lock & Face ID", symbol: "lock.fill") {
                        app.navigation.open(.settings(.privacy(.root)))
                    }
                }
                SettingsGroup(title: "") {
                    SettingsTileRow(title: "Delete Account", symbol: "trash.fill") {
                        app.navigation.open(.settings(.account(.deleteAccount)))
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
                        .stroke(app.appearance.liveAccent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 108, height: 108)
                        .scaleEffect(appeared && !reduceMotion ? 1 : 0.86)
                    Circle()
                        .stroke(app.appearance.liveAccent.opacity(0.7), lineWidth: 2)
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

    private struct SessionGroup { let key: String; let first: GreenfieldSessionInfo; var count: Int }

    private var groupedSessions: [SessionGroup] {
        var order: [String] = []
        var map: [String: SessionGroup] = [:]
        for s in sessions {
            let key = s.current ? "current" : [s.platform ?? "", s.userAgent ?? "", s.location ?? ""].joined(separator: "|")
            if map[key] == nil { order.append(key); map[key] = SessionGroup(key: key, first: s, count: 1) }
            else { map[key]?.count += 1 }
        }
        return order.compactMap { map[$0] }
    }

    private func deviceName(_ s: GreenfieldSessionInfo) -> String {
        if let p = s.platform, !p.isEmpty, p.lowercased() != "unknown" { return p }
        let ua = (s.userAgent ?? "").lowercased()
        if ua.contains("iphone") { return "iPhone" }
        if ua.contains("ipad") { return "iPad" }
        if ua.contains("android") { return "Android" }
        if ua.contains("mac") { return "Mac" }
        if ua.contains("windows") { return "Windows PC" }
        return "Unknown device"
    }

    private func deviceSymbol(_ s: GreenfieldSessionInfo) -> String {
        switch deviceName(s) {
        case "iPhone", "Android": "iphone"
        case "iPad": "ipad"
        case "Mac", "Windows PC": "laptopcomputer"
        default: "questionmark.circle"
        }
    }
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
                    // Client-side grouping: identical device/agent/location rows collapse into one
                    // with a count; missing platform reads as "Unknown device".
                    ForEach(groupedSessions, id: \.key) { group in
                        let session = group.first
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: deviceSymbol(session))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(session.current ? "This device" : deviceName(session))
                                        .font(.headline)
                                    if group.count > 1 {
                                        Text("×\(group.count)")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.08), in: Capsule())
                                    }
                                }
                                if let last = session.lastActive { Text(last).font(.caption).foregroundStyle(.secondary) }
                                if let location = session.location { Text(location).font(.caption).foregroundStyle(.secondary) }
                            }
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

