import Observation

@MainActor @Observable
final class AppEnvironment {
    let navigation = NavigationCoordinator()
    let settings = SettingsStore()
}
