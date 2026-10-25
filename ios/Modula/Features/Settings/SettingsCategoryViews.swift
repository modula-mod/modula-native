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
        destination
            .modulaSoftScrollEdge()
            // Forms/Lists: keep the last row (and footers) clear of the tab bar and floating buttons.
            .contentMargins(.bottom, SettingsInsets.bottom, for: .scrollContent)
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
        case .moliboo:
            MolibooWorldView()
        case .premium:
            PremiumHubView()
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
        case .battery, .network:
            BatteryNetworkSettingsPage()
        case .safety(let nested):
            SafetySettingsHost(route: nested)
        case .camera(let nested):
            CameraSettingsHost(route: nested)
        case .gestures, .finder, .sharing, .keyboard, .photos, .focus:
            GeneralBehaviourSettingsPage()
        case .location(let nested):
            LocationSettingsHost(route: nested)
        case .widgets(let nested):
            WidgetsSettingsHost(route: nested)
        case .labs(let nested):
            LabsSettingsHost(route: nested)

        case .digests(let nested):
            DigestsSettingsHost(route: nested)
        case .help(let nested):
            HelpSettingsHost(route: nested)
        case .whatsNew(let nested):
            WhatsNewSettingsHost(route: nested)
        case .creator(let nested):
            CreatorSettingsHost(route: nested)

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
                SettingsAPIFootnote(text: "Notification permission comes from iOS. More notification options are coming.")
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.notifications")
        case .push:
            PushAuthorizationView()
        case .social:
            NotificationCategoriesView(scope: .social)
        case .modules:
            NotificationCategoriesView(scope: .modules)
        case .quietHours:
            QuietHoursSettingsView()
        }
    }
}

struct PushAuthorizationView: View {
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var requesting = false

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
                Text("Notifications haven’t been requested yet. iOS asks once; you can change it later in iOS Settings.")
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        requesting = true
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        requesting = false
                        await refresh()
                        AccessibilityNotification.Announcement("Notifications \(label.lowercased())").post()
                    }
                } label: {
                    if requesting { ProgressView() } else { Label("Allow Notifications", systemImage: "bell.badge") }
                }
                .disabled(requesting)
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
        case .root, .privacy, .security, .appLock, .biometrics:
            // One page: Privacy + Security + App Lock + Face ID (old sub-routes land here).
            PrivacySafetySettingsPage()
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
                    ?? "Protected Chat / Vault Chat are not cryptographically complete.",
                alternatives: [
                    ("App Lock", "Hide Modula behind Face ID or a passcode", "lock.fill", .privacy(.appLock))
                ]
            )
        case .blocked:
            RelationshipListView(kind: .blocked)
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
                                    .foregroundStyle(app.appearance.accent.color)
                            }
                        }
                    }
                    .accessibilityAddTraits(lock.settings.interval == interval ? .isSelected : [])
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
                Text("Forgot your passcode? Sign out to remove App Lock from this device, then sign back in. Drafts on this device are kept unless you discard them.")
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
            .modulaSoftScrollEdge()
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
                            Text("This module asked for this access. Modula only allows what’s listed here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("This module doesn’t ask for any special access.")
                        .foregroundStyle(.secondary)
                }
            case .data:
                Text("Data saved by this module isn’t removed when you clear the cache.")
                    .foregroundStyle(.secondary)
            case .updates:
                LabeledContent("Installed version", value: manifest?.version ?? "Not installed")
                LabeledContent("Latest version", value: product?.latestVersion ?? "Not published")
            case .diagnostics:
                LabeledContent("Runtime", value: manifest?.runtime ?? "—")
                LabeledContent("Bridge", value: ModuleRuntimeController.bridgeVersion)
            case .about:
                Text(product?.description ?? "No description yet.")
            }
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle(settingsDisplayTitle(section.rawValue))
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
    @State private var confirmingClearCache = false
    @State private var clearingCache = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Data & Storage",
                    subtitle: "Measured usage, cache, and your data export.",
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
            .modulaSoftScrollEdge()
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
            // Walking the cache folders can take a while; measure off the main thread.
            .task { usage = await Task.detached(priority: .utility) { StorageUsageSnapshot.measure() }.value }
        case .cache:
            Form {
                Text("Clears URLCache and temporary files only. Account session, drafts and offline module data are kept.")
                    .foregroundStyle(.secondary)
                Button("Clear Cache", role: .destructive) {
                    confirmingClearCache = true
                    HapticEngine.shared.play(.warning)
                }
                .disabled(clearingCache)
                .confirmationDialog("Clear cache?", isPresented: $confirmingClearCache, titleVisibility: .visible) {
                    Button("Clear Cache", role: .destructive) {
                        clearingCache = true
                        Task {
                            // File deletion off the main thread.
                            await Task.detached(priority: .userInitiated) { StorageUsageSnapshot.clearCache() }.value
                            clearingCache = false
                            cleared = true
                            HapticEngine.shared.play(.confirmation)
                            AccessibilityNotification.Announcement("Cache cleared").post()
                        }
                    }
                } message: {
                    Text("Images and temporary files will download again when needed.")
                }
                if cleared {
                    Text("Cache cleared.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Cache")
        case .downloads:
            MediaDownloadsView()
        case .export:
            AccountDataExportView()
        case .backup:
            let dest = SettingsRegistry.destination(for: .dataStorage(route))
            SettingsCapabilityUnavailableView(title: dest?.title ?? "Unavailable", reason: dest?.unavailableReason ?? "", symbol: dest?.symbol ?? "slash.circle")
        }
    }
}

