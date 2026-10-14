#if DEBUG
import SwiftUI

/// DEBUG-only evidence harness: `-MOL01Scene <name>` launches straight into the 3D preview in a fixed state
/// so `simctl io screenshot` can capture deterministic MOL-01 evidence. Never compiled into Release.
enum MOL01DebugHarness {
    static var scene: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-MOL01Scene"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    /// `-MOL01Character <id>` picks the character (default pebble, so MOL-01 scripts keep working).
    static var character: String {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-MOL01Character"), i + 1 < a.count else { return "pebble" }
        return a[i + 1]
    }
}

/// Machine-readable live state for XCUITest acceptance (tiny, transparent, DEBUG only).
struct MOL01StateProbe: View {
    let controller: MolibooSceneController
    let wardrobeIDs: [String]
    var body: some View {
        // Sampled twice a second: per-frame stats are @ObservationIgnored so the probe never invalidates the view every frame.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in probe }
    }
    @ViewBuilder private var probe: some View {
        let c = controller
        let avg = c.frameCount > 0 ? c.frameTimeSum / Double(c.frameCount) * 1000 : 0
        let v = "loaded=\(c.character != nil ? 1 : 0) failed=\(c.loadFailed ? 1 : 0) meshes=\(c.meshCount) anims=\(c.character?.availableAnimations.count ?? 0) expr=\(c.expression.rawValue) yaw=\(String(format: "%.2f", c.yaw)) cap=\(c.equipped[MolibooCosmetics.signatureCapID] != nil ? 1 : 0) saved=\(wardrobeIDs.contains(MolibooCosmetics.signatureCapID) ? 1 : 0) clips=\(c.clipsPlayed) reacts=\(c.reactCount) last=\(c.lastAction) loadms=\(Int(c.loadMillis)) frames=\(c.frameCount) avgms=\(String(format: "%.2f", avg)) maxms=\(String(format: "%.1f", c.frameTimeMax * 1000)) footprintMB=\(String(format: "%.1f", MOL01Memory.footprintMB()))"
        Text(v).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
            .accessibilityIdentifier("moliboo3d.state").accessibilityValue(v).accessibilityLabel(v)
    }
}

enum MOL01Memory {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

/// `-MOL01Studio` presents the real Mascot Studio (so XCUITest can exercise the flag-gated 3D entry and back navigation).
struct MOL01StudioCover: ViewModifier {
    @State private var shown = ProcessInfo.processInfo.arguments.contains("-MOL01Studio")
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $shown) {
            NavigationStack {
                MascotStudioView()
                    .overlay(alignment: .topLeading) {
                        Text("fp=\(String(format: "%.1f", MOL01Memory.footprintMB()))").font(.system(size: 1)).opacity(0.01)
                            .accessibilityIdentifier("mol01.studio.ready")
                    }
            }
        }
    }
}

struct MOL01DebugCover: ViewModifier {
    @State private var shown = MOL01DebugHarness.scene != nil
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $shown) {
            NavigationStack { Moliboo3DPreview(characterID: MOL01DebugHarness.character, debugScene: MOL01DebugHarness.scene) }
        }
    }
}
#endif
