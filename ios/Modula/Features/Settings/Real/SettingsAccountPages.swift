import SwiftUI

// MARK: - Digests (`/v1/accounts/me/app-preferences`)

struct DigestsSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.digests.weekly") private var weekly = false
    @AppStorage("settings.digests.morning") private var morning = false
    @State private var remote: AppPreferencesResponse?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Digests", subtitle: "A short email summary of what happened around you.", symbol: "envelope.open")
            SettingsSceneGraphic(style: .waves)
            SettingsToggleCard {
                Toggle("Weekly recap", isOn: binding($weekly, key: "digests.weekly"))
                    .accessibilityHint("Emails a summary every Monday morning")
                Toggle("Morning summary", isOn: binding($morning, key: "digests.morning"))
                    .accessibilityHint("Emails a summary each morning when something happened")
            }
            .disabled(saving || !app.auth.isSignedIn)
            if let digests = remote?.digests {
                SettingsGroup(title: "Delivery") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Sent to", value: digests.deliveryEmail ?? "No email on this account")
                        if digests.deliveryEmail != nil && !digests.emailVerified {
                            Text("Verify your email to receive digests.").font(.caption).foregroundStyle(.orange)
                        }
                        LabeledContent("Time zone", value: digests.timeZone)
                        Text("Morning: \(digests.schedule.morning.lowercasedFirst). Weekly: \(digests.schedule.weekly.lowercasedFirst).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !digests.recent.isEmpty {
                    SettingsGroup(title: "Recent") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(digests.recent) { delivery in
                                HStack {
                                    Image(systemName: delivery.outcome == "queued" ? "paperplane.fill" : "moon.zzz")
                                        .foregroundStyle(delivery.outcome == "queued" ? AnyShapeStyle(app.appearance.accent.color) : AnyShapeStyle(.secondary))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(delivery.kind == "weekly" ? "Weekly recap · \(delivery.period)" : "Morning summary · \(delivery.period)")
                                            .font(.subheadline.weight(.medium))
                                        Text(Self.outcomeLabel(delivery.outcome)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            if let error {
                SettingsAPIFootnote(text: error)
            } else {
                SettingsAPIFootnote(text: "Saved to your account. Quiet periods with nothing new are skipped, so you won’t get an empty email.")
            }
        }
        .navigationTitle("Digests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    nonisolated static func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "queued": "Sent"
        case "quiet": "Skipped — nothing new"
        case "no-email": "Skipped — no verified email"
        default: outcome.capitalized
        }
    }

    private func binding(_ value: Binding<Bool>, key: String) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                Task { await save([key: .bool(newValue), "digests.timeZone": .string(TimeZone.current.identifier)]) }
            }
        )
    }

    private func load() async {
        guard app.auth.isSignedIn else { return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/accounts/me/app-preferences")
            apply(try GreenfieldValueDecoder.decode(AppPreferencesResponse.self, from: value))
            error = nil
        } catch {
            self.error = "Digest settings couldn’t load. Your last choice on this device is shown."
        }
    }

    private func save(_ patch: [String: JSONValue]) async {
        saving = true
        defer { saving = false }
        do {
            let value = try await app.client.authenticatedJSON("PATCH", path: "/v1/accounts/me/app-preferences", body: .object(["preferences": .object(patch)]))
            apply(try GreenfieldValueDecoder.decode(AppPreferencesResponse.self, from: value))
            HapticEngine.shared.play(.confirmation)
            error = nil
        } catch {
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t save. Check your connection and try again.")
            await load()
        }
    }

    private func apply(_ response: AppPreferencesResponse) {
        remote = response
        weekly = response.digests.weeklyEnabled
        morning = response.digests.morningEnabled
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - Muted / Blocked (`/v1/accounts/me/mutes|blocks`)

enum RelationshipListKind: String, Sendable {
    case muted, blocked

    var title: String { self == .muted ? "Muted" : "Blocked Accounts" }
    var path: String { self == .muted ? "/v1/accounts/me/mutes" : "/v1/accounts/me/blocks" }
    var actionTitle: String { self == .muted ? "Unmute" : "Unblock" }
    var symbol: String { self == .muted ? "speaker.slash" : "nosign" }
    var emptyMessage: String {
        self == .muted
            ? "Mute someone from their profile or a post’s menu. Their posts leave your feeds, and they aren’t told."
            : "Block someone from their profile or a post’s menu. They can’t see your profile or contact you."
    }
    func undoPath(profileID: String) -> String {
        let escaped = profileID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? profileID
        return "/v1/profiles/\(escaped)/\(self == .muted ? "mute" : "block")"
    }
}

struct RelationshipListView: View {
    let kind: RelationshipListKind
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [RelationshipListResponse.Item] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var working: Set<String> = []
    @State private var pendingUndo: RelationshipListResponse.Item?

    var body: some View {
        List {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if items.isEmpty {
                ModulaEmptyState(title: kind == .muted ? "No muted accounts" : "No blocked accounts", message: kind.emptyMessage, symbol: kind.symbol)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(items) { item in
                        row(item)
                    }
                } footer: {
                    Text(kind == .muted ? "Unmuting brings their posts back to your feeds." : "Unblocking lets them see your profile again. They aren’t notified.")
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).listRowBackground(Color.clear)
            }
        }
        .animation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion), value: items)
        .modulaSoftScrollEdge()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("\(kind.actionTitle) @\(pendingUndo?.handle ?? "")?", isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }), titleVisibility: .visible) {
            if let item = pendingUndo {
                Button(kind.actionTitle) { Task { await undo(item) } }
            }
        }
    }

    private func row(_ item: RelationshipListResponse.Item) -> some View {
        HStack(spacing: 12) {
            ModulaAvatar(initials: String(item.displayName.prefix(1)).uppercased(), url: item.avatarUrl.flatMap(URL.init(string:)), size: 40, name: item.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text("@\(item.handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if working.contains(item.id) {
                ProgressView()
            } else {
                Button(kind.actionTitle) { pendingUndo = item }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(kind.actionTitle)) { pendingUndo = item }
    }

    private func load() async {
        guard app.auth.isSignedIn else { loaded = true; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: kind.path)
            items = try GreenfieldValueDecoder.decode(RelationshipListResponse.self, from: value).items
            error = nil
        } catch {
            self.error = "Couldn’t load this list. Pull to try again."
        }
        loaded = true
    }

    private func undo(_ item: RelationshipListResponse.Item) async {
        working.insert(item.id)
        defer { working.remove(item.id) }
        do {
            _ = try await app.client.authenticatedJSON("DELETE", path: kind.undoPath(profileID: item.profileId))
            items.removeAll { $0.id == item.id }
            HapticEngine.shared.play(.success)
            error = nil
        } catch {
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t \(kind.actionTitle.lowercased()) @\(item.handle). Try again.")
        }
    }
}

