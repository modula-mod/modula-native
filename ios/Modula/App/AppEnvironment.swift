import Observation

@MainActor @Observable
final class AppEnvironment {
    let navigation = NavigationCoordinator()
    let settings = SettingsStore()
    let runtime = ModuleRuntimeController()
    init() {
        ModulaBridge.shared.runtime = runtime
        ModulaBridge.shared.navigation = navigation
    }
}
