import XCTest
@testable import Modula

final class N4DRouteTests: XCTestCase {
    func testCommandSavedCollectionsDraftsRoutes() throws {
        let paths = [
            "/command",
            "/saved",
            "/saved/posts",
            "/saved/modules",
            "/saved/links",
            "/collections",
            "/collections/design-1",
            "/drafts",
            "/drafts/posts",
            "/drafts/in-mail",
            "/drafts/stories"
        ]
        for path in paths {
            let route = try XCTUnwrap(RouteParser.parse(path), path)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route, path)
        }
        XCTAssertEqual(RouteParser.parse("/command"), .command)
        XCTAssertNil(RouteParser.parse("/command/extra"))
        XCTAssertNil(RouteParser.parse("/collections/"))
        XCTAssertEqual(RouteSerializer.serialize(.saved(.root)), "/saved")
        XCTAssertEqual(RouteSerializer.serialize(.drafts(.inMail)), "/drafts/in-mail")
    }

    func testFiveRootTabsUnchanged() {
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["home", "discover", "modules", "activity", "profile"])
        XCTAssertNil(AppRoute.command.tab)
        XCTAssertEqual(AppRoute.saved(.root).tab, .profile)
    }
}

final class CommandRegistryTests: XCTestCase {
    func testUniqueIDsAndCategories() {
        let caps = CommandCapabilitySnapshot(
            signedIn: true,
            developerMode: true,
            storyCreate: false,
            messagingSend: false,
            inMailCompose: false,
            installedModuleIDs: ["digital.modula.vault-notes"]
        )
        let commands = CommandRegistry.commands(capabilities: caps)
        let ids = commands.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Command IDs must be unique")
        XCTAssertTrue(commands.contains { $0.id.rawValue == "create.post" })
        XCTAssertTrue(commands.contains { $0.id.rawValue == "module.vault-notes.open" })
        XCTAssertTrue(commands.contains { $0.category == .navigate })
        XCTAssertTrue(commands.contains { $0.category == .developer })
    }

    func testVaultAliasRanksAboveUnrelated() {
        let caps = CommandCapabilitySnapshot(
            signedIn: true,
            installedModuleIDs: ["digital.modula.vault-notes"]
        )
        let commands = CommandRegistry.visible(capabilities: caps)
        let matches = CommandMatcher.match(query: "vault", in: commands)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.command.id.rawValue, "module.vault-notes.open")
    }

    func testAppearanceAliases() {
        let caps = CommandCapabilitySnapshot(signedIn: true)
        let commands = CommandRegistry.visible(capabilities: caps)
        let matches = CommandMatcher.match(query: "dark", in: commands)
        XCTAssertTrue(matches.contains { $0.command.id.rawValue.contains("appearance") || $0.command.title.lowercased().contains("dark") })
    }

    func testCreateStoryUnavailableWhenCapabilityOff() {
        let caps = CommandCapabilitySnapshot(signedIn: true, storyCreate: false)
        let visible = CommandRegistry.visible(capabilities: caps)
        XCTAssertFalse(visible.contains { $0.id.rawValue == "create.story" })
        let all = CommandRegistry.commands(capabilities: caps)
        if let story = all.first(where: { $0.id.rawValue == "create.story" }) {
            XCTAssertEqual(story.availability, .unavailable)
        }
    }

    func testModuleOpenActionIsTyped() {
        let caps = CommandCapabilitySnapshot(
            signedIn: true,
            installedModuleIDs: ["digital.modula.vault-notes"]
        )
        let command = CommandRegistry.visible(capabilities: caps)
            .first { $0.id.rawValue == "module.vault-notes.open" }
        guard case .moduleOpen(let id, let path)? = command?.action else {
            return XCTFail("Expected moduleOpen")
        }
        XCTAssertEqual(id, "digital.modula.vault-notes")
        XCTAssertNil(path)
    }
}

@MainActor
final class CommandExecutionTests: XCTestCase {
    func testRouteOpenComposeSearchSettings() {
        let navigation = NavigationCoordinator()
        var presented: AppPresentation?
        let present: (AppPresentation) -> Void = { presented = $0 }

        XCTAssertEqual(
            CommandExecutor.perform(.routeOpen(.home(.following)), navigation: navigation, present: present),
            .executed
        )
        XCTAssertEqual(navigation.selectedTab, .home)

        XCTAssertEqual(
            CommandExecutor.perform(.composeStart(.post), navigation: navigation, present: present),
            .executed
        )
        XCTAssertEqual(presented, .composer(.post))

        XCTAssertEqual(
            CommandExecutor.perform(.searchStart(query: "andrei"), navigation: navigation, present: present),
            .executed
        )
        XCTAssertEqual(navigation.currentRoute, .search(.root("andrei")))

        XCTAssertEqual(
            CommandExecutor.perform(.settingsOpen(.appearance(.root)), navigation: navigation, present: present),
            .executed
        )

        XCTAssertEqual(
            CommandExecutor.perform(.functionInvoke(name: "x", parameters: [:]), navigation: navigation, present: present),
            .unsupported
        )
    }

