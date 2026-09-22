import Foundation

/// Stable command identity. Never encode sensitive content into IDs.
struct CommandID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }
}

enum CommandCategory: String, CaseIterable, Sendable, Codable, Hashable {
    case navigate
    case create
    case open
    case search
    case manage
    case share
    case developer
}

enum CommandAvailability: String, Sendable, Codable, Hashable {
    case available
    /// Hidden from normal Command Center; developer diagnostics only.
    case unavailable
    case requiresSignIn
    case developerOnly
}

/// Semantic icon token — SF Symbol name under the hood, not a free-form UI callback.
struct SemanticIcon: Hashable, Sendable, Codable {
    let systemName: String
    init(_ systemName: String) { self.systemName = systemName }
}

/// Typed actions only. No downloaded closures. No arbitrary module code.
enum CommandAction: Hashable, Sendable {
    case routeOpen(AppRoute)
    case moduleOpen(moduleID: String, localPath: String?)
    case composeStart(ComposeRoute)
    case searchStart(query: String?)
    case shareStart(SharePayloadRef)
    case settingsOpen(SettingsRoute)
    case collectionOpen(collectionID: String?)
    case createPicker
    case presentCommand
    case presentIntelligenceChat
    case functionInvoke(name: String, parameters: [String: String])
}

/// Lightweight share reference for commands (full payloads live in Core/Sharing).
enum SharePayloadRef: Hashable, Sendable {
    case profile(String)
    case post(String)
    case module(String)
    case link(String)
}

struct ModulaCommand: Identifiable, Sendable, Hashable {
    let id: CommandID
    let title: String
    let subtitle: String?
    let icon: SemanticIcon
    let category: CommandCategory
    let availability: CommandAvailability
    let action: CommandAction
    /// Internal synonyms for deterministic matching. Not shown as primary titles.
    let aliases: [String]
    /// Accessibility hint describing what the command does.
    let accessibilityHint: String?

    init(
        id: CommandID,
        title: String,
        subtitle: String? = nil,
        icon: SemanticIcon,
        category: CommandCategory,
        availability: CommandAvailability = .available,
        action: CommandAction,
        aliases: [String] = [],
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.availability = availability
        self.action = action
        self.aliases = aliases
        self.accessibilityHint = accessibilityHint
    }
}

enum CommandContext: String, Sendable, Hashable {
    case home
    case discover
    case modules
    case activity
    case profile
    case settings
    case messages
    case global
}

struct CommandMatch: Identifiable, Sendable, Hashable {
    let command: ModulaCommand
    let score: Int
    var id: CommandID { command.id }
}

struct CommandSectionModel: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let commands: [ModulaCommand]
}

/// Capability snapshot used when building the registry. Keeps commands honest.
struct CommandCapabilitySnapshot: Sendable, Equatable {
    var signedIn = false
    var developerMode = false
    var postCompose = true
    var photoCompose = false
    var pollCompose = false
    var storyCreate = false
    var messagingSend = false
    var messagingInbox = true
    var inMailCompose = false
    var inMailInbox = true
    var savedList = false
    var collectionsLocal = true
    var drafts = true
    var installedModuleIDs: Set<String> = []
}
