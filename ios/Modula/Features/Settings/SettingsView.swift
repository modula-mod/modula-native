import SwiftUI

struct SettingsSection<Content: View>: View { var title: String; @ViewBuilder var content: Content; var body: some View { Section(title) { content } } }
struct SettingsRow<Content: View>: View { @ViewBuilder var content: Content; var body: some View { content.frame(minHeight: 44) } }
struct SettingsNavigationRow: View { var title: String; var subtitle: String?; var symbol: String; var action: () -> Void; var body: some View { SettingsRow { ModulaListRow(title: title, subtitle: subtitle, symbol: symbol, action: action) } } }
struct SettingsToggleRow: View { var title: String; var symbol: String; @Binding var value: Bool; var body: some View { SettingsRow { Toggle(isOn: $value) { Label(title, systemImage: symbol) } } } }
struct SettingsPickerRow<Selection: Hashable, Options: RandomAccessCollection, Label: View>: View where Options.Element == Selection {
    var title: String; @Binding var selection: Selection; var options: Options; @ViewBuilder var label: (Selection) -> Label
    var body: some View { SettingsRow { Picker(title, selection: $selection) { ForEach(Array(options), id: \.self) { label($0).tag($0) } } } }
}
struct SettingsValueRow: View { var title: String; var value: String; var symbol: String; var body: some View { LabeledContent { Text(value).foregroundStyle(.secondary) } label: { Label(title, systemImage: symbol) } } }
struct SettingsDestructiveRow: View { var title: String; var action: () -> Void; var body: some View { Button(title, role: .destructive, action: action).frame(minHeight: 44) } }
struct SettingsPreviewCard: View { var body: some View { AppearancePreviewView(compact: true) } }

struct SettingsRouteView: View {
    let route: SettingsRoute
    var body: some View {
        switch route {
        case .root: SettingsView()
        case .appearance(.appIcon): AppIconPickerView()
        case .appearance(.preview): AppearancePreviewScreen()
        case .appearance(let focus): AppearanceSettingsView(focus: focus)
        case .developer(.components):
            #if DEBUG
            ComponentCatalogView()
            #else
            DevelopmentRouteView(title: "Components", symbol: "square.grid.3x3")
            #endif
        case .developer(.runtime), .developer(.diagnostics):
            #if DEBUG
            RuntimeDiagnosticsView()
            #else
            DevelopmentRouteView(title: "Diagnostics", symbol: "stethoscope")
            #endif
        default: DevelopmentRouteView(title: title, symbol: "gearshape")
        }
    }
    private var title: String { RouteSerializer.serialize(.settings(route)).split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "-", with: " ").capitalized ?? "Settings" }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        List {
            SettingsSection(title: "You") {
                SettingsNavigationRow(title: "Account", subtitle: app.auth.account?.primaryHandle ?? "Sign in and personal information", symbol: "person.crop.circle") { app.navigation.open(app.auth.account == nil ? .auth(.login) : .settings(.account(.root))) }
                SettingsNavigationRow(title: "Appearance", subtitle: "Theme, type, motion and module branding", symbol: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
            }
            SettingsSection(title: "Preferences") {
                category("Notifications", "bell", .notifications(.root)); category("Privacy & Security", "lock.shield", .privacy(.root)); category("Modules", "shippingbox", .modules(.root)); category("Data & Storage", "internaldrive", .dataStorage(.root)); category("Accessibility", "accessibility", .accessibility(.root)); category("Features", "switch.2", .features(.root)); category("Updates", "arrow.triangle.2.circlepath", .updates(.root))
            }
            SettingsSection(title: "Modula") {
                category("About", "info.circle", .about(.root))
                #if DEBUG
                category("Developer", "hammer", .developer(.root))
                SettingsNavigationRow(title: "Component Catalog", subtitle: "Interactive native design reference", symbol: "square.grid.3x3") { app.navigation.open(.developer(.components)) }
                SettingsNavigationRow(title: "Runtime diagnostics", subtitle: "N1 runtime and memory evidence", symbol: "stethoscope") { app.navigation.open(.settings(.developer(.runtime))) }
                    .accessibilityIdentifier("settings.runtime")
                #endif
            }
        }.modulaCanvas().navigationTitle("Settings").accessibilityIdentifier("settings.root")
    }
    private func category(_ title: String, _ symbol: String, _ route: SettingsRoute) -> some View { SettingsNavigationRow(title: title, symbol: symbol) { app.navigation.open(.settings(route)) } }
}

