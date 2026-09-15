import Observation
import Foundation

@MainActor @Observable
final class AppEnvironment {
    let navigation = NavigationCoordinator()
    let appearance = AppearanceStore()
    var settings: AppearanceStore { appearance }
    let runtime = ModuleRuntimeController()
    let client: GreenfieldClient
    let catalogue: ProductHubStore
    let auth: AuthenticationStore
    let activity: ActivityStore
    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("--reset-appearance") { appearance.reset() }
        #if DEBUG
        // Deterministic visual-acceptance overrides still flow through the sole
        // AppearanceStore authority; production builds expose no test surface.
        if launchArguments.contains("--ui-light") { appearance.theme = .light }
        if launchArguments.contains("--ui-standard-dark") { appearance.theme = .dark; appearance.darkStyle = .standard }
        if launchArguments.contains("--ui-dim") { appearance.theme = .dark; appearance.darkStyle = .dim }
        if launchArguments.contains("--ui-oled") { appearance.theme = .dark; appearance.darkStyle = .oled }
        if launchArguments.contains("--ui-compact") { appearance.density = .compact }
        if launchArguments.contains("--ui-large-text") { appearance.textSize = .large }
        if launchArguments.contains("--ui-higher-contrast") { appearance.contrastTransparency = .higherContrast }
        if launchArguments.contains("--ui-reduce-transparency") { appearance.contrastTransparency = .reduceTransparency }
        #endif
        let url = (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String).flatMap(URL.init(string:))
        client = GreenfieldClient(baseURL: url)
        catalogue = ProductHubStore(client: client)
        auth = AuthenticationStore(client: client)
        activity = ActivityStore(client: client)
        let catalogueStore = catalogue
        auth.onAccountChange = { [weak runtime, weak catalogueStore] account in
            runtime?.setAccount(account?.accountId)
            Task { await catalogueStore?.load() }
        }
        ModulaBridge.shared.client = client
        ModulaBridge.shared.authenticationInvalidated = { [weak auth, weak runtime] in
            runtime?.setAccount(nil)
            Task { await auth?.signOut() }
        }
        ModulaBridge.shared.runtime = runtime
        ModulaBridge.shared.navigation = navigation
        let appearanceStore = appearance
        HapticEngine.shared.intensityProvider = { [weak appearanceStore] in appearanceStore?.haptics ?? .standard }
    }
}
