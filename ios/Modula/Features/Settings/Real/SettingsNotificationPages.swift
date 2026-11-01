import SwiftUI

// MARK: - Notification categories (`/v1/accounts/me/notification-preferences`)

/// Loads and patches the server notification preferences. The worker checks these
/// before creating each notification, so a switched-off type is never created.
@MainActor @Observable
final class NotificationPreferencesModel {
    private(set) var values: [String: JSONValue] = [:]
    private(set) var loaded = false
    var error: String?

    func bool(_ key: String, default fallback: Bool = true) -> Bool {
        if case .bool(let value)? = values[key] { return value }
        return fallback
    }

    func load(client: GreenfieldClient) async {
        do {
            let value = try await client.authenticatedJSON("GET", path: "/v1/accounts/me/notification-preferences")
            if case .object(let object) = value { values = object }
            error = nil
        } catch {
            self.error = "Couldn’t load notification settings. Pull to try again."
        }
        loaded = true
    }

    func set(_ patch: [String: JSONValue], client: GreenfieldClient) async {
        let previous = values
        for (key, value) in patch { values[key] = value }
        do {
            let value = try await client.authenticatedJSON("PATCH", path: "/v1/accounts/me/notification-preferences", body: .object(patch))
            if case .object(let object) = value { values = object }
            error = nil
        } catch {
            values = previous
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t save. Check your connection and try again.")
        }
    }
}

struct NotificationCategoriesView: View {
    enum Scope { case social, modules }
    let scope: Scope
    @Environment(AppEnvironment.self) private var app
    @State private var model = NotificationPreferencesModel()

