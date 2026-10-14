#if DEBUG
import SwiftUI

/// DEBUG-only: `-MOL03Studio <characterID>` presents the Living Studio directly (for `simctl io screenshot` evidence),
/// `-MOL03Panel style|play|expressions|photo` opens a rail panel. Never compiled into Release.
enum MOL03DebugHarness {
    static func arg(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var character: String? { arg("-MOL03Studio") }
    static var panel: String? { arg("-MOL03Panel") }
}

struct MOL03StudioCover: ViewModifier {
    @State private var shown = MOL03DebugHarness.character != nil
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $shown) {
            NavigationStack { MolibooLivingStudioView(characterID: MOL03DebugHarness.character ?? "pip") }
        }
    }
}
#endif
