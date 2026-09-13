import SwiftUI

@main
struct ModulaApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(environment.appearance.accent.color)
                .preferredColorScheme(environment.appearance.colorScheme)
        }
    }
}
