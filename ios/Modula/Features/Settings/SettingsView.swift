import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                if title == "Modula" {
                    ModulaWordmark(height: 18)
                } else {
                    Text(title).font(.headline)
                }
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            ModulaCard { content }
        }
        .modulaScrollReveal()
    }
}

/// Card of toggle / picker rows. Replaces `Form {}.scrollDisabled(true)
/// .frame(minHeight:)` nested inside a ScrollView, which clipped rows at
/// large text sizes and drew a second grouped background.
struct SettingsToggleCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
                content
                    .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .tint(app.appearance.accent.color)
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 43) }
}

struct SettingsNavigationRow: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var action: () -> Void
    var body: some View {
        ModulaListRow(title: title, subtitle: subtitle, symbol: symbol, action: action)
            .modulaTapRipple(amplitude: 5)
    }
}

private struct AppearanceChoice<Value: Hashable>: View {
    let title: String
    let symbol: String?
    let value: Value
    @Binding var selection: Value
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            selection = value
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1).minimumScaleFactor(0.78)
                if selection == value { Image(systemName: "checkmark") }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selection == value ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selection == value ? app.appearance.accent.color : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

private struct AppearanceMenuRow<Value: Hashable, Options: RandomAccessCollection>: View where Options.Element == Value {
    let title: String
    let symbol: String
    @Binding var selection: Value
    let options: Options
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
            Text(title).font(.body.weight(.medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(Array(options), id: \.self) { option in Text(label(option)).tag(option) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(minHeight: 48)
    }
}

struct SettingsRouteView: View {
    let route: SettingsRoute

    var body: some View {
        SettingsDestinationHost(route: route)
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var identityNamespace
    @State private var query = ""
    @State private var searchPresented = false
    @State private var headerProgress: CGFloat = 0
    @State private var intelligenceStatus = "Checking local providers"
    @State private var quickPane: SettingsQuickPane?
    @AppStorage("settings.battery.dataSaver") private var dataSaver = false
    @AppStorage("settings.battery.pauseAutoplayOnLowPower") private var pauseAutoplay = true
    @AppStorage("settings.audio.hapticOnPlay") private var hapticOnPlay = true
    @AppStorage("settings.sharing.preferNativeSheet") private var preferNativeShare = true
    @AppStorage("settings.focus.dimActivity") private var dimActivity = true
    @AppStorage("settings.focus.hideBadges") private var hideBadges = false
    @AppStorage("settings.focus.allowMentions") private var allowMentions = true
    @AppStorage("settings.feed.defaultMode") private var feedMode = "following"

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var compactVisible: Bool { !isSearching && headerProgress > 0.35 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ModulaScrollProgressReader()

                if !isSearching {
                    SettingsCoverHeader(
                        coverURL: app.profile.ownProfile?.coverURL,
                        displayName: identityDisplayName,
                        handle: identityHandle,
                        initials: identityInitials,
                        avatarURL: identityAvatarURL,
                        namespace: identityNamespace,
                        progress: headerProgress,
                        onIdentityTap: openAccountOrLogin,
                        onEdit: openProfileEdit
                    )
                }

                if isSearching {
                    SettingsGroup(title: "Results", subtitle: "Matches settings names and descriptions.") {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredSearchItems.enumerated()), id: \.element.id) { index, item in
                                SettingsNavigationRow(title: item.title, subtitle: item.subtitle, symbol: item.symbol) {
                                    app.navigation.settingsFocusAnchor = item.anchor
                                    app.navigation.open(.settings(item.route))
                                }
                                if index < filteredSearchItems.count - 1 { SettingsDivider() }
                            }
                            if filteredSearchItems.isEmpty {
                                ContentUnavailableView.search(text: query)
                                    .frame(minHeight: 220)
                            }
                        }
                    }
                } else {
                    SettingsGroup(title: "You") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(title: "Account", subtitle: app.auth.account?.primaryHandle ?? "Sign in and personal information", symbol: "person.crop.circle") {
                                openAccountOrLogin()
                            }
                            .contextMenu {
                                Button("Edit Profile", systemImage: "pencil") { openProfileEdit() }
                                Button("Modula Code", systemImage: "qrcode") { app.navigation.open(.settings(.qrCode(.root))) }
                                Button("Creator", systemImage: "paintbrush.pointed") { app.navigation.open(.settings(.creator(.root))) }
                            }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Appearance", subtitle: themeSubtitle, symbol: "paintpalette") {
                                app.navigation.open(.settings(.appearance(.root)))
                            }
                            .contextMenu {
                                Button("System", systemImage: "circle.lefthalf.filled") { app.appearance.theme = .system }
                                Button("Light", systemImage: "sun.max") { app.appearance.theme = .light }
                                Button("Dark", systemImage: "moon") { app.appearance.theme = .dark }
                                Divider()
                                Button("Open Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
                            }
                            SettingsDivider()
                            category("Personalisation", "Recommendations, stories and captions", "slider.horizontal.3", .personalisation(.root))
                        }
                    }

