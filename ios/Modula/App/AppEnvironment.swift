import Observation
import Foundation
import UIKit

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
    let discover: DiscoverStore
    let posts: PostStateStore
    let postActions: PostActionController
    let home: HomeStore
    let profile: ProfileStore
    let messaging: MessagingStore
    let inMail: InMailStore
    let stories: StoryStore
    let reels: ReelStore
    let commandRecents: CommandRecentsStore
    let saved: SavedStore
    let collections: CollectionStore
    let drafts: DraftStore

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
        discover = DiscoverStore(client: client)
        posts = PostStateStore()
        postActions = PostActionController(client: client, state: posts)
        home = HomeStore(client: client, posts: posts, postActions: postActions)
        profile = ProfileStore(client: client, posts: posts)
        messaging = MessagingStore(client: client)
        inMail = InMailStore(client: client)
        stories = StoryStore(client: client)
        reels = ReelStore(client: client)
        commandRecents = CommandRecentsStore()
        saved = SavedStore(client: client)
        collections = CollectionStore()
        drafts = DraftStore()
        let catalogueStore = catalogue
        let draftsStore = drafts
        auth.onAccountChange = { [weak runtime, weak catalogueStore] account in
            runtime?.setAccount(account?.accountId)
            draftsStore.setAccountID(account?.accountId)
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

    func commandCapabilities() -> CommandCapabilitySnapshot {
        CommandCapabilitySnapshot(
            signedIn: auth.isSignedIn,
            developerMode: {
                #if DEBUG
                true
                #else
                false
                #endif
            }(),
            postCompose: true,
            photoCompose: false,
            pollCompose: false,
            storyCreate: stories.capabilities.create,
            messagingSend: messaging.capabilities.send,
            messagingInbox: true,
            inMailCompose: inMail.capabilities.send,
            inMailInbox: true,
            savedList: saved.capabilities.listSavedPosts,
            collectionsLocal: collections.capabilities.localCollections,
            drafts: true,
            installedModuleIDs: catalogue.installedIDs
        )
    }

    func refreshQuickActions() {
        UIApplication.shared.shortcutItems = QuickActionMapper.shortcutItems(capabilities: commandCapabilities())
    }
}
