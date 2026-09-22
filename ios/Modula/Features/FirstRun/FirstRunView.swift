import SwiftUI
import UserNotifications

struct FirstRunView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step: FirstRunStep = .profile
    @State private var displayName = ""
    @State private var handle = ""
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(step.title)
                        .font(.largeTitle.bold())
                    Text(step.body)
                        .foregroundStyle(.secondary)
                    switch step {
                    case .profile: profileStep
                    case .modules: modulesStep
                    case .notifications: notificationsStep
                    }
                    actions
                }
                .padding(24)
            }
            .modulaSoftScrollEdge()
            .modulaCanvas()
            .navigationTitle("Set up Modula")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("firstrun.root")
        .onAppear {
            displayName = app.auth.account?.displayName ?? ""
            handle = app.auth.account?.primaryHandle ?? ""
            refreshNotificationStatus()
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Display name", text: $displayName)
                .textContentType(.name)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("firstrun.display-name")
            TextField("Username", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(true)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("firstrun.username")
            Text("Username is assigned by Greenfield at registration. Changing it is unavailable until that contract is verified.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Profile photo upload uses the Profile editor after setup. First-run does not invent a media pipeline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var modulesStep: some View {
        let vault = app.catalogue.product("digital.modula.vault-notes")
        return VStack(alignment: .leading, spacing: 16) {
            if let vault {
                HStack(spacing: 14) {
                    ProductArtwork(product: vault, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vault.name).font(.headline)
                        Text(vault.description).font(.footnote).foregroundStyle(.secondary)
                        Text(app.catalogue.installedIDs.contains(vault.id) || bundled(vault.id) ? "Ready to open" : "Available in Product Hub")
                            .font(.caption.weight(.semibold))
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No genuine installable starter modules are in the current catalogue response.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("firstrun.modules")
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(statusTitle, systemImage: "bell.badge")
                .font(.headline)
            Text("Reactions, follows and module updates can arrive as notifications. You can change this later in Settings.")
                .foregroundStyle(.secondary)
            if let notificationMessage {
                Text(notificationMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("firstrun.notifications")
    }

    @ViewBuilder
    private var actions: some View {
        Button(primaryTitle) {
            Task { await advance() }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityIdentifier("firstrun.continue")

        if step != .profile {
            Button("Back") {
                if let previous = FirstRunStep(rawValue: step.rawValue - 1) {
                    step = previous
                }
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .profile: "Continue"
        case .modules: "Continue"
        case .notifications:
            notificationStatus == .notDetermined ? "Enable Notifications" : "Finish"
        }
    }

    private var statusTitle: String {
        switch notificationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func bundled(_ id: String) -> Bool {
        app.runtime.manifests.contains { $0.id == id }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                notificationStatus = status
            }
        }
    }

    private func advance() async {
        switch step {
        case .profile:
            HapticEngine.shared.play(.navigation)
            step = .modules
        case .modules:
            HapticEngine.shared.play(.navigation)
            step = .notifications
        case .notifications:
            if notificationStatus == .notDetermined {
                let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                refreshNotificationStatus()
                notificationMessage = (granted == true)
                    ? "Notifications are allowed."
                    : "You can enable notifications later in iOS Settings."
            }
            finish()
        }
    }

    private func finish() {
        guard let accountID = app.auth.account?.accountId else { return }
        app.gate.completeFirstRun(accountID: accountID)
        app.refreshLaunchState()
        app.navigation.home()
        HapticEngine.shared.play(.success)
    }
}
