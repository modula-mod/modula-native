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
                SettingsGroup(title: "Get help", subtitle: "Start with a guide; if it doesn’t answer your question, open a case and a person replies by email. Check Status first if something looks broken for everyone.") {
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
                SettingsGroup(title: "About this app", subtitle: "Legal documents, version details and what changed in this build.") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "About & Legal", subtitle: "Version, privacy policy, terms", symbol: "info.circle") {
                            app.navigation.open(.settings(.about(.root)))
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
            Image(systemName: "checkmark.circle.fill").foregroundStyle(app.appearance.liveAccent)
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
                SproutIllustrationView(illustration: .painter, height: 148)
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
        let accent = app.appearance.liveAccent
        Button {
            HapticEngine.shared.play(.selection)
            presentedMode = app.profile.ownProfile == nil ? .scan : .myCode
        } label: {
            Group {
                if let profile = app.profile.ownProfile, let matrix = ModulaQRMatrix.make(profile.shareURL.absoluteString) {
                    ModulaBrandedQRCode(matrix: matrix, accent: accent) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                            .overlay(ModulaUnitTile(variant: .teal, cornerFraction: 0.2).padding(3))
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

// MARK: - Migration (Settings Atlas v5.0 extension M-01, stage MX-00 "Explain")

/// Host-owned Settings destination. Explanation only: no discovery, transfer, import, export or
/// recovery actions exist yet, and nothing here shows node names, counts or readiness that
/// weren't genuinely verified. Copy follows MIGRATION-DESIGN-HANDOFF.md (MX-00).
struct MigrationSettingsHost: View {
    let route: MigrationSettingsRoute

    var body: some View {
        switch route {
        case .root: MigrationOverviewPage()
        case .node: MigrationNodePage()
        case .data: MigrationDataPage()
        case .identity: MigrationIdentityPage()
        case .help: MigrationHelpPage()
        }
    }
}

private struct MigrationOverviewPage: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsWhat = false
    @State private var showsWhyNot = false

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Migration Overview", subtitle: "Your account, with a choice of home.", symbol: "arrow.triangle.swap")
            SettingsGroup(title: "Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Not yet available", systemImage: "clock.badge.questionmark")
                        .font(.headline)
                        .foregroundStyle(app.appearance.liveAccent)
                    Text("This section explains how migration is intended to work. You can’t start a move here.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Migration is designed to let you move your account to another GreenField node — the service operated to host your account. You would review the destination, supported data and any limits before deciding.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        app.navigation.open(.settings(.migration(.help)))
                    } label: {
                        Text("Learn about migration").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: .selection))
                    .modulaAccentCTA()
                    .padding(.top, 4)
                    .accessibilityIdentifier("settings.migration.learn")
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
            }
            SettingsGroup(title: "About migration") {
                VStack(spacing: 0) {
                    SettingsNavigationRow(title: "What is Migration?", subtitle: "Changing your account’s home node", symbol: "info.circle") { showsWhat = true }
                    SettingsNavigationRow(title: "Why isn’t migration available?", subtitle: "Stage MX-00 — Explain", symbol: "questionmark.circle") { showsWhyNot = true }
                    SettingsNavigationRow(title: "My GreenField Node", subtitle: "What this app connects to", symbol: "server.rack") {
                        app.navigation.open(.settings(.migration(.node)))
                    }
                    SettingsNavigationRow(title: "Data Portability", subtitle: "What a transfer would and wouldn’t include", symbol: "tray.and.arrow.up") {
                        app.navigation.open(.settings(.migration(.data)))
                    }
                    SettingsNavigationRow(title: "Identity & Recovery", subtitle: "Portable identity explained", symbol: "person.badge.shield.checkmark") {
                        app.navigation.open(.settings(.migration(.identity)))
                    }
                    SettingsNavigationRow(title: "Migration Help", subtitle: "Nodes, federation and moving", symbol: "book") {
                        app.navigation.open(.settings(.migration(.help)))
                    }
                }
            }
            SettingsGroup(title: "Learn more") {
                VStack(alignment: .leading, spacing: 0) {
                    MigrationDisclosure(title: "What could move?", text: "Your plan would list supported identity and profile data, eligible social records and module data individually. Private messages and notes are excluded by default. Wallet keys and seed phrases are never included. Connected services would need to be authorised again.")
                    Divider()
                    MigrationDisclosure(title: "What stays the same?", text: "A portable identity is intended to remain stable where the protocol guarantees it. Your local account ID may change, and your handle may need a new name or node qualification. Your iPhone is not your home node.")
                }
            }
            SettingsGroup(title: "Move My Account") {
                VStack(alignment: .leading, spacing: 8) {
                    Button {} label: {
                        Label("Move My Account", systemImage: "arrow.right.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .accessibilityLabel("Move My Account, unavailable")
                    .accessibilityHint("Not available yet. It needs portable identity and a secure node handoff.")
                    .accessibilityIdentifier("settings.migration.move")
                    Text("Not available yet: needs portable identity and secure node handoff.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
            SettingsAPIFootnote(text: "Guidance only. Nothing on these screens contacts another node or changes your account.")
        }
        .navigationTitle("Migration")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWhat) {
            MigrationInfoSheet(
                title: "What is Migration?",
                paragraphs: ["Migration would change your account’s authoritative home node: the operator responsible for its account records. Only supported records included in your plan would move. Moving your account is different from setting up a new phone, importing a file or transferring a wallet."]
            ) { app.navigation.open(.settings(.migration(.help))) }
        }
        .sheet(isPresented: $showsWhyNot) {
            MigrationInfoSheet(
                title: "Migration isn’t available yet",
                paragraphs: [
                    "Stage: MX-00 — Explain.",
                    "Account moves require verified portable identity, signed node discovery, destination acceptance and a secure handoff with recovery. These requirements must be confirmed for your account and destination before a transfer can be offered.",
                    "If capability checks are unavailable, that is not evidence that your account is ready to move."
                ]
            ) { app.navigation.open(.settings(.migration(.help))) }
        }
    }
}

private struct MigrationNodePage: View {
    private var configuredHost: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String)
            .flatMap(URL.init(string:))?
            .host()
    }

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "My GreenField Node", subtitle: "The node responsible for your account’s home-node records.", symbol: "server.rack")
            SettingsGroup(title: "This app connects to", subtitle: "Set in this build of the app. It is the server address in use, not a signed node identity.") {
                MigrationFactRow(label: "Server", value: configuredHost ?? "Not available")
            }
            SettingsGroup(title: "Signed node information", subtitle: "Shown only once signed node discovery exists. Nothing here is guessed.") {
                VStack(spacing: 0) {
                    MigrationFactRow(label: "Node identity", value: "Not available yet")
                    MigrationFactRow(label: "Operator", value: "Not available yet")
                    MigrationFactRow(label: "Signing key fingerprint", value: "Not available yet")
                    MigrationFactRow(label: "Protocol & federation", value: "Not available yet")
                    MigrationFactRow(label: "Jurisdiction & policies", value: "Not available yet")
                }
            }
            SettingsAPIFootnote(text: "Signature verified would confirm who signed node information. It does not rate the operator or guarantee service quality.")
        }
        .navigationTitle("My GreenField Node")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MigrationDataPage: View {
    private let rows: [(String, String)] = [
        ("Home-node authority", "Moves only inside a supported, approved migration."),
        ("Public profile & media", "Supported profile details, listed field by field."),
        ("Public posts & replies", "Optional, when supported. Public copies elsewhere can persist."),
        ("Follows & social graph", "Optional, when supported; some connections may not map."),
        ("Blocks, mutes, drafts & preferences", "Reviewed per item before consent."),
        ("Private messages", "Not included. Needs separate secure support."),
        ("Private notes & Vault Notes", "Not included unless the module supports encrypted portability and you choose it."),
        ("Moliboo identity & wardrobe", "Only module-supported items; keeps its native 2D look."),
        ("Installed modules", "Reinstalled from verified releases, with a fresh permission review."),
        ("Agent memories & automations", "Not included by default; agents stay paused."),
        ("Connected services & sessions", "Never copied. You reconnect after a move."),
        ("Wallet keys & seed phrases", "Never part of account migration."),
        ("Device-only settings", "Stay on this device."),
    ]

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Data Portability", subtitle: "Exporting records does not change your account’s home node.", symbol: "tray.and.arrow.up")
            SettingsGroup(title: "Export isn’t migration") {
                Text("A migration plan must separately verify identity, destination acceptance and supported data. Portability support hasn’t been verified for your account’s data.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
            SettingsGroup(title: "How each kind of data would be handled", subtitle: "Intended handling, not a check of your account.") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.0).font(.subheadline.weight(.semibold))
                            Text(row.1).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                }
            }
            SettingsAPIFootnote(text: "Consent would be per item and never pre-ticked.")
        }
        .navigationTitle("Data Portability")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MigrationIdentityPage: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Identity & Recovery", subtitle: "Your portable principal identifies you across supported nodes.", symbol: "person.badge.shield.checkmark")
            SettingsGroup(title: "How identity would work") {
                Text("A node’s local account ID can differ from your portable principal. Your handle may need to change. Private signing keys are never stored in profile data or shown here.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
            SettingsGroup(title: "Your account") {
                VStack(spacing: 0) {
                    MigrationFactRow(label: "Portable identity", value: "Not available yet")
                    MigrationFactRow(label: "Recovery readiness", value: "Hasn’t been verified")
                }
            }
            SettingsGroup(title: "Security") {
                SettingsNavigationRow(title: "Open Security Center", subtitle: "Passkeys, sessions and sign-in protection", symbol: "lock.shield") {
                    app.navigation.open(.settings(.privacy(.security)))
                }
            }
        }
        .navigationTitle("Identity & Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MigrationHelpPage: View {
    private let faqs: [(String, String)] = [
        ("What is a GreenField node?", "A GreenField node is a service instance run by an operator with its own controlled data store. Under supported federation rules, nodes can discover peers, verify identities and signed events, and exchange authorised records. Your home node is the node responsible for your account’s authoritative records. It is not your iPhone."),
        ("Is federation the same as full decentralisation?", "No. Independent operators can connect under shared rules without every part of the system being fully decentralised. Each operator can have different policies, capabilities and responsibilities. A verified signature identifies the signer of node information; it is not a recommendation or a guarantee of service quality."),
        ("What would change when I move?", "Your account’s home-node operator would change. The move would include only the supported records shown in your reviewed plan. Your portable identity is intended to stay stable where the protocol guarantees it, but your local account ID can change. Your handle, modules, licences and social connections may have limits that must be reviewed first."),
        ("Would my private messages and notes move?", "Private messages and private notes are excluded by default. They need their own independently supported secure portability design. Module data, including Vault Notes, can move only under that module’s supported encrypted contract and your explicit choice. Your plan must show exclusions before you approve."),
        ("What happens to connected services and agents?", "Connected-service tokens and sessions are not copied to a new operator. Supported services need to be authorised again. Agents and automations must stay paused until you review and authorise their permissions for the destination."),
        ("Does a move erase old public content?", "Not necessarily. Your former operator may retain records under its policy, and other operators may already hold permitted public copies. A migration receipt records transfer operations; it does not prove that every peer erased historical content. Review each operator’s retention and deletion policy."),
        ("Is this for a new phone or a wallet?", "No. Setting up another phone belongs in Devices, Storage & Sync. Running your own node is a separate operator workflow. DIMON settlement and financial recovery are separate from account migration. Ordinary settings, chats and notes do not depend on settlement finality. Wallet keys and seed phrases are never included in this migration."),
        ("Why can’t I start a move here?", "In MX-00 — Explain, this section is guidance only. Account moves require verified identity portability, signed node discovery, destination acceptance and a secure handoff with recovery. A move must not be offered until the requirements are confirmed for your account and destination."),
        ("What if a future transfer is interrupted?", "Review the last verified job status before trying again. Before the authority handoff, cancellation may be available if the service confirms that it is reversible. After the handoff is committed, use recovery or a separately approved reverse migration. Leaving the screen is not the same as cancelling the transfer."),
    ]
    private let glossary: [(String, String)] = [
        ("Operator", "The organisation or person running a node and setting its policies."),
        ("Home node", "The one authoritative node for your account at a given handoff checkpoint."),
        ("Portable principal ID", "The identity intended to remain stable across supported node moves."),
        ("Local account ID", "A node-specific identifier that can differ at the destination."),
        ("Signed discovery", "Node information whose signature and validity are checked under the protocol."),
        ("Cutover / authority handoff", "The committed change of the account’s authoritative home node."),
        ("Receipt", "Tamper-evident evidence of recorded migration operations, not a universal deletion certificate."),
        ("Recovery", "A verified action to resume or repair from a durable checkpoint, not an automatic undo."),
    ]

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Migration Help", subtitle: "Nodes, federation and what moving would mean.", symbol: "book")
            SettingsGroup(title: "Questions") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(faqs, id: \.0) { faq in
                        MigrationDisclosure(title: faq.0, text: faq.1)
                        Divider()
                    }
                }
            }
            SettingsGroup(title: "Glossary") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(glossary, id: \.0) { term in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.0).font(.subheadline.weight(.semibold))
                            Text(term.1).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Migration Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MigrationDisclosure: View {
    let title: String
    let text: String
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { value in withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded = value } }
        )) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(minHeight: 44, alignment: .leading)
        }
    }
}

private struct MigrationFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline)
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct MigrationInfoSheet: View {
    let title: String
    let paragraphs: [String]
    var onReadHelp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        dismiss()
                        onReadHelp()
                    } label: {
                        Text("Read migration help").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: .selection))
                    .modulaAccentCTA()
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
