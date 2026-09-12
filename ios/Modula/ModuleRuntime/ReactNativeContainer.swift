import SwiftUI

struct ReactNativeContainer: UIViewControllerRepresentable {
    let session: ModuleSession
    let runtime: ModuleRuntimeController
    func makeUIViewController(context: Context) -> ReactNativeViewController {
        ReactNativeViewController(session: session, runtime: runtime)
    }
    func updateUIViewController(_ controller: ReactNativeViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: ReactNativeViewController, coordinator: ()) { controller.stop() }
}
