import XCTest
@testable import Modula

/// Upgrade/downgrade between registry versions: canonical descriptor digests (cross-checked
/// against a descriptor produced by Greenfield's `descriptorDigest`), verification failure
/// modes, row actions, preview parsing and the store's switch flow.
final class ModuleVersionSwitchTests: XCTestCase {
    /// Produced on the server with `canonicalJsonStringify` + SHA-256 (issuedAt excluded).
    static let serverDescriptor = #"{"descriptorVersion":"1.0.0","moduleId":"digital.modula.vault-notes","version":"1.6.0","registryReleaseId":"rel-160","manifest":{"adapterManifestSha256":"ae1eae1d76e5b7c865c4122ce366a08025842566d2d96c75cc13e6353a73db0d","productManifestSha256":"a8792157cb4f27fb949c035f45518c61e884bb86e6f420204379c2baa8beb66e","ref":"https://api.modula.test/v1/registry/modules/digital.modula.vault-notes/versions/1.6.0"},"artifact":{"sha256":"c7c5c1d70c5dec4416ab6158afd0b223ef40c29b1dc1f97ed9428b94d4cadb1c","ref":"https://api.modula.test/v1/registry/modules/digital.modula.vault-notes/versions/1.6.0/artifact","sizeBytes":48213},"frontend":{"sha256":"1cf387c012cd2d02f1923e589f86df4a4802427057dbc90f47b87f04d29d54bc","ref":"https://api.modula.test/v1/registry/modules/digital.modula.vault-notes/versions/1.6.0/frontend"},"trust":{"signatureState":"unsigned","verified":true,"revoked":false,"quarantined":false,"warnings":["UNSIGNED_RELEASE"]},"compatibility":{"compatible":true,"platforms":["ios","web"],"hostRange":null,"note":"Notes — “vault” ✓","ratio":0.5},"permissions":{"granted":["functions:register","storage:records"],"denied":[]},"descriptorSha256":"0dce5f5639871bb8e9bfba3284b67ec7e3ee77337186f5afa9b1383dbc84ae1e","issuedAt":"2026-10-01T21:00:00.000Z"}"#

    static let facts = ModuleRegistryReleaseFacts(
        registryReleaseId: "rel-160",
        releaseSha256: "c7c5c1d70c5dec4416ab6158afd0b223ef40c29b1dc1f97ed9428b94d4cadb1c",
        adapterManifestSha256: "ae1eae1d76e5b7c865c4122ce366a08025842566d2d96c75cc13e6353a73db0d",
        productManifestSha256: "a8792157cb4f27fb949c035f45518c61e884bb86e6f420204379c2baa8beb66e",
        frontendSha256: "1cf387c012cd2d02f1923e589f86df4a4802427057dbc90f47b87f04d29d54bc")

    static func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Re-issues the fixture with `edit` applied and a freshly computed (valid) digest.
    static func reissued(_ edit: (inout [String: JSONValue]) -> Void) throws -> ModuleInstallDescriptor {
        guard case .object(var body) = try json(serverDescriptor) else { throw XCTSkip("fixture") }
        edit(&body)
        body.removeValue(forKey: "descriptorSha256"); body.removeValue(forKey: "issuedAt")
        body["descriptorSha256"] = .string(CanonicalJSON.sha256Hex(.object(body)))
        return try XCTUnwrap(ModuleInstallDescriptor(json: .object(body)))
    }