    private var rows: [(key: String, title: String, detail: String, fallback: Bool)] {
        switch scope {
        case .social:
            [("followEnabled", "New followers", "When someone follows you", true),
             ("likeEnabled", "Likes", "When someone likes your post", true),
             ("reactionEnabled", "Reactions", "When someone reacts to your post", true),
             ("commentEnabled", "Comments", "Comments on your posts", true),
             ("replyEnabled", "Replies", "Replies to your comments", true),
             ("mentionEnabled", "Mentions", "When someone mentions you", true),
             ("repostEnabled", "Reposts", "When your post is reposted", true),
             ("quoteEnabled", "Quotes", "When your post is quoted", true)]
        case .modules:
            [("moduleEventEnabled", "Module activity", "Updates from modules you use", false),
             ("extensionEnabled", "Extensions", "Activity from installed extensions", false),
             ("connectorFailureEnabled", "Connector problems", "When a connected service stops syncing", true),
             ("aiCompletionEnabled", "Nodus results", "When a long Nodus task finishes", true),
             ("automationFailureEnabled", "Automation failures", "When an automation can’t run", true)]
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.key) { row in
                    Toggle(isOn: Binding(
                        get: { model.bool(row.key, default: row.fallback) },
                        set: { value in
                            HapticEngine.shared.play(.selection)
                            Task { await model.set([row.key: .bool(value)], client: app.client) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Saved to your account and applied on every device. A type that’s off is never created, so it won’t appear in Activity either.")
            }
            .disabled(!model.loaded || !app.auth.isSignedIn)
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .tint(app.appearance.liveAccent)
        .modulaSoftScrollEdge()
        .navigationTitle(scope == .social ? "Social Notifications" : "Module Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { if app.auth.isSignedIn { await model.load(client: app.client) } }
        .refreshable { await model.load(client: app.client) }
    }
}

// MARK: - Quiet hours

/// Quiet-hours window stored on the account and mirrored locally so the app can apply it offline.
struct QuietHoursWindow: Equatable, Sendable {
    var enabled: Bool
    var startMinutes: Int
    var endMinutes: Int

    static let enabledKey = "settings.quietHours.enabled"
    static let startKey = "settings.quietHours.start"
    static let endKey = "settings.quietHours.end"

    nonisolated static func stored(_ defaults: UserDefaults = .standard) -> QuietHoursWindow {
        QuietHoursWindow(
            enabled: defaults.bool(forKey: enabledKey),
            startMinutes: defaults.object(forKey: startKey) as? Int ?? 22 * 60,
            endMinutes: defaults.object(forKey: endKey) as? Int ?? 7 * 60
        )
    }

    /// True when `date` falls inside the window; windows may cross midnight.
    nonisolated func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, startMinutes != endMinutes else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return startMinutes < endMinutes
            ? (minute >= startMinutes && minute < endMinutes)
            : (minute >= startMinutes || minute < endMinutes)
    }

    nonisolated static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    nonisolated static func minutes(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

struct QuietHoursSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @AppStorage(QuietHoursWindow.enabledKey) private var enabled = false
    @AppStorage(QuietHoursWindow.startKey) private var start = 22 * 60
    @AppStorage(QuietHoursWindow.endKey) private var end = 7 * 60
    @State private var model = NotificationPreferencesModel()

    var body: some View {
        Form {
            Section {
                Toggle("Quiet hours", isOn: $enabled.onChange { save() })
                if enabled {
                    DatePicker("From", selection: timeBinding($start), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: timeBinding($end), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("While quiet hours are on, the Activity badge stays hidden and no digest is emailed. Modula doesn’t send push notifications yet; when it does, they’ll be held during this window too. Saved to your account in your current time zone (\(TimeZone.current.identifier)).")
            }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .tint(app.appearance.liveAccent)
        .modulaSoftScrollEdge()
        .navigationTitle("Quiet Hours")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                save()
            }
        )
    }

    private func load() async {
        guard app.auth.isSignedIn else { return }
        await model.load(client: app.client)
        if case .object(let quiet)? = model.values["quietHours"] {
            if case .bool(let value)? = quiet["enabled"] { enabled = value }
            if case .string(let value)? = quiet["start"], let minutes = QuietHoursWindow.minutes(value) { start = minutes }
            if case .string(let value)? = quiet["end"], let minutes = QuietHoursWindow.minutes(value) { end = minutes }
        }
    }

    private func save() {
        guard app.auth.isSignedIn else { return }
        let patch: [String: JSONValue] = ["quietHours": .object([
            "enabled": .bool(enabled),
            "start": .string(QuietHoursWindow.clock(start)),
            "end": .string(QuietHoursWindow.clock(end)),
            "timezone": .string(TimeZone.current.identifier),
        ])]
        Task { await model.set(patch, client: app.client) }
    }
}

private extension Binding where Value == Bool {
    func onChange(_ action: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action() })
    }
}

// MARK: - Reports (`/v1/reports/me`)

struct MyReportsView: View {
    struct Report: Decodable, Sendable, Identifiable, Equatable {
        let id: String
        let targetType: String
        let category: String
        let details: String?
        let status: String
        let resolution: String?
        let createdAt: String
    }
    struct ReportList: Decodable, Sendable { let items: [Report] }

    @Environment(AppEnvironment.self) private var app
    @State private var reports: [Report]?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Label("Report a post or profile from its ••• menu. Choose what happened and add context; reports are private.", systemImage: "exclamationmark.bubble")
                    .font(.subheadline)
            }
            Section("Your reports") {
                if let reports {
                    if reports.isEmpty {
                        Text("You haven’t reported anything.").foregroundStyle(.secondary)
                    }
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(Self.targetLabel(report.targetType)) · \(report.category.replacingOccurrences(of: "_", with: " ").capitalized)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(Self.statusLabel(report.status))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            if let details = report.details, !details.isEmpty {
                                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text(SettingsISODate.parse(report.createdAt)?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Reporting")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    nonisolated static func statusLabel(_ status: String) -> String {
        switch status {
        case "open": "Received"
        case "reviewing": "In review"
        case "resolved": "Action taken"
        case "dismissed": "No action"
        default: status.capitalized
        }
    }

    nonisolated static func targetLabel(_ type: String) -> String {
        switch type {
        case "post": "Post"
        case "profile", "actor": "Profile"
        case "comment": "Comment"
        case "message": "Message"
        default: type.capitalized
        }
    }

    private func load() async {
        guard app.auth.isSignedIn else { reports = []; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/reports/me?limit=50")
            reports = try GreenfieldValueDecoder.decode(ReportList.self, from: value).items
            error = nil
        } catch {
            self.error = "Couldn’t load your reports."
        }
    }
}
