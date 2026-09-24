import SwiftUI
import UserNotifications
import UIKit

struct SettingsCapabilityUnavailableView: View {
    let title: String
    let reason: String
    var symbol: String = "slash.circle"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(reason)
        }
        .modulaSoftScrollEdge()
        .navigationTitle(title)
        .accessibilityIdentifier("settings.unavailable")
    }
}

struct SettingsDestinationHost: View {
    let route: SettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        destination.modulaSoftScrollEdge()
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .root:
            SettingsView()
        case .account:
            AccountSettingsView(route: {
                if case .account(let nested) = route { return nested }
                return .root
            }())
        case .appearance(.appIcon):
            AppIconPickerView()
        case .appearance(.preview):
            AppearancePreviewScreen()
        case .appearance(.edgePicker):
            EdgePickerSettingsView()
        case .appearance(let focus):
            AppearanceSettingsView(focus: focus)
        case .personalisation(let nested):
            PersonalisationSettingsHost(route: nested)
        case .intelligence(let nested):
            IntelligenceSettingsHost(route: nested)
        case .chats(let nested):
            ChatsSettingsHost(route: nested)
        case .audio(let nested):
            AudioSettingsHost(route: nested)
        case .language(let nested):
            LanguageSettingsHost(route: nested)
        case .media(let nested):
            MediaSettingsHost(route: nested)
        case .feed(let nested):
            FeedSettingsHost(route: nested)
        case .battery(let nested):
            BatterySettingsHost(route: nested)
        case .safety(let nested):
            SafetySettingsHost(route: nested)
        case .camera(let nested):
            CameraSettingsHost(route: nested)
        case .gestures(let nested):
            GesturesSettingsHost(route: nested)
        case .finder(let nested):
            FinderSettingsHost(route: nested)
        case .sharing(let nested):
            SharingSettingsHost(route: nested)
        case .location(let nested):
            LocationSettingsHost(route: nested)
        case .widgets(let nested):
            WidgetsSettingsHost(route: nested)
        case .labs(let nested):
            LabsSettingsHost(route: nested)
        case .photos(let nested):
            PhotosSettingsHost(route: nested)
        case .network(let nested):
            NetworkSettingsHost(route: nested)
        case .digests(let nested):
            DigestsSettingsHost(route: nested)
        case .help(let nested):
            HelpSettingsHost(route: nested)
        case .whatsNew(let nested):
            WhatsNewSettingsHost(route: nested)
        case .creator(let nested):
            CreatorSettingsHost(route: nested)
        case .focus(let nested):
            FocusSettingsHost(route: nested)
        case .passkeys(let nested):
            PasskeysSettingsHost(route: nested)
        case .translate(let nested):
            TranslateSettingsHost(route: nested)
        case .qrCode(let nested):
            QRCodeSettingsHost(route: nested)
        case .family(let nested):
            FamilySettingsHost(route: nested)
        case .timeUnits(let nested):
            TimeUnitsSettingsHost(route: nested)
        case .keyboard(let nested):
            KeyboardSettingsHost(route: nested)
        case .connectors(let nested):
            ConnectorsSettingsHost(route: nested)
        case .integrations(let nested):
            IntegrationsSettingsHost(route: nested)
        case .monetisation(let nested):
            MonetisationSettingsHost(route: nested)
        case .notifications(let nested):
            NotificationSettingsHost(route: nested)
        case .privacy(let nested):
            PrivacySecurityHost(route: nested)
        case .modules(let nested):
            ModuleSettingsHost(route: nested)
        case .dataStorage(let nested):
            DataStorageHost(route: nested)
        case .accessibility(let nested):
            AccessibilitySettingsHost(route: nested)
        case .features(let nested):
            FeatureSettingsHost(route: nested)
        case .updates(let nested):
            UpdateSettingsHost(route: nested)
        case .developer(let nested):
            DeveloperSettingsHost(route: nested)
        case .about(let nested):
            AboutSettingsHost(route: nested)
        }
    }
}

// MARK: - Notifications

