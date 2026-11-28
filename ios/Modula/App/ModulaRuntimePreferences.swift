import SwiftUI
import UIKit

/// Applies device preferences that live outside SwiftUI views (UIKit globals),
/// at launch and whenever Settings changes them.
@MainActor
enum ModulaRuntimePreferences {
    /// Perf: RootView calls `apply()` on every `UserDefaults.didChangeNotification`, which
    /// fires for any defaults write anywhere in the app (feeds, drafts, caches). Only touch
    /// UIKit when the two preferences we mirror actually changed.
    private static var lastApplied: (shakeToUndo: Bool, edgeSwipeBack: Bool)?

    static func apply() {
        // Settings → Gestures → "Shake to undo compose". iOS enables shake-to-undo
        // by default; Modula keeps it off unless you turn it on.
        let current = (shakeToUndo: ModulaPreferences.shakeToUndo, edgeSwipeBack: ModulaPreferences.edgeSwipeBack)
        if let lastApplied, lastApplied == current { return }
        lastApplied = current
        UIApplication.shared.applicationSupportsShakeToEdit = current.shakeToUndo
        EdgeSwipeBackRegistry.applyAll()
    }
}

/// Settings → Gestures → "Edge swipe to go back". Each NavigationStack root hosts an
/// invisible probe that finds its UINavigationController and toggles the system
/// interactive-pop gesture. The back button always works.
struct EdgeSwipeBackConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ProbeController { ProbeController() }
    func updateUIViewController(_ controller: ProbeController, context: Context) { controller.apply() }

    final class ProbeController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isHidden = true
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            EdgeSwipeBackRegistry.register(self)
            apply()
        }
        func apply() {
            guard let navigation = navigationController else { return }
            let enabled = ModulaPreferences.edgeSwipeBack
            navigation.interactivePopGestureRecognizer?.isEnabled = enabled
            // Screens that hide the system back button (custom close / X bars) used to lose the
            // edge swipe: UIKit's default delegate refuses it when the back item is hidden. Our
            // delegate allows it whenever there's something to pop and the screen hasn't opted out.
            navigation.interactivePopGestureRecognizer?.delegate = EdgeSwipeBackDelegate.shared
            if #available(iOS 26.0, *) {
                // iOS 26 full-width content swipe-back follows the same preference.
                navigation.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }
    }
}

/// Lets the edge swipe pop on custom-bar screens. Screens with unsaved work opt out with
/// `.modulaBlocksSwipeBack(_:)` (their own Cancel asks first).
final class EdgeSwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    @MainActor static let shared = EdgeSwipeBackDelegate()
    @MainActor static var blockers: Set<String> = []

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard ModulaPreferences.edgeSwipeBack, Self.blockers.isEmpty,
                  let navigation = Self.navigationController(for: gestureRecognizer.view) else { return false }
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    @MainActor private static func navigationController(for view: UIView?) -> UINavigationController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let navigation = current as? UINavigationController { return navigation }
            responder = current.next
        }
        return nil
    }
}

private struct SwipeBackBlocker: ViewModifier {
    let blocked: Bool
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onChange(of: blocked, initial: true) { _, value in
                if value { EdgeSwipeBackDelegate.blockers.insert(id) } else { EdgeSwipeBackDelegate.blockers.remove(id) }
            }
            .onDisappear { EdgeSwipeBackDelegate.blockers.remove(id) }
    }
}

extension View {
    /// Blocks the edge swipe-back while `blocked` (e.g. unsaved edits).
    func modulaBlocksSwipeBack(_ blocked: Bool) -> some View {
        modifier(SwipeBackBlocker(blocked: blocked))
    }
}

@MainActor
enum EdgeSwipeBackRegistry {
    private static var probes: [WeakProbe] = []
    private struct WeakProbe { weak var controller: EdgeSwipeBackConfigurator.ProbeController? }

    static func register(_ controller: EdgeSwipeBackConfigurator.ProbeController) {
        probes.removeAll { $0.controller == nil || $0.controller === controller }
        probes.append(WeakProbe(controller: controller))
    }

    static func applyAll() {
        probes.removeAll { $0.controller == nil }
        probes.forEach { $0.controller?.apply() }
    }
}

/// Settings → Labs → "Debug overlays": a small live readout pinned to the top of the
/// screen (route, network, power, motion, API host). Never shows account data.
struct ModulaDebugOverlay: View {
    let route: AppRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            VStack(alignment: .leading, spacing: 2) {
                Text(RouteSerializer.serialize(route))
                Text([
                    NetworkConditions.shared.isExpensive ? "net: metered" : "net: unmetered",
                    ProcessInfo.processInfo.isLowPowerModeEnabled ? "low power" : "power ok",
                    (reduceMotion || ModulaPreferences.extraMotionReduction) ? "motion: reduced" : "motion: full",
                    ModulaPreferences.focusFilterActive ? "focus filter" : nil
                ].compactMap { $0 }.joined(separator: " · "))
                Text(SettingsEnvironmentInfo.apiHost)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
