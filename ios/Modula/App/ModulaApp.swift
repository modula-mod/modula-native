import SwiftUI
import UIKit
import CoreSpotlight
import UserNotifications

@main
struct ModulaApp: App {
    @UIApplicationDelegateAdaptor(ModulaAppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppGateHost()
                .environment(environment)
                .tint(environment.appearance.liveAccent)
                .preferredColorScheme(environment.appearance.colorScheme)
                // Web links anywhere in the app open in the Modula browser (Settings → Links).
                .environment(\.openURL, OpenURLAction { url in ModulaLinkRouter.handle(url, source: nil) })
                .onAppear {
                    #if DEBUG
                    MainThreadHangWatchdog.start()
                    #endif
                    ModulaBrowserPresenter.shared.environment = environment
                    appDelegate.environment = environment
                    environment.refreshQuickActions()
                }
                #if DEBUG
                .task {
                    guard let url = DebugSettingsHarness.browserURL else { return }
                    try? await Task.sleep(for: .seconds(2))
                    var source: ModulaBrowserSource?
                    if let id = DebugSettingsHarness.browserPostID,
                       let post = try? await GreenfieldPostRepository(client: environment.client).post(id: id) {
                        source = ModulaBrowserSource(post: post, onLike: {}, onComment: {}, onRepost: {}, onSave: {}, onShare: nil)
                    }
                    ModulaBrowserPresenter.shared.present(url, source: source)
                }
                .modifier(MOL01DebugCover())
                .modifier(MOL01StudioCover())
                .modifier(MOL03StudioCover(environment: environment))
                #endif
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    handleSpotlight(id)
                }
        }
        .commands {
            ModulaKeyboardCommands(
                openCommandCenter: {
                    guard environment.gate.state == .ready else { return }
                    environment.navigation.presented = .commandCenter
                    HapticEngine.shared.play(.contextOpen)
                },
                openCreate: {
                    guard environment.gate.state == .ready else { return }
                    environment.navigation.presented = .createPicker
                },
                openSearch: {
                    guard environment.gate.state == .ready else { return }
                    environment.openRouted(.search(.root(nil)))
                }
            )
        }
    }

    private func handleSpotlight(_ identifier: String) {
        guard environment.gate.state == .ready else { return }
        if identifier.hasPrefix("module:") {
            let moduleID = String(identifier.dropFirst("module:".count))
            guard environment.catalogue.installedIDs.contains(moduleID) else { return }
            environment.openRouted(.module(moduleID, localPath: nil))
        } else if identifier.hasPrefix("settings:") {
            let key = String(identifier.dropFirst("settings:".count))
            switch key {
            case "appearance": environment.openRouted(.settings(.appearance(.root)))
            case "notifications": environment.openRouted(.settings(.notifications(.root)))
            case "privacy": environment.openRouted(.settings(.privacy(.root)))
            case "accessibility": environment.openRouted(.settings(.accessibility(.root)))
            default: environment.openRouted(.settings(.root))
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
        // Set before launch finishes so a notification that cold-launched the app is delivered.
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushNotificationController.current?.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in PushNotificationController.current?.didFailToRegister(message) }
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        guard let environment else { return }
        Task { await environment.intelligence.unloadNodus() }
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
        guard environment.gate.state == .ready else { return false }
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

#if DEBUG
import Darwin

/// DEBUG-only main-thread hang watchdog. When the main thread stops answering
/// for >1.2 s it signals it repeatedly and appends the main-thread backtrace to
/// Documents/hangs/hang-<ts>.txt (pull with `devicectl device copy from`).
enum MainThreadHangWatchdog {
    nonisolated(unsafe) static var fd: Int32 = -1
    nonisolated(unsafe) static var mainThread: pthread_t?
    nonisolated(unsafe) static var lastPong = Date()
    nonisolated(unsafe) static var started = false

    static func start() {
        // XCTest startup can briefly stall the simulator main thread. Its
        // signal handler is diagnostic only and is unsafe during that stall.
        guard !ProcessInfo.processInfo.arguments.contains("--modula-disable-hang-watchdog") else { return }
        guard !started else { return }
        started = true
        mainThread = pthread_self()
        signal(SIGUSR2) { _ in
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
            let n = backtrace(&frames, 128)
            let header = "\n--- main thread sample ---\n"
            _ = header.withCString { write(MainThreadHangWatchdog.fd, $0, strlen($0)) }
            backtrace_symbols_fd(&frames, n, MainThreadHangWatchdog.fd)
        }
        let thread = Thread {
            var hangSamples = 0
            while true {
                DispatchQueue.main.async { MainThreadHangWatchdog.lastPong = Date() }
                Thread.sleep(forTimeInterval: 0.25)
                let stalled = Date().timeIntervalSince(lastPong)
                if stalled > 1.2 {
                    if hangSamples == 0 { openFile() }
                    if hangSamples < 12, fd >= 0, let main = mainThread {
                        pthread_kill(main, SIGUSR2)
                        hangSamples += 1
                    }
                } else if hangSamples > 0 {
                    if fd >= 0 { close(fd); fd = -1 }
                    hangSamples = 0
                }
            }
        }
        thread.name = "modula.hang-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static func openFile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("hangs", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let path = docs.appendingPathComponent("hang-\(Int(Date().timeIntervalSince1970)).txt").path
        fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }
}
#endif
