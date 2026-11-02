import CryptoKit
import SwiftUI
import XCTest
@testable import Modula

/// MOL-03E: signed Moliboo asset packs — install, update, offline, rollback and every rejection path.
@MainActor
final class MOL03PackageTests: XCTestCase {
    private var root: URL!
    private var key: Curve25519.Signing.PrivateKey!
    private var policy: ModuleTrustPolicy!
    private let base = URL(string: "https://qa.moliboo.test/packages")!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mol03-pkg-\(UUID().uuidString)", isDirectory: true)
        key = Curve25519.Signing.PrivateKey()
        let raw = key.publicKey.rawRepresentation
        policy = ModuleTrustPolicy(signers: [TrustedSigner(keyId: TrustedSigner.keyId(for: raw), rawPublicKey: raw)], revokedKeyIds: [], allowsUnsignedLocalPackages: false)
        MolibooStubProtocol.reset()
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    // MARK: Fixtures

    private func patch(_ key: String = "somna", number: Int = 100, mid: String = "#B9A6F2", version: String = "2.0.0") -> MolibooCharacterPatch {
        MolibooCharacterPatch(schemaVersion: MolibooCharacterPatch.schemaVersion, characterId: String(format: "moliboo.%03d", number), key: key,
                              assetVersion: version, palette: .init(mid: mid, accent: "#FFD27A", iris: nil, light: "#F4EEFF", dark: nil, outline: nil),
                              size: nil, glow: "#C9B8FF", sparkles: 5, removeParts: nil, form: "The keeper of dreams (dusk)", fit: nil)
    }

    private func container(_ p: MolibooCharacterPatch, packageId: String, version: String, extra: [MolibooAssetPackContainer.File] = []) throws -> MolibooAssetPackContainer {
        let data = try JSONEncoder().encode(p)
        let f = MolibooAssetPackContainer.File(path: "character.json", mediaType: "application/json", sha256: MolibooPackageValidator.sha256Hex(data), bytes: data.count, data: data.base64EncodedString())
        return MolibooAssetPackContainer(schemaVersion: MolibooAssetPackContainer.schemaVersion, packageId: packageId, version: version, characterId: p.characterId, files: [f] + extra)
    }

    private func publish(_ c: MolibooAssetPackContainer, family: String = "dreamers", signer: Curve25519.Signing.PrivateKey? = nil, deps: [MolibooPackageDescriptor.Dependency] = [],
                         tamper: ((inout Data) -> Void)? = nil, minHost: String = "0.1.0") throws -> MolibooPackageDescriptor {
        var bytes = try JSONEncoder().encode(c)
        let digest = MolibooPackageValidator.sha256Hex(bytes)
        let k = signer ?? key!
        let sig = try k.signature(for: Data(digest.utf8)).base64EncodedString()
        let path = "artifacts/\(c.packageId)-\(c.version).json"
        tamper?(&bytes)
        MolibooStubProtocol.routes[base.appendingPathComponent(path).absoluteString] = bytes
        return MolibooPackageDescriptor(
            schemaVersion: "modula.package.1", packageId: c.packageId, publisherId: "modula", category: "asset-pack", version: c.version,
            releaseId: "qa-\(c.version)",
            artifact: .init(sha256: digest, compressedSizeBytes: bytes.count, installedSizeEstimateBytes: bytes.count, mediaType: MolibooAssetPackContainer.mediaType,
                            download: .init(pathOrUrl: path, authorization: "none", range: false)),
            signature: .init(algorithm: "Ed25519", keyId: TrustedSigner.keyId(for: k.publicKey.rawRepresentation), signature: sig, statementDigest: nil),
            minimumHostVersion: minHost, platforms: ["ios"], dependencies: deps, requiredCapabilities: [], cachePolicy: "retain-while-owned",
            sharing: "public-immutable",
            moliboo: .init(characterId: c.characterId, familyId: family, runtimeVersion: 1, assetCapabilities: ["palette", "parts"], rollbackCompatible: true))
    }