                    SettingsGroup(title: "Quick", subtitle: "These change the same device settings as their full pages.") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $dataSaver) { quickLabel("Data saver", "battery.100percent", "battery.dataSaver") }
                            SettingsDivider()
                            Toggle(isOn: $pauseAutoplay) { quickLabel("Pause autoplay in Low Power", "bolt.slash", "battery.lowPower") }
                            SettingsDivider()
                            Toggle(isOn: $hapticOnPlay) { quickLabel("Haptics on play", "hand.tap", "audio.haptics") }
                            SettingsDivider()
                            Toggle(isOn: $preferNativeShare) { quickLabel("System share sheet", "square.and.arrow.up", "sharing.sheet") }
                            SettingsDivider()
                            Toggle(isOn: $dimActivity) { quickLabel("Dim Activity in Focus", "moon.stars", "focus.dimActivity") }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: dataSaver)
                        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: dimActivity)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        Text("Intelligence").font(.headline)
                        SettingsIntelligenceCard(status: intelligenceStatus, detail: "Configure") {
                            app.navigation.open(.settings(.intelligence(.root)))
                        }
                    }

                    SettingsGroup(title: "Experience") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(title: "Feed", subtitle: feedSubtitle, symbol: "rectangle.stack") {
                                app.navigation.open(.settings(.feed(.root)))
                            }
                            .contextMenu {
                                Button("Following") { feedMode = "following" }
                                Button("For You") { feedMode = "for-you" }
                                Button("Modules") { feedMode = "modules" }
                            }
                            SettingsDivider()
                            category("Moliboo", "Choose, dress up, 3D and more", "pawprint.fill", .moliboo); SettingsDivider()
                            category("Chats", "Composer, previews and chat privacy", "bubble.left.and.bubble.right", .chats(.root)); SettingsDivider()
                            category("Media", "Quality, camera and photos", "photo.on.rectangle.angled", .media(.root)); SettingsDivider()
                            category("Audio", "Playback, voice and haptics", "speaker.wave.2", .audio(.root)); SettingsDivider()
                            category("Notifications", "Push, digests and quiet hours", "bell", .notifications(.root))
                            .contextMenu { Button("Digests", systemImage: "envelope.open") { quickPane = .digests } }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Focus", subtitle: "Behaviour during iOS Focus", symbol: "moon.stars") {
                                app.navigation.open(.settings(.focus(.root)))
                            }
                            .contextMenu {
                                Toggle("Hide tab badges", isOn: $hideBadges)
                                Toggle("Dim Activity", isOn: $dimActivity)
                                Toggle("Allow mentions", isOn: $allowMentions)
                            }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Sharing", subtitle: preferNativeShare ? "System sheet preferred" : "Link share preferred", symbol: "square.and.arrow.up") {
                                quickPane = .sharing
                            }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Gestures", subtitle: "Touch shortcuts", symbol: "hand.draw") {
                                quickPane = .gestures
                            }
                        }
                    }

                    SettingsGroup(title: "System") {
                        VStack(spacing: 0) {
                            category("Search", "Lookup behaviour on this device", "magnifyingglass", .finder(.root)); SettingsDivider()
                            category("Language & Region", "Language, translate, time and units", "globe", .language(.root)); SettingsDivider()
                            category("Accessibility", "Text, contrast and motion", "accessibility", .accessibility(.root)); SettingsDivider()
                            category("Data & Storage", "Downloads, cache, backup and export", "internaldrive", .dataStorage(.root)); SettingsDivider()
                            category("Battery & Data", "Data saver and Low Power", "battery.100.bolt", .battery(.root)); SettingsDivider()
                            SettingsNavigationRow(title: "Keyboard", subtitle: "Typing shortcuts", symbol: "keyboard") { quickPane = .keyboard }
                            SettingsDivider()
                            category("Widgets", "Home Screen surfaces", "rectangle.on.rectangle.angled", .widgets(.root))
                        }
                    }

                    SettingsGroup(title: "Privacy & Security") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(title: "Privacy & Security", subtitle: "Security, app lock and blocked accounts", symbol: "lock.shield") {
                                app.navigation.open(.settings(.privacy(.root)))
                            }
                            .contextMenu {
                                Button("Passkeys", systemImage: "person.badge.key") { app.navigation.open(.settings(.passkeys(.root))) }
                                Button("Location", systemImage: "location") { app.navigation.open(.settings(.location(.root))) }
                                Button("Network", systemImage: "network") { app.navigation.open(.settings(.network(.root))) }
                            }
                            SettingsDivider()
                            category("Safety", "Reporting and sensitive content", "shield.checkered", .safety(.root))
                        }
                    }

                    SettingsGroup(title: "Platform", subtitle: "Connectors and commerce stay capability-honest.") {
                        VStack(spacing: 0) {
                            category("Modules", moduleSummary, "shippingbox", .modules(.root))
                            SettingsDivider()
                            SettingsNavigationRow(title: "Platform services", subtitle: "Connectors, integrations, plans and family", symbol: "puzzlepiece.extension") {
                                app.navigation.open(.settings(.connectors(.root)))
                            }
                            .contextMenu {
                                Button("Connectors", systemImage: "link") { app.navigation.open(.settings(.connectors(.root))) }
                                Button("Integrations", systemImage: "puzzlepiece.extension") { app.navigation.open(.settings(.integrations(.root))) }
                                Button("Monetisation", systemImage: "creditcard") { app.navigation.open(.settings(.monetisation(.root))) }
                                Button("Family", systemImage: "figure.2.and.child.holdinghands") { app.navigation.open(.settings(.family(.root))) }
                                Button("Updates", systemImage: "arrow.triangle.2.circlepath") { app.navigation.open(.settings(.updates(.root))) }
                            }
                        }
                    }

                    SettingsGroup(title: "Modula", subtitle: versionSummary) {
                        VStack(spacing: 0) {
                            category("What’s New", "Release highlights", "sparkles", .whatsNew(.root))
                            SettingsDivider()
                            category("Help", "Guides, contact and status", "questionmark.circle", .help(.root))
                            SettingsDivider()
                            category("About", "Version, acknowledgements and legal information", "info.circle", .about(.root))
                            #if DEBUG
                            SettingsDivider()
                            category("Developer", "Native shell, bridge and feature diagnostics", "hammer", .developer(.root))
                            SettingsDivider()
                            SettingsNavigationRow(title: "Component Catalog", subtitle: "Canonical native visual reference", symbol: "square.grid.3x3") {
                                app.navigation.open(.developer(.components))
                            }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Runtime diagnostics", subtitle: "N1 runtime and memory evidence", symbol: "stethoscope") {
                                app.navigation.open(.settings(.developer(.runtime)))
                            }
                            .accessibilityIdentifier("settings.runtime")
                            #endif
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .top)
        .modulaScrollProgressTracking(collapseDistance: 88, progress: $headerProgress)
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle(compactVisible ? "" : "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(compactVisible ? colorScheme : .dark, for: .navigationBar)
        .searchable(text: $query, isPresented: $searchPresented, prompt: "Search Settings")
        .modulaMinimizedSearchToolbar()
        .task { await refreshIntelligenceStatus() }
        .sheet(item: $quickPane) { pane in
            SettingsQuickSheet(pane: pane)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if compactVisible {
                    SettingsCompactIdentity(
                        namespace: identityNamespace,
                        displayName: identityDisplayName,
                        initials: identityInitials,
                        avatarURL: identityAvatarURL
                    )
                    .opacity(reduceMotion ? 1 : Double(ModulaScrollProgress.clamp((headerProgress - 0.35) / 0.4)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(headerProgress < 0.45)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("Shortcuts") {
                        Button("Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
                        Button("Intelligence", systemImage: "brain") { app.navigation.open(.settings(.intelligence(.root))) }
                        Button("Privacy & Security", systemImage: "lock.shield") { app.navigation.open(.settings(.privacy(.root))) }
                        Button("Module Settings", systemImage: "shippingbox") { app.navigation.open(.settings(.modules(.root))) }
                    }
                    Section("Information") {
                        Button("About Modula", systemImage: "info.circle") { app.navigation.open(.settings(.about(.root))) }
                        Label("Runtime: \(app.runtime.state.capitalized)", systemImage: "memorychip")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Settings menu")
            }
        }
        .accessibilityIdentifier("settings.root")
    }

    private var identityDisplayName: String {
        if let name = app.profile.ownProfile?.displayName, !name.isEmpty { return name }
        if let handle = app.auth.account?.primaryHandle, !handle.isEmpty { return handle }
        return "Modula"
    }

    private var identityHandle: String? {
        let handle = app.profile.ownProfile?.handle ?? app.auth.account?.primaryHandle
        guard let handle, !handle.isEmpty else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }

    private var identityInitials: String {
        ProfileTabAvatarRenderer.initials(profile: app.profile.ownProfile, account: app.auth.account)
    }

    private var identityAvatarURL: URL? {
        app.profile.ownProfile?.avatarURL
    }

    private var moduleSummary: String {
        let count = app.catalogue.installedIDs.count
        return "\(count) installed · permissions and updates"
    }

    private var versionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build)) · native SwiftUI shell"
    }

    private var searchItems: [SettingsSearchItem] {
        SettingsRegistry.search(query: query, includeDeveloper: {
            #if DEBUG
            true
            #else
            false
            #endif
        }()).map {
            SettingsSearchItem($0.title, $0.subtitle, $0.symbol, $0.route, $0.anchor)
        }
    }

    private func refreshIntelligenceStatus() async {
        let providers = await app.intelligence.providers.allProviders()
        var nodusLabel = "Nodus not registered"
        for provider in providers where provider.id == NodusIntelligenceProvider.providerID {
            let availability = await provider.availability()
            nodusLabel = availability == .available ? "Nodus available" : availability.displayName
        }
        let product = providers.filter { $0.id != DeterministicLocalProvider.providerID }
        intelligenceStatus = product.isEmpty ? "No product provider registered" : "Local · \(nodusLabel)"
    }

    private var filteredSearchItems: [SettingsSearchItem] { searchItems }

    private var themeSubtitle: String {
        switch app.appearance.theme {
        case .system: "System theme"
        case .light: "Light theme"
        case .dark: "Dark theme"
        }
    }

    private var feedSubtitle: String {
        switch feedMode {
        case "for-you": "For You is the Home default"
        case "modules": "Modules is the Home default"
        default: "Following is the Home default"
        }
    }

    private func quickLabel(_ title: String, _ symbol: String, _ anchor: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.body.weight(.medium))
            .settingsAnchor(anchor)
    }

    private func category(_ title: String, _ subtitle: String, _ symbol: String, _ route: SettingsRoute) -> some View {
        SettingsNavigationRow(title: title, subtitle: subtitle, symbol: symbol) { app.navigation.open(.settings(route)) }
    }

    private func openAccountOrLogin() {
        app.navigation.open(app.auth.account == nil ? .auth(.login) : .settings(.account(.root)))
    }

    private func openProfileEdit() {
        if app.auth.account == nil {
            app.navigation.open(.auth(.login))
        } else {
            app.navigation.open(.me(.edit))
        }
    }
}

