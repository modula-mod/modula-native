import SwiftUI

/// Security Center: one hierarchy for sign-in methods, recovery, devices and this iPhone's lock.
///
/// Real routes only:
/// - `GET /v1/auth/passkeys`, `DELETE /v1/auth/passkeys/:passkeyId`
/// - `GET /v1/auth/recovery-codes`, `POST /v1/auth/recovery-codes/regenerate`
/// - `GET /v1/auth/apple/status`
/// - `DELETE /v1/accounts/me/sessions` (sign out all other devices)
/// Gaps (no fake controls): login alerts (no route), native TOTP enrolment and passkey registration flows
/// (routes exist; the QR / ASAuthorization flows are not built), Apple linking flow.
/// Psychology: a visible checklist with status (goal-gradient) and plain-language footers reduce the anxiety
/// of security settings; destructive actions are confirmed (prevent errors, Nielsen #5).
struct SettingsSecurityCenter: View {
    @Environment(AppEnvironment.self) private var app
    @State private var passkeys: [RegisteredPasskey]?
    @State private var passkeyError: String?
    @State private var recovery: JSONValue?
    @State private var recoveryError: String?
    @State private var appleLinked: Bool?
    @State private var busy: String?
    @State private var confirmSignOutOthers = false
    @State private var pendingPasskeyDelete: RegisteredPasskey?
    @State private var regenerated: [String] = []

