import CoreMotion
import SwiftUI

/// Synthwave perspective-grid backdrop. Decorative only: 60fps cap, paused off-screen /
/// backgrounded, static with Reduce Motion or Low Power; slight device-motion parallax.
struct PerspectiveGridView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var motion = GridMotion()

    private var animated: Bool {
        visible && phase == .active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated)) { ctx in
                let t = animated ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 4
                Rectangle()
                    .colorEffect(ShaderLibrary.perspectiveGrid(
                        .float2(geo.size), .float(t), .float(scheme == .dark ? 1 : 0),
                        .float2(motion.tilt)))
            }
        }
        .onAppear { visible = true; if !reduceMotion { motion.start() } }
        .onDisappear { visible = false; motion.stop() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

@MainActor @Observable
private final class GridMotion {
    var tilt = CGPoint.zero
    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            let x = max(-1, min(1, m.attitude.roll)), y = max(-1, min(1, m.attitude.pitch - 0.6))
            self?.tilt = CGPoint(x: x, y: y)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
