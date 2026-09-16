import Foundation

/// Builds the native typed command catalogue from capabilities. No arbitrary closures.
enum CommandRegistry {
    static func commands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        var items: [ModulaCommand] = []
        items.append(contentsOf: navigateCommands())
        items.append(contentsOf: createCommands(capabilities: capabilities))
        items.append(contentsOf: openCommands(capabilities: capabilities))
        items.append(contentsOf: settingsCommands(capabilities: capabilities))
        items.append(contentsOf: libraryCommands(capabilities: capabilities))
        items.append(contentsOf: searchCommands())
        items.append(contentsOf: moduleCommands(capabilities: capabilities))
        if capabilities.developerMode {
            items.append(contentsOf: developerCommands())
        }
        return deduplicate(items)
    }

    static func visible(
        capabilities: CommandCapabilitySnapshot,
        includeUnavailableInDeveloper: Bool = false
    ) -> [ModulaCommand] {
        commands(capabilities: capabilities).filter { command in
            switch command.availability {
            case .available:
                return true
            case .requiresSignIn:
                return capabilities.signedIn
            case .developerOnly:
                return capabilities.developerMode
            case .unavailable:
                return includeUnavailableInDeveloper && capabilities.developerMode
            }
        }
    }

    static func contextualSuggestions(
        context: CommandContext,
        capabilities: CommandCapabilitySnapshot
    ) -> [ModulaCommand] {
        let all = Dictionary(uniqueKeysWithValues: visible(capabilities: capabilities).map { ($0.id, $0) })
        let ids: [CommandID]
        switch context {
        case .home:
            ids = ["create.post", "navigate.home", "open.activity", "create.picker"]
        case .discover:
            ids = ["search.modula", "navigate.discover", "open.product-hub"]
        case .modules:
            ids = ["search.modules", "open.product-hub.installed", "open.product-hub"]
        case .activity:
            ids = ["navigate.activity", "open.notifications.settings"]
        case .profile:
            ids = ["manage.edit-profile", "share.profile", "open.saved", "open.drafts"]
        case .settings:
            ids = ["settings.appearance", "settings.account", "settings.root"]
        case .messages:
            ids = ["open.messages", "create.message", "create.in-mail"]
        case .global:
            ids = ["create.post", "navigate.home", "open.product-hub", "settings.appearance"]
        }
        return ids.compactMap { all[$0] }
    }

    static func emptyQuerySections(
        context: CommandContext,
        capabilities: CommandCapabilitySnapshot,
        recentIDs: [CommandID]
    ) -> [CommandSectionModel] {
        let visible = visible(capabilities: capabilities)
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var sections: [CommandSectionModel] = []

        let recent = recentIDs.compactMap { byID[$0] }
        if !recent.isEmpty {
            sections.append(.init(id: "recent", title: "Recent", commands: Array(recent.prefix(6))))
        }

        let contextual = contextualSuggestions(context: context, capabilities: capabilities)
            .filter { command in !recent.contains(where: { $0.id == command.id }) }
        if !contextual.isEmpty {
            sections.append(.init(id: "suggested", title: "Suggested", commands: Array(contextual.prefix(4))))
        }

        let create = visible.filter { $0.category == .create }
        if !create.isEmpty {
            sections.append(.init(id: "create", title: "Create", commands: Array(create.prefix(6))))
        }

        let navigate = visible.filter { $0.category == .navigate }
        if !navigate.isEmpty {
            sections.append(.init(id: "navigate", title: "Navigate", commands: Array(navigate.prefix(6))))
        }

        let modules = visible.filter {
            if case .moduleOpen = $0.action { return true }
            return $0.id.rawValue.hasPrefix("module.")
        }
        if !modules.isEmpty {
            sections.append(.init(id: "modules", title: "Modules", commands: Array(modules.prefix(6))))
        }

        return sections
    }

    // MARK: - Builders

    private static func navigateCommands() -> [ModulaCommand] {
        [
            .init(
                id: "navigate.home",
                title: "Go to Home",
                subtitle: "Following feed",
                icon: .init("house"),
                category: .navigate,
                action: .routeOpen(.home(.following)),
                aliases: ["feed", "timeline"],
                accessibilityHint: "Opens the Home tab"
            ),
            .init(
                id: "navigate.discover",
                title: "Open Discover",
                icon: .init("safari"),
                category: .navigate,
                action: .routeOpen(.discover(.trending)),
                aliases: ["explore", "trending"],
                accessibilityHint: "Opens Discover"
            ),
            .init(
                id: "navigate.activity",
                title: "Go to Activity",
                icon: .init("bell"),
                category: .navigate,
                action: .routeOpen(.activity(.all)),
                aliases: ["notifications", "alerts"],
                accessibilityHint: "Opens Activity"
            ),
            .init(
                id: "navigate.profile",
                title: "Open My Profile",
                icon: .init("person.crop.circle"),
                category: .navigate,
                action: .routeOpen(.me(.overview)),
                aliases: ["me", "account profile"],
                accessibilityHint: "Opens your profile"
            ),
            .init(
                id: "open.product-hub",
                title: "Open Product Hub",
                subtitle: "Modules and products",
                icon: .init("shippingbox"),
                category: .navigate,
                action: .routeOpen(.productHub(.featured)),
                aliases: ["modules", "store", "marketplace", "hub"],
                accessibilityHint: "Opens Product Hub"
            )
        ]
    }

    private static func createCommands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        var items: [ModulaCommand] = [
            .init(
                id: "create.picker",
                title: "Create",
                subtitle: "Choose what to create",
                icon: .init("plus.circle"),
                category: .create,
                action: .createPicker,
                aliases: ["new", "compose"],
                accessibilityHint: "Opens the create picker"
            )
        ]
        if capabilities.postCompose {
            items.append(.init(
                id: "create.post",
                title: "Create Post",
                icon: .init("square.and.pencil"),
                category: .create,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.post),
                aliases: ["write", "post", "compose post"],
                accessibilityHint: "Opens the post composer"
            ))
        }
        if capabilities.photoCompose {
            items.append(.init(
                id: "create.photo",
                title: "Create Photo Post",
                icon: .init("photo"),
                category: .create,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.photo),
                aliases: ["photo", "image"],
                accessibilityHint: "Opens the photo composer"
            ))
        }
        if capabilities.pollCompose {
            items.append(.init(
                id: "create.poll",
                title: "Create Poll",
                icon: .init("chart.bar.doc.horizontal"),
                category: .create,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.poll),
                aliases: ["poll"],
                accessibilityHint: "Opens the poll composer"
            ))
        }
        if capabilities.storyCreate {
            items.append(.init(
                id: "create.story",
                title: "Create Story",
                icon: .init("circle.dashed"),
                category: .create,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .routeOpen(.stories(.create)),
                aliases: ["story"],
                accessibilityHint: "Opens story creation"
            ))
        }
        // Messaging send gated — navigation to inbox may still exist separately.
        if capabilities.messagingSend || capabilities.messagingInbox {
            items.append(.init(
                id: "create.message",
                title: "New Message",
                icon: .init("bubble.left.and.bubble.right"),
                category: .create,
                availability: capabilities.messagingSend
                    ? (capabilities.signedIn ? .available : .requiresSignIn)
                    : .unavailable,
                action: .routeOpen(.messages(.new)),
                aliases: ["dm", "chat", "message"],
                accessibilityHint: "Starts a new message"
            ))
        }
        if capabilities.inMailCompose || capabilities.inMailInbox {
            items.append(.init(
                id: "create.in-mail",
                title: "New In-Mail",
                icon: .init("envelope"),
                category: .create,
                availability: capabilities.inMailCompose
                    ? (capabilities.signedIn ? .available : .requiresSignIn)
                    : .unavailable,
                action: .routeOpen(.messages(.inMail(.compose))),
                aliases: ["inmail", "mail", "letter"],
                accessibilityHint: "Opens In-Mail composer"
            ))
        }
        return items
    }

    private static func openCommands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        var items: [ModulaCommand] = [
            .init(
                id: "open.messages",
                title: "Open Messages",
                icon: .init("bubble.left.and.bubble.right"),
                category: .open,
                availability: capabilities.messagingInbox ? .available : .unavailable,
                action: .routeOpen(.messages(.inbox)),
                aliases: ["inbox", "chat", "dm"],
                accessibilityHint: "Opens Messages"
            ),
            .init(
                id: "open.in-mail",
                title: "Open In-Mail",
                icon: .init("envelope"),
                category: .open,
                availability: capabilities.inMailInbox ? .available : .unavailable,
                action: .routeOpen(.messages(.inMail(.inbox))),
                aliases: ["mail inbox"],
                accessibilityHint: "Opens In-Mail inbox"
            ),
            .init(
                id: "open.product-hub.installed",
                title: "Installed Modules",
                icon: .init("checkmark.circle"),
                category: .open,
                action: .routeOpen(.productHub(.collection(.installed))),
                aliases: ["installed"],
                accessibilityHint: "Opens installed modules"
            ),
            .init(
                id: "open.stories",
                title: "View Stories",
                icon: .init("circle.dashed"),
                category: .open,
                availability: .unavailable,
                action: .routeOpen(.stories(.root)),
                aliases: ["stories"],
                accessibilityHint: "Opens Stories"
            ),
            .init(
                id: "open.reels",
                title: "Reels",
                icon: .init("play.rectangle"),
                category: .open,
                availability: .unavailable,
                action: .routeOpen(.reels(.feed)),
                aliases: ["shorts"],
                accessibilityHint: "Opens Reels"
            )
        ]
        return items
    }

    private static func settingsCommands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        var items = SettingsRegistry.commands(signedIn: capabilities.signedIn, developerMode: capabilities.developerMode)
        items.append(.init(
            id: "manage.edit-profile",
            title: "Edit Profile",
            icon: .init("pencil"),
            category: .manage,
            availability: capabilities.signedIn ? .available : .requiresSignIn,
            action: .routeOpen(.me(.edit)),
            accessibilityHint: "Opens profile editing"
        ))
        items.append(.init(
            id: "open.notifications.settings",
            title: "Notification Settings",
            icon: .init("bell.badge"),
            category: .manage,
            action: .settingsOpen(.notifications(.root))
        ))
        return items
    }

    private static func libraryCommands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        [
            .init(
                id: "open.saved",
                title: "View Saved",
                subtitle: "Bookmarked content",
                icon: .init("bookmark"),
                category: .open,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .routeOpen(.saved(.root)),
                aliases: ["bookmarks", "saved posts"],
                accessibilityHint: "Opens Saved"
            ),
            .init(
                id: "open.collections",
                title: "Collections",
                icon: .init("rectangle.stack"),
                category: .open,
                availability: capabilities.collectionsLocal ? .available : .unavailable,
                action: .collectionOpen(collectionID: nil),
                aliases: ["folders", "albums"],
                accessibilityHint: "Opens Collections"
            ),
            .init(
                id: "open.drafts",
                title: "View Drafts",
                icon: .init("doc.text"),
                category: .open,
                availability: capabilities.drafts ? .available : .unavailable,
                action: .routeOpen(.drafts(.root)),
                aliases: ["unfinished"],
                accessibilityHint: "Opens Drafts"
            ),
            .init(
                id: "share.profile",
                title: "Share Profile",
                icon: .init("square.and.arrow.up"),
                category: .share,
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .shareStart(.profile("me")),
                accessibilityHint: "Shares your profile"
            )
        ]
    }

    private static func searchCommands() -> [ModulaCommand] {
        [
            .init(
                id: "search.modula",
                title: "Search Modula",
                icon: .init("magnifyingglass"),
                category: .search,
                action: .searchStart(query: nil),
                aliases: ["find", "lookup"],
                accessibilityHint: "Opens Search"
            ),
            .init(
                id: "search.modules",
                title: "Search Modules",
                icon: .init("magnifyingglass"),
                category: .search,
                action: .routeOpen(.productHub(.search(nil))),
                aliases: ["find modules"],
                accessibilityHint: "Searches Product Hub"
            )
        ]
    }

    private static func moduleCommands(capabilities: CommandCapabilitySnapshot) -> [ModulaCommand] {
        // Only trusted installed modules with known open routes.
        var items: [ModulaCommand] = []
        let vaultID = "digital.modula.vault-notes"
        if capabilities.installedModuleIDs.contains(vaultID) {
            items.append(.init(
                id: "module.vault-notes.open",
                title: "Open Vault Notes",
                subtitle: "Installed module",
                icon: .init("lock.doc"),
                category: .open,
                action: .moduleOpen(moduleID: vaultID, localPath: nil),
                aliases: ["vault", "notes", "vault notes"],
                accessibilityHint: "Opens the Vault Notes module"
            ))
            items.append(.init(
                id: "module.vault-notes.hub",
                title: "View Vault Notes in Product Hub",
                subtitle: "Product page",
                icon: .init("shippingbox"),
                category: .open,
                action: .routeOpen(.productHub(.module(vaultID, .overview))),
                aliases: ["vault product"],
                accessibilityHint: "Opens Vault Notes product information"
            ))
        }
        return items
    }

    private static func developerCommands() -> [ModulaCommand] {
        [
            .init(
                id: "developer.components",
                title: "Component Catalog",
                icon: .init("square.grid.3x3"),
                category: .developer,
                availability: .developerOnly,
                action: .routeOpen(.developer(.components)),
                accessibilityHint: "Opens the developer component catalog"
            ),
            .init(
                id: "developer.runtime",
                title: "Runtime Diagnostics",
                icon: .init("gauge.with.dots.needle.67percent"),
                category: .developer,
                availability: .developerOnly,
                action: .settingsOpen(.developer(.runtime))
            )
        ]
    }

    private static func deduplicate(_ items: [ModulaCommand]) -> [ModulaCommand] {
        var seen = Set<CommandID>()
        var result: [ModulaCommand] = []
        for item in items {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }
}
