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
    @State private var busy = false
    @State private var errorMessage: String?
    /// True once the notification prompt has resolved so the result stays on
    /// screen and the user finishes with an explicit tap.
    @State private var notificationsResolved = false

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
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("firstrun.error")
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
            Text("Your username was set when you signed up and can’t be changed yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("You can add a profile photo from your profile after setup.")
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
                Text("There are no starter modules to install right now. You can add modules later from Product Hub.")
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
        Button {
            Task { await advance() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(primaryTitle)
            }
            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
        }
        .buttonStyle(.borderedProminent)
        .tint(app.appearance.accent.color)
        .disabled(busy)
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityIdentifier("firstrun.continue")

        if step != .profile {
            Button("Back") {
                if let previous = FirstRunStep(rawValue: step.rawValue - 1) {
                    errorMessage = nil
                    step = previous
                }
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .disabled(busy)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .profile: "Continue"
        case .modules: "Continue"
        case .notifications:
            notificationStatus == .notDetermined && !notificationsResolved ? "Enable Notifications" : "Finish"
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
        guard !busy else { return }
        errorMessage = nil
        switch step {
        case .profile:
            busy = true
            let failure = await app.profile.saveDisplayName(displayName, accountHandle: app.auth.account?.primaryHandle)
            busy = false
            if let failure {
                errorMessage = failure
                HapticEngine.shared.play(.failure)
                AccessibilityNotification.Announcement(failure).post()
                return
            }
            HapticEngine.shared.play(.navigation)
            step = .modules
        case .modules:
            HapticEngine.shared.play(.navigation)
            step = .notifications
        case .notifications:
            if notificationStatus == .notDetermined && !notificationsResolved {
                busy = true
                let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                busy = false
                refreshNotificationStatus()
                let message = (granted == true)
                    ? "Notifications are allowed."
                    : "You can enable notifications later in iOS Settings."
                notificationMessage = message
                notificationsResolved = true
                AccessibilityNotification.Announcement(message).post()
                // Keep the result visible; the button now reads "Finish".
                return
            }
            finish()
        }
    }

    private func finish() {
        guard let accountID = app.auth.account?.accountId else {
            let message = "Your session ended. Sign in again to finish setup."
            errorMessage = message
            HapticEngine.shared.play(.failure)
            AccessibilityNotification.Announcement(message).post()
            return
        }
        app.gate.completeFirstRun(accountID: accountID)
        app.refreshLaunchState()
        app.navigation.home()
        HapticEngine.shared.play(.success)
    }
}
