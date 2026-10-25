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
                SettingsHeroBanner(title: "Help", subtitle: "Guides, support requests, and live service status.", symbol: "questionmark.circle")
                SettingsSceneGraphic(style: .badges)
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Guides", subtitle: "How the main settings work", symbol: "book") {
                            app.navigation.open(.settings(.help(.guides)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Contact", subtitle: "Open a case or email support", symbol: "envelope") {
                            app.navigation.open(.settings(.help(.contact)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Status", subtitle: "Live service health", symbol: "waveform.path.ecg") {
                            app.navigation.open(.settings(.help(.status)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Support requests and status come straight from Modula’s servers.")
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
        case .guides:
            HelpGuidesView()
        case .contact:
            HelpContactView()
        case .status:
            HelpStatusView()
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
                SettingsGroup(title: "In this version") {
                    VStack(alignment: .leading, spacing: 12) {
                        bullet("Live service status in Help, measured from Modula’s servers")
                        bullet("Open support requests from the app, with optional diagnostics you can review")
                        bullet("Export a copy of your account data from Data & Storage")
                        bullet("Smoother Settings motion that follows Reduce Motion")
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
                Section {
                    Picker("Default audience", selection: $audience) {
                        Text("Everyone").tag("public")
                        Text("Followers").tag("followers")
                        Text("Only me").tag("private")
                    }
                    Toggle("Show insights tip after publish", isOn: $insightsHint)
                } footer: {
                    Text("New posts start with this audience. You can still change it in the composer.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Studio defaults")
            .navigationBarTitleDisplayMode(.inline)
        case .insights:
            CreatorInsightsView()
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
                SettingsAPIFootnote(text: "To use these, add the Modula filter to a Focus: iOS Settings → Focus → choose a Focus → Add Filter → Modula. While that Focus is on, the Activity badge and list follow these choices.")
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
            PasskeysSettingsView()
        }
    }
}

// MARK: - Translate

struct TranslateSettingsHost: View {
    static let targets = ["en", "fr", "de", "es", "it", "pt", "nl", "pl", "tr", "ru", "uk", "ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant", "id", "th", "vi"]
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
                            ForEach(TranslateSettingsHost.targets, id: \.self) { code in
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                            }
                            Text("Keep original").tag("original")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                SettingsAPIFootnote(text: "Posts are translated on your iPhone with Apple Translation — the text isn’t sent anywhere. iOS may ask to download a language the first time. “Keep original” hides Translate.")
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
    @State private var presentedMode: ModulaCodeMode?

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Modula Code", subtitle: "Your profile QR and scanner.", symbol: "qrcode")
                preview
                SettingsGroup(title: "Actions") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Show My Modula Code", subtitle: "Share, save or copy your profile code", symbol: "qrcode") {
                            presentedMode = .myCode
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Scan a Code", subtitle: "Camera, torch or a photo", symbol: "qrcode.viewfinder") {
                            presentedMode = .scan
                        }
                    }
                }
                SettingsAPIFootnote(text: "Your code only contains your public profile link.")
            }
            .navigationTitle("Modula Code")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $presentedMode) { mode in
                SettingsQRModal(initialMode: mode) { presentedMode = nil }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let accent = app.appearance.accent.color
        Button {
            HapticEngine.shared.play(.selection)
            presentedMode = app.profile.ownProfile == nil ? .scan : .myCode
        } label: {
            Group {
                if let profile = app.profile.ownProfile, let matrix = ModulaQRMatrix.make(profile.shareURL.absoluteString) {
                    ModulaBrandedQRCode(matrix: matrix, accent: accent) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                            .overlay(Image("ModulaAppIcon").resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(3))
                    }
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(accent.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                            .foregroundStyle(accent.opacity(0.45)))
                }
            }
            .frame(width: 180, height: 180)
            .shadow(color: accent.opacity(0.18), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Open my Modula Code")
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
                SettingsAPIFootnote(text: "Applies to timestamps across Modula (feed, comments, chats, Activity, drafts) and is shared with modules for distances and temperatures. Doesn’t change your iOS region settings.")
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
                    Toggle("Autocorrect in composers", isOn: $periodShortcut)
                    Toggle("Auto-capitalise sentences", isOn: $capsLock)
                }
                SettingsAPIFootnote(text: "Applies to the post composer and chat composer. Double-space period, Caps Lock and keyboard layouts are iOS keyboard settings (Settings → General → Keyboard), which apps can’t change.")
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
