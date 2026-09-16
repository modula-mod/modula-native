import Observation
import Foundation
import SwiftUI
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
    let gate = AppGate()
    let appLock = AppLockStore()

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
        auth.onAccountChange = { [weak self, weak runtime, weak catalogueStore] account in
            runtime?.setAccount(account?.accountId)
            draftsStore.setAccountID(account?.accountId)
            Task {
                await catalogueStore?.load()
                await MainActor.run { self?.refreshLaunchState() }
            }
        }
        ModulaBridge.shared.client = client
        ModulaBridge.shared.authenticationInvalidated = { [weak self, weak auth, weak runtime] in
            runtime?.setAccount(nil)
            Task {
                await auth?.signOut()
                await MainActor.run { self?.refreshLaunchState() }
            }
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

    func bootstrapLaunch() async {
        gate.beginBoot()
        await auth.restore()
        drafts.setAccountID(auth.account?.accountId)
        if auth.isSignedIn {
            appLock.refreshColdLaunchLock()
            await catalogue.load()
        }
        refreshLaunchState()
        refreshQuickActions()
    }

    func refreshLaunchState() {
        gate.apply(
            signedIn: auth.isSignedIn,
            accountID: auth.account?.accountId,
            appLockEnabled: appLock.enabled,
            appLockRequiresUnlock: appLock.requiresUnlock
        )
        if gate.state == .ready, let pending = gate.takePendingDestination() {
            navigation.open(pending == .boot ? .home(.following) : pending)
        }
        refreshQuickActions()
    }

    func handleIncomingURL(_ url: URL) {
        guard let route = RouteParser.parse(url.absoluteString) else { return }
        openRouted(route)
    }

    func openRouted(_ route: AppRoute) {
        let resolved = route == .boot ? AppRoute.home(.following) : route
        if gate.state != .ready {
            if resolved.isPreAuthSurface {
                navigation.open(resolved)
                return
            }
            gate.enqueue(resolved)
            return
        }
        if appLock.requiresUnlock {
            gate.enqueue(resolved)
            return
        }
        navigation.open(resolved)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            drafts.flush()
            appLock.recordBackground()
            refreshLaunchState()
        case .inactive:
            break
        case .active:
            appLock.evaluateForeground()
            refreshLaunchState()
        @unknown default:
            break
        }
    }

    func performSignOut(resetAppLock: Bool = true) async {
        drafts.flush()
        runtime.revokeAll()
        await auth.signOut()
        drafts.setAccountID(nil)
        if resetAppLock {
            appLock.resetAfterSignOut()
        }
        navigation.home()
        refreshLaunchState()
        refreshQuickActions()
    }
}
