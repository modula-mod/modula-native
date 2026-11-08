import Foundation
import XCTest
@testable import Modula

/// URLSession hands a URLProtocol the entity on `httpBodyStream` and clears `httpBody`.
/// `GreenfieldClient.send` still assigns `httpBody`. Empty streams stay nil so body-less deletes do too.
func urlProtocolJSONBody(_ request: URLRequest) -> JSONValue? {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&chunk, maxLength: chunk.count)
            if count <= 0 { break }
            buffer.append(chunk, count: count)
        }
        if !buffer.isEmpty { data = buffer }
    }
    return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

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
        XCTAssertEqual(RouteParser.parse("/collections/"), .collections(.root))
        XCTAssertEqual(RouteSerializer.serialize(.saved(.root)), "/saved")
        XCTAssertEqual(RouteSerializer.serialize(.drafts(.inMail)), "/drafts/in-mail")
    }

    func testFiveRootTabsUnchanged() {
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["home", "discover", "modules", "activity", "profile"])
        XCTAssertNil(AppRoute.command.tab)
        XCTAssertEqual(AppRoute.saved(.root).tab, .profile)
    }

    func testSidebarDestinationsStayOffTheTabBar() {
        let tabRoots: Set<AppRoute> = [
            .home(.following),
            .discover(.trending),
            .productHub(.featured),
            .activity(.all),
            .me(.overview)
        ]
        for destination in ShellSidebarDestination.allCases {
            XCTAssertFalse(tabRoots.contains(destination.route), destination.rawValue)
        }
        XCTAssertEqual(ShellSidebarDestination.saved.route, .saved(.root))
        XCTAssertEqual(ShellSidebarDestination.community.route, .community(.hub))
        XCTAssertEqual(ShellSidebarDestination.settings.route, .settings(.root))
        XCTAssertTrue(ShellSidebarDestination.saved.requiresSignIn)
        XCTAssertFalse(ShellSidebarDestination.community.requiresSignIn)
        XCTAssertFalse(ShellSidebarDestination.settings.requiresSignIn)
    }
}

