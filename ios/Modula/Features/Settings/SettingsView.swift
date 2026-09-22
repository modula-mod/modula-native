import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            ModulaCard { content }
        }
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
    var body: some View { ModulaListRow(title: title, subtitle: subtitle, symbol: symbol, action: action) }
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
    @State private var query = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if query.isEmpty {
                    SettingsGroup(title: "You", subtitle: "Identity and the way Modula feels on this device.") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(title: "Account", subtitle: app.auth.account?.primaryHandle ?? "Sign in and personal information", symbol: "person.crop.circle") {
                                app.navigation.open(app.auth.account == nil ? .auth(.login) : .settings(.account(.root)))
                            }
                            SettingsDivider()
                            SettingsNavigationRow(title: "Appearance", subtitle: "Theme, type, motion and module branding", symbol: "paintpalette") {
                                app.navigation.open(.settings(.appearance(.root)))
                            }
                        }
                    }
                    SettingsGroup(title: "Quick Controls", subtitle: "Common destinations, grouped without adding new settings state.") {
                        ControlGroup {
                            Button { app.navigation.open(.settings(.appearance(.root))) } label: {
                                Label("Appearance", systemImage: "paintpalette")
                            }
                            Button { app.navigation.open(.settings(.privacy(.root))) } label: {
                                Label("Privacy", systemImage: "lock.shield")
                            }
                            Button { app.navigation.open(.settings(.modules(.root))) } label: {
                                Label("Modules", systemImage: "shippingbox")
                            }
                        }
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                    SettingsGroup(title: "Preferences") {
                        VStack(spacing: 0) {
                            category("Notifications", "Push, activity and quiet hours", "bell", .notifications(.root)); SettingsDivider()
                            category("Privacy & Security", "Security, app lock and blocked accounts", "lock.shield", .privacy(.root)); SettingsDivider()
                            category("Modules", moduleSummary, "shippingbox", .modules(.root)); SettingsDivider()
                            category("Data & Storage", "Downloads, cache, backup and export", "internaldrive", .dataStorage(.root)); SettingsDivider()
                            category("Accessibility", "Text, contrast and motion", "accessibility", .accessibility(.root)); SettingsDivider()
                            category("Features", "Enabled and experimental capabilities", "switch.2", .features(.root)); SettingsDivider()
                            category("Updates", "Version and update preferences", "arrow.triangle.2.circlepath", .updates(.root))
                        }
                    }
                    SettingsGroup(title: "Modula", subtitle: versionSummary) {
                        VStack(spacing: 0) {
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
                } else {
                    SettingsGroup(title: "Results", subtitle: "Matches settings names and descriptions.") {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredSearchItems.enumerated()), id: \.element.id) { index, item in
                                SettingsNavigationRow(title: item.title, subtitle: item.subtitle, symbol: item.symbol) {
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
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search Settings")
        .modulaMinimizedSearchToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Shortcuts") {
                        Button("Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
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
            SettingsSearchItem($0.title, $0.subtitle, $0.symbol, $0.route)
        }
    }

    private var filteredSearchItems: [SettingsSearchItem] { searchItems }


    private func category(_ title: String, _ subtitle: String, _ symbol: String, _ route: SettingsRoute) -> some View {
        SettingsNavigationRow(title: title, subtitle: subtitle, symbol: symbol) { app.navigation.open(.settings(route)) }
    }
}

private struct SettingsSearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let route: SettingsRoute

    init(_ title: String, _ subtitle: String, _ symbol: String, _ route: SettingsRoute) {
        id = RouteSerializer.serialize(.settings(route))
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.route = route
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
                Text("Appearance preferences are stored on this device. Account synchronization is future-capable but is not claimed in N2.")
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
                    VStack(alignment: .leading) {
                        ModulaText(text: "Modula Preview", role: .headline)
                        Text("Native design contract v1").font(.caption).foregroundStyle(.secondary)
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
                            ForEach(AppearanceStore.Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Dark Style", selection: $appearance.darkStyle) {
                            ForEach(AppearanceStore.DarkStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack {
                            Picker("Accent", selection: $appearance.accent) { ForEach(AppearanceStore.Accent.allCases) { Text($0.title).tag($0) } }
                            Picker("Font", selection: $appearance.fontFamily) { ForEach(AppearanceStore.FontFamily.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        }
                        Picker("Density", selection: $appearance.density) {
                            ForEach(AppearanceStore.Density.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                }
                AppearancePreviewView()
                catalog("Buttons & controls") {
                    VStack {
                        ModulaButton(title: "Primary Button", symbol: "sparkles") {}
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
                        Text("The five-item native tab bar is the live shell chrome below this catalog. AI Chat is a detached circle beside the Tools capsule.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                catalog("Pull actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pull down to refresh. While pulled, slide left for Command Center and right for Search.")
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
                            photoPicker: { EmptyView() },
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
