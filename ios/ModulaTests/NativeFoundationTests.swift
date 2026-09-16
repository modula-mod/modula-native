import XCTest
@testable import Modula

@MainActor
final class NativeFoundationTests: XCTestCase {
    func testNativeRoutingWithoutRuntime() {
        let coordinator = NavigationCoordinator()
        coordinator.open(.productHub(.featured))
        coordinator.open(.productHub(.module("digital.modula.vault-notes", .overview)))
        XCTAssertEqual(coordinator.selectedTab, .modules)
        XCTAssertEqual(coordinator.path(for: .modules), [.productHub(.module("digital.modula.vault-notes", .overview))])
        coordinator.close()
        XCTAssertTrue(coordinator.path(for: .modules).isEmpty)
        coordinator.open(.profile("user-1", .overview))
        XCTAssertEqual(coordinator.selectedTab, .profile)
        coordinator.home()
        coordinator.close()
        XCTAssertEqual(coordinator.currentRoute, .home(.following))
    }

    func testDeviceAppearancePersistence() {
        let name = "modula-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .system)
        store.appearance = .oled
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .oled)
    }

    func testAppearanceV2PersistsAndResetsWithoutOtherDefaults() {
        let name = "modula-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("keep", forKey: "unrelated")
        let store = AppearanceStore(defaults: defaults)
        store.theme = .dark; store.darkStyle = .dim; store.accent = .violet; store.fontFamily = .editorial
        store.textSize = .large; store.density = .comfortable; store.motion = .expressive; store.haptics = .light
        store.contrastTransparency = .higherContrast; store.iconStyle = .filled; store.interfaceShape = .soft; store.moduleBranding = .preferUserAccent
        let restored = AppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.darkStyle, .dim); XCTAssertEqual(restored.accent, .violet); XCTAssertEqual(restored.fontFamily, .editorial)
        XCTAssertEqual(restored.textSize, .large); XCTAssertEqual(restored.density, .comfortable); XCTAssertEqual(restored.motion, .expressive)
        XCTAssertEqual(restored.haptics, .light); XCTAssertEqual(restored.contrastTransparency, .higherContrast); XCTAssertEqual(restored.iconStyle, .filled)
        XCTAssertEqual(restored.interfaceShape, .soft); XCTAssertEqual(restored.moduleBranding, .preferUserAccent)
        restored.reset()
        XCTAssertEqual(restored.theme, .system); XCTAssertEqual(restored.accent, .modulaTeal); XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }

    func testCanonicalRouteRoundTripsAndDefaults() throws {
        let cases = [
            "/home/for-you",
            "/profile/123/modules",
            "/product-hub/module/digital.modula.vault-notes/permissions",
            "/settings/appearance/typography/font-family",
            "/module/digital.modula.vault-notes/note/123"
        ]
        for path in cases {
            let route = try XCTUnwrap(RouteParser.parse(path), path)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route, path)
        }
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/home"))), "/home/following")
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/discover"))), "/discover/trending")
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/activity"))), "/activity/all")
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/profile/user-1"))), "/profile/user-1/overview")
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/product-hub"))), "/product-hub/featured")
        XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse("/messages"))), "/messages/inbox")
        XCTAssertEqual(RouteParser.parse("/messages/inbox"), .messages(.inbox))
        XCTAssertEqual(RouteParser.parse("/stories/create"), .stories(.create))
        XCTAssertEqual(RouteParser.parse("/reels"), .reels(.feed))
        XCTAssertEqual(RouteParser.parse("/messages/in-mail/"), .messages(.inMail(.inbox)))
    }

    func testDeepLinksAndModuleLocalPaths() {
        XCTAssertEqual(RouteParser.parse("modula://profile/user-1/modules"), .profile("user-1", .modules))
        XCTAssertEqual(RouteParser.parse("https://modula.digital/module/digital.modula.vault-notes/note/123"), .module("digital.modula.vault-notes", localPath: "/note/123"))
        XCTAssertNil(RouteParser.parse("https://evil.example/module/digital.modula.vault-notes"))
        XCTAssertNil(RouteParser.parse("/module/digital.modula.vault-notes/../settings"))
        XCTAssertNil(RouteParser.parse("/product-hub/module/%2Fetc"))
        XCTAssertNil(RouteParser.parse(String(repeating: "a", count: 2_049)))
    }

    func testRepresentativeGlobalRouteRegistry() throws {
        let routes: [AppRoute] = [
            .auth(.forgotPassword), .discover(.modules), .search(.section(.topics, "swift ui")), .post("post-1", .comments),
            .compose(.carousel), .notification("notification-1"), .profile("user-1", .connections), .me(.links),
            .productHub(.collection(.comingSoon)), .productHub(.category("productivity")), .productHub(.publisher("modula")),
            .productHub(.search("vault")), .productHub(.module("digital.modula.vault-notes", .versionHistory)),
            .settings(.account(.sessions)), .settings(.appearance(.textSize)), .settings(.notifications(.quietHours)),
            .settings(.privacy(.biometrics)), .settings(.modules(.module("digital.modula.vault-notes", .diagnostics))),
            .settings(.dataStorage(.export)), .settings(.accessibility(.motion)), .settings(.features(.experimental)),
            .settings(.updates(.unstable)), .settings(.developer(.featureFlags)), .settings(.about(.licenses)),
            .messages(.new), .messages(.conversation("conversation-1")), .teams(.create), .teams(.team("team-1", .members)),
            .developer(.bridge)
        ]
        for route in routes {
            let path = RouteSerializer.serialize(route)
            XCTAssertEqual(RouteParser.parse(path), route, path)
        }
        for invalid in ["/home/unknown", "/settings/appearance/surface", "/settings/appearance/color-family", "/teams/team-1/unknown", "/auth/nope", "/post//comments"] {
            XCTAssertNil(RouteParser.parse(invalid), invalid)
        }
    }

    func testShellChromeAndIndependentTabState() {
        let coordinator = NavigationCoordinator()
        coordinator.open(.post("home-post", .root))
        coordinator.select(.modules)
        coordinator.open(.productHub(.module("digital.modula.vault-notes", .overview)))
        coordinator.select(.home)
        XCTAssertEqual(coordinator.path(for: .home), [.post("home-post", .root)])
        XCTAssertEqual(coordinator.path(for: .modules), [.productHub(.module("digital.modula.vault-notes", .overview))])
        XCTAssertFalse(ShellChromePolicy.policy(for: .module("digital.modula.vault-notes", localPath: nil)).bottomBarVisible)
        XCTAssertTrue(ShellChromePolicy.policy(for: .home(.following)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .auth(.login)).bottomBarVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .settings(.account(.root))).bottomBarVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .settings(.account(.root))).shellAccessoryVisible)
        XCTAssertTrue(ShellChromePolicy.policy(for: .activity(.all)).shellAccessoryVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .discover(.trending)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .search(.root(nil))).shellAccessoryVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .messages(.inbox)).bottomBarVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .messages(.inbox)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .messages(.inbox)).shellAccessoryVisible)
        XCTAssertTrue(ShellChromePolicy.policy(for: .stories(.story("s1"))).immersive)
        XCTAssertFalse(ShellChromePolicy.policy(for: .reels(.feed)).shellAccessoryVisible)
    }

    func testContextRailLoopShapeStaysEdgeDockedAcrossMorph() {
        let rect = CGRect(x: 0, y: 0, width: 54, height: 236)
        for progress in [CGFloat(0), CGFloat(0.5), CGFloat(1)] {
            let bounds = ModulaRailShape(revealProgress: progress).path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX)
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX)
            XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.001)
            XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.001)
        }
    }

    func testInstalledProductStateUsesGreenfieldResponseNotBundlePresence() {
        let response: JSONValue = .array([
            .object(["moduleId": .string("digital.modula.vault-notes"), "status": .string("enabled")]),
            .object(["module_id": .string("digital.modula.tasks"), "status": .string("disabled")])
        ])
        XCTAssertEqual(GreenfieldClient.installedIDs(from: response), ["digital.modula.vault-notes", "digital.modula.tasks"])
        XCTAssertFalse(GreenfieldClient.installedIDs(from: response).contains("modula.runtime-diagnostic"))
    }
}

