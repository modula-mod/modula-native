import SwiftUI

// MARK: - Personalisation (unique — not Appearance shortcuts)

struct PersonalisationSettingsHost: View {
    let route: PersonalisationSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.personalisation.suggestedPeople") private var suggestedPeople = true
    @AppStorage("settings.personalisation.moduleSuggestions") private var moduleSuggestions = true
    @AppStorage("settings.personalisation.storyAutoAdvance") private var storyAutoAdvance = true
    @AppStorage("settings.personalisation.captionSize") private var captionSize = "standard"

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Personalisation",
                    subtitle: "How Modula ranks and presents content for you — separate from theme, type, and Edge Picker.",
                    symbol: "slider.horizontal.3"
                )
                SettingsSceneGraphic(style: .constellation)
                SettingsGroup(title: "Destinations") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(
                            title: "Recommendations",
                            subtitle: "Suggested people and modules",
                            symbol: "sparkles"
                        ) { app.navigation.open(.settings(.personalisation(.recommendations))) }
                        SettingsDivider()
                        SettingsNavigationRow(
                            title: "Stories",
                            subtitle: "Auto-advance and viewing prefs",
                            symbol: "circle.dashed"
                        ) { app.navigation.open(.settings(.personalisation(.stories))) }
                        SettingsDivider()
                        SettingsNavigationRow(
                            title: "Captions",
                            subtitle: "Post caption density",
                            symbol: "text.alignleft"
                        ) { app.navigation.open(.settings(.personalisation(.captions))) }
                    }
                }
                SettingsAPIFootnote(text: "Saved on this device only. Theme and Edge Picker options are in Appearance.")
            }
            .navigationTitle("Personalisation")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.personalisation")
        case .recommendations:
            Form {
                Section {
                    Toggle("Suggested people", isOn: $suggestedPeople)
                    Toggle("Suggested modules", isOn: $moduleSuggestions)
                } footer: {
                    Text("Controls the suggested people and featured modules on Discover → Trending. Search and the People and Modules tabs aren’t affected.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Recommendations")
            .navigationBarTitleDisplayMode(.inline)
        case .stories:
            Form {
                Section {
                    Toggle("Auto-advance stories", isOn: $storyAutoAdvance)
                } footer: {
                    Text("Saved on this device.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Stories")
            .navigationBarTitleDisplayMode(.inline)
        case .captions:
            Form {
                Section {
                    Picker("Size", selection: $captionSize) {
                        Text("Compact").tag("compact")
                        Text("Standard").tag("standard")
                        Text("Comfortable").tag("comfortable")
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Caption density")
                } footer: {
                    Text("Changes post text size, line spacing and how much shows before “Show more”.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Captions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Language / Media / Feed / Battery / Safety

struct LanguageSettingsHost: View {
    let route: LanguageSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage("settings.language.translationHints") private var translationHints = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Language & Region",
                    subtitle: "Display language for Modula on this device.",
                    symbol: "globe"
                )
                // The in-app override was never applied anywhere. iOS already
                // offers a per-app language picker, so link to it instead.
                SettingsGroup(title: "App language", subtitle: "iOS keeps a separate language for each app. Tapping opens Modula in iOS Settings, where you pick it; Modula restarts in that language.") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(
                            title: "App Language",
                            subtitle: "\(currentLanguageName) · Change in iOS Settings",
                            symbol: "globe"
                        ) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                SettingsGroup(title: "Posts in other languages", subtitle: "When on, posts written in a language other than yours show a small “Translated from …” hint so you know what you’re reading.") {
                    SettingsToggleCard {
                        Toggle("Show translation hints", isOn: $translationHints)
                    }
                }
                SettingsGroup(title: "Region", subtitle: "Translation options and how times and measurements are shown on this device.") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Translate", subtitle: "Translation hints", symbol: "character.book.closed") {
                            app.navigation.open(.settings(.translate(.root)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Time & Units", subtitle: "Clocks and measurement", symbol: "clock") {
                            app.navigation.open(.settings(.timeUnits(.root)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Modula uses the language you choose for it in iOS Settings.")
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.language")
        }
    }

    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

struct MediaSettingsHost: View {
    let route: MediaSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.media.videoQuality") private var videoQuality = "auto"
    @AppStorage("settings.media.muteStart") private var muteStart = true
    @AppStorage("modula.video.autoPiP") private var autoPiP = true
    @AppStorage("settings.media.highResUploads") private var highResUploads = true
    @AppStorage("settings.media.saveOriginals") private var saveOriginals = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Media",
                    subtitle: "Playback and upload quality on this device.",
                    symbol: "photo.on.rectangle.angled"
                )
                MediaQualityGraphic(quality: videoQuality)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsFeatureTile(title: "Video", detail: "Quality & mute", symbol: "film", tint: app.appearance.liveAccent)
                    SettingsFeatureTile(title: "Images", detail: "Upload originals", symbol: "photo", tint: app.appearance.liveAccent)
                }
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Video", subtitle: "Playback quality", symbol: "film") {
                            app.navigation.open(.settings(.media(.video)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Images", subtitle: "Upload preferences", symbol: "photo") {
                            app.navigation.open(.settings(.media(.images)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Downloads", subtitle: "Offline media", symbol: "arrow.down.circle") {
                            app.navigation.open(.settings(.media(.downloads)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Camera", subtitle: "Capture framing and save", symbol: "camera") {
                            app.navigation.open(.settings(.camera(.root)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Photos", subtitle: "Library access and saves", symbol: "photo.on.rectangle") {
                            app.navigation.open(.settings(.photos(.root)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Saved on this device.")
            }
            .navigationTitle("Media")
            .navigationBarTitleDisplayMode(.inline)
        case .video:
            Form {
                Section {
                    Picker("Playback quality", selection: $videoQuality) {
                        Text("Auto").tag("auto")
                        Text("Data saver").tag("saver")
                        Text("High").tag("high")
                    }
                    Toggle("Start muted", isOn: $muteStart)
                } footer: {
                    Text("Auto downloads feed videos ahead of time on Wi‑Fi only. Data saver waits until you tap Load video. High always downloads ahead.")
                }
                if ModulaPiP.isSupported {
                    Section {
                        Toggle("Picture in Picture when leaving the app", isOn: $autoPiP)
                    } footer: {
                        Text("A video playing with sound keeps playing in a floating window when you go to another app. Long-press a reel or use a video's Keep watching menu for the in-app mini player.")
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
        case .images:
            Form {
                Section {
                    Toggle("Prefer high-resolution uploads", isOn: $highResUploads)
                    Toggle("Keep original file data", isOn: $saveOriginals)
                } footer: {
                    Text("High resolution uploads photos up to 4096 px (2048 px when off or with Data saver). Unless you keep original file data, photos are re-encoded so location and camera details stay on your iPhone.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Images")
            .navigationBarTitleDisplayMode(.inline)
        case .downloads:
            MediaDownloadsView()
        }
    }
}

struct FeedSettingsHost: View {
    let route: FeedSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.feed.defaultMode") private var defaultMode = "following"
    @AppStorage("settings.feed.mediaOnly") private var mediaOnly = false
    @AppStorage("settings.feed.hideModulePosts") private var hideModulePosts = false
    @AppStorage("settings.feed.showReplies") private var showReplies = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Feed",
                    subtitle: "Home defaults — distinct from Personalisation recommendations and Appearance.",
                    symbol: "rectangle.stack"
                )
                FeedCompositionGraphic(mode: defaultMode)
                SettingsGroup(title: "Default Home mode") {
                    VStack(spacing: 0) {
                        feedMode("Following", "People you follow", "following", "person.2")
                        SettingsDivider()
                        feedMode("For You", "Ranked for this device", "for-you", "sparkles")
                        SettingsDivider()
                        feedMode("Modules", "Module activity", "modules", "shippingbox")
                    }
                }
                SettingsToggleCard {
                    Toggle("Media only by default", isOn: $mediaOnly)
                    Toggle("Hide module posts by default", isOn: $hideModulePosts)
                    Toggle("Expand reply threads in posts", isOn: $showReplies)
                }
                SettingsAPIFootnote(text: "Home opens on your default feed next time Modula starts. Media only and Hide module posts apply to every Home feed until you change that feed’s own filter on Home. Reply threads open automatically for the first few comments on a post.")
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.feed")
        }
    }

    private func feedMode(_ title: String, _ subtitle: String, _ tag: String, _ symbol: String) -> some View {
        Button {
            defaultMode = tag
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if defaultMode == tag {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(defaultMode == tag ? .isSelected : [])
    }
}

struct BatterySettingsHost: View {
    let route: BatterySettingsRoute
    @AppStorage("settings.battery.dataSaver") private var dataSaver = false
    @AppStorage("settings.battery.reduceMotionExtra") private var reduceMotionExtra = false
    @AppStorage("settings.battery.pauseAutoplayOnLowPower") private var pauseAutoplay = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Battery & Data",
                    subtitle: "Keep Modula light when power or cellular is constrained.",
                    symbol: "battery.100.bolt"
                )
                BatteryDataGraphic(dataSaver: dataSaver, pauseAutoplay: pauseAutoplay)
                SettingsToggleCard {
                    Toggle("Data saver", isOn: $dataSaver)
                        .settingsAnchor("battery.dataSaver")
                    Toggle("Pause autoplay in Low Power Mode", isOn: $pauseAutoplay)
                        .settingsAnchor("battery.lowPower")
                    Toggle("Extra motion reduction", isOn: $reduceMotionExtra)
                        .settingsAnchor("battery.motion")
                }
                SettingsAPIFootnote(text: "Data saver stops feed videos downloading on their own, stops autoplay on cellular, skips chat link previews and uploads smaller photos. Extra motion reduction calms animations and Metal effects across Modula, like Reduce Motion. Low Power Mode and Low Data Mode are set in iOS Settings.")
            }
            .navigationTitle("Battery & Data")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SafetySettingsHost: View {
    let route: SafetySettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Safety",
                    subtitle: "Reporting, muting, and sensitive content controls.",
                    symbol: "shield.checkered"
                )
                SettingsGroup(title: "Tools") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Reporting", subtitle: "How reports work", symbol: "exclamationmark.bubble") {
                            app.navigation.open(.settings(.safety(.reporting)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Muted", subtitle: "Words and accounts", symbol: "speaker.slash") {
                            app.navigation.open(.settings(.safety(.muted)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Sensitive content", subtitle: "Media warnings", symbol: "eye.trianglebadge.exclamationmark") {
                            app.navigation.open(.settings(.safety(.sensitive)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "You can block or mute people from their posts and profiles, and report a safety concern from Help → Contact.")
            }
            .navigationTitle("Safety")
            .navigationBarTitleDisplayMode(.inline)
        case .reporting:
            MyReportsView()
        case .muted:
            // "Words and accounts": words were missing. Words editor on top, accounts below.
            MutedWordsAndAccountsView()
        case .sensitive:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Sensitive content", subtitle: "Warnings before opening media.", symbol: "eye.trianglebadge.exclamationmark")
                SettingsGroup(title: "What you can do now") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Report a safety concern", subtitle: "Open a case with the team", symbol: "shield.lefthalf.filled") {
                            app.navigation.open(.settings(.help(.contact)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Modula doesn’t label sensitive media yet, so there’s no warning to switch on. You can report a post or profile from its menu.")
            }
            .navigationTitle("Sensitive content")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Connectors / Integrations / Monetisation (designed UI + honesty)

struct ConnectorsSettingsHost: View {
    let route: ConnectorsSettingsRoute

    var body: some View {
        ConnectorsSettingsView()
    }
}

struct IntegrationsSettingsHost: View {
    let route: IntegrationsSettingsRoute

    var body: some View {
        SettingsDesignedUnavailableCanvas(
            title: "Integrations",
            subtitle: "Modules and services that extend Modula — not Profile social connections.",
            symbol: "puzzlepiece.extension",
            tiles: [
                ("Webhooks", "Outbound events", "antenna.radiowaves.left.and.right"),
                ("Zapier-style", "Automation bridges", "arrow.triangle.branch"),
                ("Slack", "Team alerts", "number"),
                ("Custom", "Bring your own", "plus.square.on.square")
            ],
            previewRows: [
                ("Installed", "Active integrations", "checkmark.seal"),
                ("Browse", "Catalogue", "square.grid.2x2"),
                ("Developer", "API keys", "key")
            ],
            apiNote: SettingsRegistry.destination(for: .integrations(.root))?.unavailableReason
                ?? "Integrations aren’t available yet.",
                alternatives: [
                    ("Modules", "Install and manage modules", "shippingbox", .modules(.root))
                ]
        )
        .navigationTitle("Integrations")
    }
}

struct MonetisationSettingsHost: View {
    let route: MonetisationSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Monetisation",
                    subtitle: "Plans, payouts, and invoices.",
                    symbol: "creditcard"
                )
                SettingsSceneGraphic(style: .meter)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsFeatureTile(title: "Plans", detail: "Subscriptions", symbol: "rectangle.stack", tint: app.appearance.liveAccent)
                    SettingsFeatureTile(title: "Payouts", detail: "Creator earnings", symbol: "banknote", tint: app.appearance.liveAccent)
                }
                SettingsGroup(title: "Browse") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Plans", subtitle: "Subscription tiers", symbol: "rectangle.stack") {
                            app.navigation.open(.settings(.monetisation(.plans)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Payouts", subtitle: "Creator balance", symbol: "banknote") {
                            app.navigation.open(.settings(.monetisation(.payouts)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Invoices", subtitle: "Billing history", symbol: "doc.richtext") {
                            app.navigation.open(.settings(.monetisation(.invoices)))
                        }
                    }
                }
                SettingsAPIFootnote(text: SettingsRegistry.destination(for: .monetisation(.root))?.unavailableReason
                    ?? "Plans and pricing aren’t available yet.")
            }
            .navigationTitle("Monetisation")
            .navigationBarTitleDisplayMode(.inline)
        case .plans:
            SettingsDesignedUnavailableCanvas(
                title: "Plans",
                subtitle: "Choose a Modula plan when billing is live.",
                symbol: "rectangle.stack",
                tiles: [
                    ("Free", "Core social", "gift"),
                    ("Plus", "Extras", "plus.circle"),
                    ("Pro", "Creators", "star.circle"),
                    ("Team", "Orgs", "person.3")
                ],
                previewRows: [
                    ("Compare", "Feature matrix", "tablecells"),
                    ("Restore", "App Store purchases", "arrow.clockwise")
                ],
                apiNote: "Modula plans can’t be purchased in the app yet.",
                alternatives: [
                    ("Contact support", "Ask about plans for your team", "envelope", .help(.contact))
                ]
            )
        case .payouts:
            PayoutsLedgerView()
        case .invoices:
            InvoicesListView()
        }
    }
}

// MARK: - Chats / Audio (expanded unique UI)

struct ChatsSettingsHost: View {
    let route: ChatsSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.chats.enterToSend") private var enterToSend = false
    @AppStorage("settings.chats.previewMedia") private var previewMedia = true
    @AppStorage("settings.chats.linkPreviews") private var linkPreviews = true
    @AppStorage("settings.links.openInApp") private var openLinksInApp = true
    @AppStorage("settings.links.blockTrackers") private var blockTrackers = true
    @AppStorage("settings.chats.spellCheck") private var spellCheck = true
    @AppStorage("settings.chats.readReceiptsDisplay") private var readReceiptsDisplay = true
    @State private var showsQuickReplies = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Chats",
                    subtitle: "Composer, previews, and local privacy defaults.",
                    symbol: "bubble.left.and.bubble.right"
                )
                ChatsPrivacyGraphic(receipts: readReceiptsDisplay)
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Composer", subtitle: "Moliboo, enter to send, spell check", symbol: "keyboard") {
                            app.navigation.open(.settings(.chats(.composer)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Previews", subtitle: "Media and links", symbol: "eye") {
                            app.navigation.open(.settings(.chats(.previews)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Chat privacy", subtitle: app.messaging.capabilities.privacyControls ? "Receipts, typing, last seen, lock screen" : "Receipts on this device", symbol: "lock.rectangle.on.rectangle") {
                            app.navigation.open(.settings(.chats(.privacy)))
                        }
                        if app.messaging.capabilities.features4.quickReplies {
                            SettingsDivider()
                            SettingsNavigationRow(title: "Quick replies", subtitle: "Type / in a chat to use them", symbol: "text.bubble") {
                                showsQuickReplies = true
                            }
                            .accessibilityIdentifier("settings.chats.quickReplies")
                        }
                    }
                }
                .sheet(isPresented: $showsQuickReplies) { QuickRepliesManageSheet().modulaSheetStyle() }
                SettingsAPIFootnote(text: "These change how chats look and behave on this iPhone.")
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.chats")
        case .composer:
            Form {
                Section {
                    Toggle("Enter to send", isOn: $enterToSend)
                    Toggle("Spell check", isOn: $spellCheck)
                }
                ComposerMascotSettingsSection()
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Composer")
            .navigationBarTitleDisplayMode(.inline)
        case .previews:
            Form {
                Section {
                    Toggle("Preview media inline", isOn: $previewMedia)
                    Toggle("Link previews", isOn: $linkPreviews)
                } footer: {
                    Text("Image links in messages show as images. Other links show a preview card. Post and comment previews are fetched through Modula’s link preview service. Data saver turns link previews off.")
                }
                Section {
                    Toggle("Open links in Modula", isOn: $openLinksInApp)
                        .accessibilityIdentifier("settings.links.openInApp")
                    if openLinksInApp {
                        Toggle("Block trackers", isOn: $blockTrackers)
                            .accessibilityIdentifier("settings.links.blockTrackers")
                    }
                } header: {
                    Text("Links")
                } footer: {
                    Text("Web links from posts, chats, bios, comments and notifications open in Modula’s browser, with the post or chat kept at hand. Modula links open right in the app, and links that belong to an installed app, like YouTube or Maps, still open in that app. Block trackers stops a short list of well-known ad and tracking services from loading. Turn off Open links in Modula to use Safari.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Previews")
            .navigationBarTitleDisplayMode(.inline)
        case .privacy:
            Form {
                if app.messaging.capabilities.privacyControls {
                    Section {
                        Toggle("Read receipts", isOn: Binding(
                            get: { app.messaging.privacy.readReceipts },
                            set: { value in Task { await app.messaging.setReadReceipts(value) } }
                        ))
                        Toggle("Typing indicators", isOn: Binding(
                            get: { app.messaging.privacy.typingIndicators },
                            set: { value in Task { await app.messaging.setTypingIndicators(value) } }
                        ))
                        Picker("Last seen & online", selection: Binding(
                            get: { app.messaging.privacy.presenceVisibility },
                            set: { value in Task { await app.messaging.setPresenceVisibility(value) } }
                        )) {
                            ForEach(PresenceVisibility.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    } footer: {
                        Text("These apply across your chats. Turning receipts or last seen off is reciprocal — you won't see other people's either.")
                    }
                    Section {
                        Picker("Lock screen preview", selection: Binding(
                            get: { app.messaging.privacy.notificationPreview },
                            set: { value in Task { await app.messaging.setNotificationPreview(value) } }
                        )) {
                            ForEach(NotificationPreviewSetting.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    } footer: {
                        Text("Controls what a message notification can show on the lock screen. Your phone still needs notifications allowed.")
                    }
                }
                Section {
                    Toggle("Show read receipts (display)", isOn: $readReceiptsDisplay)
                } footer: {
                    Text("Only changes what you see on this iPhone. It doesn’t change what others see.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Chat privacy")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await app.messaging.probeCapabilities()
                await app.messaging.loadPrivacyIfNeeded()
            }
        }
    }
}

struct AudioSettingsHost: View {
    let route: AudioSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.audio.hapticOnPlay") private var hapticOnPlay = true
    @AppStorage("settings.audio.autoplayPreviews") private var autoplayPreviews = false
    @AppStorage("settings.audio.voicePlaybackSpeed") private var voiceSpeed = 1.0
    @AppStorage("settings.audio.raiseToListen") private var raiseToListen = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Audio",
                    subtitle: "Playback, voice notes, and haptics.",
                    symbol: "speaker.wave.2"
                )
                AudioWaveGraphic()
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Playback", subtitle: "Autoplay and quality feel", symbol: "play.circle") {
                            app.navigation.open(.settings(.audio(.playback)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Voice", subtitle: "Voice note speed", symbol: "waveform") {
                            app.navigation.open(.settings(.audio(.voice)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Haptics", subtitle: "Feel on play", symbol: "hand.tap") {
                            app.navigation.open(.settings(.audio(.haptics)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Applies to audio posts and video in Modula. Volume is managed by iOS.")
            }
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.audio")
        case .playback:
            Form {
                Section {
                    Toggle("Autoplay previews", isOn: $autoplayPreviews)
                } footer: {
                    Text("Starts audio as soon as you open it.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
        case .voice:
            Form {
                Section {
                    Toggle("Raise to listen", isOn: $raiseToListen)
                } footer: {
                    Text("While audio plays, holding your iPhone to your ear switches to the earpiece (only if Modula already has microphone access, which iOS requires for the earpiece).")
                }
                VStack(alignment: .leading) {
                    Text("Voice playback speed")
                    Slider(value: $voiceSpeed, in: 0.75...2.0, step: 0.25)
                        .accessibilityLabel("Voice playback speed")
                        .accessibilityValue(voiceSpeed.formatted(.number.precision(.fractionLength(0...2))) + " times")
                    Text(voiceSpeed.formatted(.number.precision(.fractionLength(0...2))) + "×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
        case .haptics:
            Form {
                Toggle("Haptic on play", isOn: $hapticOnPlay)
                    .settingsAnchor("audio.haptics")
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Haptics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AudioWaveGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(app.appearance.liveAccent.opacity(0.35 + Double(index % 4) * 0.15))
                    .frame(width: 6, height: CGFloat(12 + (index % 5) * 8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(app.appearance.liveAccent.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}


struct MutedWordsAndAccountsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var tab = Tab.words
    enum Tab: String, CaseIterable, Identifiable { case words = "Words", accounts = "Accounts"; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            ModulaSegmentedControl("Muted", selection: $tab, options: Tab.allCases, symbol: { $0 == .words ? "textformat" : "person.crop.circle.badge.xmark" }, identifier: { "safety.muted.\($0.rawValue.lowercased())" }) { $0.rawValue }
                .padding(.horizontal, 16).padding(.vertical, 8)
            switch tab {
            case .words: MutedWordsEditor()
            case .accounts: RelationshipListView(kind: .muted)
            }
        }
        .navigationTitle("Muted")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MutedWordsEditor: View {
    @Environment(AppEnvironment.self) private var app
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a word, phrase or #tag", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).count < 2)
                }
            } footer: {
                Text("Posts containing these are hidden from Home. Saved on this device only.")
            }
            if !app.home.mutedWords.isEmpty {
                Section("\(app.home.mutedWords.count) muted") {
                    ForEach(app.home.mutedWords, id: \.self) { word in
                        Label(word, systemImage: "speaker.slash")
                    }
                    .onDelete { offsets in
                        var words = app.home.mutedWords
                        words.remove(atOffsets: offsets)
                        app.home.setMutedWords(words)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func add() {
        let word = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 2 else { return }
        app.home.setMutedWords([word] + app.home.mutedWords)
        draft = ""
        HapticEngine.shared.play(.selection)
    }
}
