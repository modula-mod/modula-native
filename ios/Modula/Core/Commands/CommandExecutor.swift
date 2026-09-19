import Foundation

/// Executes typed command actions through NavigationCoordinator. No arbitrary code paths.
@MainActor
enum CommandExecutor {
    enum Outcome: Equatable {
        case executed
        case requiresSignIn(AppRoute)
        case unavailable
        case unsupported
    }

    static func execute(
        _ command: ModulaCommand,
        navigation: NavigationCoordinator,
        signedIn: Bool,
        present: (AppPresentation) -> Void
    ) -> Outcome {
        switch command.availability {
        case .unavailable:
            return .unavailable
        case .requiresSignIn where !signedIn:
            return .requiresSignIn(routeForSignInReturn(command.action) ?? .command)
        case .developerOnly, .available, .requiresSignIn:
            break
        }
        return perform(command.action, navigation: navigation, present: present)
    }

    static func perform(
        _ action: CommandAction,
        navigation: NavigationCoordinator,
        present: (AppPresentation) -> Void
    ) -> Outcome {
        switch action {
        case .routeOpen(let route):
            navigation.open(route)
            return .executed
        case .moduleOpen(let moduleID, let localPath):
            // Native ModuleHost only — never grants shell privileges to module code.
            navigation.open(.module(moduleID, localPath: localPath))
            return .executed
        case .composeStart(let route):
            present(.composer(route))
            return .executed
        case .searchStart(let query):
            navigation.open(.search(.root(query)))
            return .executed
        case .shareStart(let ref):
            present(.universalShare(SharePayload.from(ref)))
            return .executed
        case .settingsOpen(let route):
            navigation.open(.settings(route))
            return .executed
        case .collectionOpen(let id):
            if let id {
                navigation.open(.collections(.collection(id)))
            } else {
                navigation.open(.collections(.root))
            }
            return .executed
        case .createPicker:
            present(.createPicker)
            return .executed
        case .presentCommand:
            present(.commandCenter)
            return .executed
        case .functionInvoke:
            // Reserved for future module action architecture. Disabled in N4D.
            return .unsupported
        }
    }

    private static func routeForSignInReturn(_ action: CommandAction) -> AppRoute? {
        switch action {
        case .routeOpen(let route): route
        case .composeStart(let route): .compose(route)
        case .settingsOpen(let route): .settings(route)
        case .moduleOpen(let id, let path): .module(id, localPath: path)
        case .searchStart(let q): .search(.root(q))
        case .collectionOpen(let id):
            id.map { .collections(.collection($0)) } ?? .collections(.root)
        default: .command
        }
    }
}