@MainActor
final class HostBoundaryTests: XCTestCase {
    func testUnknownAndMalformedNavigationRejected() {
        XCTAssertNil(ModulaBridge.route(["route": "execute", "command": "anything"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": "../../account"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": ""]))
        XCTAssertEqual(ModulaBridge.route(["route": "profile", "userId": "account-1"]), .profile("account-1", .overview))
    }
    func testPreparingAndRevokingDoesNotInitializeReact() {
        let runtime = ModuleRuntimeController()
        let environment = ModuleEnvironment(colorScheme: "dark", oled: true, reduceMotion: true, textScale: 1.3)
        let session = runtime.prepare(moduleID: "modula.runtime-diagnostic", environment: environment)
        XCTAssertNotNil(session)
        XCTAssertEqual(runtime.initializationCount, 0)
        if let session {
            runtime.unmount(session)
            XCTAssertFalse(session.isValid)
            XCTAssertNil(runtime.sessions[session.id])
        }
        XCTAssertEqual(runtime.initializationCount, 0)
    }
    func testMissingSessionAndUnversionedRequestsDenied() {
        ModulaBridge.shared.request("{}") { result in
            XCTAssertTrue(result.contains("REQUEST_DENIED"))
        }
    }
}

@MainActor
final class ModuleAuthorizationTests: XCTestCase {
    func testIdentityExpiryUnmountAndLogoutRejectHostRequests() async throws {
        let runtime = ModuleRuntimeController()
        let bridge = ModulaBridge()
        bridge.runtime = runtime
        let navigation = NavigationCoordinator()
        bridge.navigation = navigation
        let session = try XCTUnwrap(runtime.prepare(moduleID: "modula.runtime-diagnostic", environment: ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)))
        func request(moduleID: String? = nil, params: [String: Any] = [:]) -> String {
            let wire: [String: Any] = ["version": "0.1.0", "sessionID": session.id, "moduleID": moduleID ?? session.manifest.id, "action": "haptics.selection", "params": params]
            var response = ""
            bridge.request(String(data: try! JSONSerialization.data(withJSONObject: wire), encoding: .utf8)!) { response = $0 }
            return response
        }
        XCTAssertTrue(request(moduleID: "digital.modula.vault-notes").contains("REQUEST_DENIED"))
        XCTAssertTrue(request(params: ["unexpected": true]).contains("INVALID_PAYLOAD"))
        session.expiresAt = .distantPast
        XCTAssertTrue(request().contains("REQUEST_DENIED"))
        session.expiresAt = .distantFuture
        runtime.unmount(session)
        XCTAssertTrue(request().contains("REQUEST_DENIED"))
        runtime.setAccount("fixture-account")
        let signedIn = try XCTUnwrap(runtime.prepare(moduleID: "modula.runtime-diagnostic", environment: session.environment))
        XCTAssertTrue(runtime.authorize(signedIn))
        runtime.setAccount(nil)
        XCTAssertFalse(runtime.authorize(signedIn))
        XCTAssertEqual(runtime.initializationCount, 0)
    }
    func testBackendRejectsURLInjectionCrossCollectionAndBadRevision() {
        let manifest = ModuleManifest(id: "digital.modula.vault-notes", name: "Vault", version: "1.7.0", runtime: "react-native", entry: "vault", permissions: [], minHostVersion: "0.1.0", minBridgeVersion: "0.1.0", collections: ["note"])
        XCTAssertNil(ModuleBackendRequest.parse(action: "backend.records.list", params: ["collection": "note", "url": "https://example.com"], manifest: manifest))
        XCTAssertNil(ModuleBackendRequest.parse(action: "backend.records.list", params: ["collection": "account"], manifest: manifest))
        for revision: Any in [true, -1, 1.5, "1"] {
            XCTAssertNil(ModuleBackendRequest.parse(action: "backend.records.delete", params: ["collection": "note", "recordID": "note-1", "expectedRevision": revision], manifest: manifest))
        }
        XCTAssertEqual(ModuleBackendRequest.parse(action: "backend.records.list", params: ["collection": "note"], manifest: manifest)?.method, "GET")
    }

    func testJavaScriptInitialPropertiesContainNoCredential() throws {
        let runtime = ModuleRuntimeController()
        runtime.setAccount("account-identifier")
        let session = try XCTUnwrap(runtime.prepare(
            moduleID: "digital.modula.vault-notes",
            environment: ModuleEnvironment(colorScheme: "dark", oled: true, reduceMotion: true, textScale: 1.2)
        ))
        let properties = runtime.initialProperties(for: session)
        XCTAssertEqual(Set(properties.keys), ["sessionID", "moduleID", "bridgeVersion", "environment", "userID", "initialPath"])
        let wire = String(data: try JSONSerialization.data(withJSONObject: properties), encoding: .utf8)!.lowercased()
        for forbidden in ["password", "accesstoken", "refreshtoken", "authorization", "bearer", "cookie", "keychain"] {
            XCTAssertFalse(wire.contains(forbidden), "Initial module properties contained forbidden credential material")
        }
    }

    func testUnknownModuleAndReduceMotionEnvironmentAreSafe() {
        let runtime = ModuleRuntimeController()
        XCTAssertNil(runtime.prepare(moduleID: "digital.modula.unknown", environment: ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)))
        let session = runtime.prepare(moduleID: "digital.modula.vault-notes", environment: ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1))
        XCTAssertNotNil(session)
        if let session {
            runtime.update(ModuleEnvironment(colorScheme: "dark", oled: true, reduceMotion: true, textScale: 1.3), session: session)
            XCTAssertTrue(session.environment.reduceMotion)
            XCTAssertEqual(session.environment.colorScheme, "dark")
            XCTAssertTrue(session.environment.oled)
        }
        XCTAssertEqual(runtime.initializationCount, 0)
    }
}

