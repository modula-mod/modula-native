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
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-appearance") { appearance.reset() }
        let url = (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String).flatMap(URL.init(string:))
        client = GreenfieldClient(baseURL: url)
        catalogue = ProductHubStore(client: client)
        auth = AuthenticationStore(client: client)
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