    func testUnavailableCommandDoesNotExecute() {
        let navigation = NavigationCoordinator()
        let command = ModulaCommand(
            id: "create.story",
            title: "Create Story",
            icon: .init("circle.dashed"),
            category: .create,
            availability: .unavailable,
            action: .routeOpen(.stories(.create))
        )
        let outcome = CommandExecutor.execute(command, navigation: navigation, signedIn: true) { _ in }
        XCTAssertEqual(outcome, .unavailable)
    }
}

@MainActor
final class CommandRecentsTests: XCTestCase {
    func testDedupBoundedAndPrivacy() {
        let store = CommandRecentsStore(limit: 3, store: PrivateFileStore(domain: .commands))
        store.clear()
        let a = ModulaCommand(id: "a", title: "Open Home", icon: .init("house"), category: .navigate, action: .routeOpen(.home(.following)))
        let b = ModulaCommand(id: "b", title: "Open Discover", icon: .init("safari"), category: .navigate, action: .routeOpen(.discover(.trending)))
        let c = ModulaCommand(id: "c", title: "Open Activity", icon: .init("bell"), category: .navigate, action: .routeOpen(.activity(.all)))
        let d = ModulaCommand(id: "d", title: "Open Settings", icon: .init("gearshape"), category: .manage, action: .settingsOpen(.root))
        let bad = ModulaCommand(
            id: "bad",
            title: "Send message to Sophia: \"my bank…\"",
            icon: .init("bubble.left"),
            category: .create,
            action: .shareStart(.post("x"))
        )
        store.record(a); store.record(b); store.record(a); store.record(c); store.record(d); store.record(bad)
        XCTAssertEqual(store.recentIDs.count, 3)
        XCTAssertEqual(store.recentIDs.first?.rawValue, "d")
        XCTAssertFalse(store.recentIDs.contains(where: { $0.rawValue == "bad" }))
        XCTAssertFalse(CommandRecentsStore.isSafeForRecents(bad))
        store.clear()
    }
}

@MainActor
final class CollectionsDraftsShareTests: XCTestCase {
    func testLocalCollectionsCRUD() {
        let store = CollectionStore(
            fileStore: PrivateFileStore(domain: .collections)
        )
        // Isolate from any prior device state by renaming/deleting created items only.
        let created = store.create(name: "Design inspiration")
        XCTAssertNotNil(created)
        guard let id = created?.id else { return }
        store.add(postID: "post-1", to: id)
        store.add(postID: "post-1", to: id)
        XCTAssertEqual(store.collections.first { $0.id == id }?.itemCount, 1)
        store.rename(id: id, name: "Read later")
        XCTAssertEqual(store.collections.first { $0.id == id }?.name, "Read later")
        store.remove(postID: "post-1", from: id)
        XCTAssertEqual(store.collections.first { $0.id == id }?.itemCount, 0)
        store.delete(id: id)
        XCTAssertNil(store.collections.first { $0.id == id })
        XCTAssertNotNil(store.defaultSaved)
        XCTAssertTrue(store.defaultSaved?.isDefault == true)
    }

    func testDraftAutosaveRestoreDiscardPrivacyCounts() async throws {
        let drafts = DraftStore(
            fileStore: PrivateFileStore(domain: .drafts),
            autosaveMilliseconds: 10
        )
        drafts.discardPost()
        drafts.upsertPost(PostDraft(
            id: "post-primary",
            text: "Profile should become the social OS home",
            mediaReferences: [],
            lastEdited: Date()
        ), debounce: false)
        XCTAssertEqual(drafts.postDraft()?.preview.contains("Profile"), true)
        XCTAssertEqual(drafts.countsByKind[.post], 1)
        drafts.upsertInMail(InMailDraft(toHandle: "sophia", subject: "Partnership idea", body: "Hello"), debounce: false)
        XCTAssertEqual(drafts.countsByKind[.inMail], 1)
        drafts.discardPost()
        XCTAssertNil(drafts.postDraft())
    }

