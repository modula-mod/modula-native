import XCTest
@testable import Modula

@MainActor
final class NativeFoundationTests: XCTestCase {
    func testNativeRoutingWithoutRuntime() {
        let coordinator = NavigationCoordinator()
        coordinator.open(.productHub)
        coordinator.open(.profile("user-1"))
        XCTAssertEqual(coordinator.path, [.productHub, .profile("user-1")])
        coordinator.close()
        XCTAssertEqual(coordinator.path, [.productHub])
        coordinator.home()
        coordinator.close()
        XCTAssertTrue(coordinator.path.isEmpty)
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
}

@MainActor
final class HostBoundaryTests: XCTestCase {
    func testUnknownAndMalformedNavigationRejected() {
        XCTAssertNil(ModulaBridge.route(["route": "execute", "command": "anything"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": "../../account"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": ""]))
        XCTAssertEqual(ModulaBridge.route(["route": "profile", "userId": "account-1"]), .profile("account-1"))
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
        XCTAssertEqual(Set(properties.keys), ["sessionID", "moduleID", "bridgeVersion", "environment", "userID"])
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
        let client = GreenfieldClient(baseURL: try XCTUnwrap(URL(string: fixture.apiURL)))
        let account = try await client.signIn(email: fixture.email, password: fixture.password)

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