// MARK: - Password step-up (`/v1/auth/step-up/password`)

struct PasswordStepUpSheet: View {
    var reason: String
    var onConfirmed: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { Task { await confirm() } }
                } header: {
                    Text("Confirm it’s you")
                } footer: {
                    Text(reason)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Enter Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Confirm") { Task { await confirm() } }.disabled(password.isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func confirm() async {
        guard !password.isEmpty, !working else { return }
        working = true
        defer { working = false }
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/auth/step-up/password", body: .object(["password": .string(password)]))
            password = ""
            HapticEngine.shared.play(.success)
            dismiss()
            onConfirmed()
        } catch {
            HapticEngine.shared.play(.failure)
            if case APIError.rejected(_, "VALIDATION_FAILED") = error {
                self.error = "That password isn’t correct."
            } else if case APIError.rejected(_, "CONFLICT") = error {
                self.error = "This account doesn’t use a password. Sign out and back in to confirm, then try again within 10 minutes."
            } else {
                self.error = SettingsRemoteError.message(error, fallback: "Couldn’t confirm. Check your connection and try again.")
            }
        }
    }
}

// MARK: - Delete account (re-auth + 7-day grace)

struct DeleteAccountView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: DeletionStatusResponse?
    @State private var loaded = false
    @State private var acknowledged = false
    @State private var confirmText = ""
    @State private var showStepUp = false
    @State private var working = false
    @State private var error: String?
    @State private var idempotencyKey = "delete-\(UUID().uuidString.lowercased())"

    var body: some View {
        SettingsScrollCanvas {
            if let request = status?.request {
                scheduled(request)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if loaded {
                intro
                    .transition(.opacity)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
            if let error { SettingsAPIFootnote(text: error) }
        }
        .animation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion), value: status)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showStepUp) {
            PasswordStepUpSheet(reason: "We ask for your password before scheduling deletion. It’s valid for 10 minutes.") {
                Task { await requestDeletion() }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeroBanner(title: "Delete your account", subtitle: "Scheduled for 7 days from now. You can cancel any time before then.", symbol: "trash")
            SettingsGroup(title: "What happens") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your account is scheduled for deletion in 7 days.", systemImage: "calendar.badge.clock")
                    Label("Until then, cancel here to keep everything.", systemImage: "arrow.uturn.backward")
                    Label("After that, your posts, profile, messages and files are removed. Records we must keep by law are retained only as long as required.", systemImage: "doc.text.magnifyingglass")
                    Label("Download your data first from Data & Storage → Export.", systemImage: "square.and.arrow.down")
                }
                .font(.subheadline)
            }
            SettingsToggleCard {
                Toggle("I understand this can’t be undone after 7 days", isOn: $acknowledged)
                TextField("Type DELETE to confirm", text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityHint("Type the word DELETE in capitals")
            }
            Button(role: .destructive) {
                showStepUp = true
            } label: {
                HStack {
                    if working { ProgressView() }
                    Text("Schedule Deletion").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!canSubmit || working)
        }
    }

    private var canSubmit: Bool { acknowledged && confirmText.trimmingCharacters(in: .whitespaces) == "DELETE" && app.auth.isSignedIn }

    private func scheduled(_ request: DeletionStatusResponse.Request) -> some View {
        let date = SettingsISODate.parse(request.scheduledFor)
        return VStack(alignment: .leading, spacing: 18) {
            SettingsHeroBanner(title: "Deletion scheduled", subtitle: date.map { "Your account will be deleted after \($0.formatted(date: .complete, time: .shortened))." } ?? "Your account is scheduled for deletion.", symbol: "hourglass")
            if let date {
                SettingsGroup(title: "Time left") {
                    Text(date, style: .relative)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .accessibilityLabel("Time left: \(date.formatted(.relative(presentation: .named)))")
                }
            }
            Button {
                Task { await cancel(request) }
            } label: {
                HStack {
                    if working { ProgressView() }
                    Text("Keep My Account").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
            SettingsAPIFootnote(text: "Deletion runs after the grace period ends. Until it does, you can keep using Modula and cancel here.")
        }
    }

    private func load() async {
        guard app.auth.isSignedIn else { loaded = true; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/account/deletion-requests/current")
            status = try GreenfieldValueDecoder.decode(DeletionStatusResponse.self, from: value)
            error = nil
        } catch {
            self.error = "Couldn’t check your account status. Pull to try again."
        }
        loaded = true
    }

    private func requestDeletion() async {
        working = true
        defer { working = false }
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/account/deletion-requests", body: .object(["confirm": .bool(true)]), idempotencyKey: idempotencyKey)
            HapticEngine.shared.play(.warning)
            await load()
        } catch {
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t schedule deletion. Nothing has changed.")
        }
    }

    private func cancel(_ request: DeletionStatusResponse.Request) async {
        working = true
        defer { working = false }
        let id = request.requestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.requestId
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/account/data-requests/\(id)/cancel", body: .object([:]))
            HapticEngine.shared.play(.success)
            idempotencyKey = "delete-\(UUID().uuidString.lowercased())"
            acknowledged = false
            confirmText = ""
            await load()
        } catch {
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t cancel. Try again.")
        }
    }
}

