import Observation
import Foundation

@MainActor @Observable
final class AppEnvironment {
    let navigation = NavigationCoordinator()
    let settings = SettingsStore()
    let runtime = ModuleRuntimeController()
    let client: GreenfieldClient
    let auth: AuthenticationStore
    init() {
        let url = (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String).flatMap(URL.init(string:))
        client = GreenfieldClient(baseURL: url)
        auth = AuthenticationStore(client: client)
        auth.onAccountChange = { [weak runtime] account in runtime?.setAccount(account?.accountId) }
        ModulaBridge.shared.client = client
        ModulaBridge.shared.authenticationInvalidated = { [weak auth, weak runtime] in
            runtime?.setAccount(nil)
            Task { await auth?.signOut() }
        }
        ModulaBridge.shared.runtime = runtime
        ModulaBridge.shared.navigation = navigation
    }
}
