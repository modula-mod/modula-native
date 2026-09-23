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
                SettingsAPIFootnote(text: "These preferences are stored on this device only. Ranking signals are not synced to Greenfield yet — Appearance / Edge Picker live under Appearance.")
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
                    Text("Local display preferences. Discovery ranking APIs are not claimed here.")
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
                    Text("Controls local Story viewer behaviour. Does not invent a Story preference endpoint.")
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
                    Text("Affects how captions wrap in feed cards on this device.")
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
    @AppStorage("settings.language.appOverride") private var appOverride = "system"
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
                SettingsGroup(title: "App language") {
                    VStack(spacing: 0) {
                        languageRow("System", "Follow iOS language", "system")
                        SettingsDivider()
                        languageRow("English", "English (UK)", "en-GB")
                        SettingsDivider()
                        languageRow("English (US)", "English (United States)", "en-US")
                    }
                }
                Form {
                    Toggle("Show translation hints", isOn: $translationHints)
                }
                .scrollDisabled(true)
                .frame(minHeight: 72)
                SettingsAPIFootnote(text: "Override is device-local. Server-side locale / translation endpoints are not verified in this client.")
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.language")
        }
    }

    private func languageRow(_ title: String, _ subtitle: String, _ tag: String) -> some View {
        Button {
            appOverride = tag
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if appOverride == tag {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct MediaSettingsHost: View {
    let route: MediaSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.media.videoQuality") private var videoQuality = "auto"
    @AppStorage("settings.media.muteStart") private var muteStart = true
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsFeatureTile(title: "Video", detail: "Quality & mute", symbol: "film", tint: app.appearance.accent.color)
                    SettingsFeatureTile(title: "Images", detail: "Upload originals", symbol: "photo", tint: app.appearance.accent.color)
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
                    }
                }
                SettingsAPIFootnote(text: "Preferences are local. Adaptive bitrate / CDN policies are owned by Greenfield media and are not mutated here.")
            }
            .navigationTitle("Media")
            .navigationBarTitleDisplayMode(.inline)
        case .video:
            Form {
                Picker("Playback quality", selection: $videoQuality) {
                    Text("Auto").tag("auto")
                    Text("Data saver").tag("saver")
                    Text("High").tag("high")
                }
                Toggle("Start muted", isOn: $muteStart)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
        case .images:
            Form {
                Toggle("Prefer high-resolution uploads", isOn: $highResUploads)
                Toggle("Keep originals in Photos", isOn: $saveOriginals)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Images")
            .navigationBarTitleDisplayMode(.inline)
        case .downloads:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Downloads", subtitle: "Offline media store.", symbol: "arrow.down.circle")
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "tray",
                    description: Text("This build has no offline media catalogue.")
                )
                .frame(minHeight: 180)
                SettingsAPIFootnote(text: "A downloads subsystem is not present. UI is ready for when offline media lands.")
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeedSettingsHost: View {
    let route: FeedSettingsRoute
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
                SettingsSceneGraphic(style: .waves)
                SettingsGroup(title: "Default Home mode") {
                    VStack(spacing: 0) {
                        feedMode("Following", "People you follow", "following", "person.2")
                        SettingsDivider()
                        feedMode("For You", "Ranked for this device", "for-you", "sparkles")
                        SettingsDivider()
                        feedMode("Modules", "Module activity", "modules", "shippingbox")
                    }
                }
                Form {
                    Toggle("Media only by default", isOn: $mediaOnly)
                    Toggle("Hide module posts by default", isOn: $hideModulePosts)
                    Toggle("Show reply threads", isOn: $showReplies)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Stored on device. Does not invent a feed-preferences PATCH. Home Feeds sheet can still override per session.")
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
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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
                Form {
                    Toggle("Data saver", isOn: $dataSaver)
                    Toggle("Pause autoplay in Low Power Mode", isOn: $pauseAutoplay)
                    Toggle("Extra motion reduction", isOn: $reduceMotionExtra)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Local heuristics only. iOS Low Power Mode remains the system authority; Modula does not override Focus or cellular settings.")
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
                SettingsAPIFootnote(text: "Block/mute mutations exist on posts in Greenfield inventory, but a verified settings-owned safety preference surface is not fully wired. UI is designed ahead of that contract.")
            }
            .navigationTitle("Safety")
            .navigationBarTitleDisplayMode(.inline)
        case .reporting:
            SettingsDesignedUnavailableCanvas(
                title: "Reporting",
                subtitle: "Choose what happened and send context.",
                symbol: "exclamationmark.bubble",
                tiles: [
                    ("Post", "Report a post", "text.bubble"),
                    ("Profile", "Report a person", "person.crop.circle.badge.exclamationmark"),
                    ("Message", "Report a chat", "bubble.left"),
                    ("Module", "Report a module", "shippingbox")
                ],
                previewRows: [
                    ("Spam", "Misleading or repetitive", "flame"),
                    ("Harassment", "Targeted abuse", "hand.raised"),
                    ("Illegal content", "Against the law", "scalemass")
                ],
                apiNote: "Report reason enums and endpoints need VPS verification before these rows become actionable."
            )
        case .muted:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Muted", subtitle: "Quiet words and accounts on this device.", symbol: "speaker.slash")
                ContentUnavailableView("Nothing muted yet", systemImage: "speaker.slash", description: Text("Muted lists will appear here when persistence is verified."))
                    .frame(minHeight: 160)
                SettingsAPIFootnote(text: "No verified mute-list settings contract is wired for this screen.")
            }
            .navigationTitle("Muted")
            .navigationBarTitleDisplayMode(.inline)
        case .sensitive:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Sensitive content", subtitle: "Warnings before opening media.", symbol: "eye.trianglebadge.exclamationmark")
                Form {
                    Toggle("Warn before sensitive media", isOn: .constant(true))
                        .disabled(true)
                }
                .scrollDisabled(true)
                .frame(minHeight: 72)
                SettingsAPIFootnote(text: "Toggle is illustrative until a verified sensitive-media preference exists. Left disabled so it cannot fake server state.")
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
        SettingsDesignedUnavailableCanvas(
            title: "Connectors",
            subtitle: "Link accounts Modula can use with your permission.",
            symbol: "link",
            tiles: [
                ("Calendar", "Events & reminders", "calendar"),
                ("Cloud drive", "Files & attachments", "externaldrive"),
                ("Music", "Listening context", "music.note"),
                ("Health", "Activity signals", "heart")
            ],
            previewRows: [
                ("Apple", "Sign in with Apple services", "apple.logo"),
                ("Google", "Calendar and Drive", "g.circle"),
                ("GitHub", "Developer links", "chevron.left.forwardslash.chevron.right")
            ],
            apiNote: SettingsRegistry.destination(for: .connectors(.root))?.unavailableReason
                ?? "No verified Greenfield OAuth connector contract is wired in this native client."
        )
        .navigationTitle("Connectors")
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
                ?? "No verified integration catalog is present."
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
                    subtitle: "Plans, payouts, and invoices — designed ahead of billing APIs.",
                    symbol: "creditcard"
                )
                SettingsSceneGraphic(style: .meter)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsFeatureTile(title: "Plans", detail: "Subscriptions", symbol: "rectangle.stack", tint: app.appearance.accent.color)
                    SettingsFeatureTile(title: "Payouts", detail: "Creator earnings", symbol: "banknote", tint: app.appearance.accent.color)
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
                    ?? "No verified billing contract. Native will not invent prices.")
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
                apiNote: "Plan names and prices are illustrative placeholders only — not offered for purchase."
            )
        case .payouts:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Payouts", subtitle: "Creator balance.", symbol: "banknote")
                ModulaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("—")
                            .font(.largeTitle.weight(.semibold))
                        Text("No payout provider connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                SettingsAPIFootnote(text: "Balance is blank until a verified payouts API exists. No fabricated currency amounts.")
            }
            .navigationTitle("Payouts")
            .navigationBarTitleDisplayMode(.inline)
        case .invoices:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Invoices", subtitle: "Billing history.", symbol: "doc.richtext")
                ContentUnavailableView("No invoices", systemImage: "doc", description: Text("History appears when StoreKit / Greenfield billing is verified."))
                    .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Invoice list is empty on purpose — no sample rows.")
            }
            .navigationTitle("Invoices")
            .navigationBarTitleDisplayMode(.inline)
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
    @AppStorage("settings.chats.spellCheck") private var spellCheck = true
    @AppStorage("settings.chats.readReceiptsDisplay") private var readReceiptsDisplay = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(
                    title: "Chats",
                    subtitle: "Composer, previews, and local privacy defaults.",
                    symbol: "bubble.left.and.bubble.right"
                )
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Composer", subtitle: "Enter to send, spell check", symbol: "keyboard") {
                            app.navigation.open(.settings(.chats(.composer)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Previews", subtitle: "Media and links", symbol: "eye") {
                            app.navigation.open(.settings(.chats(.previews)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Chat privacy", subtitle: "Receipts on this device", symbol: "lock.rectangle.on.rectangle") {
                            app.navigation.open(.settings(.chats(.privacy)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Device-local defaults only. Does not invent Greenfield messaging preference PATCH routes.")
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.chats")
        case .composer:
            Form {
                Toggle("Enter to send", isOn: $enterToSend)
                Toggle("Spell check", isOn: $spellCheck)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Composer")
            .navigationBarTitleDisplayMode(.inline)
        case .previews:
            Form {
                Toggle("Preview media inline", isOn: $previewMedia)
                Toggle("Link previews", isOn: $linkPreviews)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Previews")
            .navigationBarTitleDisplayMode(.inline)
        case .privacy:
            Form {
                Section {
                    Toggle("Show read receipts (display)", isOn: $readReceiptsDisplay)
                } footer: {
                    Text("Display preference only. Sending/hiding receipts requires a verified messaging privacy contract.")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Chat privacy")
            .navigationBarTitleDisplayMode(.inline)
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
                SettingsAPIFootnote(text: "Device-local. System volume and Focus modes remain with iOS.")
            }
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.audio")
        case .playback:
            Form {
                Toggle("Autoplay previews", isOn: $autoplayPreviews)
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
        case .voice:
            Form {
                Toggle("Raise to listen", isOn: $raiseToListen)
                VStack(alignment: .leading) {
                    Text("Voice playback speed")
                    Slider(value: $voiceSpeed, in: 0.75...2.0, step: 0.25)
                    Text(String(format: "%.2g×", voiceSpeed))
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
                    .fill(app.appearance.accent.color.opacity(0.35 + Double(index % 4) * 0.15))
                    .frame(width: 6, height: CGFloat(12 + (index % 5) * 8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(app.appearance.accent.color.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}