    func testShareCanonicalPayloads() {
        XCTAssertEqual(
            SharePayload.profile(identity: "andrei", displayName: "Andrei", handle: "andrei", avatarURL: nil).canonicalURL.absoluteString,
            "https://modula.digital/profile/andrei"
        )
        XCTAssertEqual(
            SharePayload.post(id: "p1", authorName: "A", excerpt: "Hi", hasMedia: false).canonicalURL.absoluteString,
            "https://modula.digital/post/p1"
        )
        XCTAssertEqual(
            SharePayload.module(id: "digital.modula.vault-notes", name: "Vault", publisher: nil).canonicalURL.absoluteString,
            "https://modula.digital/product-hub/module/digital.modula.vault-notes"
        )
        let link = SharePayload.link(url: URL(string: "https://modula.digital/docs")!, title: "Docs")
        XCTAssertEqual(ShareCoordinator.copyLink(link), "https://modula.digital/docs")
        let destinations = ShareDestinationRegistry.destinations(
            for: .post(id: "p1", authorName: nil, excerpt: nil, hasMedia: false),
            messagingSend: false,
            inMailCompose: false,
            collectionsAvailable: true
        )
        XCTAssertTrue(destinations.contains { $0.kind == .systemShare })
        XCTAssertTrue(destinations.contains { $0.kind == .copyLink })
        XCTAssertFalse(destinations.contains { $0.kind == .messages })
        XCTAssertTrue(destinations.contains { $0.kind == .saveToCollection })
    }

    func testPeoplePickerSelectionSemantics() {
        let people = [
            PeoplePickerPerson(id: "1", displayName: "Sophia", handle: "sophia"),
            PeoplePickerPerson(id: "2", displayName: "Marcus", handle: "marcus")
        ]
        XCTAssertEqual(people.count, 2)
        PeopleRecentsStore.record(ids: ["1", "2", "1"])
        let recents = PeopleRecentsStore.load()
        XCTAssertEqual(recents.first, "1")
        XCTAssertLessThanOrEqual(recents.count, 12)
    }

    func testQuickActionMapping() {
        XCTAssertEqual(
            QuickActionMapper.commandID(forShortcutType: QuickActionID.createPost.rawValue)?.rawValue,
            "create.post"
        )
        XCTAssertNil(QuickActionMapper.commandID(forShortcutType: "unknown.shortcut"))
        let items = QuickActionMapper.shortcutItems(
            capabilities: CommandCapabilitySnapshot(
                messagingInbox: true,
                installedModuleIDs: ["digital.modula.vault-notes"]
            )
        )
        XCTAssertTrue(items.contains { $0.type == QuickActionID.vaultNotes.rawValue })
        XCTAssertTrue(items.contains { $0.type == QuickActionID.command.rawValue })
    }

    func testAppIntentRouteMapping() {
        XCTAssertEqual(ModulaAppIntentBridge.route(for: "create.post", parameter: nil), .compose(.post))
        XCTAssertEqual(ModulaAppIntentBridge.route(for: "search.modula", parameter: "vault"), .search(.root("vault")))
        XCTAssertEqual(
            ModulaAppIntentBridge.route(for: "open.module", parameter: "digital.modula.vault-notes"),
            .module("digital.modula.vault-notes", localPath: nil)
        )
        XCTAssertNil(ModulaAppIntentBridge.route(for: "open.module", parameter: "../evil"))
        XCTAssertFalse(ModulaAppIntentBridge.canOpenModule(id: "digital.modula.vault-notes", installed: [], signedIn: true))
        XCTAssertTrue(ModulaAppIntentBridge.canOpenModule(
            id: "digital.modula.vault-notes",
            installed: ["digital.modula.vault-notes"],
            signedIn: true
        ))
    }

    func testCreateActionRegistryGatesMessaging() {
        let caps = CommandCapabilitySnapshot(signedIn: true, messagingSend: false, inMailCompose: false, storyCreate: false)
        let actions = CreateActionRegistry.actions(capabilities: caps)
        XCTAssertTrue(actions.contains { $0.id == "post" && $0.availability == .available })
        XCTAssertFalse(actions.contains { $0.id == "message" && $0.availability == .available })
    }

    func testSavedListCapabilityOpenByDefault() {
        XCTAssertFalse(SavedBackendCapabilities.production.listSavedPosts)
        XCTAssertTrue(SavedBackendCapabilities.production.toggleSave)
    }
}
