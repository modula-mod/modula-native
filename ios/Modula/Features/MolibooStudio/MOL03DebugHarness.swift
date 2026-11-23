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
    var environment: AppEnvironment? = nil
    @State private var shown = MOL03DebugHarness.character != nil
    /// `-MOLWorld 1` presents the Moliboo home directly (with `-MOLWorldKind`, `-MOLWorldScrollY`,
    /// `-MOLWorldFamily`, `-MOLWorldAutoTap` for screenshot evidence).
    @State private var worldShown = MOL03DebugHarness.arg("-MOLWorld") != nil
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $shown) {
                NavigationStack { MolibooLivingStudioView(characterID: MOL03DebugHarness.character ?? "pip") }
            }
            .fullScreenCover(isPresented: $worldShown) {
                if let environment { NavigationStack { MolibooWorldView() }.environment(environment) }
            }
    }
}
#endif