struct NotificationSettingsHost: View {
    let route: NotificationSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Notifications",
                    subtitle: "Push authorization and category delivery.",
                    symbol: "bell"
                )
                NotificationStackGraphic()
                SettingsGroup(title: "Categories") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Push", subtitle: "Device authorization", symbol: "iphone.radiowaves.left.and.right") {
                            app.navigation.open(.settings(.notifications(.push)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Social", subtitle: "Reactions, comments, follows", symbol: "heart") {
                            app.navigation.open(.settings(.notifications(.social)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Modules", subtitle: "Updates and activity", symbol: "shippingbox") {
                            app.navigation.open(.settings(.notifications(.modules)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Quiet Hours", subtitle: "Delivery window", symbol: "moon.zzz") {
                            app.navigation.open(.settings(.notifications(.quietHours)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Digests", subtitle: "Weekly and morning summaries", symbol: "envelope.open") {
                            app.navigation.open(.settings(.digests(.root)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Push status is live from iOS. Social / modules / quiet-hours stay capability-honest until preference contracts are verified.")
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.notifications")
        case .push:
            PushAuthorizationView()
        case .social:
            SettingsDesignedUnavailableCanvas(
                title: "Social Notifications",
                subtitle: "Reactions, comments, follows, mentions.",
                symbol: "heart",
                tiles: [
                    ("Reactions", "When people react", "face.smiling"),
                    ("Comments", "Replies on your posts", "text.bubble"),
                    ("Follows", "New followers", "person.badge.plus"),
                    ("Mentions", "When you’re tagged", "at")
                ],
                previewRows: [
                    ("All social", "Master toggle", "bell.badge"),
                    ("Digest", "Daily summary", "calendar")
                ],
                apiNote: SettingsRegistry.destination(for: .notifications(.social))?.unavailableReason
                    ?? "Preference contract unverified."
            )
        case .modules:
            SettingsDesignedUnavailableCanvas(
                title: "Module Notifications",
                subtitle: "Updates and module activity alerts.",
                symbol: "shippingbox",
                tiles: [
                    ("Updates", "New versions", "arrow.triangle.2.circlepath"),
                    ("Activity", "Module events", "bolt"),
                    ("Permissions", "Grant requests", "switch.2"),
                    ("Security", "Runtime warnings", "lock.shield")
                ],
                previewRows: [
                    ("Installed only", "Limit to installed", "checkmark.circle"),
                    ("Quiet", "Collapse into digest", "moon")
                ],
                apiNote: SettingsRegistry.destination(for: .notifications(.modules))?.unavailableReason
                    ?? "No verified module-notification preference contract."
            )
        case .quietHours:
            SettingsDesignedUnavailableCanvas(
                title: "Quiet Hours",
                subtitle: "Pause delivery overnight.",
                symbol: "moon.zzz",
                tiles: [
                    ("Starts", "Local evening", "sunset"),
                    ("Ends", "Local morning", "sunrise"),
                    ("Allowlist", "Critical only", "star"),
                    ("Focus", "Respect iOS Focus", "moon.stars")
                ],
                previewRows: [
                    ("Schedule", "Weekdays / weekends", "calendar"),
                    ("Override", "Mentions still deliver", "bell")
                ],
                apiNote: SettingsRegistry.destination(for: .notifications(.quietHours))?.unavailableReason
                    ?? "Dispatcher not available."
            )
        }
    }
}

struct PushAuthorizationView: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            LabeledContent("Status", value: label)
                .accessibilityIdentifier("settings.push.status")
            if status == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else if status == .notDetermined {
                Text("Modula asks for permission during first-run setup, not immediately at launch.")
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Push")
        .task { await refresh() }
        .accessibilityIdentifier("settings.notifications.push")
    }

    private var label: String {
        switch status {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }
}

// MARK: - Privacy & Security

struct PrivacySecurityHost: View {
    let route: PrivacySettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Privacy & Security",
                    subtitle: "Locks, biometrics, and account protection.",
                    symbol: "lock.shield"
                )
                PrivacyLayersGraphic()
                SettingsGroup(title: "Privacy") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Privacy", subtitle: "Profile visibility", symbol: "hand.raised") {
                            app.navigation.open(.settings(.privacy(.privacy)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Glass Privacy", subtitle: "Conversation levels", symbol: "bubble.left.and.bubble.right") {
                            app.navigation.open(.settings(.privacy(.glassPrivacy)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Blocked Accounts", subtitle: "People you’ve blocked", symbol: "nosign") {
                            app.navigation.open(.settings(.privacy(.blocked)))
                        }
                    }
                }
                SettingsGroup(title: "Security") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Security", subtitle: "Account & device", symbol: "lock") {
                            app.navigation.open(.settings(.privacy(.security)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "App Lock", subtitle: "Passcode for this device", symbol: "lock.fill") {
                            app.navigation.open(.settings(.privacy(.appLock)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Face ID & Biometrics", subtitle: "Unlock with biometrics", symbol: "faceid") {
                            app.navigation.open(.settings(.privacy(.biometrics)))
                        }
                    }
                }
            }
            .navigationTitle("Privacy & Security")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.privacy-security")
        case .privacy:
            Form {
                Text("Profile visibility is enforced by Greenfield. Native never shows email or phone on Profile.")
                Text("Account privacy controls that lack a verified persistence contract are omitted rather than faked.")
                    .foregroundStyle(.secondary)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Privacy")
        case .security:
            Form {
                Button("App Lock") { app.navigation.open(.settings(.privacy(.appLock))) }
                Button("Face ID") { app.navigation.open(.settings(.privacy(.biometrics))) }
                Button("Sessions") { app.navigation.open(.settings(.account(.sessions))) }
                Button("Password") { app.navigation.open(.settings(.account(.password))) }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Security")
        case .glassPrivacy:
            SettingsDesignedUnavailableCanvas(
                title: "Glass Privacy",
                subtitle: "Conversation privacy levels.",
                symbol: "bubble.left.and.bubble.right",
                tiles: [
                    ("Standard", "Normal chats", "bubble.left"),
                    ("Protected", "Extra barriers", "lock.shield"),
                    ("Vault", "Highest local protection", "lock.rectangle.stack"),
                    ("Forwarding", "Control resharing", "arrowshape.turn.up.right")
                ],
                previewRows: [
                    ("Default for new chats", "Choose a level", "slider.horizontal.3"),
                    ("Screen security", "App Switcher blur", "eye.slash")
                ],
                apiNote: SettingsRegistry.destination(for: .privacy(.glassPrivacy))?.unavailableReason
                    ?? "Protected Chat / Vault Chat are not cryptographically complete."
            )
        case .blocked:
            SettingsDesignedUnavailableCanvas(
                title: "Blocked Accounts",
                subtitle: "People you’ve blocked.",
                symbol: "nosign",
                tiles: [
                    ("People", "Blocked profiles", "person.crop.circle.badge.xmark"),
                    ("Modules", "Blocked modules", "shippingbox"),
                    ("Import", "From other apps", "square.and.arrow.down"),
                    ("Export", "Your block list", "square.and.arrow.up")
                ],
                previewRows: [
                    ("Search blocked", "Find someone", "magnifyingglass"),
                    ("Unblock", "Restore access", "arrow.uturn.backward")
                ],
                apiNote: SettingsRegistry.destination(for: .privacy(.blocked))?.unavailableReason
                    ?? "Verified block-list endpoint not available in native DTOs this run."
            )
        case .appLock:
            AppLockSettingsView()
        case .biometrics:
            BiometricsSettingsView()
        }
    }
}

struct AppLockSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsSetup = false
    @State private var showsChange = false
    @State private var confirmSignOutReset = false

    var body: some View {
        let lock = app.appLock
        Form {
            Section {
                Toggle("Enable App Lock", isOn: Binding(
                    get: { lock.enabled },
                    set: { value in
                        if value, (try? lock.setEnabled(true)) == nil {
                            showsSetup = true
                        } else if !value {
                            try? lock.setEnabled(false)
                            app.refreshLaunchState()
                        }
                    }
                ))
                .accessibilityIdentifier("settings.applock.enable")
            } footer: {
                Text("App Lock protects the already signed-in Modula app on this device. It does not replace account login.")
            }
            Section("Require Lock") {
                ForEach(AppLockInterval.allCases, id: \.self) { interval in
                    Button {
                        lock.setInterval(interval)
                    } label: {
                        HStack {
                            Text(interval.title)
                            Spacer()
                            if lock.settings.interval == interval {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section {
                Button("Change Passcode") { showsChange = true }
                Toggle("Use \(lock.biometricAvailability.kind.title)", isOn: Binding(
                    get: { lock.settings.biometricsEnabled },
                    set: { lock.setBiometricsEnabled($0) }
                ))
                .disabled(!lock.biometricAvailability.isUsable)
                Toggle("Privacy screen in App Switcher", isOn: Binding(
                    get: { lock.settings.hideInAppSwitcher },
                    set: { lock.setHideInAppSwitcher($0) }
                ))
            }
            Section {
                Button("Forgot Passcode? Sign Out and Reset App Lock", role: .destructive) {
                    confirmSignOutReset = true
                }
            } footer: {
                Text("Greenfield has no verified re-auth reset for a local App Lock PIN this run. Signing out clears the local lock. Unsynced drafts on this device are kept unless you discard them.")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("App Lock")
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                PasscodeSetupView(title: "App Lock") { passcode in
                    try app.appLock.setPasscode(passcode)
                    try app.appLock.setEnabled(true)
                    app.refreshLaunchState()
                }
            }
        }
        .sheet(isPresented: $showsChange) {
            NavigationStack {
                PasscodeSetupView(title: "Change Passcode") { passcode in
                    try app.appLock.setPasscode(passcode)
                }
            }
        }
        .confirmationDialog("Sign out and reset App Lock?", isPresented: $confirmSignOutReset, titleVisibility: .visible) {
            Button("Sign Out and Reset", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("settings.privacy-security.app-lock")
    }
}

struct BiometricsSettingsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let availability = app.appLock.biometricAvailability
        Form {
            LabeledContent("Status", value: availability.explanation)
            Toggle("Unlock with \(availability.kind.title)", isOn: Binding(
                get: { app.appLock.settings.biometricsEnabled },
                set: { app.appLock.setBiometricsEnabled($0) }
            ))
            .disabled(!availability.isUsable)
            Text("Biometric unlock falls back to your Modula passcode. Failed biometric attempts never open Home.")
                .foregroundStyle(.secondary)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Face ID & Biometrics")
        .accessibilityIdentifier("settings.privacy-security.biometrics")
    }
}

// MARK: - Modules

struct ModuleSettingsHost: View {
    let route: ModuleSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Modules",
                    subtitle: "Installed modules, updates, and HostBridge permissions.",
                    symbol: "shippingbox"
                )
                ModuleOrbitGraphic(installedCount: app.catalogue.installedIDs.count)
                SettingsGroup(title: "Manage") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Installed", subtitle: "On this account", symbol: "arrow.down.circle") {
                            app.navigation.open(.settings(.modules(.installed)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Updates", subtitle: "Catalogue versions", symbol: "arrow.triangle.2.circlepath") {
                            app.navigation.open(.settings(.modules(.updates)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Auto Updates", subtitle: "Update policy", symbol: "arrow.clockwise") {
                            app.navigation.open(.settings(.modules(.autoUpdates)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Permissions", subtitle: "HostBridge grants", symbol: "switch.2") {
                            app.navigation.open(.settings(.modules(.permissions)))
                        }
                    }
                }
            }
            .navigationTitle("Modules")
            .navigationBarTitleDisplayMode(.inline)
        case .installed:
            ModuleInstalledList()
        case .updates:
            Form {
                ForEach(app.catalogue.products.filter { app.catalogue.installedIDs.contains($0.id) }) { product in
                    LabeledContent(product.name, value: product.latestVersion ?? "Unknown version")
                }
                if app.catalogue.installedIDs.isEmpty {
                    Text("No installed modules to update.")
                        .foregroundStyle(.secondary)
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Module Updates")
        case .autoUpdates:
            let dest = SettingsRegistry.destination(for: .modules(.autoUpdates))
            SettingsCapabilityUnavailableView(title: dest?.title ?? "Auto Updates", reason: dest?.unavailableReason ?? "", symbol: "arrow.clockwise")
        case .permissions:
            ModulePermissionsOverview()
        case .module(let id, let section):
            InstalledModuleSettings(moduleID: id, section: section)
        }
    }
}

private struct ModuleInstalledList: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        List {
            ForEach(app.catalogue.products.filter { app.catalogue.installedIDs.contains($0.id) || bundled($0.id) }) { product in
                Button {
                    app.navigation.open(.settings(.modules(.module(product.id, .general))))
                } label: {
                    Label(product.name, systemImage: "shippingbox")
                }
            }
            if app.catalogue.installedIDs.isEmpty && app.runtime.manifests.isEmpty {
                Text("No modules are installed on this account.")
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Installed")
    }

    private func bundled(_ id: String) -> Bool {
        app.runtime.manifests.contains { $0.id == id }
    }
}

private struct ModulePermissionsOverview: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        List {
            ForEach(app.runtime.manifests, id: \.id) { manifest in
                Section(manifest.name) {
                    if manifest.permissions.isEmpty {
                        Text("This module declares no HostBridge permissions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manifest.permissions, id: \.self) { permission in
                            LabeledContent(permission, value: "Granted by manifest")
                        }
                    }
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Permissions")
    }
}

private struct InstalledModuleSettings: View {
    let moduleID: String
    let section: ModuleSettingsSection
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let product = app.catalogue.product(moduleID)
        let manifest = app.runtime.manifests.first { $0.id == moduleID }
        Form {
            switch section {
            case .general:
                LabeledContent("Name", value: product?.name ?? manifest?.name ?? moduleID)
                LabeledContent("Version", value: product?.latestVersion ?? manifest?.version ?? "—")
                LabeledContent("Installed", value: app.catalogue.installedIDs.contains(moduleID) ? "Yes" : "Bundled only")
            case .permissions:
                if let manifest, !manifest.permissions.isEmpty {
                    ForEach(manifest.permissions, id: \.self) { permission in
                        VStack(alignment: .leading) {
                            Text(permission).font(.headline)
                            Text("Declared by the module manifest. HostBridge enforces this grant; there is no decorative toggle.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No HostBridge permissions are declared for this module.")
                        .foregroundStyle(.secondary)
                }
            case .data:
                Text("Offline module data is owned by the module runtime. Clearing cache does not delete it.")
                    .foregroundStyle(.secondary)
            case .updates:
                LabeledContent("Catalogue version", value: product?.latestVersion ?? "Not published")
            case .diagnostics:
                LabeledContent("Runtime", value: manifest?.runtime ?? "—")
                LabeledContent("Bridge", value: ModuleRuntimeController.bridgeVersion)
            case .about:
                Text(product?.description ?? "No catalogue description.")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(section.rawValue.capitalized)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Open") { app.navigation.open(.module(moduleID, localPath: nil)) }
                    Button("Product page") { app.navigation.open(.productHub(.module(moduleID, .overview))) }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

// MARK: - Data & Storage

struct DataStorageHost: View {
    let route: DataSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @State private var usage: StorageUsageSnapshot?
    @State private var cleared = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Data & Storage",
                    subtitle: "Measured usage, cache, and export honesty.",
                    symbol: "internaldrive"
                )
                SettingsGroup(title: "On this device") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Storage", subtitle: "Measured local usage", symbol: "externaldrive") {
                            app.navigation.open(.settings(.dataStorage(.storage)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Cache", subtitle: "Clear rebuildable cache", symbol: "xmark.bin") {
                            app.navigation.open(.settings(.dataStorage(.cache)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Downloads", subtitle: "Downloaded content", symbol: "arrow.down.to.line") {
                            app.navigation.open(.settings(.dataStorage(.downloads)))
                        }
                    }
                }
                SettingsGroup(title: "Account data") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Backup", subtitle: "Account or module backup", symbol: "arrow.clockwise.icloud") {
                            app.navigation.open(.settings(.dataStorage(.backup)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Export", subtitle: "Account data export", symbol: "square.and.arrow.up") {
                            app.navigation.open(.settings(.dataStorage(.export)))
                        }
                    }
                }
            }
            .navigationTitle("Data & Storage")
            .navigationBarTitleDisplayMode(.inline)
        case .storage:
            Form {
                if let usage {
                    LabeledContent("Caches", value: usage.caches)
                    LabeledContent("Temporary", value: usage.temporary)
                    LabeledContent("Application support", value: usage.applicationSupport)
                    LabeledContent("Draft Media", value: usage.draftMedia)
                    Text("Figures are measured from this device. Drafts, draft media, and Keychain sessions are not included as cache.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Measuring…")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Storage")
            .task { usage = StorageUsageSnapshot.measure() }
        case .cache:
            Form {
                Text("Clears URLCache and temporary files only. Account session, drafts and offline module data are kept.")
                    .foregroundStyle(.secondary)
                Button("Clear Cache", role: .destructive) {
                    StorageUsageSnapshot.clearCache()
                    cleared = true
                    HapticEngine.shared.play(.confirmation)
                }
                if cleared {
                    Text("Cache cleared.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Cache")
        case .downloads:
            ContentUnavailableView("No downloaded content", systemImage: "arrow.down.to.line", description: Text("This build has no downloads subsystem."))
                .modulaSoftScrollEdge()
                .navigationTitle("Downloads")
        case .backup, .export:
            let dest = SettingsRegistry.destination(for: .dataStorage(route))
            SettingsCapabilityUnavailableView(title: dest?.title ?? "Unavailable", reason: dest?.unavailableReason ?? "", symbol: dest?.symbol ?? "slash.circle")
        }
    }
}

struct StorageUsageSnapshot {
    var caches: String
    var temporary: String
    var applicationSupport: String
    var draftMedia: String

    static func measure() -> StorageUsageSnapshot {
        let fm = FileManager.default
        func size(of directory: FileManager.SearchPathDirectory) -> String {
            guard let url = fm.urls(for: directory, in: .userDomainMask).first else { return "—" }
            return byteCount(folderSize(url))
        }
        return StorageUsageSnapshot(
            caches: size(of: .cachesDirectory),
            temporary: byteCount(folderSize(URL(fileURLWithPath: NSTemporaryDirectory()))),
            applicationSupport: size(of: .applicationSupportDirectory),
            draftMedia: byteCount(DraftMediaStore().byteCount())
        )
    }

    static func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let items = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for item in items { try? fm.removeItem(at: item) }
        }
        if let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: NSTemporaryDirectory()), includingPropertiesForKeys: nil) {
            for item in items { try? fm.removeItem(at: item) }
        }
    }

    private static func folderSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

// MARK: - Accessibility / Features / Updates / Developer / About

struct AccessibilitySettingsHost: View {
    let route: AccessibilitySettingsRoute
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Form {
            switch route {
            case .root, .text:
                AccessibilityPreviewGraphic(
                    sample: "Modula text follows the system size you choose.",
                    scale: dynamicTypeSize.isAccessibilitySize ? 1.35 : 1
                )
                LabeledContent("Dynamic Type", value: String(describing: dynamicTypeSize))
                Text("Modula follows system text size. Appearance Text Size is an additional product scale and does not override Dynamic Type.")
                    .foregroundStyle(.secondary)
            case .contrast:
                LabeledContent("System contrast", value: contrast == .increased ? "Increased" : "Standard")
                Text("Increase Contrast in iOS Settings is respected. Appearance Contrast & Transparency can raise contrast further without disabling system settings.")
                    .foregroundStyle(.secondary)
            case .motion:
                LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
                Text("Modula does not override Reduce Motion. Motion Personality only applies when the system allows motion.")
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(route == .root ? "Accessibility" : route.rawValue.capitalized)
    }
}

struct FeatureSettingsHost: View {
    let route: FeatureSettingsRoute

    var body: some View {
        let flags: [FeatureFlag] = {
            switch route {
            case .root, .enabled: FeatureFlagRegistry.productionVisible
            case .experimental: FeatureFlagRegistry.experimentalVisible
            }
        }()
        List(flags) { flag in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(flag.title).font(.headline)
                    Spacer()
                    Text(flag.enabled ? "On" : "Off").foregroundStyle(.secondary)
                }
                Text(flag.detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(route == .experimental ? "Experimental" : "Features")
    }
}

struct UpdateSettingsHost: View {
    let route: UpdateSettingsRoute

    var body: some View {
        Form {
            switch route {
            case .root, .channel, .stable:
                LabeledContent("Distribution", value: channelTitle)
                Text("Production iOS builds follow the App Store release channel. This client cannot switch or downgrade the installed binary.")
                    .foregroundStyle(.secondary)
            case .unstable:
                Text("Unstable channels are meaningful for internal and TestFlight builds only.")
                    .foregroundStyle(.secondary)
            case .versionLock:
                Text("Version Lock applies to module catalogue versions Modula controls, not the App Store binary. No module auto-update policy contract is verified this run, so there is no toggle that pretends to pin the iOS app.")
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(title)
    }

    private var title: String {
        switch route {
        case .root: "Updates"
        case .channel, .stable: "Update Channel"
        case .unstable: "Unstable Channel"
        case .versionLock: "Version Lock"
        }
    }

    private var channelTitle: String {
        #if DEBUG
        "Internal Debug"
        #else
        "App Store"
        #endif
    }
}

struct DeveloperSettingsHost: View {
    let route: DeveloperSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        #if DEBUG
        switch route {
        case .root:
            Form {
                Button("Runtime") { app.navigation.open(.settings(.developer(.runtime))) }
                Button("Modules") { app.navigation.open(.settings(.developer(.modules))) }
                Button("Network") { app.navigation.open(.settings(.developer(.network))) }
                Button("Feature Flags") { app.navigation.open(.settings(.developer(.featureFlags))) }
                Button("Environment") { app.navigation.open(.settings(.developer(.environment))) }
                Button("Components") { app.navigation.open(.settings(.developer(.components))) }
                Button("Diagnostics") { app.navigation.open(.settings(.developer(.diagnostics))) }
                Button("Local Intelligence") { app.navigation.open(.settings(.developer(.intelligence))) }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Developer")
        case .runtime, .diagnostics:
            RuntimeDiagnosticsView()
        case .intelligence:
            IntelligenceDiagnosticsView()
        case .nodusChat:
            NodusChatView()
        case .modules:
            List(app.runtime.manifests, id: \.id) { manifest in
                LabeledContent(manifest.name, value: manifest.version)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Developer Modules")
        case .network:
            Form {
                LabeledContent("API host", value: apiHost)
                Text("Tokens are never shown here.")
                    .foregroundStyle(.secondary)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Network")
        case .featureFlags:
            FeatureSettingsHost(route: .root)
        case .environment:
            Form {
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Environment")
        case .components:
            ComponentCatalogView()
        }
        #else
        SettingsCapabilityUnavailableView(
            title: "Developer",
            reason: "Developer settings are only available in internal builds.",
            symbol: "hammer"
        )
        #endif
    }

    private var apiHost: String {
        (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String)
            .flatMap { URL(string: $0) }?
            .host ?? "unconfigured"
    }
}

struct AboutSettingsHost: View {
    let route: AboutSettingsRoute
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            switch route {
            case .root, .version:
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                LabeledContent("Name", value: "Modula")
            case .licenses:
                Text("React Native, Hermes and CocoaPods components ship under their upstream licenses in the iOS workspace. Application source is Modula.")
            case .privacy:
                Button("Open Privacy Policy") {
                    if let url = URL(string: "https://modula.digital/privacy") { openURL(url) }
                }
            case .terms:
                Button("Open Terms") {
                    if let url = URL(string: "https://modula.digital/terms") { openURL(url) }
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(route == .root ? "About" : route.rawValue.capitalized)
        .accessibilityIdentifier("settings.about")
    }
}
