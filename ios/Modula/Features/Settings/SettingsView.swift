import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 14)
            }
            SettingsGlassCard { content }
            // iOS-style footer, only when a page supplies one.
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
            }
        }
    }
}

/// Card of toggle / picker rows. Replaces `Form {}.scrollDisabled(true)
/// .frame(minHeight:)` nested inside a ScrollView, which clipped rows at
/// large text sizes and drew a second grouped background.
struct SettingsToggleCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .tint(app.appearance.accent.color)
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 42) }
}

struct SettingsNavigationRow: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var action: () -> Void
    var body: some View {
        SettingsTileRow(title: title, subtitle: subtitle, symbol: symbol, action: action)
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
            SettingsIconTile(symbol: symbol)
            Text(title)
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(Array(options), id: \.self) { option in Text(label(option)).tag(option) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(minHeight: 52)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if isSearching {
                    SettingsGroup(title: "Results") {
                        ForEach(Array(filteredSearchItems.enumerated()), id: \.element.id) { index, item in
                            SettingsTileRow(title: item.title, subtitle: item.subtitle, symbol: item.symbol) {
                                app.navigation.settingsFocusAnchor = item.anchor
                                app.navigation.open(.settings(item.route))
                            }
                            if index < filteredSearchItems.count - 1 { SettingsDivider() }
                        }
                        if filteredSearchItems.isEmpty {
                            ContentUnavailableView.search(text: query).frame(minHeight: 220)
                        }
                    }
                } else {
                    SettingsProfileHeaderRow(
                        name: identityDisplayName,
                        handle: identityHandle,
                        initials: identityInitials,
                        avatarURL: identityAvatarURL,
                        action: { app.auth.account == nil ? openAccountOrLogin() : openProfileEdit() }
                    )

                    SettingsGlassCard {
                        row("Account", "person.crop.circle", value: nil, .account(.root))
                        SettingsDivider()
                        row("Privacy & Safety", "hand.raised.fill", value: nil, .privacy(.root))
                        SettingsDivider()
                        row("Notifications", "bell.badge.fill", value: nil, .notifications(.root))
                    }

                    SettingsGlassCard {
                        row("Appearance", "paintpalette.fill", value: themeValue, .appearance(.root))
                        SettingsDivider()
                        row("Accessibility", "accessibility", value: nil, .accessibility(.root))
                        SettingsDivider()
                        row("Language & Region", "globe", value: nil, .language(.root))
                        SettingsDivider()
                        row("Moliboo", "pawprint.fill", value: nil, .moliboo)
                    }

                    SettingsGlassCard {
                        row("Feed", "rectangle.stack.fill", value: feedValue, .feed(.root))
                        SettingsDivider()
                        row("Chats", "bubble.left.and.bubble.right.fill", value: nil, .chats(.root))
                        SettingsDivider()
                        row("Media & Camera", "photo.on.rectangle.angled", value: nil, .media(.root))
                        SettingsDivider()
                        row("Audio & Haptics", "speaker.wave.2.fill", value: nil, .audio(.root))
                        SettingsDivider()
                        row("Gestures, Typing & Sharing", "hand.draw.fill", value: nil, .gestures(.root))
                        SettingsDivider()
                        row("Personalisation", "slider.horizontal.3", value: nil, .personalisation(.root))
                        SettingsDivider()
                        row("Intelligence", "brain", value: intelligenceStatus, .intelligence(.root))
                    }

                    SettingsGlassCard {
                        row("Data & Storage", "internaldrive.fill", value: nil, .dataStorage(.root))
                        SettingsDivider()
                        row("Battery & Network", "battery.100.bolt", value: dataSaver ? "Data saver" : nil, .battery(.root))
                        SettingsDivider()
                        row("Modules", "shippingbox.fill", value: "\(app.catalogue.installedIDs.count)", .modules(.root))
                    }

                    SettingsGlassCard {
                        row("What’s New", "sparkles", value: nil, .whatsNew(.root))
                        SettingsDivider()
                        row("Help & Status", "questionmark.circle.fill", value: nil, .help(.root))
                        SettingsDivider()
                        row("About", "info.circle.fill", value: shortVersion, .about(.root))
                    }

                    #if DEBUG
                    SettingsGroup(title: "Developer", subtitle: "Debug builds only — includes previews of features without a backend.") {
                        row("Developer", "hammer.fill", value: nil, .developer(.root))
                        SettingsDivider()
                        row("Labs", "flask.fill", value: nil, .labs(.root))
                        SettingsDivider()
                        SettingsTileRow(title: "Component Catalog", symbol: "square.grid.3x3.fill") { app.navigation.open(.developer(.components)) }
                        SettingsDivider()
                        row("Runtime diagnostics", "stethoscope", value: nil, .developer(.runtime))
                            .accessibilityIdentifier("settings.runtime")
                        SettingsDivider()
                        row("Glass Privacy (preview)", "bubble.left.and.bubble.right", value: nil, .privacy(.glassPrivacy))
                        SettingsDivider()
                        row("Connectors & Integrations (preview)", "puzzlepiece.extension", value: nil, .connectors(.root))
                        SettingsDivider()
                        row("Monetisation (preview)", "creditcard", value: nil, .monetisation(.root))
                        SettingsDivider()
                        row("Family (preview)", "figure.2.and.child.holdinghands", value: nil, .family(.root))
                        SettingsDivider()
                        row("Widgets & Location (preview)", "rectangle.on.rectangle.angled", value: nil, .widgets(.root))
                    }
                    #endif
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, SettingsInsets.bottom)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Settings")
        .task { await refreshIntelligenceStatus() }
        .accessibilityIdentifier("settings.root")
    }

    private func row(_ title: String, _ symbol: String, value: String?, _ route: SettingsRoute) -> some View {
        SettingsTileRow(title: title, value: value, symbol: symbol) { app.navigation.open(.settings(route)) }
    }

    private var themeValue: String {
        switch app.appearance.theme { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }

    private var feedValue: String {
        switch feedMode { case "for-you": "For You"; case "modules": "Modules"; default: "Following" }
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
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
        }()).filter { entry in
            #if DEBUG
            return true
            #else
            return !SettingsAudit.previewOnly(entry.route)
            #endif
        }.map {
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