struct AppearanceSettingsView: View {
    let focus: AppearanceSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var confirmsReset = false
    var body: some View {
        @Bindable var store = app.appearance
        List {
            SettingsSection(title: "Live preview") { SettingsPreviewCard() }
            SettingsSection(title: "Colour") {
                SettingsPickerRow(title: "Theme", selection: $store.theme, options: AppearanceStore.Theme.allCases) { Text($0.rawValue.capitalized) }
                SettingsPickerRow(title: "Dark Style", selection: $store.darkStyle, options: AppearanceStore.DarkStyle.allCases) { Text($0.rawValue.capitalized) }.disabled(scheme != .dark && store.theme != .dark)
                VStack(alignment: .leading, spacing: 10) { Text("Accent"); HStack { ForEach(AppearanceStore.Accent.allCases) { accent in Button { store.accent = accent; HapticEngine.shared.play(.selection) } label: { Circle().fill(accent.color).frame(width: 34, height: 34).overlay(Circle().stroke(.primary, lineWidth: store.accent == accent ? 3 : 0).padding(-3)) }.accessibilityLabel(accent.title).accessibilityAddTraits(store.accent == accent ? .isSelected : []) } } }.padding(.vertical, 6)
                SettingsPickerRow(title: "Contrast & Transparency", selection: $store.contrastTransparency, options: AppearanceStore.ContrastTransparency.allCases) { Text(display($0.rawValue)) }
            }
            SettingsSection(title: "Typography") {
                SettingsPickerRow(title: "Font Family", selection: $store.fontFamily, options: AppearanceStore.FontFamily.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Text Size", selection: $store.textSize, options: AppearanceStore.TextSize.allCases) { Text(display($0.rawValue)) }
            }
            SettingsSection(title: "Interface") {
                SettingsNavigationRow(title: "App Icon", subtitle: "Default · device-local", symbol: "app.dashed") { app.navigation.open(.settings(.appearance(.appIcon))) }
                SettingsPickerRow(title: "Density", selection: $store.density, options: AppearanceStore.Density.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Motion", selection: $store.motion, options: AppearanceStore.MotionPersonality.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Haptics", selection: $store.haptics, options: AppearanceStore.HapticIntensity.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Icon Style", selection: $store.iconStyle, options: AppearanceStore.IconStyle.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Interface Shape", selection: $store.interfaceShape, options: AppearanceStore.InterfaceShape.allCases) { Text(display($0.rawValue)) }
                SettingsPickerRow(title: "Module Branding", selection: $store.moduleBranding, options: AppearanceStore.ModuleBranding.allCases) { Text(display($0.rawValue)) }
            }
            SettingsSection(title: "Preview") { SettingsNavigationRow(title: "Full Appearance Preview", symbol: "rectangle.inset.filled") { app.navigation.open(.settings(.appearance(.preview))) } }
            SettingsSection(title: "Defaults") { SettingsDestructiveRow(title: "Reset Appearance") { confirmsReset = true } }
            Section { Text("Appearance preferences are stored on this device. Account synchronization is future-capable but is not claimed in N2.").font(.footnote).foregroundStyle(.secondary) }
        }
        .modulaCanvas().navigationTitle(focus == .root ? "Appearance" : display(focus.rawValue))
        .confirmationDialog("Reset Appearance?", isPresented: $confirmsReset, titleVisibility: .visible) { Button("Reset Appearance", role: .destructive) { store.reset() } } message: { Text("This restores Modula appearance defaults without changing other settings.") }
        .accessibilityIdentifier("settings.appearance")
    }
    private func display(_ value: String) -> String { value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "-", with: " ").capitalized }
}

struct AppearancePreviewView: View {
    var compact = false
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: 12 * app.appearance.density.spacingScale) {
                HStack { ModulaAvatar(initials: "M"); VStack(alignment: .leading) { ModulaText(text: "Modula Preview", role: .headline); Text("Native design contract v1").font(.caption).foregroundStyle(.secondary) }; Spacer(); ModulaBadge(title: "Live", symbol: "sparkles") }
                ModulaText(text: "Your digital world, your way.", role: compact ? .headline : .title)
                HStack { ModulaMetric(value: "3", label: "Modes"); Spacer(); ModulaMetric(value: "1", label: "Runtime"); Spacer(); ModulaMetric(value: "Swift", label: "Shell") }
                if !compact { ModulaButton(title: "Primary Action", symbol: "arrow.right") {} }
                HStack { Image(systemName: "person.2"); Text("Following"); Spacer(); Image(systemName: "shippingbox"); Text("Modules") }.font(.caption).foregroundStyle(app.appearance.accent.color)
            }
        }
    }
}