    func testCanonicalDigestMatchesRegistryDescriptor() throws {
        let descriptor = try XCTUnwrap(ModuleInstallDescriptor(json: try Self.json(Self.serverDescriptor)))
        XCTAssertEqual(descriptor.computedSha256, "0dce5f5639871bb8e9bfba3284b67ec7e3ee77337186f5afa9b1383dbc84ae1e")
        XCTAssertEqual(descriptor.computedSha256, descriptor.descriptorSha256)
        XCTAssertEqual(CanonicalJSON.string(.object(["b": .number(1), "a": .array([.null, .bool(true), .number(0.5)]), "é": .string("q\"\n")])),
                       #"{"a":[null,true,0.5],"b":1,"é":"q\"\n"}"#)
    }

    func testVerifierAcceptsDescriptorMatchingRegistry() throws {
        let descriptor = try XCTUnwrap(ModuleInstallDescriptor(json: try Self.json(Self.serverDescriptor)))
        XCTAssertNoThrow(try InstallDescriptorVerifier.verify(descriptor, moduleId: "digital.modula.vault-notes", version: "1.6.0",
                                                              registry: Self.facts, registryHost: "api.modula.test"))
    }

    func testVerifierRejectsTamperedOrUntrustedDescriptors() throws {
        let id = "digital.modula.vault-notes"
        func check(_ descriptor: ModuleInstallDescriptor, version: String = "1.6.0", registry: ModuleRegistryReleaseFacts = ModuleVersionSwitchTests.facts,
                   host: String? = "api.modula.test", _ expected: InstallDescriptorVerificationError, line: UInt = #line) {
            XCTAssertThrowsError(try InstallDescriptorVerifier.verify(descriptor, moduleId: id, version: version, registry: registry, registryHost: host), line: line) {
                XCTAssertEqual($0 as? InstallDescriptorVerificationError, expected, line: line)
            }
        }
        // Body edited without re-issuing: the descriptor digest no longer recomputes.
        guard case .object(var tampered) = try Self.json(Self.serverDescriptor) else { return XCTFail() }
        tampered["permissions"] = .object(["granted": .array([.string("network:any")]), "denied": .array([])])
        check(try XCTUnwrap(ModuleInstallDescriptor(json: .object(tampered))), .digestMismatch)
        // A validly digested descriptor for another version or release.
        let good = try XCTUnwrap(ModuleInstallDescriptor(json: try Self.json(Self.serverDescriptor)))
        check(good, version: "1.7.0", .wrongRelease)
        check(good, registry: .init(registryReleaseId: "rel-other", releaseSha256: Self.facts.releaseSha256, adapterManifestSha256: Self.facts.adapterManifestSha256,
                                    productManifestSha256: Self.facts.productManifestSha256, frontendSha256: Self.facts.frontendSha256), .wrongRelease)
        // Digests that disagree with what the public registry publishes.
        let swapped = try Self.reissued { $0["artifact"] = .object(["sha256": .string(String(repeating: "a", count: 64))]) }
        check(swapped, .registryMismatch("artifact"))
        let malformed = try Self.reissued { $0["frontend"] = .object(["sha256": .string("XYZ")]) }
        check(malformed, .digestMalformed("frontend"))
        // Artifacts may only come from the registry origin: never GitHub, never http.
        let github = try Self.reissued {
            $0["artifact"] = .object(["sha256": .string(Self.facts.releaseSha256!), "ref": .string("https://github.com/modula-mod/modula-vault-notes/releases/download/v1.6.0/a.zip")])
        }
        check(github, .untrustedRef("the artifact"))
        let plain = try Self.reissued {
            $0["frontend"] = .object(["sha256": .string(Self.facts.frontendSha256!), "ref": .string("http://api.modula.test/f")])
        }
        check(plain, .untrustedRef("the frontend"))
        check(good, host: nil, .untrustedRef("the artifact"))
        // Revoked / quarantined / bad signature are refused even if the digests line up.
        let revoked = try Self.reissued { body in
            body["trust"] = .object(["signatureState": .string("valid"), "verified": .bool(true), "revoked": .bool(true), "quarantined": .bool(false)])
        }
        check(revoked, .releaseNotTrusted("it was revoked"))
        let badSignature = try Self.reissued { body in
            body["trust"] = .object(["signatureState": .string("invalid"), "verified": .bool(false), "revoked": .bool(false), "quarantined": .bool(false)])
        }
        check(badSignature, .releaseNotTrusted("its signature is invalid"))
        // Registry-relative refs resolve to the registry itself.
        let relative = try Self.reissued {
            $0["artifact"] = .object(["sha256": .string(Self.facts.releaseSha256!), "ref": .string("/v1/registry/modules/x/versions/1.6.0/artifact")])
        }
        XCTAssertNoThrow(try InstallDescriptorVerifier.verify(relative, moduleId: id, version: "1.6.0", registry: Self.facts, registryHost: "api.modula.test"))
    }

    static func option(_ version: String, direction: String, current: Bool = false, latest: Bool = false, switchable: Bool = true,
                       state: String = "published", blockers: String = "[]") throws -> ModuleVersionOption {
        try XCTUnwrap(ModuleVersionOption(json: try json(#"{"version":"\#(version)","releaseId":"rel-\#(version)","releaseState":"\#(state)","publishedAt":"2026-09-20T10:00:00.000Z","releaseNotes":"Notes for \#(version)","trust":{"signatureState":"valid","verified":true,"revoked":false,"quarantined":false,"warnings":[]},"direction":"\#(direction)","current":\#(current),"latest":\#(latest),"switchable":\#(switchable),"blockers":\#(blockers)}"#)))
    }

    func testRowActionsLabelUpgradeDowngradeAndGates() throws {
        let latest = try Self.option("1.7.0", direction: "upgrade", latest: true)
        let middle = try Self.option("1.6.5", direction: "upgrade")
        let older = try Self.option("1.2.0", direction: "downgrade")
        let current = try Self.option("1.6.0", direction: "none", current: true)
        let blocked = try Self.option("0.1.0", direction: "downgrade", switchable: false, state: "superseded",
                                      blockers: #"[{"code":"HOST_INCOMPATIBLE","message":"Needs a newer host"}]"#)

        XCTAssertEqual(ModuleVersionAction.resolve(latest, installed: true, busy: false), .update)
        XCTAssertEqual(ModuleVersionAction.resolve(middle, installed: true, busy: false), .installThisVersion(.upgrade))
        XCTAssertEqual(ModuleVersionAction.installThisVersion(.upgrade).badge, "Upgrade")
        XCTAssertEqual(ModuleVersionAction.resolve(older, installed: true, busy: false), .installThisVersion(.downgrade))
        XCTAssertEqual(ModuleVersionAction.installThisVersion(.downgrade).badge, "Downgrade")
        XCTAssertEqual(ModuleVersionAction.installThisVersion(.downgrade).title, "Install this version")
        XCTAssertEqual(ModuleVersionAction.resolve(current, installed: true, busy: false), .installed)
        XCTAssertEqual(ModuleVersionAction.resolve(blocked, installed: true, busy: false), .needsNewerApp,
                       "Only a registry HOST_INCOMPATIBLE blocker means the app is too old")
        let revoked = try Self.option("1.5.0", direction: "downgrade", switchable: false,
                                      blockers: #"[{"code":"RELEASE_REVOKED","message":"Revoked"}]"#)
        XCTAssertEqual(ModuleVersionAction.resolve(revoked, installed: true, busy: false), .unavailable("Revoked"))
        // A newer module release the registry accepts is an Update, whatever version label
        // the app's bundled module code carries (Vault Notes 1.8.0 on a 1.7.0 bundle).
        let vault180 = try Self.option("1.8.0", direction: "upgrade", latest: true)
        XCTAssertEqual(ModuleVersionAction.resolve(vault180, installed: true, busy: false), .update)
        XCTAssertNotEqual(ModuleVersionAction.resolve(vault180, installed: true, busy: false), .needsNewerApp)
        XCTAssertFalse(ModuleVersionAction.resolve(older, installed: true, busy: true).isEnabled)
        XCTAssertFalse(ModuleVersionAction.resolve(older, installed: false, busy: false).isEnabled)
        XCTAssertEqual(latest.trustLabel, "Signed · Verified")
        XCTAssertEqual(blocked.direction, .downgrade)
        XCTAssertNotNil(latest.publishedAt)
    }

    static func preview(from: String, to: String, direction: String, descriptor: String, older: Bool) -> String {
        #"{"moduleId":"digital.modula.vault-notes","fromVersion":"\#(from)","toVersion":"\#(to)","direction":"\#(direction)","noop":false,"allowed":true,"blockers":[],"permissions":{"added":[{"permission":"network:fetch","risk":"high","reason":"Sync notes"}],"removed":["storage:legacy"],"retained":["functions:register"],"requiresConsent":["network:fetch"],"highRiskIncrease":true},"dataSchema":{"older":\#(older),"missingInTarget":["vault.tags"]},"warnings":[{"code":"DATA_SCHEMA_OLDER","message":"Version \#(to) uses an older data schema."},{"code":"DOWNGRADE","message":"Older version"}],"descriptor":\#(descriptor)}"#
    }

    func testPreviewParsesPermissionDiffAndDowngradeWarning() throws {
        let value = try Self.json(Self.preview(from: "1.7.0", to: "1.6.0", direction: "downgrade", descriptor: Self.serverDescriptor, older: true))
        let preview = try XCTUnwrap(ModuleVersionPreview(json: value))
        XCTAssertTrue(preview.isDowngrade)
        XCTAssertEqual(preview.addedPermissions.map(\.permission), ["network:fetch"])
        XCTAssertEqual(preview.addedPermissions.first?.risk, "high")
        XCTAssertEqual(preview.removedPermissions, ["storage:legacy"])
        XCTAssertEqual(preview.requiresConsent, ["network:fetch"])
        XCTAssertTrue(preview.highRiskIncrease)
        XCTAssertTrue(preview.dataSchemaOlder)
        XCTAssertEqual(preview.missingCollections, ["vault.tags"])
        XCTAssertEqual(preview.downgradeWarning, "Version 1.6.0 uses an older data schema.")
        let upgrade = try XCTUnwrap(ModuleVersionPreview(json: try Self.json(Self.preview(from: "1.6.0", to: "1.7.0", direction: "upgrade", descriptor: Self.serverDescriptor, older: false))))
        XCTAssertNil(upgrade.downgradeWarning)
        XCTAssertNil(ModuleVersionPreview(json: try Self.json(#"{"moduleId":"x","fromVersion":"1","toVersion":"2","descriptor":{"descriptorVersion":"0.9"}}"#)))
    }
}

private final class VersionRouterProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var log: [String] = []
    nonisolated(unsafe) static var queries: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.log.append("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
        if let query = request.url?.query { Self.queries.append("\(request.url?.path ?? "")?\(query)") }
        let (status, body) = Self.handler?(request) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> JSONValue? {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = Data(); var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&chunk, maxLength: chunk.count); if n <= 0 { break }; buffer.append(chunk, count: n) }
        data = buffer
    }
    return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

final class ModuleVersionSwitchStoreTests: XCTestCase {
    private static let id = "digital.modula.vault-notes"

    override func tearDown() {
        VersionRouterProtocol.handler = nil
        super.tearDown()
    }

    /// The fixture re-issued for `host` so its refs point at the client's registry origin.
    private static func descriptorJSON(host: String) throws -> String {
        let text = ModuleVersionSwitchTests.serverDescriptor.replacingOccurrences(of: "api.modula.test", with: host)
        guard case .object(var body) = try ModuleVersionSwitchTests.json(text) else { throw XCTSkip("fixture") }
        body.removeValue(forKey: "descriptorSha256"); body.removeValue(forKey: "issuedAt")
        body["descriptorSha256"] = .string(CanonicalJSON.sha256Hex(.object(body)))
        let data = try JSONEncoder().encode(JSONValue.object(body))
        return String(decoding: data, as: UTF8.self)
    }

    private struct Harness {
        let client: GreenfieldClient
        let host: String
    }

    private func harness(issuedDescriptor: @escaping (String) -> String = { $0 }, updateBody: @escaping (JSONValue?) -> Void) throws -> Harness {
        let host = "versions-\(UUID().uuidString.prefix(8).lowercased()).modula.test"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VersionRouterProtocol.self]
        VersionRouterProtocol.log = []
        VersionRouterProtocol.queries = []
        let client = GreenfieldClient(baseURL: URL(string: "https://\(host)")!, transport: URLSession(configuration: config))
        let descriptor = try Self.descriptorJSON(host: host)
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        nonisolated(unsafe) var version = "1.7.0"
        nonisolated(unsafe) var polls = 0
        let facts = ModuleVersionSwitchTests.facts
        VersionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#)
            case ("GET", "/v1/modules/\(Self.id)/versions"):
                let current = version
                return (200, #"{"ok":true,"data":{"moduleId":"\#(Self.id)","installedVersion":"\#(current)","latestVersion":"1.7.0","updateAvailable":false,"versions":[{"version":"1.7.0","releaseId":"rel-170","releaseState":"published","direction":"\#(current == "1.7.0" ? "none" : "upgrade")","current":\#(current == "1.7.0"),"latest":true,"switchable":true,"trust":{"signatureState":"unsigned","verified":true}},{"version":"1.6.0","releaseId":"rel-160","releaseState":"published","direction":"\#(current == "1.6.0" ? "none" : "downgrade")","current":\#(current == "1.6.0"),"latest":false,"switchable":true,"trust":{"signatureState":"unsigned","verified":true}}]}}"#)
            case ("POST", "/v1/modules/\(Self.id)/version-preview"):
                return (200, #"{"ok":true,"data":\#(ModuleVersionSwitchTests.preview(from: "1.7.0", to: "1.6.0", direction: "downgrade", descriptor: descriptor, older: true))}"#)
            case ("GET", "/v1/registry/modules/\(Self.id)/versions/1.6.0"):
                return (200, #"{"ok":true,"data":{"registryReleaseId":"rel-160","version":"1.6.0","registryTrust":{"digests":{"releaseSha256":"\#(facts.releaseSha256!)","adapterManifestSha256":"\#(facts.adapterManifestSha256!)","productManifestSha256":"\#(facts.productManifestSha256!)","frontendSha256":"\#(facts.frontendSha256!)"}}}}"#)
            case ("POST", "/v1/modules/\(Self.id)/update"):
                updateBody(requestBody(request))
                version = "1.6.0"; polls = 0
                return (202, #"{"ok":true,"data":{"installationId":"i1","status":"updating","fromVersion":"1.7.0","toVersion":"1.6.0","direction":"downgrade","descriptor":\#(issuedDescriptor(descriptor))}}"#)
            case ("GET", "/v1/modules/installed"):
                polls += 1
                let status = polls >= 2 || version == "1.7.0" ? "enabled" : "updating"
                return (200, #"{"ok":true,"data":{"items":[{"installationId":"i1","moduleId":"\#(Self.id)","status":"\#(status)","version":"\#(polls >= 2 ? version : "1.7.0")"}]}}"#)
            default: return (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
            }
        }
        return Harness(client: client, host: host)
    }

    @MainActor
    func testDowngradeVerifiesDescriptorConsentsAndSettlesOnTarget() async throws {
        nonisolated(unsafe) var body: JSONValue?
        let h = try harness(updateBody: { body = $0 })
        _ = try await h.client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: h.client)
        store.settlePollInterval = .milliseconds(5)

        await store.loadVersions(Self.id)
        XCTAssertEqual(store.versionLists[Self.id]?.versions.map(\.version), ["1.7.0", "1.6.0"])
        XCTAssertEqual(store.versionLists[Self.id]?.versions.last?.direction, .downgrade)

        let preview = try await store.prepareVersionSwitch(Self.id, to: "1.6.0")
        XCTAssertTrue(preview.isDowngrade)
        XCTAssertNotNil(preview.downgradeWarning)
        XCTAssertTrue(VersionRouterProtocol.log.contains("GET /v1/registry/modules/\(Self.id)/versions/1.6.0"),
                      "The descriptor is checked against the public registry before the sheet confirms")

        let switched = await store.switchVersion(Self.id, preview: preview)
        XCTAssertTrue(switched, store.lifecycleErrors.description)
        XCTAssertEqual(store.installations[Self.id]?.version, "1.6.0")
        XCTAssertNil(store.operations[Self.id])
        XCTAssertEqual(body?["version"]?.string, "1.6.0")
        XCTAssertEqual(body?["approvedPermissions"]?.array?.compactMap(\.string), ["network:fetch"], "Consent covers exactly the permissions shown")
        XCTAssertEqual(body?["acknowledgeDowngradeRisk"]?.bool, true)
        XCTAssertEqual(body?["hostVersion"]?.string, ModulaHost.version, "The switch reports the host contract version")
        XCTAssertTrue(VersionRouterProtocol.queries.contains("/v1/modules/\(Self.id)/versions?platform=ios&hostVersion=\(ModulaHost.version)"),
                      "The versions list is evaluated against this app's host version")
        XCTAssertTrue(body?["idempotencyKey"]?.string?.hasPrefix("ios-version-") == true)
        XCTAssertEqual(store.versionLists[Self.id]?.installedVersion, "1.6.0")
        XCTAssertFalse(VersionRouterProtocol.log.contains { $0.contains("github") })
    }

    @MainActor
    func testSwitchRefusesDescriptorThatDiffersFromConfirmedOne() async throws {
        let h = try harness(issuedDescriptor: { $0.replacingOccurrences(of: "\"sizeBytes\":48213", with: "\"sizeBytes\":1") }, updateBody: { _ in })
        _ = try await h.client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: h.client)
        store.settlePollInterval = .milliseconds(5)
        let preview = try await store.prepareVersionSwitch(Self.id, to: "1.6.0")
        let switched = await store.switchVersion(Self.id, preview: preview)
        XCTAssertFalse(switched)
        XCTAssertEqual(store.lifecycleErrors[Self.id], InstallDescriptorVerificationError.digestMismatch.errorDescription)
        XCTAssertNil(store.operations[Self.id])
    }

    @MainActor
    func testPrepareRejectsDescriptorNotMatchingRegistry() async throws {
        let h = try harness(updateBody: { _ in })
        _ = try await h.client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: h.client)
        // Same preview, but the registry publishes a different artifact digest.
        let original = VersionRouterProtocol.handler
        VersionRouterProtocol.handler = { request in
            if request.url?.path == "/v1/registry/modules/\(Self.id)/versions/1.6.0" {
                return (200, #"{"ok":true,"data":{"registryReleaseId":"rel-160","registryTrust":{"digests":{"releaseSha256":"\#(String(repeating: "b", count: 64))"}}}}"#)
            }
            return original?(request) ?? (500, "{}")
        }
        do {
            _ = try await store.prepareVersionSwitch(Self.id, to: "1.6.0")
            XCTFail("expected verification failure")
        } catch {
            XCTAssertEqual(error as? InstallDescriptorVerificationError, .registryMismatch("artifact"))
        }
        XCTAssertFalse(VersionRouterProtocol.log.contains("POST /v1/modules/\(Self.id)/update"))
    }
}