/// Centered Settings identity that dissolves into compact toolbar chrome on scroll.
struct SettingsIdentityHero: View {
    let namespace: Namespace.ID
    var progress: CGFloat
    var displayName: String
    var handle: String?
    var initials: String
    var avatarURL: URL?
    var onIdentityTap: () -> Void
    var onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat { ModulaScrollProgress.clamp(progress) }
    private var heroOpacity: Double {
        reduceMotion ? (clamped > 0.55 ? 0 : 1) : Double(max(0, 1 - clamped * 1.35))
    }
    private var heroScale: CGFloat {
        reduceMotion ? 1 : max(0.72, 1 - clamped * 0.28)
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onIdentityTap) {
                ModulaAvatar(initials: initials, url: avatarURL, size: 96)
                    .matchedGeometryEffect(id: "settings.identity.avatar", in: namespace, isSource: clamped < 0.55)
                    .scaleEffect(heroScale)
                    .accessibilityLabel("Account")
            }
            .buttonStyle(.plain)

            Button(action: onIdentityTap) {
                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let handle {
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(handle.map { "\(displayName), \($0)" } ?? displayName)

            Button(action: onEdit) {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("settings.identity.edit")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .opacity(heroOpacity)
        .allowsHitTesting(heroOpacity > 0.2)
        .accessibilityHidden(heroOpacity < 0.2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.identity.hero")
    }
}

struct SettingsCompactIdentity: View {
    let namespace: Namespace.ID
    var displayName: String
    var initials: String
    var avatarURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            ModulaAvatar(initials: initials, url: avatarURL, size: 28)
                .matchedGeometryEffect(id: "settings.identity.avatar", in: namespace, isSource: true)
            Text(displayName)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayName)
        .accessibilityIdentifier("settings.identity.compact")
    }
}

enum SettingsQuickPane: String, Identifiable {
    case gestures, keyboard, sharing, digests
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gestures: "Gestures"
        case .keyboard: "Keyboard"
        case .sharing: "Sharing"
        case .digests: "Digests"
        }
    }
}