struct AppearancePreviewScreen: View {
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 22) { AppearancePreviewView(); ModulaSection(title: "Navigation") { ModulaTabBar() }; ModulaSection(title: "Rail") { HStack { Spacer(); ModulaContextRail(route: .home(.following)) } }; ModulaSection(title: "Module sample") { ModulaCard { VStack(alignment: .leading, spacing: 10) { ModulaBadge(title: "Module environment v1", symbol: "shippingbox"); ModulaText(text: "Vault Notes", role: .title); Text("Accent, type, density, motion and branding update through the additive host environment.").foregroundStyle(.secondary) } } } }.padding(18) }.navigationTitle("Appearance Preview") }
}

struct AppIconPickerView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)], spacing: 18) {
                Button { app.appearance.appIcon = .default; HapticEngine.shared.play(.selection) } label: {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous).fill(LinearGradient(colors: [app.appearance.accent.color, .cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 96, height: 96).overlay(Image(systemName: "m.square.fill").font(.system(size: 44)).foregroundStyle(.white))
                        Label("Default", systemImage: "checkmark.circle.fill").font(.headline)
                    }.frame(maxWidth: .infinity).padding().background(.background, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(.isSelected)
            }.padding(18)
            Text("Only the approved production icon is available. Alternate icons will appear here after their device assets pass visual review.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 18)
        }.navigationTitle("App Icon")
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
                        Picker("Theme", selection: $appearance.theme) { ForEach(AppearanceStore.Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                        Picker("Dark Style", selection: $appearance.darkStyle) { ForEach(AppearanceStore.DarkStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                        HStack {
                            Picker("Accent", selection: $appearance.accent) { ForEach(AppearanceStore.Accent.allCases) { Text($0.title).tag($0) } }
                            Picker("Font", selection: $appearance.fontFamily) { ForEach(AppearanceStore.FontFamily.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        }
                        Picker("Density", selection: $appearance.density) { ForEach(AppearanceStore.Density.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                    }
                }
                AppearancePreviewView()
                catalog("Buttons & controls") { VStack { ModulaButton(title: "Primary Button", symbol: "sparkles") {}; HStack { ModulaIconButton(title: "Search", symbol: "magnifyingglass") {}; ModulaChip(title: "Selected", selected: true) {}; ModulaChip(title: "Available") {} } } }
                catalog("Typography") { VStack(alignment: .leading) { ModulaText(text: "Hero typography", role: .hero); ModulaText(text: "Section title", role: .title); ModulaText(text: "Body copy follows Dynamic Type.", role: .body); ModulaText(text: "Supporting caption", role: .caption) } }
                catalog("Identity & status") { HStack { ModulaAvatar(initials: "M", size: 56); ModulaBadge(title: "Verified", symbol: "checkmark.seal"); ModulaBadge(title: "Installed", symbol: "arrow.down.circle") } }
                catalog("Forms & rows") { VStack { ModulaSearchField(text: $query); ModulaListRow(title: "Appearance", subtitle: "Live settings", symbol: "paintpalette") {}; ModulaListRow(title: "Static information", subtitle: "No fake action", symbol: "info.circle") } }
                catalog("Metrics") { ModulaMetadataRail(values: [("24", "Modules"), ("1", "Runtime"), ("Swift", "Shell")]) }
                catalog("States") { VStack { ModulaLoadingState(title: "Loading state"); ModulaEmptyState(title: "Empty state", message: "Nothing here yet.", symbol: "tray"); ModulaErrorState(message: "A recoverable error state.") {} } }
                if let product = app.catalogue.product("digital.modula.vault-notes") { catalog("Product Hub") { VStack { ProductHero(product: product) {}; ProductCard(product: product, installed: true) {} } } }
                catalog("Global navigation") { ModulaTabBar() }
                catalog("Context rail") { HStack { Spacer(); ModulaContextRail(route: .home(.following)) } }
            }.padding(18)
        }.navigationTitle("Components").accessibilityIdentifier("developer.components")
    }
    private func catalog<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { ModulaSection(title: title) { content() } }
}