    var body: some View {
        let lock = app.appLock.settings
        Form {
            Section {
                statusRow("Passkeys", value: passkeys.map { $0.isEmpty ? "None" : "\($0.count)" } ?? "…",
                          symbol: "person.badge.key.fill", good: (passkeys?.isEmpty == false))
                statusRow("Recovery codes", value: recoverySummary, symbol: "key.horizontal.fill", good: recoveryRemaining.map { $0 > 0 } ?? false)
                statusRow("Sign in with Apple", value: appleLinked.map { $0 ? "Linked" : "Not linked" } ?? "…",
                          symbol: "apple.logo", good: appleLinked == true)
                statusRow("App Lock", value: lock.enabled ? "On" : "Off", symbol: "lock.fill", good: lock.enabled)
            } header: {
                Text("Overview")
            } footer: {
                Text("A green check means that protection is on. Each section below explains what it does and how to change it.")
            }

            Section {
                if let passkeys {
                    if passkeys.isEmpty {
                        Text("No passkeys on this account yet.").foregroundStyle(.secondary)
                    }
                    ForEach(passkeys.filter { $0.revokedAt == nil }) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.label ?? "Passkey").font(.body)
                                Text("Added \(Self.day(key.createdAt))" + (key.lastUsedAt.map { " · last used \(Self.day($0))" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { pendingPasskeyDelete = key } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(busy != nil)
                            .accessibilityLabel("Remove \(key.label ?? "passkey")")
                        }
                    }
                } else if let passkeyError {
                    Text(passkeyError).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Passkeys")
            } footer: {
                Text("Passkeys let you sign in with Face ID instead of a password. Removing one signs that passkey out everywhere. Adding new passkeys from this app is coming; the account already supports them.")
            }

            Section {
                LabeledContent("Status", value: recoverySummary)
                if !regenerated.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(regenerated, id: \.self) { Text($0).font(.body.monospaced()) }
                    }
                    .textSelection(.enabled)
                    Button("Copy codes") {
                        UIPasteboard.general.string = regenerated.joined(separator: "\n")
                        HapticEngine.shared.play(.confirmation)
                    }
                }
                Button {
                    Task { await regenerateRecovery() }
                } label: {
                    Text(busy == "recovery" ? "Generating…" : "Generate new recovery codes")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .modulaAccentCTA(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(busy != nil)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Recovery codes")
            } footer: {
                Text(recoveryError ?? "Recovery codes get you back in if you lose your device. New codes replace the old ones; store them somewhere safe. Codes are shown once.")
            }

            Section {
                Button { app.navigation.open(.settings(.account(.sessions))) } label: {
                    Label("Devices and sessions", systemImage: "laptopcomputer.and.iphone")
                }
                Button(role: .destructive) { confirmSignOutOthers = true } label: {
                    Label(busy == "sessions" ? "Signing out…" : "Sign out of all other devices", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(busy != nil)
            } header: {
                Text("Where you're signed in")
            } footer: {
                Text("See each device, when it was last active, and sign it out. Signing out all other devices keeps you signed in here.")
            }

            Section {
                Button { app.navigation.open(.settings(.privacy(.appLock))) } label: {
                    LabeledContent { Text(lock.enabled ? "On" : "Off") } label: { Label("App Lock", systemImage: "lock.fill") }
                }
                Button { app.navigation.open(.settings(.privacy(.biometrics))) } label: {
                    LabeledContent { Text(lock.biometricsEnabled ? "On" : "Off") } label: { Label("Face ID / Touch ID", systemImage: "faceid") }
                }
                Button { app.navigation.open(.settings(.account(.password))) } label: {
                    Label("Change password", systemImage: "key.fill")
                }
            } header: {
                Text("This iPhone")
            } footer: {
                Text("App Lock protects Modula on this device only. Login alerts for new sign-ins aren't available yet.")
            }
        }
        .navigationTitle("Security")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Sign out of all other devices?", isPresented: $confirmSignOutOthers, titleVisibility: .visible) {
            Button("Sign Out Others", role: .destructive) { Task { await signOutOthers() } }
        } message: {
            Text("You'll stay signed in on this iPhone.")
        }
        .confirmationDialog("Remove this passkey?", isPresented: Binding(get: { pendingPasskeyDelete != nil }, set: { if !$0 { pendingPasskeyDelete = nil } }), titleVisibility: .visible) {
            Button("Remove Passkey", role: .destructive) {
                if let key = pendingPasskeyDelete { Task { await deletePasskey(key) } }
            }
        } message: {
            Text("You can still sign in with your password or other passkeys.")
        }
        .accessibilityIdentifier("settings.security-center")
    }

    // MARK: Data

    private var recoveryRemaining: Int? {
        guard let recovery else { return nil }
        if let n = recovery["remaining"]?.int ?? recovery["remainingCount"]?.int ?? recovery["count"]?.int { return n }
        if case .array(let codes) = recovery["codes"] ?? .null { return codes.count }
        return nil
    }

    private var recoverySummary: String {
        if recoveryError != nil && recovery == nil { return "Unavailable" }
        guard recovery != nil else { return "…" }
        return recoveryRemaining.map { $0 == 0 ? "None left" : "\($0) remaining" } ?? "Set up"
    }

    private func load() async {
        guard app.auth.isSignedIn else { return }
        async let keys: Void = loadPasskeys()
        async let codes: Void = loadRecovery()
        async let apple: Void = loadApple()
        _ = await (keys, codes, apple)
    }

    private func loadPasskeys() async {
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/auth/passkeys")
            passkeys = try GreenfieldValueDecoder.decode([RegisteredPasskey].self, from: value["passkeys"] ?? value["items"] ?? value)
            passkeyError = nil
        } catch {
            passkeyError = "Couldn't load passkeys."
        }
    }

    private func loadRecovery() async {
        do {
            recovery = try await app.client.authenticatedJSON("GET", path: "/v1/auth/recovery-codes")
            recoveryError = nil
        } catch {
            recoveryError = (error as? APIError)?.userFacingMessage ?? "Couldn't read recovery code status."
        }
    }

    private func loadApple() async {
        if let value = try? await app.client.authenticatedJSON("GET", path: "/v1/auth/apple/status") {
            appleLinked = value["linked"]?.bool ?? value["isLinked"]?.bool ?? false
        }
    }

    private func regenerateRecovery() async {
        busy = "recovery"; defer { busy = nil }
        do {
            let value = try await app.client.authenticatedJSON("POST", path: "/v1/auth/recovery-codes/regenerate", body: .object([:]))
            if case .array(let codes) = value["codes"] ?? .null {
                regenerated = codes.compactMap(\.string)
            }
            HapticEngine.shared.play(.success)
            await loadRecovery()
        } catch {
            HapticEngine.shared.play(.failure)
            recoveryError = (error as? APIError)?.userFacingMessage ?? "Couldn't generate new codes. You may need to confirm your password first."
        }
    }

    private func signOutOthers() async {
        busy = "sessions"; defer { busy = nil }
        do {
            _ = try await app.client.authenticatedJSON("DELETE", path: "/v1/accounts/me/sessions")
            HapticEngine.shared.play(.success)
            app.navigation.flash("Signed out of other devices", symbol: "checkmark.shield.fill")
        } catch {
            HapticEngine.shared.play(.failure)
            app.navigation.flash((error as? APIError)?.userFacingMessage ?? "Couldn't sign out other devices", symbol: "exclamationmark.triangle")
        }
    }

    private func deletePasskey(_ key: RegisteredPasskey) async {
        busy = "passkey"; defer { busy = nil; pendingPasskeyDelete = nil }
        do {
            let id = key.passkeyId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key.passkeyId
            _ = try await app.client.authenticatedJSON("DELETE", path: "/v1/auth/passkeys/\(id)")
            passkeys?.removeAll { $0.id == key.id }
            HapticEngine.shared.play(.success)
        } catch {
            HapticEngine.shared.play(.failure)
            app.navigation.flash((error as? APIError)?.userFacingMessage ?? "Couldn't remove the passkey", symbol: "exclamationmark.triangle")
        }
    }

    // MARK: Helpers

    private func statusRow(_ title: String, value: String, symbol: String, good: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(app.appearance.liveAccent))
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Image(systemName: good ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(good ? Color.green : Color.secondary)
                .accessibilityLabel(good ? "On" : "Off")
        }
        .accessibilityElement(children: .combine)
    }

    private static func day(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? iso.prefix(10).description
    }
}
