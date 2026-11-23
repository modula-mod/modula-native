import SwiftUI
import UserNotifications

// MARK: - Preferences model (`/v1/push/preferences`)

@MainActor @Observable
final class PushPreferencesModel {
    private(set) var preferences: PushPreferences?
    private(set) var loading = false
    var error: String?

    func load(client: GreenfieldClient) async {
        loading = true
        defer { loading = false }
        do {
            let value = try await client.authenticatedJSON("GET", path: PushAPI.preferences)
            preferences = try GreenfieldValueDecoder.decode(PushPreferences.self, from: value)
            error = nil
        } catch {
            self.error = Self.message(error, fallback: "Couldn’t load push settings.")
        }
    }

    /// Optimistic patch with the server version; reverts on failure.
    func patch(_ body: [String: JSONValue], apply: (inout PushPreferences) -> Void, client: GreenfieldClient) async {
        guard var next = preferences else { return }
        let previous = next
        apply(&next)
        preferences = next
        var payload = body
        payload["expectedVersion"] = .number(Double(previous.version))
        do {
            let value = try await client.authenticatedJSON("PATCH", path: PushAPI.preferences, body: .object(payload))
            preferences = try GreenfieldValueDecoder.decode(PushPreferences.self, from: value)
            error = nil
        } catch {
            preferences = previous
            self.error = Self.message(error, fallback: "Couldn’t save. Check your connection and try again.")
            if case APIError.rejected(409, _)? = error as? APIError { await load(client: client) }
        }
    }

    static func message(_ error: Error, fallback: String) -> String {
        if case APIError.rejected(404, _)? = error as? APIError { return "Push isn’t available on this server yet." }
        return SettingsRemoteError.message(error, fallback: fallback)
    }
}

// MARK: - Settings › Notifications › Push

