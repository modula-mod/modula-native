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
                .modifier(CallOverlayHost())
                .environment(environment)
                .tint(environment.appearance.liveAccent)
                .preferredColorScheme(environment.appearance.colorScheme)
                // Web links anywhere in the app open in the Modula browser (Settings → Links).
                .environment(\.openURL, OpenURLAction { url in ModulaLinkRouter.handle(url, source: nil) })
                .onAppear {
                    ModulaPerf.mark("firstFrame")
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
            ModulaPolishKeyboardCommands(environment: environment)
        }
    }

    private func handleSpotlight(_ identifier: String) {
        guard environment.gate.state == .ready else { return }
        if let route = ModulaSpotlightDestinations.route(for: identifier) {
            environment.openRouted(route)
            return
        }
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
        // PushKit must be registered during launch so a VoIP push that woke the app is delivered.
        CallManager.shared.bootstrapAtLaunch()
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

// MARK: - Perf probe
// Prints `MODULA_PERF <mark> <ms since process start>` once per mark to stdout
// (visible with `devicectl device process launch --console`), plus a 1 s
// frame-hitch summary for the first ~12 s after launch. No network, no files.
@MainActor
enum ModulaPerf {
    static let processStart: Double = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date().timeIntervalSince1970 }
        let tv = info.kp_proc.p_un.__p_starttime
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
    }()
    private static var marked = Set<String>()
    private static var monitor: HitchMonitor?

    static func mark(_ name: String) {
        guard !marked.contains(name) else { return }
        marked.insert(name)
        let ms = Int((Date().timeIntervalSince1970 - processStart) * 1000)
        print("MODULA_PERF \(name) \(ms)ms")
        // Settings → About → Performance shows the last launch (local only).
        UserDefaults.standard.set(ms, forKey: "modula.perf.\(name)")
        if name == "firstFrame", monitor == nil {
            let m = HitchMonitor()
            monitor = m
            m.start()
        }
    }

    final class HitchMonitor: NSObject {
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0
        private var windowStart: CFTimeInterval = 0
        private var frames = 0, hitches = 0
        private var hitchMs: Double = 0, worst: Double = 0
        private var windows = 0
        private var totalFrames = 0, totalHitches = 0
        private var totalHitchMs: Double = 0

        func start() {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        @objc private func tick(_ l: CADisplayLink) {
            let now = l.timestamp
            if last > 0 {
                let expected = max(l.targetTimestamp - l.timestamp, 1.0 / 120.0)
                let dt = now - last
                frames += 1
                if dt > expected * 1.5 {
                    hitches += 1
                    hitchMs += (dt - expected) * 1000
                    worst = max(worst, dt * 1000)
                }
            } else { windowStart = now }
            last = now
            if now - windowStart >= 1 {
                windows += 1
                print("MODULA_PERF hitch w=\(windows) frames=\(frames) hitches=\(hitches) hitchMs=\(Int(hitchMs)) worstMs=\(Int(worst))")
                totalFrames += frames; totalHitches += hitches; totalHitchMs += hitchMs
                frames = 0; hitches = 0; hitchMs = 0; worst = 0; windowStart = now
                if windows >= 12 {
                    l.invalidate(); link = nil
                    let d = UserDefaults.standard
                    d.set(totalFrames, forKey: "modula.perf.launchFrames")
                    d.set(totalHitches, forKey: "modula.perf.launchHitches")
                    d.set(Int(totalHitchMs), forKey: "modula.perf.launchHitchMs")
                }
            }
        }
    }
}
