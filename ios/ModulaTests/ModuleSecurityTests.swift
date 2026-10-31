import XCTest
@testable import Modula

/// Module security: surface-bound sessions, per-surface events, release gates, semver
/// ranges, renewal, keep-alive, permission policy and error mapping.
@MainActor
final class ModuleSecurityTests: XCTestCase {
    private func manifest(_ id: String, permissions: [String] = ["diagnostics.ready", "backend.records.list"],
                          host: String = "0.1.0", bridge: String = "0.1.0") -> ModuleManifest {
        ModuleManifest(id: id, name: id, version: "1.0.0", runtime: "react-native", entry: "index",
                       permissions: permissions, minHostVersion: host, minBridgeVersion: bridge, collections: ["note"])
    }
    private var environment: ModuleEnvironment { ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1) }
    private let bridge = ModulaBridge()

    private func request(_ token: String, module: String, action: String = "diagnostics.ready",
                         params: [String: Any] = [:]) async -> [String: Any] {
        let wire = try! JSONSerialization.data(withJSONObject: [
            "version": "0.1.0", "moduleID": module, "surfaceToken": token, "action": action, "params": params,
        ])
        return await withCheckedContinuation { continuation in
            bridge.request(String(data: wire, encoding: .utf8)!) { reply in
                continuation.resume(returning: try! JSONSerialization.jsonObject(with: Data(reply.utf8)) as! [String: Any])
            }
        }
    }
    private func code(_ reply: [String: Any]) -> String? { (reply["error"] as? [String: Any])?["code"] as? String }

    func testSpoofedSessionIDIsRejected() async {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        bridge.runtime = runtime
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        let reply1 = await request(session.id, module: "a.mod")

        XCTAssertEqual(code(reply1), "REQUEST_DENIED", "native session ID must not authorize")
        let reply2 = await request(ModuleSession.randomToken(), module: "a.mod")

        XCTAssertEqual(code(reply2), "REQUEST_DENIED")
        XCTAssertNotNil(runtime.session(forToken: session.surfaceToken, moduleID: "a.mod"))
    }

    func testModuleCannotUseAnotherModulesTokenWithItsOwnIdentity() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod"), manifest("b.mod")])
        let a = runtime.prepare(moduleID: "a.mod", environment: environment)!
        _ = runtime.prepare(moduleID: "b.mod", environment: environment)!
        XCTAssertNil(runtime.session(forToken: a.surfaceToken, moduleID: "b.mod"))
    }

    func testEventsAreDeliveredPerSurfaceWithoutTokens() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod"), manifest("b.mod")])
        let a = runtime.prepare(moduleID: "a.mod", environment: environment)!
        let b = runtime.prepare(moduleID: "b.mod", environment: environment)!
        var delivered: [(String, [String: Any])] = []
        runtime.eventObserver = { delivered.append(($0, $1)) }
        var changed = environment
        changed.accent = "#FF0000"
        runtime.update(changed, session: a)
        XCTAssertEqual(delivered.map(\.0), [a.id])
        let props = delivered[0].1
        XCTAssertEqual(props["surfaceToken"] as? String, a.surfaceToken)
        XCTAssertFalse(props.values.contains { ($0 as? String) == b.surfaceToken })
        XCTAssertNil(props["sessionID"])
    }

    func testNotInstalledBlocksLoad() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        runtime.installationGate = { _ in .notInstalled }
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        XCTAssertEqual(session.state, .notInstalled)
        XCTAssertFalse(session.isValid)
        XCTAssertNil(runtime.session(forToken: session.surfaceToken, moduleID: "a.mod"))
    }

    func testInstalledReleaseWithoutTrustedPlanFailsClosed() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        runtime.installationGate = { _ in .untrustedRelease }
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        XCTAssertEqual(session.state, .integrityFailed)
        XCTAssertFalse(session.isValid)
        XCTAssertNil(runtime.session(forToken: session.surfaceToken, moduleID: "a.mod"))
    }

    private func descriptor(module: String = "a.mod", tamper: Bool = false, revoked: Bool = false,
                            granted: [String] = ["storage:records"]) throws -> ModuleInstallDescriptor {
        var body: [String: JSONValue] = [
            "permissions": .object(["granted": .array(granted.map(JSONValue.string)), "denied": .array([])]),
            "descriptorVersion": .string("1.0.0"), "moduleId": .string(module), "version": .string("1.0.0"),
            "registryReleaseId": .string("r1"),
            "trust": .object(["revoked": .bool(revoked), "quarantined": .bool(false), "signatureState": .string("valid")]),
        ]
        body["descriptorSha256"] = .string(CanonicalJSON.sha256Hex(.object(body)))
        if tamper { body["version"] = .string("9.9.9") }
        return try XCTUnwrap(ModuleInstallDescriptor(json: .object(body)))
    }

    func testHashMismatchBlocksLoad() throws {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        runtime.installationGate = { _ in .runnable(descriptor: try! self.descriptor(tamper: true)) }
        let blocked = try XCTUnwrap(runtime.prepare(moduleID: "a.mod", environment: environment))
        XCTAssertEqual(blocked.state, .integrityFailed)
        XCTAssertFalse(blocked.isValid)
        XCTAssertEqual(ModuleReleaseVerifier.verify(moduleID: "a.mod", bundledManifest: nil, descriptor: try descriptor(tamper: true)), .descriptorDigest)
        XCTAssertEqual(ModuleReleaseVerifier.verify(moduleID: "b.mod", bundledManifest: nil, descriptor: try descriptor()), .wrongModule)
        XCTAssertEqual(ModuleReleaseVerifier.verify(moduleID: "a.mod", bundledManifest: nil, descriptor: try descriptor(revoked: true)), .revoked)
        runtime.installationGate = { _ in .runnable(descriptor: try! self.descriptor()) }
        XCTAssertTrue(try XCTUnwrap(runtime.prepare(moduleID: "a.mod", environment: environment)).isValid)
    }

    func testBundledManifestDigestMustMatchWhenPublished() throws {
        let bundled: JSONValue = .object(["id": .string("a.mod"), "version": .string("1.0.0")])
        var body: [String: JSONValue] = [
            "descriptorVersion": .string("1.0.0"), "moduleId": .string("a.mod"), "version": .string("1.0.0"),
            "registryReleaseId": .string("r1"), "trust": .object(["revoked": .bool(false), "quarantined": .bool(false)]),
            "manifest": .object(["bundledManifestSha256": .string(String(repeating: "a", count: 64))]),
        ]
        body["descriptorSha256"] = .string(CanonicalJSON.sha256Hex(.object(body)))
        let mismatched = try XCTUnwrap(ModuleInstallDescriptor(json: .object(body)))
        XCTAssertEqual(ModuleReleaseVerifier.verify(moduleID: "a.mod", bundledManifest: bundled, descriptor: mismatched), .bundledDigest)
        body["manifest"] = .object(["bundledManifestSha256": .string(CanonicalJSON.sha256Hex(bundled))])
        body.removeValue(forKey: "descriptorSha256")
        body["descriptorSha256"] = .string(CanonicalJSON.sha256Hex(.object(body)))
        let matching = try XCTUnwrap(ModuleInstallDescriptor(json: .object(body)))
        XCTAssertNil(ModuleReleaseVerifier.verify(moduleID: "a.mod", bundledManifest: bundled, descriptor: matching))
    }

    func testSemverVectorsShared() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../packages/module-contracts/test-vectors/semver.json").standardized
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("Shared vectors not readable from this destination") }
        let cases = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["satisfies"] as? [[String: Any]])
        for item in cases {
            let range = item["range"] as! String, version = item["version"] as! String
            XCTAssertEqual(SemverRange.satisfies(version, range: range), item["expected"] as? Bool, "\(range) vs \(version)")
        }
    }

    func testUpdateRequiredState() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod", host: "^0.2.0")])
        XCTAssertEqual(runtime.prepare(moduleID: "a.mod", environment: environment)?.state, .updateRequired)
        let patched = ModuleRuntimeController(manifests: [manifest("a.mod", host: "0.1.0", bridge: ">=0.1.0 <0.2.0")])
        XCTAssertNotEqual(patched.prepare(moduleID: "a.mod", environment: environment)?.state, .updateRequired)
    }

    func testActivityRenewsAndIdleExpires() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        runtime.now = { clock }
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        clock += 14 * 60
        XCTAssertTrue(runtime.authorize(session))          // activity renews to +15 min
        clock += 14 * 60
        XCTAssertTrue(runtime.authorize(session))          // still valid because renewed
        clock += 16 * 60
        XCTAssertFalse(runtime.authorize(session))
        XCTAssertEqual(session.state, .expired)
    }

    func testSuspendKeepsSessionAndResumeRestores() {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        session.state = .ready
        runtime.suspend(session)
        XCTAssertTrue(session.isValid); XCTAssertEqual(session.state, .suspended)
        runtime.resume(session)
        XCTAssertEqual(session.state, .ready)
        runtime.setAccount("other")
        XCTAssertFalse(session.isValid, "account change still revokes")
    }

    func testPermissionDeniedAndUserIDGated() async {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod", permissions: ["diagnostics.ready"])])
        runtime.setAccount("acct-1")
        bridge.runtime = runtime
        let session = runtime.prepare(moduleID: "a.mod", environment: environment)!
        XCTAssertTrue(runtime.initialProperties(for: session)["userID"] is NSNull, "no identity.userID ⇒ no userID")
        let reply3 = await request(session.surfaceToken, module: "a.mod", action: "haptics.selection")

        XCTAssertEqual(code(reply3), "PERMISSION_DENIED")
        XCTAssertTrue(session.deniedCapabilities.contains("haptics.selection"))
        let withIdentity = ModuleRuntimeController(manifests: [manifest("b.mod", permissions: ["diagnostics.ready", "identity.userID"])])
        withIdentity.setAccount("acct-1")
        let b = withIdentity.prepare(moduleID: "b.mod", environment: environment)!
        XCTAssertEqual(withIdentity.initialProperties(for: b)["userID"] as? String, "acct-1")
        let required = ModuleRuntimeController(manifests: [manifest("c.mod", permissions: ["diagnostics.ready", "camera.capture"])])
        XCTAssertEqual(required.prepare(moduleID: "c.mod", environment: environment)?.deniedCapabilities, ["camera.capture"])
        // The registry withheld record storage the module declared → native permission-denied state.
        let withheld = ModuleRuntimeController(manifests: [manifest("a.mod")])
        withheld.installationGate = { _ in .runnable(descriptor: try! self.descriptor(granted: ["functions:register"])) }
        let blocked = withheld.prepare(moduleID: "a.mod", environment: environment)
        XCTAssertEqual(blocked?.state, .permissionDenied)
        XCTAssertEqual(blocked?.deniedCapabilities, ["backend.records.list"])
        withheld.installationGate = { _ in .runnable(descriptor: try! self.descriptor(granted: ["storage:records"])) }
        XCTAssertEqual(withheld.prepare(moduleID: "a.mod", environment: environment)?.isValid, true)
    }

    func testRecordGrantsCoverHostRecordCapabilities() throws {
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod", permissions: [
            "backend.records.list", "backend.records.get", "backend.records.create", "backend.records.delete",
        ])])
        runtime.installationGate = { _ in .runnable(descriptor: try! self.descriptor(granted: [
            "records:module.digital.modula.vault-notes.note:read",
            "records:module.digital.modula.vault-notes.note:write",
            "records:module.digital.modula.vault-notes.note:delete",
        ])) }
        let session = try XCTUnwrap(runtime.prepare(moduleID: "a.mod", environment: environment))
        XCTAssertTrue(session.isValid, "record grants cover the host record actions they name")
        XCTAssertTrue(session.grantedCapabilities.isSuperset(of: [
            "backend.records.list", "backend.records.get", "backend.records.create", "backend.records.delete",
        ]))
        let readOnly = ModuleRuntimeController(manifests: [manifest("b.mod", permissions: [
            "backend.records.list", "backend.records.create",
        ])])
        readOnly.installationGate = { _ in .runnable(descriptor: try! self.descriptor(module: "b.mod", granted: [
            "records:module.digital.modula.vault-notes.note:read",
        ])) }
        let blocked = try XCTUnwrap(readOnly.prepare(moduleID: "b.mod", environment: environment))
        XCTAssertEqual(blocked.state, .permissionDenied)
        XCTAssertTrue(blocked.deniedCapabilities.contains("backend.records.create"))
    }

    func testEveryVaultNotesPermissionIsClassified() {
        let permissions = [
            "schemas:register", "settings:register", "routes:register", "functions:register", "events:subscribe", "search:index",
            "records:module.digital.modula.vault-notes.note:read", "records:module.digital.modula.vault-notes.note:write", "records:module.digital.modula.vault-notes.note:delete",
            "records:module.digital.modula.vault-notes.folder:read", "records:module.digital.modula.vault-notes.folder:write", "records:module.digital.modula.vault-notes.folder:delete",
            "records:module.digital.modula.vault-notes.tag:read", "records:module.digital.modula.vault-notes.tag:write",
            "records:module.digital.modula.vault-notes.note-link:read", "records:module.digital.modula.vault-notes.note-link:write",
            "records:module.digital.modula.vault-notes.note-version:read", "records:module.digital.modula.vault-notes.note-version:write",
            "records:module.digital.modula.vault-notes.saved-source:read", "records:module.digital.modula.vault-notes.saved-source:write",
            "records:module.digital.modula.vault-notes.attachment:read", "records:module.digital.modula.vault-notes.attachment:write", "records:module.digital.modula.vault-notes.attachment:delete",
            "records:module.digital.modula.vault-notes.template:read", "records:module.digital.modula.vault-notes.template:write", "records:module.digital.modula.vault-notes.template:delete",
            "records:module.digital.modula.vault-notes.saved-search:read", "records:module.digital.modula.vault-notes.saved-search:write", "records:module.digital.modula.vault-notes.saved-search:delete",
            "settings:read", "settings:write",
            "media:module.digital.modula.vault-notes.note:read", "media:module.digital.modula.vault-notes.note:write",
            "sharing:module.digital.modula.vault-notes.note:read", "sharing:module.digital.modula.vault-notes.note:write",
        ]
        XCTAssertEqual(permissions.count, 35)
        XCTAssertEqual(Set(permissions.map(ModulePolicy.classify)), ["server", "records", "settings", "media", "sharing"])
        XCTAssertFalse(permissions.contains { ModulePolicy.classify($0) == "unrecognized" })
        XCTAssertEqual(ModulePolicy.classify("records:module.digital.modula.vault-notes.tag:read"), "records")
        XCTAssertEqual(ModulePolicy.classify("events:subscribe"), "server")
        XCTAssertEqual(ModulePolicy.classify("search:index"), "server")
        XCTAssertEqual(ModulePolicy.classify("notifications:create"), "notifications")
        XCTAssertEqual(ModulePolicy.classify("files:temporary:write"), "files")
        XCTAssertEqual(ModulePolicy.classify("jobs:create"), "jobs")
        XCTAssertEqual(ModulePolicy.classify("widgets:register"), "server")
        XCTAssertEqual(ModulePolicy.classify("records:module.digital.modula.vault-notes.tag:delete"), "records")
        XCTAssertEqual(ModulePolicy.classify("reminders:create"), "reminders")
        XCTAssertEqual(ModulePolicy.classify("ai:complete"), "ai")
    }

    func testVerifiedFrontendRejectsReencodedJSON() {
        let original = Data("{\"releaseVersion\":\"2.0.0\"}".utf8)
        let reencoded = Data("{\n  \"releaseVersion\" : \"2.0.0\"\n}".utf8)
        let sha = VerifiedFrontendSelection.sha256(original)
        XCTAssertNotEqual(VerifiedFrontendSelection.sha256(reencoded), sha)
        XCTAssertEqual(
            VerifiedFrontendSelection.choose(declaredSha256: sha, artifact: original, hosted: reencoded),
            original
        )
        XCTAssertNil(VerifiedFrontendSelection.choose(declaredSha256: sha, artifact: nil, hosted: reencoded))
        XCTAssertEqual(ModulePolicy.hostCapabilities(coveredBy: [
            "records:module.digital.modula.vault-notes.note:read",
            "records:module.digital.modula.vault-notes.note:write",
            "records:module.digital.modula.vault-notes.note:delete",
        ]), [
            "backend.records.create", "backend.records.delete", "backend.records.get",
            "backend.records.list", "backend.records.update",
        ])
    }

    func testBackendErrorsMapToCodes() {
        XCTAssertEqual(HostErrorCode(APIError.rejected(409, "raw server text")), .backendConflict)
        XCTAssertEqual(HostErrorCode(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(HostErrorCode(APIError.rejected(401, "MODULE_NOT_INSTALLED")), .backendUnauthenticated)
        XCTAssertEqual(HostErrorCode(APIError.rejected(503, "upstream detail")), .backendUnavailable)
        XCTAssertFalse(ModulaBridge.reply(error: .backendConflict).contains("raw server text"))
    }

    func testModule401DoesNotSignTheAppOutWhileShellSessionIsValid() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModuleAuthRouter.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://msec-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        ModuleAuthRouter.handler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "", path) {
            case ("POST", "/v1/sessions"), ("POST", "/v1/sessions/refresh"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct","primaryHandle":"me","status":"active"}}"#)
            case ("DELETE", "/v1/sessions/current"): return (200, #"{"ok":true,"data":{"revoked":true}}"#)
            default:
                if path.hasPrefix("/v1/modules/a.mod/records") {
                    return (401, #"{"ok":false,"error":{"code":"MODULE_NOT_INSTALLED","message":"raw backend detail"}}"#)
                }
                return (404, "{}")
            }
        }
        defer { ModuleAuthRouter.handler = nil }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let runtime = ModuleRuntimeController(manifests: [manifest("a.mod")])
        runtime.setAccount("acct")
        bridge.runtime = runtime
        bridge.client = client
        var signedOut = false
        bridge.authenticationInvalidated = { signedOut = true }
        let session = try XCTUnwrap(runtime.prepare(moduleID: "a.mod", environment: environment))
        let reply = await request(session.surfaceToken, module: "a.mod", action: "backend.records.list", params: ["collection": "note"])
        XCTAssertEqual(code(reply), "BACKEND_UNAUTHENTICATED")
        XCTAssertFalse(String(describing: reply).contains("raw backend detail"), "backend text never reaches JS")
        let stillSignedIn = await client.hasSession()
        XCTAssertTrue(stillSignedIn, "a module-scoped 401 must not invalidate the shell session")
        XCTAssertFalse(signedOut)
        try? await client.signOut()
    }
}

private final class ModuleAuthRouter: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