struct StorageUsageSnapshot: Sendable {
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
    @Environment(AppEnvironment.self) private var app
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
                LabeledContent("Dynamic Type", value: dynamicTypeSize.settingsLabel)
                Text("Modula follows system text size. Appearance Text Size is an additional product scale and does not override Dynamic Type.")
                    .foregroundStyle(.secondary)
                if route == .root {
                    Section("More") {
                        Button {
                            app.navigation.open(.settings(.accessibility(.contrast)))
                        } label: {
                            LabeledContent { Text(contrast == .increased ? "Increased" : "Standard") } label: { Label("Contrast", systemImage: "circle.lefthalf.filled") }
                        }
                        Button {
                            app.navigation.open(.settings(.accessibility(.motion)))
                        } label: {
                            LabeledContent { Text(reduceMotion ? "Reduced" : "Full") } label: { Label("Motion", systemImage: "figure.walk.motion") }
                        }
                        Button {
                            app.navigation.open(.settings(.appearance(.textSize)))
                        } label: {
                            Label("Modula Text Size", systemImage: "textformat.size")
                        }
                    }
                    .foregroundStyle(.primary)
                }
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
        .navigationTitle(route == .root ? "Accessibility" : settingsDisplayTitle(route.rawValue))
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
                Text("Version Lock applies to modules, not to the Modula app itself. App updates are managed by the App Store.")
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
                Button("Module Studio") { app.navigation.open(.developer(.studio)) }
                    .accessibilityIdentifier("developer.settings.studio")
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
        case .nodus:
            NodusWorkspaceView()
        case .nodusChat:
            NodusChatView()
        case .nodusKnowledge:
            NodusKnowledgeView()
        case .nodusMemory:
            NodusMemoryView()
        case .nodusLearning:
            NodusLearningView()
        case .nodusModel:
            NodusModelDiagnosticsView()
        case .nodusSearch:
            NodusSearchSettingsView()
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
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .privacy:
            // Native in-app document (owner decision: legal pages live in the app, not on the web).
            LegalDocumentView(document: .document(.privacy))
        case .terms:
            LegalDocumentView(document: .document(.terms))
        case .root, .version, .licenses:
            aboutForm
        }
    }

    private var aboutForm: some View {
        Form {
            switch route {
            case .root, .version:
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                    LabeledContent("Name", value: "Modula")
                }
                if route == .root {
                    Section("Legal") {
                        Button { app.navigation.open(.settings(.about(.licenses))) } label: { Label("Licenses", systemImage: "doc.plaintext") }
                        Button { app.navigation.open(.settings(.about(.privacy))) } label: { Label("Privacy Policy", systemImage: "hand.raised") }
                        Button { app.navigation.open(.settings(.about(.terms))) } label: { Label("Terms of Service", systemImage: "doc.text") }
                    }
                    .foregroundStyle(.primary)
                    Section("Service") {
                        Button { app.navigation.open(.settings(.help(.status))) } label: { Label("Service Status", systemImage: "waveform.path.ecg") }
                        Button { app.navigation.open(.settings(.whatsNew(.root))) } label: { Label("What’s New", systemImage: "sparkles") }
                    }
                    .foregroundStyle(.primary)
                }
            case .licenses:
                Text("React Native, Hermes and CocoaPods components ship under their upstream licenses in the iOS workspace. Application source is Modula.")
            case .privacy, .terms:
                EmptyView() // Rendered by LegalDocumentView above.
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(route == .root ? "About" : settingsDisplayTitle(route.rawValue))
        .accessibilityIdentifier("settings.about")
    }
}