@MainActor
final class GreenfieldBridgeIntegrationTests: XCTestCase {
    private struct Fixture: Decodable {
        let apiURL: String
        let email: String
        let password: String
    }
    private struct BridgeEnvelope: Decodable {
        let ok: Bool
        let data: JSONValue?
        let error: BridgeError?
        struct BridgeError: Decodable { let code: String }
    }

    func testRealVaultCRUDThroughAuthenticatedSwiftBridge() async throws {
        let secretPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["N1_SECRET_FILE"]
                ?? Bundle.main.object(forInfoDictionaryKey: "N1SecretFilePath") as? String
                ?? "/Users/msjoy/Developer/modula-native/.env.n1.local"
        )
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: secretPath)))
        // Prefer the Cloudflare N1 edge when the fixture points at the local TLS tunnel:
        // simulator unit tests do not install the development CA by default.
        let preferredURL: URL = {
            if let local = URL(string: fixture.apiURL),
               let host = local.host,
               host == "localhost" || host == "127.0.0.1",
               let edge = URL(string: "https://native-n1.modula.digital") {
                return edge
            }
            return URL(string: fixture.apiURL) ?? URL(string: "https://native-n1.modula.digital")!
        }()
        let client = GreenfieldClient(baseURL: preferredURL)
        let account: GreenfieldAccount
        do {
            account = try await client.signIn(email: fixture.email, password: fixture.password)
        } catch {
            throw XCTSkip("N1 fixture unreachable for bridge integration: \(error.localizedDescription)")
        }

        let runtime = ModuleRuntimeController()
        runtime.setAccount(account.accountId)
        let navigation = NavigationCoordinator()
        let bridge = ModulaBridge()
        bridge.runtime = runtime
        bridge.navigation = navigation
        bridge.client = client
        let session = try XCTUnwrap(runtime.prepare(
            moduleID: "digital.modula.vault-notes",
            environment: ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)
        ))

        let initial = try await call(bridge, session, action: "backend.records.list", params: ["collection": "note"])
        let initialItems = try items(initial)
        XCTAssertGreaterThanOrEqual(initialItems.filter { $0["data"]?["title"]?.string?.hasPrefix("N1 Fixture ") == true }.count, 4)

        let invalid = await rawCall(bridge, session, action: "backend.records.get", params: ["collection": "note", "recordID": "missing-note"])
        XCTAssertFalse(invalid.ok)
        XCTAssertEqual(invalid.error?.code, "BACKEND_REQUEST_FAILED")
        let recoveredList = try await call(bridge, session, action: "backend.records.list", params: ["collection": "note"])
        XCTAssertNotNil(recoveredList["items"])

        let title = "N1 Swift Bridge \(UUID().uuidString.prefix(8))"
        let created = try await call(bridge, session, action: "backend.records.create", params: [
            "collection": "note",
            "data": note(title: title, text: "Created through the authenticated Swift host bridge.")
        ])
        let recordID = try XCTUnwrap(created["record_id"]?.string)
        let revision = try integer(created["revision"])

        let read = try await call(bridge, session, action: "backend.records.get", params: ["collection": "note", "recordID": recordID])
        XCTAssertEqual(read["data"]?["title"]?.string, title)

        let editedTitle = "\(title) edited"
        let updated = try await call(bridge, session, action: "backend.records.update", params: [
            "collection": "note", "recordID": recordID, "expectedRevision": revision,
            "data": note(title: editedTitle, text: "The persisted edit also travelled through Swift.")
        ])
        let updatedRevision = try integer(updated["revision"])
        let reloaded = try await call(bridge, session, action: "backend.records.get", params: ["collection": "note", "recordID": recordID])
        XCTAssertEqual(reloaded["data"]?["title"]?.string, editedTitle)

        _ = try await call(bridge, session, action: "backend.records.delete", params: [
            "collection": "note", "recordID": recordID, "expectedRevision": updatedRevision
        ])
        let final = try await call(bridge, session, action: "backend.records.list", params: ["collection": "note"])
        XCTAssertFalse(try items(final).contains { $0["record_id"]?.string == recordID })

        runtime.unmount(session)
        let rejected = await rawCall(bridge, session, action: "backend.records.list", params: ["collection": "note"])
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.error?.code, "REQUEST_DENIED")
        // Keep the valid Keychain session for the RN UI acceptance that follows.
    }

    private func call(_ bridge: ModulaBridge, _ session: ModuleSession, action: String, params: [String: Any]) async throws -> JSONValue {
        let result = await rawCall(bridge, session, action: action, params: params)
        guard result.ok, let data = result.data else {
            XCTFail("Bridge request rejected with \(result.error?.code ?? "missing error")")
            throw APIError.invalidResponse
        }
        return data
    }

    private func rawCall(_ bridge: ModulaBridge, _ session: ModuleSession, action: String, params: [String: Any]) async -> BridgeEnvelope {
        let request: [String: Any] = [
            "version": ModuleRuntimeController.bridgeVersion,
            "moduleID": session.manifest.id,
            "sessionID": session.id,
            "action": action,
            "params": params
        ]
        let wire = String(data: try! JSONSerialization.data(withJSONObject: request), encoding: .utf8)!
        return await withCheckedContinuation { continuation in
            bridge.request(wire) { response in
                continuation.resume(returning: try! JSONDecoder().decode(BridgeEnvelope.self, from: Data(response.utf8)))
            }
        }
    }

    private func note(title: String, text: String) -> [String: Any] {
        [
            "title": title,
            "document": ["schemaVersion": "1.0.0", "blocks": [["id": "block-1", "type": "paragraph", "text": text]]],
            "plainTextProjection": text,
            "tagIds": [], "pinned": false, "favourite": false, "archived": false,
            "dataSchemaVersion": "1.0.0"
        ]
    }

    private func items(_ value: JSONValue) throws -> [[String: JSONValue]] {
        guard case .array(let values) = value["items"] else { throw APIError.invalidResponse }
        return try values.map {
            guard case .object(let object) = $0 else { throw APIError.invalidResponse }
            return object
        }
    }

    private func integer(_ value: JSONValue?) throws -> Int {
        guard case .number(let number) = value, number.rounded() == number else { throw APIError.invalidResponse }
        return Int(number)
    }
}
