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
        case .root, .account(.root), .appearance(.root), .notifications(.root), .privacy(.root),
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