// MARK: - Username (`POST /v1/accounts/me/handle`)

struct UsernameChangeView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var handle = ""
    @State private var working = false
    @State private var message: String?
    @State private var succeeded = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Current", value: "@\(app.auth.account?.primaryHandle ?? "—")")
                TextField("new-username", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: handle) { _, value in
                        let cleaned = UsernameRules.sanitize(value)
                        if cleaned != value { handle = cleaned }
                        message = nil
                        succeeded = false
                    }
            } footer: {
                Text(UsernameRules.problem(handle) ?? "Your old username stops working straight away and links to it won’t redirect.")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(succeeded ? Color.green : Color.red)
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if working { ProgressView() }; Text("Change Username") }
                }
                .disabled(working || UsernameRules.problem(handle) != nil || handle == app.auth.account?.primaryHandle)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Username")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/accounts/me/handle", body: .object(["handle": .string(handle)]))
            await app.auth.refreshAccount()
            succeeded = true
            message = "Your username is now @\(handle)."
            HapticEngine.shared.play(.success)
        } catch {
            succeeded = false
            if case APIError.rejected(_, let code) = error, code == "CONFLICT" || code == "HANDLE_TAKEN" || code == "HANDLE_UNAVAILABLE" {
                message = "@\(handle) is taken. Try another."
            } else {
                message = SettingsRemoteError.message(error, fallback: "Couldn’t change your username. Try again.")
            }
            HapticEngine.shared.play(.failure)
        }
    }
}

enum UsernameRules {
    nonisolated static func sanitize(_ value: String) -> String {
        String(value.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }.prefix(30))
    }

    /// Mirrors the server rule: 3–30 lowercase letters/numbers with single `.`, `_` or `-` separators inside.
    nonisolated static func problem(_ value: String) -> String? {
        if value.isEmpty { return "Use 3–30 lowercase letters or numbers. Dots, dashes and underscores can go in between." }
        if value.count < 3 { return "Usernames need at least 3 characters." }
        if value.range(of: "^[a-z0-9](?:[a-z0-9]|[._-](?![._-])){1,28}[a-z0-9]$", options: .regularExpression) == nil {
            return "Start and end with a letter or number, with one separator at a time."
        }
        return nil
    }
}
