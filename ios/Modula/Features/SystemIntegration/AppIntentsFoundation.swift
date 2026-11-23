import AppIntents
import Foundation

/// App Intents foundation. Opens routes via typed commands — never publishes content silently,
/// never bypasses authentication or ModuleHost permissions.
@available(iOS 16.0, *)
enum ModulaAppIntentBridge {
    static func route(for intentIdentifier: String, parameter: String?) -> AppRoute? {
        switch intentIdentifier {
        case "open.modula":
            return .home(.following)
        case "open.messages":
            return .messages(.inbox)
        case "create.post":
            return .compose(.post)
        case "search.modula":
            return .search(.root(parameter))
        case "open.module":
            guard let parameter, RouteParser.validID(parameter) else { return nil }
            return .module(parameter, localPath: nil)
        case "open.command":
            return .command
        default:
            return nil
        }
    }

    /// Module open only when installed. Host still enforces N1 ModuleHost rules.
    static func canOpenModule(id: String, installed: Set<String>, signedIn: Bool) -> Bool {
        signedIn && installed.contains(id) && RouteParser.validID(id)
    }
}

@available(iOS 16.0, *)
struct OpenModulaIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Modula" }
    static var description: IntentDescription { IntentDescription("Opens the Modula app.") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct CreatePostIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Post" }
    static var description: IntentDescription { IntentDescription("Opens the Modula post composer. Does not publish.") }
    static var openAppWhenRun: Bool { true }

    // Enhancements-50: actually route instead of only opening the app.
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.compose(.post))
        return .result()
    }
}

@available(iOS 16.0, *)
struct SearchModulaIntent: AppIntent {
    static var title: LocalizedStringResource { "Search Modula" }
    static var description: IntentDescription { IntentDescription("Opens Modula Search.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Query")
    var query: String?

    // Enhancements-50: actually route instead of only opening the app.
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.search(.root(query)))
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenMessagesIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Messages" }
    static var description: IntentDescription { IntentDescription("Opens Modula Messages.") }
    static var openAppWhenRun: Bool { true }

    // Enhancements-50: actually route instead of only opening the app.
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.messages(.inbox))
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenVaultNotesIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Vault Notes" }
    static var description: IntentDescription { IntentDescription("Opens the installed Vault Notes module via ModuleHost.") }
    static var openAppWhenRun: Bool { true }

    // Enhancements-50: actually route instead of only opening the app.
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.module("digital.modula.vault-notes", localPath: nil))
        return .result()
    }
}

@available(iOS 16.0, *)
struct ModulaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenModulaIntent(),
            phrases: ["Open \(.applicationName)", "Launch \(.applicationName)"],
            shortTitle: "Open Modula",
            systemImageName: "m.circle"
        )
        AppShortcut(
            intent: CreatePostIntent(),
            phrases: ["Create a post in \(.applicationName)", "New post in \(.applicationName)"],
            shortTitle: "Create Post",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SearchModulaIntent(),
            phrases: ["Search \(.applicationName)", "Find in \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenMessagesIntent(),
            phrases: ["Open messages in \(.applicationName)"],
            shortTitle: "Messages",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: OpenVaultNotesIntent(),
            phrases: ["Open Vault Notes in \(.applicationName)"],
            shortTitle: "Vault Notes",
            systemImageName: "lock.doc"
        )
    }
}