    private func manager(catalog: [MolibooPackageDescriptor]) throws -> MolibooPackageManager {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MolibooStubProtocol.self]
        MolibooStubProtocol.routes[base.appendingPathComponent("catalog.json").absoluteString] =
            try JSONEncoder().encode(MolibooPackageCatalog(schemaVersion: MolibooPackageCatalog.schemaVersion, packages: catalog))
        let m = MolibooPackageManager(runtime: MolibooPackageRuntime(store: MolibooPackageStore(root: root)), session: URLSession(configuration: cfg), baseURL: base)
        m.policy = { [policy] in policy! }
        m.hostVersion = "0.1.0"
        return m
    }

    private func render(_ kind: ModulaMascotKind, runtime: MolibooPackageRuntime) -> MolibooSpec? { runtime.patchedSpec(kind, MolibooFamilySpecs.table[kind]) }

    // MARK: Happy path

    func testInstallUpdateRollbackAndOfflineReload() async throws {
        let v1 = try publish(container(patch(mid: "#9FB2F0", version: "1.0.1"), packageId: "moliboo.character.100", version: "1.0.1"))
        let v2 = try publish(container(patch(version: "2.0.0"), packageId: "moliboo.character.100", version: "2.0.0"))
        let m = try manager(catalog: [v1, v2])
        XCTAssertEqual(MolibooStubProtocol.requests, 0, "creating the manager must not download anything")
        await m.refreshCatalog()
        XCTAssertEqual(m.catalog.count, 2)

        let ok1 = await m.install(v1)
        XCTAssertTrue(ok1, m.lastError ?? "")
        XCTAssertTrue(m.statusHistory.contains(.downloading(v1.id)))
        XCTAssertTrue(m.statusHistory.contains(.verifying(v1.id)))
        XCTAssertTrue(m.statusHistory.contains(.installing(v1.id)))
        XCTAssertEqual(m.installedVersions["moliboo.character.100"], "1.0.1")
        XCTAssertEqual(m.updates.map(\.version), ["2.0.0"])
        let ok2 = await m.install(v2)
        XCTAssertTrue(ok2, m.lastError ?? "")
        XCTAssertTrue(m.statusHistory.contains(.updating(v2.id)))
        XCTAssertEqual(m.runtime.store.index("moliboo.character.100").active, "2.0.0")
        XCTAssertEqual(m.runtime.store.index("moliboo.character.100").previous, "1.0.1")

        let spec = try XCTUnwrap(render(.somna, runtime: m.runtime))
        XCTAssertEqual(spec.form, "The keeper of dreams (dusk)")
        XCTAssertEqual(spec.parts.filter { $0.patchName == "sparkles" }.count, 1)
        XCTAssertNotEqual(spec.palette.mid, MolibooFamilySpecs.table[.somna]!.palette.mid, "v2 artwork is drawn")
        XCTAssertEqual(render(.dozi, runtime: m.runtime)?.form, MolibooFamilySpecs.table[.dozi]?.form, "other characters untouched")

        // Offline: a fresh runtime over the same disk sees v2 with no network at all.
        MolibooStubProtocol.offline = true
        let offline = MolibooPackageRuntime(store: MolibooPackageStore(root: root))
        XCTAssertEqual(offline.active(for: .somna)?.version, "2.0.0")
        XCTAssertEqual(render(.somna, runtime: offline)?.form, "The keeper of dreams (dusk)")

        m.rollback("moliboo.character.100")
        XCTAssertEqual(m.runtime.store.index("moliboo.character.100").active, "1.0.1")
        XCTAssertEqual(m.runtime.active(for: .somna)?.version, "1.0.1")

        let before = m.storageBytes()
        XCTAssertGreaterThan(before, 0)
        m.remove("moliboo.character.100")
        XCTAssertEqual(m.storageBytes(), 0)
        XCTAssertNil(m.runtime.active(for: .somna))
        XCTAssertNotNil(render(.somna, runtime: m.runtime), "built-in Somna remains after removal")
    }

    // MARK: Rejections keep the last good version

    private func assertRejected(_ d: MolibooPackageDescriptor, catalog extra: [MolibooPackageDescriptor] = [], _ expect: (String) -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let good = try publish(container(patch(version: "1.0.0"), packageId: "moliboo.character.100", version: "1.0.0"))
        let m = try manager(catalog: [good, d] + extra)
        await m.refreshCatalog()
        let installed = await m.install(good)
        XCTAssertTrue(installed, file: file, line: line)
        let ok = await m.install(d)
        XCTAssertFalse(ok, "must reject", file: file, line: line)
        XCTAssertTrue(expect(m.lastError ?? ""), "unexpected error: \(m.lastError ?? "nil")", file: file, line: line)
        XCTAssertEqual(m.runtime.store.index("moliboo.character.100").active, "1.0.0", "last good version stays active", file: file, line: line)
        XCTAssertEqual(m.runtime.active(for: .somna)?.version, "1.0.0", file: file, line: line)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: m.runtime.store.packageDir("moliboo.character.100").path))?.filter { $0.hasPrefix(".staging") } ?? []
        XCTAssertEqual(leftovers, [], "no staging left behind", file: file, line: line)
    }

    func testRejectsTamperedArtifact() async throws {
        let d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0")) { $0[$0.count / 2] ^= 0x20 }
        try await assertRejected(d) { $0.contains("digest") }
    }

    func testRejectsUntrustedAndRevokedSigners() async throws {
        let d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"), signer: Curve25519.Signing.PrivateKey())
        try await assertRejected(d) { $0.contains("does not trust") }
        policy.revokedKeyIds = [TrustedSigner.keyId(for: key.publicKey.rawRepresentation)]
        let m = try manager(catalog: [])
        let r = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        let ok = await m.install(r)
        XCTAssertFalse(ok)
        XCTAssertTrue(m.lastError?.contains("revoked") ?? false, m.lastError ?? "")
    }

    func testRejectsForgedSignature() async throws {
        var d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        d.signature.signature = try key.signature(for: Data("something else".utf8)).base64EncodedString()
        try await assertRejected(d) { $0.contains("signature") }
    }

    func testRejectsActivationWithoutConfirmedOwnership() async throws {
        let descriptor = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        let m = try manager(catalog: [descriptor])
        m.authorization = { _ in false }
        let requestsBeforeInstall = MolibooStubProtocol.requests
        let accepted = await m.install(descriptor)
        XCTAssertFalse(accepted)
        XCTAssertEqual(m.lastError, MolibooPackageError.unauthorized.errorDescription)
        XCTAssertEqual(MolibooStubProtocol.requests, requestsBeforeInstall, "ownership is checked before artifact download")
        XCTAssertNil(m.runtime.store.index(descriptor.packageId).active)
    }

    func testManifestIdentityAndDependencyRangesFailClosed() throws {
        let discovered = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        XCTAssertTrue(MolibooPackageManager.manifestIsSameRelease(discovered, discovered: discovered))
        var otherRelease = discovered
        otherRelease.releaseId = "different-release"
        XCTAssertFalse(MolibooPackageManager.manifestIsSameRelease(otherRelease, discovered: discovered))
        XCTAssertTrue(MolibooPackageManager.satisfies("2.4.1", range: "^2.0.0"))
        XCTAssertFalse(MolibooPackageManager.satisfies("3.0.0", range: "^2.0.0"))
        XCTAssertTrue(MolibooPackageManager.satisfies("0.2.9", range: "^0.2.3"))
        XCTAssertFalse(MolibooPackageManager.satisfies("0.3.0", range: "^0.2.3"))
        XCTAssertFalse(MolibooPackageManager.satisfies("0.0.4", range: "^0.0.3"))
        XCTAssertFalse(MolibooPackageManager.satisfies("2.0.0", range: "not-a-range"))
    }

    func testRejectsPathTraversalAbsoluteAndHiddenPaths() async throws {
        for bad in ["../evil.json", "/etc/passwd.json", "a/../../b.json", ".hidden.json", "run.sh", "x\\y.json"] {
            let payload = Data("{}".utf8)
            let f = MolibooAssetPackContainer.File(path: bad, mediaType: "application/json", sha256: MolibooPackageValidator.sha256Hex(payload), bytes: payload.count, data: payload.base64EncodedString())
            let d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0", extra: [f]))
            try await assertRejected(d) { $0.contains("unsafe") }
            MolibooStubProtocol.reset()
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testRejectsDecompressionBombAndOversize() async throws {
        let huge = String(repeating: "A", count: 200_000)
        let f = MolibooAssetPackContainer.File(path: "thumb.png", mediaType: "image/png", sha256: String(repeating: "0", count: 64), bytes: 10, data: huge)
        let d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0", extra: [f]))
        try await assertRejected(d) { $0.contains("larger") }
        MolibooStubProtocol.reset(); try? FileManager.default.removeItem(at: root)
        var big = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        big.artifact.compressedSizeBytes = MolibooPackageLimits.maxArtifactBytes + 1
        try await assertRejected(big) { $0.contains("larger") }
    }

    func testRejectsSchemaCategoryHostAndCharacterMismatches() async throws {
        var schema = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0")); schema.schemaVersion = "modula.package.9"
        try await assertRejected(schema) { $0.contains("schema") }
        MolibooStubProtocol.reset(); try? FileManager.default.removeItem(at: root)
        var cat = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0")); cat.category = "module"
        try await assertRejected(cat) { $0.contains("asset pack") }
        MolibooStubProtocol.reset(); try? FileManager.default.removeItem(at: root)
        let host = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"), minHost: "9.0.0")
        try await assertRejected(host) { $0.contains("9.0.0") }
        MolibooStubProtocol.reset(); try? FileManager.default.removeItem(at: root)
        let wrong = try publish(container(patch("dozi", number: 86), packageId: "moliboo.character.100", version: "2.0.0"))
        try await assertRejected(wrong) { $0.contains("damaged") || $0.contains("unknown") }
    }

    func testRejectsMissingDependencyAndCycles() async throws {
        let missing = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"), deps: [.init(packageId: "moliboo.shared.effects", versionRange: "^1.0.0")])
        try await assertRejected(missing) { $0.contains("missing") }
        MolibooStubProtocol.reset(); try? FileManager.default.removeItem(at: root)
        let a = try publish(container(patch(version: "2.0.0"), packageId: "moliboo.character.100", version: "2.0.0"), deps: [.init(packageId: "moliboo.character.099", versionRange: "*")])
        let b = try publish(container(patch("comfi", number: 99, version: "1.1.0"), packageId: "moliboo.character.099", version: "1.1.0"), deps: [.init(packageId: "moliboo.character.100", versionRange: "*")])
        XCTAssertThrowsError(try MolibooPackageValidator.installOrder(for: a, catalog: [a, b], installed: [])) { e in
            XCTAssertEqual(e as? MolibooPackageError, .dependencyCycle("moliboo.character.100"))
        }
    }

    func testRejectsInvalidPatchesAndLegendFits() throws {
        let d = try publish(container(patch(), packageId: "moliboo.character.100", version: "2.0.0"))
        var bad = patch(); bad.palette?.mid = "red"
        XCTAssertThrowsError(try MolibooPackageValidator.validate(patch: bad, descriptor: d, registry: MolibooRegistryStore.bundled))
        var size = patch(); size.size = .init(width: 3, height: 0.8)
        XCTAssertThrowsError(try MolibooPackageValidator.validate(patch: size, descriptor: d, registry: MolibooRegistryStore.bundled))
        var legend = patch("kringle", number: 101); legend.fit = .init(hatScale: 1, hatMaxWidth: nil, headTopExtra: nil)
        var ld = d; ld.moliboo.characterId = "moliboo.101"; ld.packageId = "moliboo.character.101"; ld.moliboo.familyId = "legends"
        XCTAssertThrowsError(try MolibooPackageValidator.validate(patch: legend, descriptor: ld, registry: MolibooRegistryStore.bundled))
        legend.fit = nil
        XCTAssertNoThrow(try MolibooPackageValidator.validate(patch: legend, descriptor: ld, registry: MolibooRegistryStore.bundled))
    }

    func testFailedActivationHealthCheckRestoresPreviousVersion() async throws {
        let good = try publish(container(patch(version: "1.0.0"), packageId: "moliboo.character.100", version: "1.0.0"))
        let next = try publish(container(patch(version: "2.0.0"), packageId: "moliboo.character.100", version: "2.0.0"))
        let m = try manager(catalog: [good, next])
        let ok = await m.install(good)
        XCTAssertTrue(ok)
        m.healthCheck = { $0.assetVersion != "2.0.0" }
        let bad = await m.install(next)
        XCTAssertFalse(bad)
        XCTAssertEqual(m.status, .rolledBack("moliboo.character.100"))
        XCTAssertTrue(m.statusHistory.contains(.rollingBack("moliboo.character.100")))
        XCTAssertEqual(m.runtime.store.index("moliboo.character.100").active, "1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: m.runtime.store.versionDir("moliboo.character.100", "2.0.0").path), "broken version removed")
    }

    func testInterruptedInstallIsSweptAndNeverActive() throws {
        let store = MolibooPackageStore(root: root)
        let stale = store.packageDir("moliboo.character.100").appendingPathComponent(".staging-crash", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: stale.appendingPathComponent("character.json"))
        XCTAssertNil(MolibooPackageRuntime(store: store).active(for: .somna))
        store.sweepStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testSafePathRules() {
        for ok in ["character.json", "thumbs/somna-64.png", "a_b-c.json"] { XCTAssertTrue(MolibooPackageValidator.isSafe(path: ok), ok) }
        for bad in ["", "../a.json", "/a.json", "a//b.json", "./a.json", ".a.json", "a.exe", "a.js", "a/..", "é.json"] { XCTAssertFalse(MolibooPackageValidator.isSafe(path: bad), bad) }
    }
}

/// Serves fixture bytes for the QA package host; counts requests; can simulate airplane mode.
final class MolibooStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: Data] = [:]
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var offline = false
    static func reset() { routes = [:]; requests = 0; offline = false }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        guard !Self.offline else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let url = request.url!.absoluteString
        if let data = Self.routes[url] {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "\(data.count)"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