private struct SettingsQuickSheet: View {
    let pane: SettingsQuickPane
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .gestures: GesturesSettingsHost(route: .root)
                case .keyboard: KeyboardSettingsHost(route: .root)
                case .sharing: SharingSettingsHost(route: .root)
                case .digests: DigestsSettingsHost(route: .root)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct SettingsSearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let route: SettingsRoute
    let anchor: String?

    init(_ title: String, _ subtitle: String, _ symbol: String, _ route: SettingsRoute, _ anchor: String?) {
        id = RouteSerializer.serialize(.settings(route)) + (anchor ?? "")
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.route = route
        self.anchor = anchor
    }
}

struct AppearanceSettingsView: View {
    let focus: AppearanceSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var store = app.appearance
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AppearancePreviewView(compact: true)
                SettingsGroup(title: "Colour", subtitle: "Teal remains the Modula semantic default.") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Theme").font(.subheadline.weight(.semibold))
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                AppearanceChoice(title: "System", symbol: "circle.lefthalf.filled", value: .system, selection: $store.theme)
                                AppearanceChoice(title: "Light", symbol: "sun.max", value: .light, selection: $store.theme)
                                AppearanceChoice(title: "Dark", symbol: "moon", value: .dark, selection: $store.theme)
                            }
                            VStack(spacing: 8) {
                                AppearanceChoice(title: "System", symbol: "circle.lefthalf.filled", value: .system, selection: $store.theme)
                                AppearanceChoice(title: "Light", symbol: "sun.max", value: .light, selection: $store.theme)
                                AppearanceChoice(title: "Dark", symbol: "moon", value: .dark, selection: $store.theme)
                            }
                        }
                        if store.theme == .dark || scheme == .dark {
                            Text("Dark canvas").font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                AppearanceChoice(title: "Standard", symbol: nil, value: .standard, selection: $store.darkStyle)
                                AppearanceChoice(title: "Dim", symbol: nil, value: .dim, selection: $store.darkStyle)
                                AppearanceChoice(title: "OLED", symbol: nil, value: .oled, selection: $store.darkStyle)
                            }
                        }
                        Divider()
                        Text("Accent").font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 12) {
                            ForEach(AppearanceStore.Accent.allCases) { accent in
                                Button {
                                    store.accent = accent
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    VStack(spacing: 7) {
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 38, height: 38)
                                            .overlay(Circle().stroke(.primary, lineWidth: store.accent == accent ? 3 : 0).padding(-4))
                                        Text(accent.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.72)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 68)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(accent.title)
                                .accessibilityAddTraits(store.accent == accent ? .isSelected : [])
                            }
                        }
                        Divider()
                        AppearanceMenuRow(title: "Contrast & Transparency", symbol: "circle.righthalf.filled", selection: $store.contrastTransparency, options: AppearanceStore.ContrastTransparency.allCases, label: display)
                    }
                }
                SettingsGroup(title: "Typography", subtitle: "Every sample responds to Dynamic Type.") {
                    VStack(spacing: 0) {
                        AppearanceMenuRow(title: "Font Family", symbol: "textformat", selection: $store.fontFamily, options: AppearanceStore.FontFamily.allCases, label: display)
                        Divider().padding(.leading, 43)
                        AppearanceMenuRow(title: "Text Size", symbol: "textformat.size", selection: $store.textSize, options: AppearanceStore.TextSize.allCases, label: display)
                        Divider().padding(.vertical, 12)
                        TypographyPreviewCard(family: store.fontFamily)
                    }
                }
                SettingsGroup(title: "Interface") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "App Icon", subtitle: "Default · device-local", symbol: "app.dashed") {
                            app.navigation.open(.settings(.appearance(.appIcon)))
                        }
                        SettingsDivider()
                        AppearanceMenuRow(title: "Density", symbol: "arrow.up.left.and.arrow.down.right", selection: $store.density, options: AppearanceStore.Density.allCases, label: display)
                        SettingsDivider()
                        AppearanceMenuRow(title: "Motion", symbol: "waveform.path", selection: $store.motion, options: AppearanceStore.MotionPersonality.allCases, label: display)
                        SettingsDivider()
                        AppearanceMenuRow(title: "Haptics", symbol: "hand.tap", selection: $store.haptics, options: AppearanceStore.HapticIntensity.allCases, label: display)
                        SettingsDivider()
                        AppearanceMenuRow(title: "Icon Style", symbol: "circle.grid.cross", selection: $store.iconStyle, options: AppearanceStore.IconStyle.allCases, label: display)
                        SettingsDivider()
                        AppearanceMenuRow(title: "Interface Shape", symbol: "rectangle.roundedtop", selection: $store.interfaceShape, options: AppearanceStore.InterfaceShape.allCases, label: display)
                        SettingsDivider()
                        AppearanceMenuRow(title: "Module Branding", symbol: "paintbrush", selection: $store.moduleBranding, options: AppearanceStore.ModuleBranding.allCases, label: display)
                        SettingsDivider()
                        SettingsNavigationRow(title: "Edge Picker", subtitle: "Position, size, side, glass", symbol: "rectangle.trailinghalf.inset.filled") {
                            app.navigation.open(.settings(.appearance(.edgePicker)))
                        }
                    }
                }
                SettingsGroup(title: "Preview & Defaults") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Full Appearance Preview", subtitle: nil, symbol: "rectangle.inset.filled") {
                            app.navigation.open(.settings(.appearance(.preview)))
                        }
                        SettingsDivider()
                        Button(role: .destructive) { confirmsReset = true } label: {
                            Label("Reset Appearance", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                    }
                }
                Text("Appearance preferences are saved on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle(focus == .root ? "Appearance" : display(focus.rawValue))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset Appearance?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Appearance", role: .destructive) { store.reset() }
        } message: {
            Text("This restores Modula appearance defaults without changing other settings.")
        }
        .accessibilityIdentifier("settings.appearance")
    }

    private func display<T: RawRepresentable>(_ value: T) -> String where T.RawValue == String { display(value.rawValue) }
    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "-", with: " ").capitalized
    }
}

