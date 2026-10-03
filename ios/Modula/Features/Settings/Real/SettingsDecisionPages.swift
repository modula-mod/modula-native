import SwiftUI

// Pages whose last step needs a product/ops decision. Each shows the real data that
// exists today and names exactly what is missing, instead of a fake control.

// MARK: - Passkeys (`GET /v1/auth/passkeys`)

struct RegisteredPasskey: Decodable, Sendable, Identifiable, Equatable {
    var id: String { passkeyId }
    let passkeyId: String
    let createdAt: String
    let lastUsedAt: String?
    let backupEligible: Bool?
    let label: String?
    let revokedAt: String?
}

enum PasskeySupport {
    /// Bundle IDs the modula.digital association file lists for `webcredentials` today.
    static let associatedAppIDs = ["M29V4ZGUNK.digital.modula.app"]

    /// Passkeys need this app's ID in the domain's association file and the
    /// Associated Domains entitlement in the app. Both are checked, not assumed.
    nonisolated static func nativeCreationReady(bundleID: String?, teamID: String = "M29V4ZGUNK", hasEntitlement: Bool) -> Bool {
        guard let bundleID, hasEntitlement else { return false }
        return associatedAppIDs.contains("\(teamID).\(bundleID)")
    }
}

struct PasskeysSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var passkeys: [RegisteredPasskey]?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if let passkeys {
                    let active = passkeys.filter { $0.revokedAt == nil }
                    if active.isEmpty {
                        Text("No passkeys on this account.").foregroundStyle(.secondary)
                    }
                    ForEach(active) { passkey in
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.key.fill").foregroundStyle(app.appearance.accent.color).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(passkey.label ?? "Passkey").font(.body.weight(.medium))
                                Text(Self.detail(passkey)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } header: {
                Text("On your account")
            } footer: {
                Text("Passkeys you added on the web sign you in at modula.digital.")
            }
            Section {
                Label("Adding a passkey from this app isn’t set up yet", systemImage: "info.circle")
                Text("iOS only lets an app create passkeys for modula.digital once the site lists the app and the app declares the domain. The site currently lists a different app ID, so the button stays hidden rather than failing.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("This iPhone")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    nonisolated static func detail(_ passkey: RegisteredPasskey) -> String {
        let added = SettingsISODate.parse(passkey.createdAt)?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        let used = SettingsISODate.parse(passkey.lastUsedAt)?.formatted(.relative(presentation: .named))
        let synced = passkey.backupEligible == true ? " · Synced" : ""
        return "Added \(added)\(used.map { " · Last used \($0)" } ?? "")\(synced)"
    }

    private func load() async {
        guard app.auth.isSignedIn else { passkeys = []; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/auth/passkeys")
            passkeys = try GreenfieldValueDecoder.decode([RegisteredPasskey].self, from: value)
            error = nil
        } catch {
            self.error = "Couldn’t load passkeys."
        }
    }
}

// MARK: - Connectors (`GET /v1/connectors`, `GET /v1/connections`)

struct ConnectorProvider: Decodable, Sendable, Identifiable, Equatable {
    var id: String { providerId }
    let providerId: String
    let displayName: String
    let configuredStatus: String?
    let operational: Bool?
    let privacySummary: String?
    let capabilities: [String]?

    var canConnect: Bool { configuredStatus == "configured" && operational == true }

    var statusLabel: String {
        if canConnect { return "Available" }
        switch configuredStatus {
        case "not-configured": return "Not set up on Modula’s servers yet"
        case "disabled": return "Turned off"
        default: return "Unavailable"
        }
    }
}

struct ConnectorsSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var providers: [ConnectorProvider]?
    @State private var connections: [JSONValue] = []
    @State private var error: String?

    var body: some View {
        List {
            if !connections.isEmpty {
                Section("Connected") {
                    ForEach(Array(connections.enumerated()), id: \.offset) { _, connection in
                        Label(Self.connectionTitle(connection), systemImage: "link")
                    }
                }
            }
            Section {
                if let providers {
                    ForEach(providers) { provider in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(provider.displayName).font(.body.weight(.medium))
                                Spacer()
                                Text(provider.statusLabel)
                                    .font(.caption)
                                    .foregroundStyle(provider.canConnect ? AnyShapeStyle(app.appearance.accent.color) : AnyShapeStyle(.secondary))
                            }
                            if let privacy = provider.privacySummary {
                                Text(privacy).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Services")
            } footer: {
                Text("Each service needs its own sign-in credentials registered on Modula’s servers before you can connect it. Nothing is shared with a service until you connect it and choose what it can access.")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    nonisolated static func connectionTitle(_ value: JSONValue) -> String {
        if case .object(let object) = value {
            for key in ["displayName", "providerDisplayName", "providerId"] {
                if case .string(let text)? = object[key], !text.isEmpty { return text }
            }
        }
        return "Connection"
    }

    private func load() async {
        do {
            let value = try await app.client.publicJSON("GET", path: "/v1/connectors")
            providers = try GreenfieldValueDecoder.decode([ConnectorProvider].self, from: value)
            error = nil
        } catch {
            self.error = "Couldn’t load services."
        }
        if app.auth.isSignedIn, let value = try? await app.client.authenticatedJSON("GET", path: "/v1/connections") {
            switch value {
            case .array(let items): connections = items
            case .object(let object): if case .array(let items)? = object["items"] { connections = items }
            default: break
            }
        }
    }
}
