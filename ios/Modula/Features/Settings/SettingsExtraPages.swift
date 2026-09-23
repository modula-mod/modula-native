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
                SettingsAPIFootnote(text: "Help content is UI-first. No invented ticket IDs or uptime percentages.")
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
                SettingsAPIFootnote(text: "Article bodies are not fetched — catalogue/CMS help is unverified this run.")
            }
            .navigationTitle("Guides")
            .navigationBarTitleDisplayMode(.inline)
        case .contact:
            SettingsDesignedUnavailableCanvas(
                title: "Contact",
                subtitle: "Support channels when verified.",
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
                apiNote: "No verified support-ticket endpoint is wired. UI stays non-submitting."
            )
        case .status:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Status", subtitle: "Service health overview.", symbol: "waveform.path.ecg")
                SettingsSceneGraphic(style: .radar)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsStatChip(label: "API", value: "—", symbol: "server.rack")
                    SettingsStatChip(label: "Realtime", value: "—", symbol: "antenna.radiowaves.left.and.right")
                }
                SettingsAPIFootnote(text: "Status chips stay blank — no fabricated uptime or incident copy.")
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - What's New

struct WhatsNewSettingsHost: View {
    let route: WhatsNewSettingsRoute

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
                SettingsAPIFootnote(text: "Highlights are local release notes for this native checkout — not App Store What’s New scraped from the store.")
            }
            .navigationTitle("What’s New")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
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
                SettingsAPIFootnote(text: "Creator Studio product routes exist elsewhere; these are settings defaults only. Insights stay honest when APIs are missing.")
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
                SettingsAPIFootnote(text: "No fabricated analytics. Values stay em dashes until a verified insights contract exists.")
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
                SettingsSceneGraphic(style: .radar)
                Form {
                    Toggle("Hide tab badges during Focus", isOn: $hideBadges)
                    Toggle("Dim Activity list", isOn: $dimActivity)
                    Toggle("Still allow @mentions", isOn: $allowMentions)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Local Focus adaptations. iOS Focus configuration stays in system Settings — this does not duplicate Quiet Hours delivery.")
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
                    ("Remove passkey", "Revoke on Greenfield", "trash")
                ],
                apiNote: "Passkey registration/assertion endpoints are not verified in this native client. UI is design-only."
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
                Form {
                    Toggle("Auto-detect language", isOn: $autoDetect)
                    Toggle("Show Translate on posts", isOn: $showButton)
                    Picker("Target language", selection: $target) {
                        Text("System").tag("system")
                        Text("English").tag("en")
                        Text("Keep original").tag("original")
                    }
                }
                .scrollDisabled(true)
                .frame(minHeight: 180)
                SettingsAPIFootnote(text: "Prefs are local. Does not invent a translation API or claim Apple Translate integration until wired.")
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
                SettingsAPIFootnote(text: "Profile QR already lives on Profile share. Dedicated scanner route is not verified — Scan stays inactive.")
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
                apiNote: "No verified Family Sharing / parental contract in native. Distinct from Monetisation plans."
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
                Form {
                    Toggle("24-hour time", isOn: $use24h)
                    Toggle("Relative timestamps", isOn: $relative)
                    Picker("Distance", selection: $distance) {
                        Text("Metric").tag("metric")
                        Text("Imperial").tag("imperial")
                    }
                    Picker("Temperature", selection: $temperature) {
                        Text("Celsius").tag("c")
                        Text("Fahrenheit").tag("f")
                    }
                }
                .scrollDisabled(true)
                .frame(minHeight: 240)
                SettingsAPIFootnote(text: "Device-local formatting prefs. Does not change Appearance typography or system Region.")
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
                Form {
                    Toggle("Swipe between composer tools", isOn: $swipe)
                    Toggle("Double-space for period", isOn: $periodShortcut)
                    Toggle("Caps Lock mapping", isOn: $capsLock)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Local composer behaviour. System keyboards remain in iOS Settings.")
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
