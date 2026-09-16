import SwiftUI
import UIKit
import CoreSpotlight

@main
struct ModulaApp: App {
    @UIApplicationDelegateAdaptor(ModulaAppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            // N4D: shortcuts/⌘K land before AppGate (N4E). Still roots RootView.
            RootView()
                .environment(environment)
                .tint(environment.appearance.accent.color)
                .preferredColorScheme(environment.appearance.colorScheme)
                .onAppear {
                    appDelegate.environment = environment
                    environment.refreshQuickActions()
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    handleSpotlight(id)
                }
        }
        .commands {
            ModulaKeyboardCommands(
                openCommandCenter: {
                    environment.navigation.presented = .commandCenter
                    HapticEngine.shared.play(.contextOpen)
                },
                openCreate: {
                    environment.navigation.presented = .createPicker
                },
                openSearch: {
                    environment.navigation.open(.search(.root(nil)))
                }
            )
        }
    }

    private func handleSpotlight(_ identifier: String) {
        if identifier.hasPrefix("module:") {
            let moduleID = String(identifier.dropFirst("module:".count))
            guard environment.catalogue.installedIDs.contains(moduleID) else { return }
            environment.navigation.open(.module(moduleID, localPath: nil))
        } else if identifier.hasPrefix("settings:") {
            let key = String(identifier.dropFirst("settings:".count))
            switch key {
            case "appearance": environment.navigation.open(.settings(.appearance(.root)))
            case "notifications": environment.navigation.open(.settings(.notifications(.root)))
            case "privacy": environment.navigation.open(.settings(.privacy(.root)))
            case "accessibility": environment.navigation.open(.settings(.accessibility(.root)))
            default: environment.navigation.open(.settings(.root))
            }
        }
    }
}

final class ModulaAppDelegate: NSObject, UIApplicationDelegate {
    weak var environment: AppEnvironment?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            pendingShortcut = shortcut
        }
        return true
    }

    private var pendingShortcut: UIApplicationShortcutItem?

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    func consumePendingShortcutIfNeeded() {
        guard let pendingShortcut else { return }
        _ = handle(pendingShortcut)
        self.pendingShortcut = nil
    }

    private func handle(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard let environment else { return false }
        return QuickActionRouter.handle(
            shortcut,
            navigation: environment.navigation,
            signedIn: environment.auth.isSignedIn,
            capabilities: environment.commandCapabilities()
        ) { presentation in
            environment.navigation.presented = presentation
        }
    }
}
