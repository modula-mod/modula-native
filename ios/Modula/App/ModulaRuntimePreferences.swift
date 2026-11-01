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
            navigationController?.interactivePopGestureRecognizer?.isEnabled = ModulaPreferences.edgeSwipeBack
        }
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