struct AppearancePreviewView: View {
    var compact = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: 12 * app.appearance.density.spacingScale) {
                HStack {
                    ModulaAvatar(initials: "M")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        ModulaText(text: "Modula Preview", role: .headline)
                        Text("How your choices look").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ModulaBadge(title: "Live", symbol: "sparkles")
                }
                ModulaText(text: "Your digital world, your way.", role: compact ? .headline : .title)
                HStack {
                    ModulaMetric(value: "3", label: "Modes"); Spacer()
                    ModulaMetric(value: "1", label: "Runtime"); Spacer()
                    ModulaMetric(value: "Swift", label: "Shell")
                }
                if !compact { ModulaButton(title: "Primary Action", symbol: "arrow.right") {} }
            }
        }
    }
}

struct AppearancePreviewScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AppearancePreviewView()
                ModulaSection(title: "Navigation accessory") {
                    VStack(alignment: .leading, spacing: 8) {
                        ModulaTabAccessory(route: .home(.following))
                        Text("The live system tab bar remains visible below and minimizes with this accessory while scrolling.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ModulaSection(title: "Edge Picker") { HStack { Spacer(); ShellEdgeLoop(route: .home(.following)) } }
                ModulaSection(title: "Module sample") {
                    ModulaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ModulaBadge(title: "Module environment v1", symbol: "shippingbox")
                            ModulaText(text: "Vault Notes", role: .title)
                            Text("Accent, type, density, motion and branding update through the additive host environment.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Appearance Preview")
    }
}

struct AppIconPickerView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)], spacing: 18) {
                Button {
                    app.appearance.appIcon = .default
                    HapticEngine.shared.play(.selection)
                } label: {
                    VStack(spacing: 10) {
                        Image("ModulaAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Label("Default", systemImage: "checkmark.circle.fill").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isSelected)
            }
            .padding(18)
            Text("Only the approved production icon is available. Alternate icons will appear here after their device assets pass visual review.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("App Icon")
    }
}

struct ComponentCatalogView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""

    var body: some View {
        @Bindable var appearance = app.appearance
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                catalog("Live Appearance") {
                    VStack(spacing: 12) {
                        Picker("Theme", selection: $appearance.theme) {
                            ForEach(AppearanceStore.Theme.allCases, id: \.self) { Text(settingsDisplayTitle($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Dark Style", selection: $appearance.darkStyle) {
                            ForEach(AppearanceStore.DarkStyle.allCases, id: \.self) { Text(settingsDisplayTitle($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack {
                            Picker("Accent", selection: $appearance.accent) { ForEach(AppearanceStore.Accent.allCases) { Text($0.title).tag($0) } }
                            Picker("Font", selection: $appearance.fontFamily) { ForEach(AppearanceStore.FontFamily.allCases, id: \.self) { Text(settingsDisplayTitle($0.rawValue)).tag($0) } }
                        }
                        Picker("Density", selection: $appearance.density) {
                            ForEach(AppearanceStore.Density.allCases, id: \.self) { Text(settingsDisplayTitle($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                }
                AppearancePreviewView()
                catalog("Advanced Interaction") {
                    NavigationLink {
                        AdvancedInteractionCatalogView()
                    } label: {
                        Label("Open interaction laboratory", systemImage: "hand.tap")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch, alignment: .leading)
                    }
                    .accessibilityIdentifier("catalog.advanced-interaction")
                }
                catalog("Content & Posts") {
                    NavigationLink {
                        ContentPostCatalogView()
                    } label: {
                        Label("Open universal content laboratory", systemImage: "rectangle.stack.badge.play")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch, alignment: .leading)
                    }
                    .accessibilityIdentifier("catalog.content-posts")
                }
                catalog("Profile") {
                    NavigationLink {
                        ProfileCatalogLabView()
                    } label: {
                        Label("Open profile media laboratory", systemImage: "person.crop.rectangle.stack")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch, alignment: .leading)
                    }
                    .accessibilityIdentifier("catalog.profile")
                }
                catalog("Buttons & controls") {
                    VStack {
                        ModulaButton(title: "Primary Button", symbol: "sparkles") {}
                        ModulaButton(title: "Primary Button", isLoading: true, loadingTitle: "Working…") {}
                        ModulaButton(title: "Disabled Button") {}.disabled(true)
                        FormFieldCatalogSample()
                        HStack {
                            ModulaIconButton(title: "Search", symbol: "magnifyingglass") {}
                            ModulaChip(title: "Selected", selected: true) {}
                            ModulaChip(title: "Available") {}
                        }
                    }
                }
                catalog("Typography") {
                    VStack(alignment: .leading) {
                        ModulaText(text: "Hero typography", role: .hero)
                        ModulaText(text: "Section title", role: .title)
                        ModulaText(text: "Body copy follows Dynamic Type.", role: .body)
                        ModulaText(text: "0123456789 · Supporting caption", role: .caption)
                        TypographyPreviewCard(family: appearance.fontFamily)
                    }
                }
                catalog("Identity & status") {
                    ViewThatFits(in: .horizontal) {
                        HStack { ModulaAvatar(initials: "M", size: 56); ModulaBadge(title: "Verified", symbol: "checkmark.seal"); ModulaBadge(title: "Installed", symbol: "arrow.down.circle") }
                        VStack(alignment: .leading) { ModulaAvatar(initials: "M", size: 56); ModulaBadge(title: "Verified", symbol: "checkmark.seal"); ModulaBadge(title: "Installed", symbol: "arrow.down.circle") }
                    }
                }
                catalog("Forms & rows") {
                    VStack {
                        ModulaSearchField(text: $query)
                        ModulaListRow(title: "Appearance", subtitle: "Live settings", symbol: "paintpalette") {}
                        ModulaListRow(title: "Static information", subtitle: "No fake action", symbol: "info.circle")
                    }
                }
                catalog("Metrics") { ModulaMetadataRail(values: [("24", "Modules"), ("1", "Runtime"), ("Swift", "Shell")]) }
                catalog("States") {
                    VStack {
                        ModulaLoadingState(title: "Loading state")
                        ModulaEmptyState(title: "Empty state", message: "Nothing here yet.", symbol: "tray")
                        ModulaErrorState(message: "A recoverable error state.") {}
                    }
                }
                if let product = app.catalogue.product("digital.modula.vault-notes") {
                    catalog("Product Hub") { VStack { ProductHero(product: product) {}; ProductCard(product: product, installed: true) {} } }
                }
                catalog("Global navigation accessory") {
                    VStack(alignment: .leading, spacing: 8) {
                        ShellAccessoryDock(route: .home(.following))
                        Text("The five-item native tab bar is the live shell chrome below this catalog. AI Mode is a pull-from-top action beside Search, Refresh, and Command.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                catalog("Pull actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pull down to refresh. While pulled, slide left for Command, right for Search, and further right for AI Mode.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ModulaPullActionsChooser(destination: .refresh, refreshing: false, progress: 1)
                    }
                }
                catalog("Global sidebar") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Leading overlay for library and account destinations. The five root tabs stay in the tab bar; Edge Picker stays on the content edge.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ShellSidebarTrigger()
                        ForEach(ShellSidebarDestination.allCases) { item in
                            ModulaListRow(title: item.title, subtitle: item.subtitle, symbol: item.symbol)
                        }
                    }
                }
                catalog("Edge Picker") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Canonical carved-edge channel — orange-reference geometry. Outer silhouette stays fixed; the selection aperture expands vertically with whole-phrase rotated labels.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer(minLength: 0)
                            ShellEdgeLoop(route: .home(.following))
                                .frame(height: 280)
                        }
                        Text("Tune Position / Size / Side / Labels / Glass under Appearance → Edge Picker. ContainedLoopPicker (Typography) does not use the shell carve.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                catalog("Messages, stories, profile accent") {
                    VStack(alignment: .leading, spacing: 16) {
                        MessageBubble(message: MessagingFixtures.thread()[1]) { _ in }
                        MessageBubble(message: MessagingFixtures.thread()[0]) { _ in }
                        HStack(spacing: 16) {
                            StoryRing(state: .unseen, accent: app.appearance.accent.color)
                            StoryRing(state: .seen, accent: app.appearance.accent.color)
                            StoryRing(state: .own, accent: app.appearance.accent.color)
                        }
                        StoryProgressBar(count: 4, index: 1, progress: 0.4)
                        ProfileAccentPicker(selection: .constant(.violet), writable: true)
                    }
                }
                catalog("Creation Studio") {
                    VStack(alignment: .leading, spacing: 12) {
                        AudiencePicker(selection: .constant(.everyone))
                        DraftStatusView(saved: true, publishing: false)
                        CreationToolDock(
                            kind: .post,
                            capabilities: .production,
                            developerMode: true,
                            accent: app.appearance.accent.color,
                            photoPicker: { EmptyView() },
                            videoPicker: { EmptyView() },
                            onTool: { _ in }
                        )
                    }
                }
                catalog("Command platform") {
                    VStack(alignment: .leading, spacing: 12) {
                        CommandRow(
                            command: ModulaCommand(
                                id: "create.post",
                                title: "Create Post",
                                icon: .init("square.and.pencil"),
                                category: .create,
                                action: .composeStart(.post)
                            ),
                            selected: false,
                            action: {}
                        )
                        DraftRow(
                            kind: .post,
                            preview: "Profile should become the social OS home",
                            lastEdited: Date(),
                            onContinue: {},
                            onDelete: {}
                        )
                        SharePreview(payload: .module(id: "digital.modula.vault-notes", name: "Vault Notes", publisher: "Modula"))
                        CollectionCard(collection: ModulaCollection(
                            id: "sample",
                            name: "Design inspiration",
                            storage: .local,
                            itemIDs: ["a", "b"],
                            createdAt: Date(),
                            updatedAt: Date(),
                            isDefault: false
                        ))
                    }
                }
            }
            .padding(18)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Components")
        .accessibilityIdentifier("developer.components")
    }

    private func catalog<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ModulaSection(title: title) { content() }
    }
}

private struct ProfileCatalogLabView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                lab("Profile Hero", note: "Uses the production cover crop, progressive fade, overlap geometry, and authenticated media loader.") {
                    ProfileCover(
                        coverURL: app.profile.ownProfile?.coverURL,
                        coverColour: app.profile.ownProfile?.coverColour ?? "#369CAA",
                        safeAreaTop: 0,
                        pocketCenterX: ModulaLayout.contentInset + 52,
                        pocketRadius: 60
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous))
                }
                lab("Avatar states", note: "Absent media uses initials. Loading and network failure remain visually distinct from absence.") {
                    HStack(spacing: ModulaSpacing.md) {
                        avatarState("Absent", url: nil)
                        VStack(spacing: 6) {
                            ProgressView().frame(width: 64, height: 64).background(Color.primary.opacity(0.05), in: Circle())
                            Text("Loading").font(.caption2).foregroundStyle(.secondary)
                        }
                        avatarState("Failure", url: URL(string: "https://invalid.example.test/avatar.jpg"))
                        if let url = app.profile.ownProfile?.avatarURL { avatarState("Live", url: url) }
                    }
                }
                lab("Cover states", note: "The fallback is intentional Modula artwork; unavailable remote media exposes retry instead of appearing absent.") {
                    VStack(spacing: ModulaSpacing.sm) {
                        ProfileCover(coverURL: nil, coverColour: "#369CAA", safeAreaTop: 0)
                            .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: ModulaRadius.medium))
                        ProfileCover(coverURL: URL(string: "https://invalid.example.test/cover.jpg"), coverColour: "#369CAA", safeAreaTop: 0)
                            .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: ModulaRadius.medium))
                    }
                }
                lab("Large Dynamic Type", note: "Identity content may grow without changing media ownership or creating a second profile layout.") {
                    HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                        ModulaAvatar(initials: "AR", size: 72)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Alex Rivers").font(.title2.bold())
                            Text("@alex · Product designer and photographer")
                            Text("Joined September 2026").foregroundStyle(.secondary)
                        }
                    }
                    .environment(\.dynamicTypeSize, .accessibility3)
                }
            }
            .padding(ModulaSpacing.md)
        }
        .modulaCanvas()
        .navigationTitle("Profile Lab")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("catalog.profile.lab")
    }

    private func avatarState(_ title: String, url: URL?) -> some View {
        VStack(spacing: 6) {
            ModulaAvatar(initials: "AR", url: url, size: 64)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func lab<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text(title).font(.headline)
            Text(note).font(.footnote).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ModulaSpacing.md)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: ModulaRadius.large))
    }
}

/// Developer catalog sample for `ModulaFormField` (focus, validation, secure toggle).
private struct FormFieldCatalogSample: View {
    private enum Field: Hashable { case email, secret }
    @State private var email = "name@"
    @State private var secret = ""
    @FocusState private var focused: Field?

    var body: some View {
        VStack(spacing: ModulaSpacing.sm) {
            ModulaFormField(title: "Email", symbol: "envelope", text: $email,
                            message: SignInView.looksLikeEmail(email) ? nil : "That email address looks incomplete.",
                            focus: $focused, focusValue: Field.email, identifier: "catalog.form-field.email")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            ModulaFormField(title: "Password", symbol: "lock", text: $secret, kind: .secure,
                            focus: $focused, focusValue: Field.secret, identifier: "catalog.form-field.secret")
        }
    }
}
