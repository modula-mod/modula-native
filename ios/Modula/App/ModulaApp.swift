import SwiftUI

@main
struct ModulaApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(ModulaColor.accent)
                .preferredColorScheme(environment.settings.colorScheme)
        }
    }
}