struct PushNotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = PushPreferencesModel()
    #if DEBUG
    @AppStorage(PushFeatureFlags.debugOverrideKey) private var debugPushEnabled = false
    #endif

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(
                title: "Push Notifications",
                subtitle: "Replies, messages and requests, even when Modula is closed.",
                symbol: "bell.badge"
            )
            permissionCard
            readinessGroup
            if app.push.flagEnabled {
                if let prefs = model.preferences {
                    deliveryGroup(prefs)
                    categoriesGroup(prefs)
                    quietHoursGroup(prefs)
                } else if model.loading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let error = model.error {
                    SettingsAPIFootnote(text: error)
                }
            } else {
                SettingsAPIFootnote(text: "Push delivery is switched off in this build until the Modula push service is live. In-app Activity keeps working.")
            }
            #if DEBUG
            SettingsGroup(title: "Developer", subtitle: "Debug builds only. Turns on registration with /v1/push/devices.") {
                SettingsToggleCard {
                    Toggle("Enable push (pre-release)", isOn: $debugPushEnabled)
                        .accessibilityIdentifier("settings.push.debugFlag")
                }
            }
            #endif
        }
        .navigationTitle("Push")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.notifications.push")
        .task { await reload() }
        .refreshable { await reload() }
        #if DEBUG
        .onChange(of: debugPushEnabled) { _, _ in Task { await reload() } }
        #endif
    }

    private func reload() async {
        await app.push.refreshAuthorization()
        guard app.push.flagEnabled, app.auth.isSignedIn else { return }
        await model.load(client: app.client)
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionCard: some View {
        SettingsGroup(title: "This iPhone") {
            VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                HStack(spacing: ModulaSpacing.sm) {
                    Image(systemName: statusSymbol)
                        .font(.title3)
                        .foregroundStyle(app.appearance.liveAccent)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : statusSymbol.hashValue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).font(.body.weight(.semibold))
                        Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.push.status")
                switch app.push.authorization {
                case .notDetermined:
                    ModulaButton(title: "Turn On Notifications", symbol: "bell.badge") {
                        app.push.noteMoment(.settings)
                    }
                    .disabled(!app.push.flagEnabled || !app.auth.isSignedIn)
                case .denied:
                    ModulaButton(title: "Open iOS Settings", symbol: "gear") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .padding(.vertical, ModulaSpacing.sm)
        }
    }

    // MARK: Readiness (#38) — only what this iPhone can know

    private var readinessGroup: some View {
        let readiness = PushReadiness(
            authorizationTitle: statusTitle,
            flagEnabled: app.push.flagEnabled,
            signing: PushReadiness.signingFromEmbeddedProfile(),
            registration: app.push.registration
        )
        return SettingsGroup(
            title: "Push readiness",
            subtitle: "What this iPhone can check. It can't confirm that a notification will arrive."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(readiness.rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: ModulaSpacing.sm) {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(row.ok ? AnyShapeStyle(app.appearance.liveAccent) : AnyShapeStyle(.secondary))
                            .accessibilityHidden(true)
                        Text(row.label).font(.subheadline)
                        Spacer(minLength: 12)
                        Text(row.value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                Text("Delivery isn't checked here. Only Modula's servers know whether a notification was sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, ModulaSpacing.xs)
            }
            .accessibilityIdentifier("settings.push.readiness")
        }
    }

    private var statusSymbol: String {
        switch app.push.authorization {
        case .authorized, .provisional, .ephemeral: "bell.badge.fill"
        case .denied: "bell.slash"
        default: "bell"
        }
    }

    private var statusTitle: String {
        switch app.push.authorization {
        case .authorized: "Allowed"
        case .provisional: "Delivered quietly"
        case .ephemeral: "Allowed for this session"
        case .denied: "Off in iOS Settings"
        case .notDetermined: "Not turned on"
        @unknown default: "Unknown"
        }
    }

    private var statusDetail: String {
        switch app.push.registration {
        case .registered: return "This device is registered for push."
        case .registering: return "Registering this device…"
        case .failed(let message): return message
        case .unavailable: return "Push isn’t live in this build yet."
        case .idle:
            return app.push.authorization == .denied
                ? "Turn notifications on for Modula in iOS Settings."
                : "Modula asks iOS only after you choose to turn them on."
        }
    }

    // MARK: Groups

    private func deliveryGroup(_ prefs: PushPreferences) -> some View {
        SettingsGroup(title: "Delivery") {
            SettingsToggleCard {
                Toggle(isOn: Binding(
                    get: { prefs.enabled },
                    set: { value in save(["enabled": .bool(value)]) { $0.enabled = value } }
                )) {
                    rowLabel("Push notifications", "All push from Modula on this account", "bell")
                }
                .accessibilityIdentifier("settings.push.enabled")
            }
        }
    }

    private func categoriesGroup(_ prefs: PushPreferences) -> some View {
        SettingsGroup(title: "Notify me about", subtitle: "Synced to your account on every device. Activity in the app is unaffected.") {
            SettingsToggleCard {
                ForEach(Array(PushCategoryKey.allCases.enumerated()), id: \.element) { index, key in
                    if index > 0 { SettingsDivider() }
                    Toggle(isOn: Binding(
                        get: { prefs.categories[key.rawValue] ?? true },
                        set: { value in
                            save(["categories": .object([key.rawValue: .bool(value)])]) { $0.categories[key.rawValue] = value }
                        }
                    )) {
                        rowLabel(key.title, key.detail, key.symbol)
                    }
                    .accessibilityIdentifier("settings.push.category.\(key.rawValue)")
                }
            }
            .disabled(!prefs.enabled)
            .opacity(prefs.enabled ? 1 : 0.55)
        }
    }

    private func quietHoursGroup(_ prefs: PushPreferences) -> some View {
        SettingsGroup(
            title: "Quiet Hours",
            subtitle: "Push that arrives during this window is held and delivered when it ends. Times use \(prefs.quietHours.timezone)."
        ) {
            SettingsToggleCard {
                Toggle(isOn: Binding(
                    get: { prefs.quietHours.enabled },
                    set: { value in saveQuiet(prefs) { $0.enabled = value } }
                )) {
                    rowLabel("Quiet hours", "Hold push overnight", "moon.zzz")
                }
                .accessibilityIdentifier("settings.push.quietHours")
                if prefs.quietHours.enabled {
                    SettingsDivider()
                    DatePicker("From", selection: timeBinding(prefs.quietHours.start) { clock in saveQuiet(prefs) { $0.start = clock } }, displayedComponents: .hourAndMinute)
                    SettingsDivider()
                    DatePicker("Until", selection: timeBinding(prefs.quietHours.end) { clock in saveQuiet(prefs) { $0.end = clock } }, displayedComponents: .hourAndMinute)
                }
            }
            .disabled(!prefs.enabled)
        }
    }

    private func rowLabel(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(app.appearance.liveAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save(_ body: [String: JSONValue], apply: @escaping (inout PushPreferences) -> Void) {
        HapticEngine.shared.play(.selection)
        Task { await model.patch(body, apply: apply, client: app.client) }
    }

    private func saveQuiet(_ prefs: PushPreferences, _ change: @escaping (inout PushPreferences.QuietHours) -> Void) {
        var quiet = prefs.quietHours
        change(&quiet)
        quiet.timezone = TimeZone.current.identifier
        let body: [String: JSONValue] = ["quietHours": .object([
            "enabled": .bool(quiet.enabled),
            "start": .string(quiet.start),
            "end": .string(quiet.end),
            "timezone": .string(quiet.timezone),
        ])]
        save(body) { $0.quietHours = quiet }
    }

    private func timeBinding(_ clock: String, set: @escaping (String) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let minutes = QuietHoursWindow.minutes(clock) ?? 0
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(QuietHoursWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
            }
        )
    }
}

// MARK: - Soft pre-prompt

/// Shown at a value moment (never on launch) before the one-time iOS alert.
struct PushPrePromptSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let reasons: [(String, String, String)] = [
        ("arrowshape.turn.up.left", "Replies and mentions", "Answer right from the notification."),
        ("paperplane", "Messages", "Know when a friend writes back."),
        ("person.badge.plus", "Follow requests", "Accept without opening the app."),
        ("leaf", "Moliboo care", "A nudge when your Moliboo needs you."),
    ]

    var body: some View {
        VStack(spacing: ModulaSpacing.lg) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(width: 88, height: 88)
                .modulaGlass(in: Circle(), interactive: false, tint: app.appearance.liveAccent.opacity(0.18))
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .accessibilityHidden(true)
            VStack(spacing: ModulaSpacing.xs) {
                Text("Stay in the loop")
                    .font(.title2.weight(.bold))
                Text("Modula only notifies you about people and things you care about. Choose exactly which in Settings, and set quiet hours.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                ForEach(reasons, id: \.1) { symbol, title, detail in
                    HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                        Image(systemName: symbol)
                            .foregroundStyle(app.appearance.liveAccent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.body.weight(.semibold))
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(ModulaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
            VStack(spacing: ModulaSpacing.xs) {
                ModulaButton(title: "Turn On Notifications", symbol: "bell") {
                    Task { await app.push.requestPermission() }
                }
                .accessibilityIdentifier("push.prePrompt.allow")
                Button("Not Now") { app.push.dismissPrePrompt() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(minHeight: ModulaLayout.minimumTouch)
                    .accessibilityIdentifier("push.prePrompt.notNow")
            }
        }
        .padding(.horizontal, ModulaSpacing.lg)
        .padding(.top, ModulaSpacing.xl)
        .padding(.bottom, ModulaSpacing.md)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
        }
        .accessibilityIdentifier("push.prePrompt")
    }
}


/// Push readiness facts the phone itself can observe. Pure, so it is unit-testable.
struct PushReadiness: Equatable {
    enum Signing: Equatable { case allowsPush, noPush, unknown }

    struct Row: Equatable {
        let label: String
        let value: String
        let ok: Bool
    }

    var authorizationTitle: String
    var flagEnabled: Bool
    var signing: Signing
    var registration: PushNotificationController.RegistrationState

    var rows: [Row] {
        [
            Row(label: "iOS permission", value: authorizationTitle,
                ok: authorizationTitle == "Allowed" || authorizationTitle == "Delivered quietly" || authorizationTitle == "Allowed for this session"),
            Row(label: "Push in this build", value: flagEnabled ? "On" : "Off", ok: flagEnabled),
            Row(label: "Signing profile allows push", value: {
                switch signing {
                case .allowsPush: "Yes"
                case .noPush: "No"
                case .unknown: "Can't tell"
                }
            }(), ok: signing == .allowsPush),
            Row(label: "Registered with Modula", value: {
                switch registration {
                case .registered: "Yes"
                case .registering: "In progress"
                case .failed: "Failed"
                case .unavailable: "Not available"
                case .idle: "Not yet"
                }
            }(), ok: registration == .registered),
        ]
    }

    /// Reads the installed provisioning profile (present in development builds only). It
    /// says whether push is permitted for this install; it never reads tokens or secrets.
    static func signingFromEmbeddedProfile(bundle: Bundle = .main) -> Signing {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return .unknown }
        return signing(fromProfileData: data)
    }

    static func signing(fromProfileData data: Data) -> Signing {
        data.range(of: Data("<key>aps-environment</key>".utf8)) != nil ? .allowsPush : .noPush
    }
}
