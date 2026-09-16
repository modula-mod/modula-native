import UIKit

/// Home Screen Quick Actions map into typed Modula commands — no second deep-link parser.
enum QuickActionID: String, CaseIterable, Sendable {
    case createPost = "digital.modula.shortcut.create-post"
    case messages = "digital.modula.shortcut.messages"
    case search = "digital.modula.shortcut.search"
    case vaultNotes = "digital.modula.shortcut.vault-notes"
    case command = "digital.modula.shortcut.command"
}

enum QuickActionMapper {
    static func commandID(forShortcutType type: String) -> CommandID? {
        switch QuickActionID(rawValue: type) {
        case .createPost: CommandID(rawValue: "create.post")
        case .messages: CommandID(rawValue: "open.messages")
        case .search: CommandID(rawValue: "search.modula")
        case .vaultNotes: CommandID(rawValue: "module.vault-notes.open")
        case .command: CommandID(rawValue: "present.command")
        case .none: nil
        }
    }

    static func shortcutItems(capabilities: CommandCapabilitySnapshot) -> [UIApplicationShortcutItem] {
        var items: [UIApplicationShortcutItem] = [
            UIApplicationShortcutItem(
                type: QuickActionID.createPost.rawValue,
                localizedTitle: "Create Post",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: QuickActionID.search.rawValue,
                localizedTitle: "Search Modula",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: QuickActionID.command.rawValue,
                localizedTitle: "Command Center",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "command"),
                userInfo: nil
            )
        ]
        if capabilities.messagingInbox {
            items.insert(
                UIApplicationShortcutItem(
                    type: QuickActionID.messages.rawValue,
                    localizedTitle: "Messages",
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right"),
                    userInfo: nil
                ),
                at: 1
            )
        }
        if capabilities.installedModuleIDs.contains("digital.modula.vault-notes") {
            items.append(
                UIApplicationShortcutItem(
                    type: QuickActionID.vaultNotes.rawValue,
                    localizedTitle: "Open Vault Notes",
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "lock.doc"),
                    userInfo: nil
                )
            )
        }
        return items
    }
}

@MainActor
enum QuickActionRouter {
    /// Returns false for unknown shortcut types (fails safely).
    static func handle(
        _ shortcut: UIApplicationShortcutItem,
        navigation: NavigationCoordinator,
        signedIn: Bool,
        capabilities: CommandCapabilitySnapshot,
        present: (AppPresentation) -> Void
    ) -> Bool {
        guard let commandID = QuickActionMapper.commandID(forShortcutType: shortcut.type) else {
            return false
        }
        if commandID.rawValue == "present.command" {
            present(.commandCenter)
            return true
        }
        let commands = CommandRegistry.commands(capabilities: capabilities)
        guard let command = commands.first(where: { $0.id == commandID }) else {
            return false
        }
        switch CommandExecutor.execute(command, navigation: navigation, signedIn: signedIn, present: present) {
        case .executed, .requiresSignIn:
            return true
        case .unavailable, .unsupported:
            return false
        }
    }
}
