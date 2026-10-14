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
}

struct MOL01DebugCover: ViewModifier {
    @State private var shown = MOL01DebugHarness.scene != nil
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $shown) {
            NavigationStack { Moliboo3DPreview(debugScene: MOL01DebugHarness.scene) }
        }
    }
}
#endif
