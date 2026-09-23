import Foundation

enum SettingsAvailability: String, Hashable, Sendable {
    case implemented
    case capabilityUnavailable
    case developerOnly

    var auditLabel: String {
        switch self {
        case .implemented: "IMPLEMENTED"
        case .capabilityUnavailable: "CAPABILITY-UNAVAILABLE"
        case .developerOnly: "DEVELOPER-ONLY"
        }
    }
}

struct SettingsDestination: Identifiable, Hashable, Sendable {
    var id: String { RouteSerializer.serialize(.settings(route)) }
    let route: SettingsRoute
    let title: String
    let subtitle: String
    let symbol: String
    let availability: SettingsAvailability
    let searchTerms: [String]
    /// Factual reason when availability is capabilityUnavailable.
    let unavailableReason: String?

    var commandID: CommandID {
        let path = id.hasPrefix("/") ? String(id.dropFirst()) : id
        let dotted = path.replacingOccurrences(of: "/", with: ".")
        return CommandID(rawValue: dotted == "settings" ? "settings.root" : dotted)
    }
}

enum SettingsRegistry {
    static let destinations: [SettingsDestination] = makeDestinations()

    static func destination(for route: SettingsRoute) -> SettingsDestination? {
        destinations.first { $0.route == route }
    }

    static func search(query: String, includeDeveloper: Bool) -> [SettingsDestination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visibleRoots(includeDeveloper: includeDeveloper) }
        return destinations.filter { destination in
            if destination.availability == .developerOnly && !includeDeveloper { return false }
            let haystack = ([destination.title, destination.subtitle] + destination.searchTerms)
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(trimmed.lowercased())
        }
    }

    static func visibleRoots(includeDeveloper: Bool) -> [SettingsDestination] {
        destinations.filter { destination in
            if destination.availability == .developerOnly && !includeDeveloper { return false }
            return isRoot(destination.route)
        }
    }

    static func commands(signedIn: Bool, developerMode: Bool) -> [ModulaCommand] {
        destinations.map { destination in
            let availability: CommandAvailability
            switch destination.availability {
            case .developerOnly:
                availability = .developerOnly
            case .implemented, .capabilityUnavailable:
                if requiresSignIn(destination.route) && !signedIn {
                    availability = .requiresSignIn
                } else {
                    availability = .available
                }
            }
            return ModulaCommand(
                id: destination.commandID,
                title: destination.title,
                subtitle: destination.subtitle,
                icon: .init(destination.symbol),
                category: .manage,
                availability: availability,
                action: .settingsOpen(destination.route),
                aliases: destination.searchTerms,
                accessibilityHint: "Opens \(destination.title)"
            )
        }
        .filter { command in
            if command.availability == .developerOnly { return developerMode }
            return true
        }
    }

    private static func requiresSignIn(_ route: SettingsRoute) -> Bool {
        switch route {
        case .account, .privacy(.appLock), .privacy(.biometrics), .privacy(.blocked):
            true
        default:
            false
        }
    }

    static func auditRows() -> [(route: String, status: String, title: String)] {
        destinations.map {
            (RouteSerializer.serialize(.settings($0.route)), $0.availability.auditLabel, $0.title)
        }
    }

    private static func isRoot(_ route: SettingsRoute) -> Bool {
        switch route {
        case .root, .account(.root), .appearance(.root), .personalisation(.root),
             .intelligence(.root), .chats(.root), .audio(.root),
             .language(.root), .media(.root), .feed(.root), .battery(.root), .safety(.root),
             .camera(.root), .gestures(.root), .finder(.root), .sharing(.root),
             .location(.root), .widgets(.root), .labs(.root), .photos(.root),
             .network(.root), .digests(.root),
             .help(.root), .whatsNew(.root), .creator(.root), .focus(.root),
             .passkeys(.root), .translate(.root), .qrCode(.root), .family(.root),
             .timeUnits(.root), .keyboard(.root),
             .connectors(.root), .integrations(.root), .monetisation(.root),
             .notifications(.root), .privacy(.root),
             .modules(.root), .dataStorage(.root), .accessibility(.root), .features(.root),
             .updates(.root), .developer(.root), .about(.root):
            true
        default: false
        }
    }

    private static func item(
        _ route: SettingsRoute,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ availability: SettingsAvailability,
        terms: [String] = [],
        reason: String? = nil
    ) -> SettingsDestination {
        SettingsDestination(
            route: route,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            availability: availability,
            searchTerms: terms,
            unavailableReason: reason
        )
    }

    private static func makeDestinations() -> [SettingsDestination] {
        [
            item(.root, "Settings", "Account, appearance, security and more", "gearshape", .implemented, terms: ["settings", "prefs"]),
            item(.account(.root), "Account", "Personal information, sessions and sign out", "person.crop.circle", .implemented, terms: ["account", "login"]),
            item(.account(.personalInformation), "Personal Information", "Private account details", "person.text.rectangle", .implemented, terms: ["name", "account id"]),
            item(.account(.username), "Username", "Greenfield handle", "at", .capabilityUnavailable, terms: ["username", "handle"], reason: "Greenfield has no verified native username-change contract in this checkout. Handle is shown as read-only."),
            item(.account(.email), "Email", "Account email", "envelope", .capabilityUnavailable, terms: ["email"], reason: "Email change and re-verification are documented on Greenfield, but the live mutation path is unverified this run. Current email is shown when the session provides it."),
            item(.account(.password), "Password", "Reset through Greenfield", "key", .implemented, terms: ["password"]),
            item(.account(.sessions), "Sessions", "Devices signed into this account", "laptopcomputer.and.iphone", .implemented, terms: ["sessions", "devices", "sign out"]),
            item(.account(.deleteAccount), "Delete Account", "Close this Modula account", "trash", .capabilityUnavailable, terms: ["delete", "close account"], reason: "No verified delete-account endpoint is present in native DTOs or inventory for this run."),
            item(.appearance(.root), "Appearance", "Theme, type, motion and branding", "paintpalette", .implemented, terms: ["theme", "oled", "dim", "font", "accent", "dark", "light"]),
            item(.appearance(.theme), "Theme", "Light, dark or system", "circle.lefthalf.filled", .implemented, terms: ["light", "dark", "system theme"]),
            item(.appearance(.darkStyle), "Dark Style", "Standard, Dim or OLED", "moon", .implemented, terms: ["oled", "dim", "dark"]),
            item(.appearance(.accent), "Accent", "Modula Teal and accents", "drop", .implemented, terms: ["teal", "colour", "color"]),
            item(.appearance(.typography), "Typography", "Font family and text size", "textformat", .implemented, terms: ["font", "type"]),
            item(.appearance(.fontFamily), "Font Family", "System, rounded, mono and more", "textformat", .implemented, terms: ["font family"]),
            item(.appearance(.textSize), "Text Size", "Compact, standard or large", "textformat.size", .implemented, terms: ["text size", "font size"]),
            item(.appearance(.appIcon), "App Icon", "Approved production icon", "app.badge", .implemented, terms: ["icon"]),
            item(.appearance(.density), "Density", "Spacing scale", "arrow.up.left.and.arrow.down.right", .implemented, terms: ["density", "compact"]),
            item(.appearance(.motion), "Motion Personality", "Calm, standard or expressive", "waveform.path", .implemented, terms: ["motion", "reduce motion"]),
            item(.appearance(.haptics), "Haptic Intensity", "Off through strong", "hand.tap", .implemented, terms: ["haptics"]),
            item(.appearance(.contrastTransparency), "Contrast & Transparency", "Contrast and reduce transparency", "circle.righthalf.filled", .implemented, terms: ["contrast", "transparency"]),
            item(.appearance(.iconStyle), "Icon Style", "Outline, balanced or filled", "circle.grid.cross", .implemented, terms: ["icons"]),
            item(.appearance(.interfaceShape), "Interface Shape", "Soft, balanced or precise", "rectangle.roundedtop", .implemented, terms: ["shape"]),
            item(.appearance(.moduleBranding), "Module Branding", "How modules use their colour", "paintbrush", .implemented, terms: ["branding"]),
            item(.appearance(.edgePicker), "Edge Picker", "Position, size, side, labels, glass", "rectangle.trailinghalf.inset.filled", .implemented, terms: ["edge picker", "position", "size", "side", "labels", "glass", "visibility", "haptics", "rail"]),
            item(.appearance(.preview), "Appearance Preview", "Live contract preview", "rectangle.inset.filled", .implemented, terms: ["preview"]),
            item(.personalisation(.root), "Personalisation", "Recommendations, stories and captions", "slider.horizontal.3", .implemented, terms: ["personalisation", "personalization", "recommendations", "stories", "captions"]),
            item(.personalisation(.recommendations), "Recommendations", "Suggested people and modules", "sparkles", .implemented, terms: ["suggested", "recommendations"]),
            item(.personalisation(.stories), "Stories prefs", "Auto-advance stories", "circle.dashed", .implemented, terms: ["stories", "auto-advance"]),
            item(.personalisation(.captions), "Captions", "Caption density", "text.alignleft", .implemented, terms: ["captions"]),
            item(.intelligence(.root), "Intelligence", "On-device models, knowledge and privacy", "brain", .implemented, terms: ["intelligence", "ai", "models", "local"]),
            item(.intelligence(.models), "Models", "Registered local intelligence providers", "cpu", .implemented, terms: ["models", "providers", "nodus", "apple"]),
            item(.intelligence(.knowledge), "Knowledge", "Local knowledge surfaces", "books.vertical", .implemented, terms: ["knowledge", "corpus"]),
            item(.intelligence(.privacy), "Intelligence Privacy", "Local-only fail-closed policy", "hand.raised.fill", .implemented, terms: ["privacy", "local-only"]),
            item(.intelligence(.tools), "Tools", "Registered intelligence tools", "wrench.and.screwdriver", .implemented, terms: ["tools", "tool registry"]),
            item(.chats(.root), "Chats", "Composer, previews and chat privacy", "bubble.left.and.bubble.right", .implemented, terms: ["chats", "messages", "messaging"]),
            item(.chats(.composer), "Composer", "Enter to send and spell check", "keyboard", .implemented, terms: ["composer", "enter to send"]),
            item(.chats(.previews), "Chat Previews", "Media and link previews", "eye", .implemented, terms: ["previews", "links"]),
            item(.chats(.privacy), "Chat Privacy", "Read receipts display", "lock.rectangle.on.rectangle", .implemented, terms: ["receipts"]),
            item(.audio(.root), "Audio", "Playback, voice and haptics", "speaker.wave.2", .implemented, terms: ["audio", "sound", "playback"]),
            item(.audio(.playback), "Playback", "Autoplay previews", "play.circle", .implemented, terms: ["autoplay"]),
            item(.audio(.voice), "Voice", "Voice note speed", "waveform", .implemented, terms: ["voice", "speed"]),
            item(.audio(.haptics), "Audio Haptics", "Haptic on play", "hand.tap", .implemented, terms: ["haptics"]),
            item(.language(.root), "Language", "App language on this device", "globe", .implemented, terms: ["language", "locale", "region"]),
            item(.media(.root), "Media", "Video and image quality", "photo.on.rectangle.angled", .implemented, terms: ["media", "video", "images"]),
            item(.media(.video), "Video", "Playback quality", "film", .implemented, terms: ["video quality"]),
            item(.media(.images), "Images", "Upload preferences", "photo", .implemented, terms: ["images", "upload"]),
            item(.media(.downloads), "Media Downloads", "Offline media", "arrow.down.circle", .implemented, terms: ["downloads"]),
            item(.feed(.root), "Feed", "Home defaults for this device", "rectangle.stack", .implemented, terms: ["feed", "home", "following", "for you"]),
            item(.battery(.root), "Battery & Data", "Data saver and Low Power", "battery.100.bolt", .implemented, terms: ["battery", "data saver"]),
            item(.safety(.root), "Safety", "Reporting and sensitive content", "shield.checkered", .implemented, terms: ["safety", "report", "mute"]),
            item(.safety(.reporting), "Reporting", "Report reasons", "exclamationmark.bubble", .capabilityUnavailable, terms: ["report"], reason: "Report reason enums and endpoints need VPS verification before these rows become actionable."),
            item(.safety(.muted), "Muted", "Muted words and accounts", "speaker.slash", .capabilityUnavailable, terms: ["mute"], reason: "No verified mute-list settings contract is wired for this screen."),
            item(.safety(.sensitive), "Sensitive content", "Media warnings", "eye.trianglebadge.exclamationmark", .capabilityUnavailable, terms: ["sensitive"], reason: "Sensitive-media preference contract is unverified. Controls stay non-mutating."),
            item(.camera(.root), "Camera", "Capture framing and save behaviour", "camera", .implemented, terms: ["camera", "capture"]),
            item(.camera(.capture), "Capture", "Grid, mirror, format", "viewfinder", .implemented, terms: ["grid", "mirror"]),
            item(.camera(.permissions), "Camera Permissions", "Camera & mic access", "hand.raised.square", .implemented, terms: ["camera permission", "microphone"]),
            item(.gestures(.root), "Gestures", "Touch shortcuts", "hand.draw", .implemented, terms: ["gestures", "swipe", "double tap"]),
            item(.finder(.root), "Search", "Lookup behaviour on this device", "magnifyingglass", .implemented, terms: ["search", "finder", "history"]),
            item(.sharing(.root), "Sharing", "Share sheet defaults", "square.and.arrow.up", .implemented, terms: ["sharing", "share sheet"]),
            item(.location(.root), "Location", "Precise and approximate access", "location", .capabilityUnavailable, terms: ["location", "gps", "map"], reason: "No verified location-preference contract in native settings this run."),
            item(.location(.map), "Map posts", "Place attachments", "map", .capabilityUnavailable, terms: ["map posts"], reason: "Place pickers stay off until a verified location attach contract exists."),
            item(.widgets(.root), "Widgets", "Home Screen surfaces", "rectangle.on.rectangle.angled", .capabilityUnavailable, terms: ["widgets", "widgetkit"], reason: "WidgetKit targets are not shipping in this build. Previews are illustrative."),
            item(.widgets(.gallery), "Widget gallery", "Sizes and timelines", "square.grid.3x3", .capabilityUnavailable, terms: ["widget gallery"], reason: "Gallery is design-only until Widget extensions land."),
            item(.labs(.root), "Labs", "Optional local experiments", "flask", .implemented, terms: ["labs", "experiments"]),
            item(.photos(.root), "Photos", "Library access and save behaviour", "photo.on.rectangle", .implemented, terms: ["photos", "library"]),
            item(.network(.root), "Network", "Upload and preload behaviour", "network", .implemented, terms: ["network", "wifi", "preload"]),
            item(.digests(.root), "Digests", "Weekly and morning summaries", "envelope.open", .implemented, terms: ["digest", "email summary"]),
            item(.help(.root), "Help", "Guides, contact and status", "questionmark.circle", .implemented, terms: ["help", "support"]),
            item(.help(.guides), "Guides", "How Modula works", "book", .implemented, terms: ["guides", "howto"]),
            item(.help(.contact), "Contact", "Reach Modula support", "envelope", .capabilityUnavailable, terms: ["contact", "support"], reason: "No verified support-ticket endpoint is wired. UI stays non-submitting."),
            item(.help(.status), "Status", "Service health", "waveform.path.ecg", .implemented, terms: ["status", "uptime"]),
            item(.whatsNew(.root), "What’s New", "Release highlights", "sparkles", .implemented, terms: ["whats new", "release notes"]),
            item(.creator(.root), "Creator", "Studio defaults", "paintbrush.pointed", .implemented, terms: ["creator", "studio"]),
            item(.creator(.studio), "Studio defaults", "Audience and hints", "slider.horizontal.2.square", .implemented, terms: ["audience"]),
            item(.creator(.insights), "Insights", "Reach overview", "chart.line.uptrend.xyaxis", .capabilityUnavailable, terms: ["insights", "analytics"], reason: "No fabricated analytics. Values stay blank until a verified insights contract exists."),
            item(.focus(.root), "Focus", "Behaviour during iOS Focus", "moon.stars", .implemented, terms: ["focus", "dnd"]),
            item(.passkeys(.root), "Passkeys", "Passwordless sign-in", "person.badge.key", .capabilityUnavailable, terms: ["passkey", "webauthn"], reason: "Passkey registration/assertion endpoints are not verified in this native client."),
            item(.translate(.root), "Translate", "Translation hints for posts", "character.book.closed", .implemented, terms: ["translate", "language detect"]),
            item(.qrCode(.root), "Modula Code", "Profile QR and scanner", "qrcode", .implemented, terms: ["qr", "modula code"]),
            item(.family(.root), "Family", "Shared plans and parental controls", "figure.2.and.child.holdinghands", .capabilityUnavailable, terms: ["family", "parental"], reason: "No verified Family Sharing contract in native."),
            item(.timeUnits(.root), "Time & Units", "Clocks and measurement", "clock", .implemented, terms: ["time", "units", "metric", "24-hour"]),
            item(.keyboard(.root), "Keyboard", "Typing shortcuts in Modula", "keyboard", .implemented, terms: ["keyboard", "typing"]),
            item(.connectors(.root), "Connectors", "Link external accounts", "link", .capabilityUnavailable, terms: ["connectors", "oauth", "link account"], reason: "No verified Greenfield OAuth connector contract is wired in this native client."),
            item(.integrations(.root), "Integrations", "Extend Modula with services", "puzzlepiece.extension", .capabilityUnavailable, terms: ["integrations", "third party"], reason: "Integrations are distinct from Profile social connections and are not available yet. No verified integration catalog is present."),
            item(.monetisation(.root), "Monetisation", "Plans, payouts and invoices", "creditcard", .capabilityUnavailable, terms: ["monetisation", "monetization", "billing", "subscription", "wallet"], reason: "No verified billing or subscription contract is wired. Native will not invent plans or prices."),
            item(.monetisation(.plans), "Plans", "Subscription tiers", "rectangle.stack", .capabilityUnavailable, terms: ["plans"], reason: "Plan names and prices are illustrative placeholders only — not offered for purchase."),
            item(.monetisation(.payouts), "Payouts", "Creator balance", "banknote", .capabilityUnavailable, terms: ["payouts"], reason: "Balance stays blank until a verified payouts API exists."),
            item(.monetisation(.invoices), "Invoices", "Billing history", "doc.richtext", .capabilityUnavailable, terms: ["invoices"], reason: "Invoice list is empty until StoreKit / Greenfield billing is verified."),
            item(.notifications(.root), "Notifications", "Push, social and modules", "bell", .implemented, terms: ["notifications"]),
            item(.notifications(.push), "Push", "iOS authorization state", "iphone.radiowaves.left.and.right", .implemented, terms: ["push", "alerts"]),
            item(.notifications(.social), "Social Notifications", "Reactions, comments, follows", "heart", .capabilityUnavailable, terms: ["reactions", "comments", "follows", "mentions", "messages"], reason: "GET/PATCH /v1/accounts/me/notification-preferences is documented, but live VPS verification is OPEN. Native does not persist speculative categories."),
            item(.notifications(.modules), "Module Notifications", "Updates and module activity", "shippingbox", .capabilityUnavailable, terms: ["module alerts"], reason: "No verified module-notification preference contract is wired in this client."),
            item(.notifications(.quietHours), "Quiet Hours", "Do not disturb window", "moon.zzz", .capabilityUnavailable, terms: ["quiet hours", "dnd"], reason: "Notification delivery cannot honor quiet hours until a dispatcher exists."),
            item(.privacy(.root), "Privacy & Security", "App Lock, biometrics and blocked accounts", "lock.shield", .implemented, terms: ["privacy", "security", "face id", "app lock"]),
            item(.privacy(.privacy), "Privacy", "Profile visibility and data", "hand.raised", .implemented, terms: ["visibility"]),
            item(.privacy(.security), "Security", "Account and device security", "lock", .implemented, terms: ["security"]),
            item(.privacy(.glassPrivacy), "Glass Privacy", "Conversation privacy levels", "bubble.left.and.bubble.right", .capabilityUnavailable, terms: ["protected chat", "vault chat", "glass"], reason: "Protected Chat / Vault Chat are not cryptographically complete. This screen stays capability-aware."),
            item(.privacy(.blocked), "Blocked Accounts", "People you’ve blocked", "nosign", .capabilityUnavailable, terms: ["blocked", "block list"], reason: "Greenfield block mutations exist on posts, but a verified block-list endpoint is not available in native DTOs this run."),
            item(.privacy(.appLock), "App Lock", "Passcode lock for this device", "lock.fill", .implemented, terms: ["app lock", "passcode", "pin"]),
            item(.privacy(.biometrics), "Face ID & Biometrics", "Unlock with Face ID or Touch ID", "faceid", .implemented, terms: ["face id", "touch id", "biometrics"]),
            item(.modules(.root), "Modules", "Installed modules and permissions", "shippingbox", .implemented, terms: ["modules"]),
            item(.modules(.installed), "Installed Modules", "Modules on this account", "arrow.down.circle", .implemented, terms: ["installed"]),
            item(.modules(.updates), "Module Updates", "Catalogue versions", "arrow.triangle.2.circlepath", .implemented, terms: ["updates"]),
            item(.modules(.autoUpdates), "Auto Updates", "Module auto-update policy", "arrow.clockwise", .capabilityUnavailable, terms: ["auto updates"], reason: "No verified auto-update preference contract is present. App Store binary updates are not user-toggleable here."),
            item(.modules(.permissions), "Module Permissions", "HostBridge grants", "switch.2", .implemented, terms: ["permissions"]),
            item(.dataStorage(.root), "Data & Storage", "Cache, downloads, backup and export", "internaldrive", .implemented, terms: ["storage", "cache"]),
            item(.dataStorage(.storage), "Storage", "Measured local usage", "externaldrive", .implemented, terms: ["storage", "mb"]),
            item(.dataStorage(.cache), "Cache", "Clear rebuildable cache", "xmark.bin", .implemented, terms: ["cache", "clear"]),
            item(.dataStorage(.downloads), "Downloads", "Downloaded content", "arrow.down.to.line", .implemented, terms: ["downloads"]),
            item(.dataStorage(.backup), "Backup", "Account or module backup", "arrow.clockwise.icloud", .capabilityUnavailable, terms: ["backup"], reason: "Backup is not available for this data yet. No Greenfield backup workflow is verified."),
            item(.dataStorage(.export), "Export", "Account data export", "square.and.arrow.up", .capabilityUnavailable, terms: ["export"], reason: "No verified complete account-export contract is wired. Native will not generate an incomplete archive and label it complete."),
            item(.accessibility(.root), "Accessibility", "Complements system accessibility", "accessibility", .implemented, terms: ["accessibility", "voiceover"]),
            item(.accessibility(.text), "Text", "Uses system Dynamic Type", "textformat.size", .implemented, terms: ["dynamic type", "text"]),
            item(.accessibility(.contrast), "Contrast", "Follows system and appearance", "circle.righthalf.filled", .implemented, terms: ["contrast"]),
            item(.accessibility(.motion), "Motion", "Reduce Motion stays with the system", "figure.walk.motion", .implemented, terms: ["reduce motion"]),
            item(.features(.root), "Features", "Typed feature registry", "switch.2", .implemented, terms: ["features", "flags"]),
            item(.features(.enabled), "Enabled Features", "Shipped capabilities", "checkmark.seal", .implemented, terms: ["enabled"]),
            item(.features(.experimental), "Experimental Features", "Explicitly exposed experiments", "flask", .implemented, terms: ["experimental", "labs"]),
            item(.updates(.root), "Updates", "Distribution channel truth", "arrow.triangle.2.circlepath", .implemented, terms: ["updates", "version"]),
            item(.updates(.channel), "Update Channel", "App Store or TestFlight", "antenna.radiowaves.left.and.right", .implemented, terms: ["channel", "testflight", "app store"]),
            item(.updates(.stable), "Stable Channel", "App Store release", "checkmark.seal", .implemented, terms: ["stable"]),
            item(.updates(.unstable), "Unstable Channel", "Internal / TestFlight", "hammer", .developerOnly, terms: ["unstable"]),
            item(.updates(.versionLock), "Version Lock", "Module version policy", "lock.rotation", .implemented, terms: ["version lock"]),
            item(.developer(.root), "Developer", "Runtime and diagnostics", "hammer", .developerOnly, terms: ["developer"]),
            item(.developer(.runtime), "Runtime", "Hermes and native diagnostics", "memorychip", .developerOnly, terms: ["runtime"]),
            item(.developer(.modules), "Developer Modules", "Installed runtime modules", "shippingbox", .developerOnly, terms: ["modules"]),
            item(.developer(.network), "Network", "API origin without secrets", "network", .developerOnly, terms: ["network", "api"]),
            item(.developer(.featureFlags), "Feature Flags", "Internal flags", "flag", .developerOnly, terms: ["flags"]),
            item(.developer(.environment), "Environment", "Build configuration", "gearshape.2", .developerOnly, terms: ["environment"]),
            item(.developer(.components), "Components", "Visual catalog", "square.grid.3x3", .developerOnly, terms: ["catalog"]),
            item(.developer(.diagnostics), "Diagnostics", "Runtime evidence", "stethoscope", .developerOnly, terms: ["diagnostics"]),
            item(.developer(.intelligence), "Local Intelligence", "Native intelligence diagnostics", "brain", .developerOnly, terms: ["intelligence", "ai", "local"]),
            item(.developer(.nodusChat), "Nodus Chat", "Local Nodus conversation testing", "bubble.left.and.bubble.right", .developerOnly, terms: ["nodus", "chat", "intelligence"]),
            item(.about(.root), "About", "Version, licenses and legal", "info.circle", .implemented, terms: ["about"]),
            item(.about(.version), "Version", "Bundle version and build", "number", .implemented, terms: ["version", "build"]),
            item(.about(.licenses), "Licenses", "Third-party notices", "doc.plaintext", .implemented, terms: ["licenses", "oss"]),
            item(.about(.privacy), "Privacy Policy", "modula.digital/privacy", "hand.raised", .implemented, terms: ["privacy policy"]),
            item(.about(.terms), "Terms", "modula.digital/terms", "doc.text", .implemented, terms: ["terms"])
        ]
    }
}

struct FeatureFlag: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let exposedToProduction: Bool
    let enabled: Bool
}

enum FeatureFlagRegistry {
    static let all: [FeatureFlag] = [
        .init(id: "shell.native", title: "Native shell", detail: "SwiftUI shell is the product surface.", exposedToProduction: true, enabled: true),
        .init(id: "post.like", title: "Post likes", detail: "Like toggle against Greenfield.", exposedToProduction: true, enabled: true),
        .init(id: "reactions.v2", title: "Multi-reactions", detail: "Capability-gated until Greenfield reaction types are verified.", exposedToProduction: false, enabled: false),
        .init(id: "app.lock", title: "App Lock", detail: "Local passcode and biometrics.", exposedToProduction: true, enabled: true),
        .init(id: "command.center", title: "Command Center", detail: "Native command palette.", exposedToProduction: true, enabled: true)
    ]

    static var productionVisible: [FeatureFlag] { all.filter(\.exposedToProduction) }
    static var experimentalVisible: [FeatureFlag] { all.filter { $0.exposedToProduction == false } }
}