private final class CollectionsDraftsContractProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var captured: [(method: String, path: String, query: String?, body: JSONValue?, authorization: String?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        let query = request.url?.query
        let body = urlProtocolJSONBody(request)
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let responseBody: String

        switch (method, path) {
        case ("POST", "/v1/sessions"):
            let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
            responseBody = #"{"ok":true,"data":{"accessToken":"access","refreshToken":"refresh","sessionId":"session","accessExpiresAt":"\#(future)","refreshExpiresAt":"\#(future)"}}"#
        case ("GET", "/v1/accounts/me"):
            responseBody = #"{"ok":true,"data":{"accountId":"account","primaryHandle":"me","status":"active"}}"#
        case ("POST", "/v1/me/collections"):
            Self.capture(method, path, query, body, authorization)
            responseBody = Self.collection(name: "Research", version: 1)
        case ("PATCH", "/v1/me/collections/11111111-1111-4111-8111-111111111111"):
            Self.capture(method, path, query, body, authorization)
            responseBody = Self.collection(name: "Field Notes", version: 2)
        case ("POST", "/v1/posts/22222222-2222-4222-8222-222222222222/save"):
            Self.capture(method, path, query, body, authorization)
            responseBody = #"{"ok":true,"data":{"saved":true}}"#
        case ("POST", "/v1/me/collections/11111111-1111-4111-8111-111111111111/items"):
            Self.capture(method, path, query, body, authorization)
            responseBody = #"{"ok":true,"data":{"item":{"id":"33333333-3333-4333-8333-333333333333","collectionId":"11111111-1111-4111-8111-111111111111","postId":"22222222-2222-4222-8222-222222222222","position":0,"available":true,"post":null,"version":1,"addedAt":"2026-11-03T10:00:00.000Z","updatedAt":"2026-11-03T10:00:00.000Z"}}}"#
        case ("DELETE", "/v1/me/collections/11111111-1111-4111-8111-111111111111/items/33333333-3333-4333-8333-333333333333"),
             ("DELETE", "/v1/me/collections/11111111-1111-4111-8111-111111111111"):
            Self.capture(method, path, query, body, authorization)
            responseBody = #"{"ok":true,"data":{"deleted":true}}"#
        case ("POST", "/v1/me/drafts"):
            Self.capture(method, path, query, body, authorization)
            responseBody = Self.draft(text: "Offline words", state: "editing", version: 1, publishedPostID: nil)
        case ("PATCH", "/v1/me/drafts/44444444-4444-4444-8444-444444444444"):
            Self.capture(method, path, query, body, authorization)
            responseBody = Self.draft(text: "Revised words", state: "editing", version: 2, publishedPostID: nil)
        case ("POST", "/v1/me/drafts/44444444-4444-4444-8444-444444444444/publish"):
            Self.capture(method, path, query, body, authorization)
            let draft = Self.draftObject(text: "Revised words", state: "published", version: 3,
                                         publishedPostID: "66666666-6666-4666-8666-666666666666")
            responseBody = #"{"ok":true,"data":{"draft":\#(draft),"postId":"66666666-6666-4666-8666-666666666666","created":true}}"#
        case ("GET", "/v1/posts/66666666-6666-4666-8666-666666666666"):
            Self.capture(method, path, query, body, authorization)
            responseBody = #"{"ok":true,"data":{"post":{"id":"66666666-6666-4666-8666-666666666666","createdAt":"2026-11-03T10:00:00.000Z","text":"Revised words","kind":"text","audience":"public","media":[]}}}"#
        case ("DELETE", "/v1/me/drafts/44444444-4444-4444-8444-444444444444"):
            Self.capture(method, path, query, body, authorization)
            responseBody = #"{"ok":true,"data":{"deleted":true}}"#
        default:
            responseBody = #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#
        }

        let status = responseBody.contains(#""ok":true"#) ? 200 : 404
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func capture(_ method: String, _ path: String, _ query: String?, _ body: JSONValue?, _ authorization: String?) {
        captured.append((method, path, query, body, authorization))
    }

    private static func collection(name: String, version: Int) -> String {
        #"{"ok":true,"data":{"collection":{"id":"11111111-1111-4111-8111-111111111111","name":"\#(name)","itemCount":0,"version":\#(version),"createdAt":"2026-11-03T10:00:00.000Z","updatedAt":"2026-11-03T10:00:00.000Z"}}}"#
    }

    private static func draft(text: String, state: String, version: Int, publishedPostID: String?) -> String {
        #"{"ok":true,"data":{"draft":\#(draftObject(text: text, state: state, version: version, publishedPostID: publishedPostID))}}"#
    }

    private static func draftObject(text: String, state: String, version: Int, publishedPostID: String?) -> String {
        let published = publishedPostID.map { #""\#($0)""# } ?? "null"
        return #"{"id":"44444444-4444-4444-8444-444444444444","idempotencyKey":"draft-idempotency","text":"\#(text)","feed":"following","audience":"public","replyPermission":"followers","content":[{"type":"image","attachmentId":"55555555-5555-4555-8555-555555555555","caption":"Evidence"}],"publishToAtproto":false,"state":"\#(state)","publishedPostId":\#(published),"version":\#(version),"createdAt":"2026-11-03T10:00:00.000Z","updatedAt":"2026-11-03T10:00:00.000Z"}"#
    }
}

final class CollectionsDraftsRepositoryContractTests: XCTestCase {
    func testCollectionsUseExactAtlasPathsBodiesVersionsAndAuthentication() async throws {
        CollectionsDraftsContractProtocol.captured = []
        let client = try await signedInClient()
        let repository = GreenfieldCollectionRepository(client: client)
        let collectionID = "11111111-1111-4111-8111-111111111111"
        let postID = "22222222-2222-4222-8222-222222222222"
        let itemID = "33333333-3333-4333-8333-333333333333"

        let created = try await repository.create(name: "Research")
        let renamed = try await repository.rename(id: collectionID, name: "Field Notes", expectedVersion: 1)
        let item = try await repository.add(collectionID: collectionID, postID: postID)
        try await repository.remove(collectionID: collectionID, itemID: itemID)
        try await repository.delete(id: collectionID, expectedVersion: 2)

        XCTAssertEqual(created.version, 1)
        XCTAssertEqual(renamed.name, "Field Notes")
        XCTAssertEqual(item.postID, postID)
        let requests = CollectionsDraftsContractProtocol.captured
        XCTAssertEqual(requests.map(\.path), [
            "/v1/me/collections",
            "/v1/me/collections/\(collectionID)",
            "/v1/posts/\(postID)/save",
            "/v1/me/collections/\(collectionID)/items",
            "/v1/me/collections/\(collectionID)/items/\(itemID)",
            "/v1/me/collections/\(collectionID)",
        ])
        XCTAssertEqual(requests[0].body, .object(["name": .string("Research")]))
        XCTAssertEqual(requests[1].body, .object(["name": .string("Field Notes"), "expectedVersion": .number(1)]))
        XCTAssertEqual(requests[2].body, .object([:]))
        XCTAssertEqual(requests[3].body, .object(["postId": .string(postID)]))
        XCTAssertNil(requests[4].body)
        XCTAssertEqual(requests[5].query, "expectedVersion=2")
        XCTAssertTrue(requests.allSatisfy { $0.authorization == "Bearer access" })
    }

    func testDraftsUseExactAtlasPayloadAndExactlyOncePublishContract() async throws {
        CollectionsDraftsContractProtocol.captured = []
        let client = try await signedInClient()
        let repository = GreenfieldDraftRepository(client: client)
        let draftID = "44444444-4444-4444-8444-444444444444"
        let attachmentID = "55555555-5555-4555-8555-555555555555"
        let media = CreationMedia(
            id: "local-image", kind: .image, filename: "image.jpg", altText: "Evidence",
            pixelWidth: 1200, pixelHeight: 900, byteCount: 1024, duration: nil, sensitive: false,
            remoteAttachmentID: attachmentID, uploadState: .ready
        )
        let local = PostDraft(
            id: "local-draft", accountID: "account", text: " Offline words ",
            mediaReferences: [media.id], media: [media], audience: "public", lastEdited: Date(),
            idempotencyKey: "draft-idempotency", feed: "following", replyPermission: "followers"
        )
        let created = try await repository.create(local)
        var update = local
        update.text = "Revised words"
        update.serverID = draftID
        update.serverVersion = 1
        let revised = try await repository.update(update)
        let outcome = try await repository.publish(id: draftID, expectedVersion: 2)
        let post = try await repository.post(id: outcome.postID)
        try await repository.delete(id: draftID, expectedVersion: 3)

        XCTAssertEqual(created.version, 1)
        XCTAssertEqual(revised.version, 2)
        XCTAssertEqual(outcome.draft.state, "published")
        XCTAssertEqual(post.id, outcome.postID)
        let requests = CollectionsDraftsContractProtocol.captured
        XCTAssertEqual(requests.map(\.path), [
            "/v1/me/drafts",
            "/v1/me/drafts/\(draftID)",
            "/v1/me/drafts/\(draftID)/publish",
            "/v1/posts/\(outcome.postID)",
            "/v1/me/drafts/\(draftID)",
        ])
        XCTAssertEqual(requests[0].body, .object([
            "idempotencyKey": .string("draft-idempotency"),
            "text": .string("Offline words"),
            "feed": .string("following"),
            "audience": .string("public"),
            "replyPermission": .string("followers"),
            "content": .array([.object([
                "type": .string("image"), "attachmentId": .string(attachmentID), "caption": .string("Evidence"),
            ])]),
            "publishToAtproto": .bool(false),
        ]))
        guard case .object(let updateBody)? = requests[1].body else { return XCTFail("Expected update object") }
        XCTAssertEqual(updateBody["expectedVersion"], .number(1))
        XCTAssertNil(updateBody["idempotencyKey"])
        XCTAssertEqual(requests[2].body, .object(["expectedVersion": .number(2)]))
        XCTAssertEqual(requests[4].query, "expectedVersion=3")
        XCTAssertTrue(requests.allSatisfy { $0.authorization == "Bearer access" })
    }

    func testLegacyLocalRecordsDecodeWithoutServerMetadata() throws {
        let collection = try JSONDecoder().decode(ModulaCollection.self, from: Data(#"{"id":"old","name":"Local","storage":"local","itemIDs":["post"],"createdAt":0,"updatedAt":0,"isDefault":false}"#.utf8))
        XCTAssertEqual(collection.syncState, .localOnly)
        XCTAssertNil(collection.version)

        let draft = try JSONDecoder().decode(PostDraft.self, from: Data(#"{"id":"old","text":"Safe","mediaReferences":[],"lastEdited":0}"#.utf8))
        XCTAssertEqual(draft.syncState, .localOnly)
        XCTAssertNil(draft.serverID)
        XCTAssertEqual(draft.feed, "following")
    }

    private func signedInClient() async throws -> GreenfieldClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollectionsDraftsContractProtocol.self]
        let client = GreenfieldClient(
            baseURL: URL(string: "https://collections-drafts-\(UUID().uuidString.prefix(8)).modula.test")!,
            transport: URLSession(configuration: configuration)
        )
        _ = try await client.signIn(email: "sync@example.com", password: "test-only")
        return client
    }
}

@MainActor
final class CollectionsDraftsConflictTests: XCTestCase {
    func testKeepBothPreservesStaleLocalEditAndServerRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = PrivateFileStore(domain: .drafts, rootURL: root)
        let media = DraftMediaStore(fileStore: PrivateFileStore(domain: .draftMedia, rootURL: root))
        let server = GreenfieldPostDraft(
            id: "44444444-4444-4444-8444-444444444444", idempotencyKey: "server-key",
            text: "Edited on client B", feed: "following", audience: "public",
            replyPermission: "everyone", content: [], publishToATProto: false,
            state: "editing", publishedPostID: nil, version: 2,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
        )
        let local = PostDraft(
            id: "local-a", accountID: nil, text: "Stale edit from client A", mediaReferences: [],
            lastEdited: Date(timeIntervalSince1970: 3), idempotencyKey: "local-key",
            serverID: server.id, serverVersion: 1, syncState: .conflict,
            syncConflict: DraftSyncConflict(server: server, detectedAt: Date(timeIntervalSince1970: 4))
        )
        let index = DraftIndex(posts: [local], inMails: [], stories: [])
        try files.saveData(try JSONEncoder().encode(index), filename: "draft-index.json")
        let store = DraftStore(fileStore: files, mediaStore: media)

        store.resolveConflictKeepingLocal(id: local.id)

        XCTAssertEqual(store.posts.count, 2)
        let preserved = try XCTUnwrap(store.posts.first(where: { $0.id == local.id }))
        XCTAssertEqual(preserved.text, "Stale edit from client A")
        XCTAssertNil(preserved.serverID)
        XCTAssertEqual(preserved.syncState, .pending)
        let serverCopy = try XCTUnwrap(store.posts.first(where: { $0.serverID == server.id }))
        XCTAssertEqual(serverCopy.text, "Edited on client B")
        XCTAssertEqual(serverCopy.serverVersion, 2)
        XCTAssertEqual(serverCopy.syncState, .synced)
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

    func testExperimentalNodusCommandIdentity() {
        let commands = CommandRegistry.visible(capabilities: CommandCapabilitySnapshot(signedIn: true))
        let command = commands.first { $0.id.rawValue == "open.intelligence.chat" }
        XCTAssertEqual(command?.title, "Nodus")
        XCTAssertTrue(command?.aliases.contains("nodus") == true)
        XCTAssertEqual(command?.action, .presentIntelligenceChat)
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
            CommandExecutor.perform(.presentIntelligenceChat, navigation: navigation, present: present),
            .executed
        )
        XCTAssertEqual(presented, .intelligenceChat)

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
    func testStoryPhotoAndAudienceSurviveReloadAndPostDraftCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = PrivateFileStore(domain: .drafts, rootURL: root)
        let media = DraftMediaStore(fileStore: PrivateFileStore(domain: .draftMedia, rootURL: root))
        let store = DraftStore(fileStore: files, mediaStore: media)
        store.setAccountID("story-owner")
        let photo = try media.importJPEG(Data([0xff, 0xd8, 0xff]), accountID: "story-owner", width: 1, height: 1)
        store.upsertStory(StoryDraft(id: "story-primary", mediaAssetIDs: [photo.id], caption: "A moment",
            lastEdited: Date(), media: photo, visibility: "followers"), debounce: false)
        store.upsertPost(PostDraft(id: "temporary-post", text: "Discard", mediaReferences: [], lastEdited: Date()), debounce: false)
        store.discardPost(id: "temporary-post")
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.fileURL(photo).path))
        let reloaded = DraftStore(fileStore: files, mediaStore: media)
        reloaded.setAccountID("story-owner")
        XCTAssertEqual(reloaded.stories.first?.media, photo)
        XCTAssertEqual(reloaded.stories.first?.visibility, "followers")
        reloaded.discardStory(id: "story-primary")
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.fileURL(photo).path))
    }

    func testComposerCloseCannotResavePublishedOrDiscardedDraft() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = PrivateFileStore(domain: .drafts, rootURL: root)
        let store = DraftStore(fileStore: files)
        var draft = CreationDraft.fresh(kind: .post, accountID: "acceptance", audience: .everyone)
        draft.text = "Finished"
        for terminalState in [CreationState.published, .discarded] {
            draft.state = terminalState
            store.upsertCreation(draft, debounce: false)
            XCTAssertTrue(store.flush())
            XCTAssertTrue(DraftStore(fileStore: files).posts.isEmpty)
        }
    }

    func testFlushPersistsEveryDraftKindBeforeDebounce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = PrivateFileStore(domain: .drafts, rootURL: root)
        let store = DraftStore(fileStore: files, autosaveMilliseconds: 60_000)
        store.upsertPost(PostDraft(id: "p", text: "Post", mediaReferences: [], lastEdited: Date()))
        store.upsertInMail(InMailDraft(toHandle: "reader", subject: "Subject", body: "Mail"))
        store.upsertStory(StoryDraft(id: "s", mediaAssetIDs: [], caption: "Story", lastEdited: Date()))
        XCTAssertTrue(store.flush())
        let reloaded = DraftStore(fileStore: files)
        XCTAssertEqual(reloaded.posts.first?.text, "Post")
        XCTAssertEqual(reloaded.inMailDraft()?.body, "Mail")
        XCTAssertEqual(reloaded.stories.first?.caption, "Story")
    }

    func testDiscardCancelsPendingAutosaveForEveryKind() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = PrivateFileStore(domain: .drafts, rootURL: root)
        let store = DraftStore(fileStore: files, autosaveMilliseconds: 10)
        store.upsertPost(PostDraft(id: "p", text: "Post", mediaReferences: [], lastEdited: Date()))
        store.upsertInMail(InMailDraft(toHandle: "reader", subject: "Subject", body: "Mail"))
        store.upsertStory(StoryDraft(id: "s", mediaAssetIDs: [], caption: "Story", lastEdited: Date()))
        store.discardPost(id: "p")
        store.discardInMail()
        store.discardStory(id: "s")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.flush())
        XCTAssertTrue(DraftStore(fileStore: files).allPreviews.isEmpty)
        XCTAssertTrue(DraftStore(fileStore: files).libraryItems.isEmpty)
    }

    func testDraftAudienceTitleIgnoresUnknownValues() {
        XCTAssertEqual(DraftLibraryItem.audienceTitle(for: "public"), "Everyone")
        XCTAssertEqual(DraftLibraryItem.audienceTitle(for: "followers"), "Followers")
        XCTAssertEqual(DraftLibraryItem.audienceTitle(for: "private"), "Only Me")
        XCTAssertNil(DraftLibraryItem.audienceTitle(for: nil))
        XCTAssertNil(DraftLibraryItem.audienceTitle(for: "close_friends"))
    }

    func testDiskFailureNeverReportsSavedAndCanRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // A regular file where a directory is required deterministically fails writes.
        try Data("blocked".utf8).write(to: root)
        let store = DraftStore(fileStore: PrivateFileStore(domain: .drafts, rootURL: root))
        store.upsertPost(PostDraft(id: "p", text: "Keep me", mediaReferences: [], lastEdited: Date()), debounce: false)
        XCTAssertFalse(store.showSavedIndicator)
        XCTAssertNotNil(store.saveError)
        XCTAssertFalse(store.flush())
        XCTAssertEqual(store.postDraft(id: "p")?.text, "Keep me")
        let collections = CollectionStore(fileStore: PrivateFileStore(domain: .collections, rootURL: root))
        XCTAssertNil(collections.create(name: "Must not claim success"))
        XCTAssertNotNil(collections.error)
        XCTAssertTrue(collections.userCollections.isEmpty)
        try FileManager.default.removeItem(at: root)
        XCTAssertTrue(store.flush())
        XCTAssertNil(store.saveError)
        XCTAssertEqual(DraftStore(fileStore: PrivateFileStore(domain: .drafts, rootURL: root)).posts.first?.text, "Keep me")
    }

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

    func testShareOutboundMessageKeepsTheCanonicalLink() {
        let post = SharePayload.post(id: "p1", authorName: "A", excerpt: "Hi", hasMedia: true)
        XCTAssertEqual(ShareOutboundMessage.text(note: "  ", payload: post), "https://modula.digital/post/p1")
        XCTAssertEqual(ShareOutboundMessage.text(note: "Look at this", payload: post), "Look at this\nhttps://modula.digital/post/p1")
    }

    func testShareAudienceUsesExistingDirectChatsAndSkipsEveryoneElse() {
        let group = Conversation(
            id: "group-1",
            kind: .group,
            participants: [MessagingFixtures.alex],
            lastMessage: nil,
            unreadCount: 0,
            updatedAt: Date(),
            titleOverride: "Group"
        )
        let request = Conversation(
            id: "req-1",
            kind: .request,
            participants: [MessagingFixtures.alex],
            lastMessage: nil,
            unreadCount: 0,
            updatedAt: Date(),
            titleOverride: nil
        )
        let people = ShareAudience.recipients(
            conversations: [MessagingFixtures.unreadConversation, MessagingFixtures.readConversation, group, request],
            suggestions: [
                person(id: "user-sophia", handle: "sophia.chen", name: "Sophia Chen"),
                person(id: "user-ada", handle: "ada", name: "Ada"),
                person(id: "user-me", handle: "me", name: "You"),
                person(id: "fixture", handle: "vps-checked-demo", name: "Fixture")
            ],
            ownID: "user-me",
            ownHandle: "me"
        )
        XCTAssertEqual(people.map(\.key), ["sophia.chen", "marcus", "ada"])
        XCTAssertEqual(people[0].conversationID, "convo-sophia")
        XCTAssertEqual(people[1].conversationID, "convo-marcus")
        XCTAssertNil(people[2].conversationID)
        XCTAssertFalse(people[2].hasDirectChat)
        XCTAssertEqual(people[2].subtitle, "@ada · Start a chat")
        XCTAssertEqual(
            ShareAudience.directConversationID(matching: "@Sophia.Chen", in: [MessagingFixtures.unreadConversation]),
            "convo-sophia"
        )
        XCTAssertNil(ShareAudience.directConversationID(matching: "ada", in: [MessagingFixtures.unreadConversation]))
        XCTAssertNil(ShareAudience.directConversationID(matching: "alex", in: [group, request]))
    }

    private func person(id: String, handle: String, name: String) -> DiscoverPerson {
        DiscoverPerson(
            id: id,
            handle: handle,
            displayName: name,
            kind: nil,
            bio: nil,
            avatarURL: nil,
            followerCount: nil,
            followingCount: nil,
            postCount: nil,
            isFollowing: false,
            followsViewer: false,
            isVerified: false,
            joinedAt: nil
        )
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
        let caps = CommandCapabilitySnapshot(signedIn: true, storyCreate: false, messagingSend: false, inMailCompose: false)
        let actions = CreateActionRegistry.actions(capabilities: caps)
        XCTAssertTrue(actions.contains { $0.id == "post" && $0.availability == .available })
        XCTAssertFalse(actions.contains { $0.id == "message" && $0.availability == .available })
    }

    func testSavedListCapabilityOpenByDefault() {
        XCTAssertTrue(SavedBackendCapabilities.production.listSavedPosts)
        XCTAssertTrue(SavedBackendCapabilities.production.toggleSave)
        XCTAssertEqual(SavedBackendCapabilities.Paths.savedPosts(cursor: nil), "/v1/saves?limit=30")
        XCTAssertTrue(SavedBackendCapabilities.Paths.savedPosts(cursor: "a|b").contains("cursor=a%7Cb"))
        XCTAssertTrue(SavedBackendCapabilities.production.pagination)
    }

    func testIntelligenceChatReplyUsesRealTextOnly() {
        XCTAssertEqual(IntelligenceChatIdentity.title, "Nodus")
        XCTAssertTrue(IntelligenceChatIdentity.aliases.contains("nodus"))
        XCTAssertEqual(IntelligenceChatView.activeProviderID, NodusIntelligenceProvider.providerID)
        XCTAssertFalse(NodusChatPresentation.accessorySheet.showsDeveloperDiagnostics)
        XCTAssertTrue(NodusChatPresentation.developerWorkspace.showsDeveloperDiagnostics)
        XCTAssertEqual(IntelligenceChatView.replyText(from: .string(" Hello ")), "Hello")
        XCTAssertEqual(
            IntelligenceChatView.replyText(from: .object(["text": .string("On device")])),
            "On device"
        )
        XCTAssertNil(IntelligenceChatView.replyText(from: .object(["source": .string(DeterministicLocalProvider.providerID)])))
        XCTAssertEqual(
            IntelligenceChatView.userMessage(for: .localProviderUnavailable),
            "On-device intelligence isn’t available right now."
        )
    }

    func testPullDestinationResolvesFromHorizontal() {
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 0), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: -20), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 20), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: -52), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 52), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: -80), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 80), .refresh)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: -88), .command)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 88), .search)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 167), .search)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 168), .ai)
        XCTAssertEqual(ModulaPullDestination.resolve(horizontal: 220), .ai)
        XCTAssertEqual(ModulaPullDestination.allCases.map(\.title), ["Command", "Refresh", "Search", "AI Mode"])
    }
}
