import SwiftUI
import UIKit

// MARK: - Help

struct HelpSettingsHost: View {
    let route: HelpSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Help", subtitle: "Guides, contact, and status — designed surfaces.", symbol: "questionmark.circle")
                SettingsSceneGraphic(style: .badges)
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Guides", subtitle: "How Modula works", symbol: "book") {
                            app.navigation.open(.settings(.help(.guides)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Contact", subtitle: "Reach Modula support", symbol: "envelope") {
                            app.navigation.open(.settings(.help(.contact)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Status", subtitle: "Service health", symbol: "waveform.path.ecg") {
                            app.navigation.open(.settings(.help(.status)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Help articles and contact options are being prepared.")
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
        case .guides:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Guides", subtitle: "Short how-tos.", symbol: "book")
                SettingsSceneGraphic(style: .stack)
                SettingsGroup(title: "Topics") {
                    VStack(spacing: 0) {
                        SettingsPreviewRow(title: "Getting started", subtitle: "Shell, tabs, Edge Picker", symbol: "flag", enabled: false)
                        SettingsDivider()
                        SettingsPreviewRow(title: "Modules", subtitle: "Install and permissions", symbol: "shippingbox", enabled: false)
                        SettingsDivider()
                        SettingsPreviewRow(title: "Privacy", subtitle: "App Lock and biometrics", symbol: "lock.shield", enabled: false)
                    }
                }
                SettingsAPIFootnote(text: "Full articles aren’t available in the app yet.")
            }
            .navigationTitle("Guides")
            .navigationBarTitleDisplayMode(.inline)
        case .contact:
            SettingsDesignedUnavailableCanvas(
                title: "Contact",
                subtitle: "Ways to get help.",
                symbol: "envelope",
                tiles: [
                    ("Email", "Write in", "envelope"),
                    ("In-app", "Message Modula", "bubble.left"),
                    ("Bug", "Attach diagnostics", "ant"),
                    ("Privacy", "Data requests", "hand.raised")
                ],
                previewRows: [
                    ("Open a case", "Starts a thread", "plus.bubble"),
                    ("Attach logs", "Developer diagnostics", "doc")
                ],
                apiNote: "Sending support requests from the app isn’t available yet."
            )
        case .status:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Status", subtitle: "Service health overview.", symbol: "waveform.path.ecg")
                SettingsSceneGraphic(style: .radar)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsStatChip(label: "API", value: "—", symbol: "server.rack")
                    SettingsStatChip(label: "Realtime", value: "—", symbol: "antenna.radiowaves.left.and.right")
                }
                SettingsAPIFootnote(text: "Live service status isn’t available in the app yet.")
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - What's New

struct WhatsNewSettingsHost: View {
    let route: WhatsNewSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "What’s New", subtitle: "Release highlights for this build.", symbol: "sparkles")
                SettingsSceneGraphic(style: .ribbon)
                SettingsGroup(title: "This checkout") {
                    VStack(alignment: .leading, spacing: 12) {
                        bullet("Settings identity hero with progressive collapse")
                        bullet("Intelligence product settings (Models / Knowledge / Privacy / Tools)")
                        bullet("Expanded Preferences IA with designed unavailable canvases")
                    }
                    .padding(.vertical, 8)
                }
                SettingsAPIFootnote(text: "Highlights from this version of Modula.")
            }
            .navigationTitle("What’s New")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(app.appearance.accent.color)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Creator

struct CreatorSettingsHost: View {
    let route: CreatorSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.creator.showInsightsHint") private var insightsHint = true
    @AppStorage("settings.creator.defaultAudience") private var audience = "public"

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Creator", subtitle: "Studio defaults for people who publish.", symbol: "paintbrush.pointed")
                SettingsSceneGraphic(style: .stack)
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Studio defaults", subtitle: "Audience and hints", symbol: "slider.horizontal.2.square") {
                            app.navigation.open(.settings(.creator(.studio)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Insights", subtitle: "Reach overview", symbol: "chart.line.uptrend.xyaxis") {
                            app.navigation.open(.settings(.creator(.insights)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "These are defaults for new posts. Insights appear only when real data is available.")
            }
            .navigationTitle("Creator")
            .navigationBarTitleDisplayMode(.inline)
        case .studio:
            Form {
                Picker("Default audience", selection: $audience) {
                    Text("Public").tag("public")
                    Text("Followers").tag("followers")
                    Text("Close friends").tag("close")
                }
                Toggle("Show insights tip after publish", isOn: $insightsHint)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Studio defaults")
            .navigationBarTitleDisplayMode(.inline)
        case .insights:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Insights", subtitle: "Reach and engagement.", symbol: "chart.line.uptrend.xyaxis")
                SettingsSceneGraphic(style: .meter)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsStatChip(label: "Views", value: "—", symbol: "eye")
                    SettingsStatChip(label: "Follows", value: "—", symbol: "person.badge.plus")
                }
                SettingsAPIFootnote(text: "Insights show a dash until real data is available.")
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Focus

struct FocusSettingsHost: View {
    let route: FocusSettingsRoute
    @AppStorage("settings.focus.hideBadges") private var hideBadges = false
    @AppStorage("settings.focus.dimActivity") private var dimActivity = true
    @AppStorage("settings.focus.allowMentions") private var allowMentions = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Focus", subtitle: "How Modula behaves when iOS Focus is on.", symbol: "moon.stars")
                FocusAdaptationGraphic(dimActivity: dimActivity, hideBadges: hideBadges, allowMentions: allowMentions)
                SettingsToggleCard {
                    Toggle("Hide tab badges during Focus", isOn: $hideBadges)
                        .settingsAnchor("focus.hideBadges")
                    Toggle("Dim Activity list", isOn: $dimActivity)
                        .settingsAnchor("focus.dimActivity")
                    Toggle("Still allow @mentions", isOn: $allowMentions)
                        .settingsAnchor("focus.mentions")
                }
                SettingsAPIFootnote(text: "Saved on this device. Set up Focus modes in iOS Settings.")
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Passkeys

struct PasskeysSettingsHost: View {
    let route: PasskeysSettingsRoute

    var body: some View {
        switch route {
        case .root:
            SettingsDesignedUnavailableCanvas(
                title: "Passkeys",
                subtitle: "Passwordless sign-in with iCloud Keychain.",
                symbol: "person.badge.key",
                tiles: [
                    ("Create", "New passkey", "plus.circle"),
                    ("Devices", "Where it syncs", "laptopcomputer.and.iphone"),
                    ("Security", "Phishing resistant", "lock.shield"),
                    ("Fallback", "Password still works", "key")
                ],
                previewRows: [
                    ("This iPhone", "Platform authenticator", "iphone"),
                    ("Remove passkey", "Stop using a passkey", "trash")
                ],
                apiNote: "Passkeys aren’t available yet."
            )
        }
    }
}

// MARK: - Translate

struct TranslateSettingsHost: View {
    let route: TranslateSettingsRoute
    @AppStorage("settings.translate.autoDetect") private var autoDetect = true
    @AppStorage("settings.translate.showButton") private var showButton = true
    @AppStorage("settings.translate.target") private var target = "system"

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Translate", subtitle: "On-device translation hints for posts.", symbol: "character.book.closed")
                SettingsSceneGraphic(style: .ribbon)
                SettingsToggleCard {
                    Toggle("Auto-detect language", isOn: $autoDetect)
                    Toggle("Show Translate on posts", isOn: $showButton)
                    LabeledContent("Target language") {
                        Picker("Target language", selection: $target) {
                            Text("System").tag("system")
                            Text("English").tag("en")
                            Text("Keep original").tag("original")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                SettingsAPIFootnote(text: "Saved on this device. Translation itself isn’t available yet.")
            }
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - QR / Modula Code

struct QRCodeSettingsHost: View {
    let route: QRCodeSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Modula Code", subtitle: "Your profile QR and scanner.", symbol: "qrcode")
                SettingsSceneGraphic(style: .grid)
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .foregroundStyle(app.appearance.accent.color.opacity(0.45))
                        .frame(width: 180, height: 180)
                    Image(systemName: "qrcode")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(app.appearance.accent.color.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                SettingsGroup(title: "Actions") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Open My Modula Code", subtitle: "Profile share QR", symbol: "person.crop.rectangle") {
                            app.navigation.open(.me(.overview))
                        }
                        SettingsDivider()
                        SettingsPreviewRow(title: "Scan", subtitle: "Camera scanner", symbol: "qrcode.viewfinder", enabled: false)
                    }
                }
                SettingsAPIFootnote(text: "Share your code from your profile. Scanning codes isn’t available yet.")
            }
            .navigationTitle("Modula Code")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Family

struct FamilySettingsHost: View {
    let route: FamilySettingsRoute

    var body: some View {
        switch route {
        case .root:
            SettingsDesignedUnavailableCanvas(
                title: "Family",
                subtitle: "Shared plans and parental controls.",
                symbol: "figure.2.and.child.holdinghands",
                tiles: [
                    ("Members", "People in the group", "person.3"),
                    ("Plan", "Shared subscription", "creditcard"),
                    ("Approvals", "Purchase asks", "checkmark.seal"),
                    ("Screen time", "Limits", "hourglass")
                ],
                previewRows: [
                    ("Invite", "Send a family invite", "paperplane"),
                    ("Leave family", "Remove this account", "rectangle.portrait.and.arrow.right")
                ],
                apiNote: "Family controls aren’t available yet."
            )
        }
    }
}

// MARK: - Time & Units

struct TimeUnitsSettingsHost: View {
    let route: TimeUnitsSettingsRoute
    @AppStorage("settings.time.use24h") private var use24h = false
    @AppStorage("settings.time.relative") private var relative = true
    @AppStorage("settings.units.distance") private var distance = "metric"
    @AppStorage("settings.units.temperature") private var temperature = "c"

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Time & Units", subtitle: "Clocks and measurement on this device.", symbol: "clock")
                SettingsSceneGraphic(style: .orbit)
                SettingsToggleCard {
                    Toggle("24-hour time", isOn: $use24h)
                    Toggle("Relative timestamps", isOn: $relative)
                    LabeledContent("Distance") {
                        Picker("Distance", selection: $distance) {
                            Text("Metric").tag("metric")
                            Text("Imperial").tag("imperial")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    LabeledContent("Temperature") {
                        Picker("Temperature", selection: $temperature) {
                            Text("Celsius").tag("c")
                            Text("Fahrenheit").tag("f")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                SettingsAPIFootnote(text: "Saved on this device. Doesn’t change your iOS region settings.")
            }
            .navigationTitle("Time & Units")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Keyboard

struct KeyboardSettingsHost: View {
    let route: KeyboardSettingsRoute
    @AppStorage("settings.keyboard.swipe") private var swipe = true
    @AppStorage("settings.keyboard.periodShortcut") private var periodShortcut = true
    @AppStorage("settings.keyboard.capsLock") private var capsLock = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Keyboard", subtitle: "Typing shortcuts inside Modula.", symbol: "keyboard")
                SettingsSceneGraphic(style: .pulse)
                SettingsToggleCard {
                    Toggle("Swipe between composer tools", isOn: $swipe)
                    Toggle("Double-space for period", isOn: $periodShortcut)
                    Toggle("Caps Lock mapping", isOn: $capsLock)
                }
                SettingsAPIFootnote(text: "Saved on this device. Keyboards are managed in iOS Settings.")
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
