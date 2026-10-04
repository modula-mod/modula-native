import CryptoKit
import XCTest
@testable import Modula

final class NodusReleaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var root: URL!

    override func setUpWithError() throws {
        suiteName = "NodusReleaseTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        root = FileManager.default.temporaryDirectory.appending(path: "nodus-release-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Feature flag

    func testFeatureFlagDefaultsOnAndHonoursUserPreference() {
        let bundle = Bundle(for: Self.self) // no ModulaNodusChatEnabled key
        XCTAssertTrue(NodusChatFeature.isShipped(bundle: bundle))
        XCTAssertTrue(NodusChatFeature.isEnabled(bundle: bundle, defaults: defaults))
        NodusChatFeature.setUserPrefersNodus(false, defaults: defaults)
        XCTAssertFalse(NodusChatFeature.isEnabled(bundle: bundle, defaults: defaults))
        NodusChatFeature.setUserPrefersNodus(true, defaults: defaults)
        XCTAssertTrue(NodusChatFeature.isEnabled(bundle: bundle, defaults: defaults))
    }

    func testAppShipsNodusChatFlagOn() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: NodusChatFeature.infoPlistKey) as? Bool, true)
    }

    // MARK: Routing

    func testReleaseRoutingFallsBackToAppleUnlessNodusIsAvailable() {
        let fallbacks: [IntelligenceAvailability?] = [nil, .modelNotInstalled, .modelDownloading, .unsupportedDevice, .insufficientMemory, .disabled]
        for availability in fallbacks {
            XCTAssertEqual(
                NodusChatRouting.surface(featureEnabled: true, nodusAvailability: availability, showsUnavailableNodus: false),
                .appleFallback, "\(String(describing: availability))"
            )
        }
        XCTAssertEqual(
            NodusChatRouting.surface(featureEnabled: true, nodusAvailability: .available, showsUnavailableNodus: false),
            .nodus
        )
    }

    func testFeatureOffAlwaysUsesApple() {
        XCTAssertEqual(NodusChatRouting.surface(featureEnabled: false, nodusAvailability: .available, showsUnavailableNodus: false), .appleFallback)
        XCTAssertEqual(NodusChatRouting.surface(featureEnabled: false, nodusAvailability: .available, showsUnavailableNodus: true), .appleFallback)
    }

    func testDeveloperRoutingShowsNodusEvenWhenUnavailable() {
        XCTAssertEqual(NodusChatRouting.surface(featureEnabled: true, nodusAvailability: .unsupportedDevice, showsUnavailableNodus: true), .nodus)
        #if DEBUG
        XCTAssertTrue(NodusChatFeature.showsUnavailableNodus)
        #endif
    }

    // MARK: Device capability

    func testDeviceCapability() {
        let gib: UInt64 = 1_024 * 1_024 * 1_024
        XCTAssertEqual(NodusDeviceCapability.evaluate(physicalMemory: 8 * gib, isSimulator: true, mlxAvailable: true), .unsupportedDevice)
        XCTAssertEqual(NodusDeviceCapability.evaluate(physicalMemory: 8 * gib, isSimulator: false, mlxAvailable: false), .unsupportedDevice)
        XCTAssertEqual(NodusDeviceCapability.evaluate(physicalMemory: 4 * gib, isSimulator: false, mlxAvailable: true), .insufficientMemory)
        XCTAssertEqual(NodusDeviceCapability.evaluate(physicalMemory: 6 * gib, isSimulator: false, mlxAvailable: true), .supported)
        XCTAssertEqual(NodusDeviceCapability.evaluate(physicalMemory: 12 * gib, isSimulator: false, mlxAvailable: true), .supported)
        #if targetEnvironment(simulator)
        XCTAssertEqual(NodusDeviceCapability.evaluate(), .unsupportedDevice)
        #endif
    }

    // MARK: Endpoint

    func testEndpointResolution() throws {
        let bundle = Bundle(for: Self.self)
        let api = URL(string: "https://api.example.test")!
        let resolved = try XCTUnwrap(NodusModelEndpoint.resolve(apiBaseURL: api, bundle: bundle, defaults: defaults))
        XCTAssertEqual(resolved.host, "api.example.test")
        XCTAssertEqual(resolved.path, "/v1/intelligence/nodus/releases/latest")
        XCTAssertTrue(resolved.query?.contains("platform=ios") ?? false)

        defaults.set("http://insecure.example.test/r.json", forKey: NodusModelEndpoint.overrideKey)
        XCTAssertEqual(NodusModelEndpoint.resolve(apiBaseURL: api, bundle: bundle, defaults: defaults)?.host, "api.example.test")
        defaults.set("https://cdn.example.test/nodus/latest.json", forKey: NodusModelEndpoint.overrideKey)
        XCTAssertEqual(NodusModelEndpoint.resolve(apiBaseURL: api, bundle: bundle, defaults: defaults)?.absoluteString, "https://cdn.example.test/nodus/latest.json")

        defaults.removeObject(forKey: NodusModelEndpoint.overrideKey)
        XCTAssertNil(NodusModelEndpoint.resolve(apiBaseURL: nil, bundle: bundle, defaults: defaults))
        XCTAssertNil(NodusModelEndpoint.resolve(apiBaseURL: URL(string: "http://api.example.test")!, bundle: bundle, defaults: defaults))
    }

    // MARK: Release descriptor

    func testReleaseValidationRejectsUnsafeDescriptors() throws {
        let fixture = try Fixture()
        XCTAssertNoThrow(try fixture.release.validate())
        func mutated(_ change: (inout [NodusModelRelease.File]) -> Void, hash: String? = nil, schema: Int = 1) -> NodusModelRelease {
            var files = fixture.release.files
            change(&files)
            return NodusModelRelease(
                schemaVersion: schema, nodusVersion: "1.0.0", artifactHash: hash ?? fixture.release.artifactHash,
                manifestURL: fixture.release.manifestURL, manifestSHA256: fixture.release.manifestSHA256, files: files
            )
        }
        let first = fixture.release.files[0]
        let bad: [NodusModelRelease] = [
            mutated({ _ in }, schema: 2),
            mutated({ _ in }, hash: "sha256:XYZ"),
            mutated({ $0 = [] }),
            mutated({ $0[0] = .init(path: "../escape", url: first.url, sha256: first.sha256, bytes: first.bytes) }),
            mutated({ $0[0] = .init(path: "/abs", url: first.url, sha256: first.sha256, bytes: first.bytes) }),
            mutated({ $0[0] = .init(path: first.path, url: URL(string: "http://cdn.example.test/a")!, sha256: first.sha256, bytes: first.bytes) }),
            mutated({ $0[0] = .init(path: first.path, url: first.url, sha256: first.sha256.uppercased(), bytes: first.bytes) }),
            mutated({ $0.append($0[0]) }),
            mutated({ $0[0] = .init(path: "nodus-manifest.json", url: first.url, sha256: first.sha256, bytes: first.bytes) }),
        ]
        for release in bad {
            XCTAssertThrowsError(try release.validate()) { XCTAssertEqual($0 as? NodusModelDownloadError, .unsupportedRelease) }
        }
    }

    // MARK: Downloader

    func testDownloaderInstallsVerifiedArtifactAtomically() async throws {
        let fixture = try Fixture()
        let downloader = makeDownloader(transport: fixture.transport)
        let progress = ProgressRecorder()
        let manifest = try await downloader.install(fixture.release) { progress.record($0) }
        XCTAssertEqual(manifest.artifactHash, fixture.release.artifactHash)
        let installed = try await NodusArtifactInstaller(root: root).installedManifest()
        XCTAssertEqual(installed, manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "accepted/weights/model.safetensors").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: NodusModelStorage.downloadMarker(root: root).path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("download-") || $0.hasPrefix("staging-") }
        XCTAssertEqual(leftovers, [])
        XCTAssertEqual(progress.values.last, 1)
    }

    func testDownloaderRejectsTamperedFileAndKeepsNothing() async throws {
        let fixture = try Fixture()
        fixture.transport.payloads[fixture.release.files[1].url] = Data("tampered".utf8)
        let downloader = makeDownloader(transport: fixture.transport)
        do {
            try await downloader.install(fixture.release)
            XCTFail("tampered artifact installed")
        } catch {
            XCTAssertEqual(error as? NodusModelDownloadError, .hashMismatch(fixture.release.files[1].path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "accepted").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: NodusModelStorage.downloadMarker(root: root).path))
    }

    func testDownloaderRejectsTamperedManifest() async throws {
        let fixture = try Fixture()
        fixture.transport.payloads[fixture.release.manifestURL] = Data("{}".utf8)
        do {
            try await makeDownloader(transport: fixture.transport).install(fixture.release)
            XCTFail("tampered manifest installed")
        } catch {
            XCTAssertEqual(error as? NodusModelDownloadError, .hashMismatch("nodus-manifest.json"))
        }
    }

    func testDownloaderRejectsDescriptorThatDisagreesWithManifest() async throws {
        let fixture = try Fixture()
        let other = "sha256:" + String(repeating: "0", count: 64)
        let release = NodusModelRelease(
            schemaVersion: 1, nodusVersion: "1.0.0", artifactHash: other,
            manifestURL: fixture.release.manifestURL, manifestSHA256: fixture.release.manifestSHA256,
            files: fixture.release.files
        )
        do {
            try await makeDownloader(transport: fixture.transport).install(release)
            XCTFail("mismatched descriptor installed")
        } catch {
            XCTAssertEqual(error as? NodusModelDownloadError, .manifestMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "accepted").path))
    }

    func testDownloaderRefusesUnsupportedDeviceAndLowStorage() async throws {
        let fixture = try Fixture()
        do {
            try await makeDownloader(transport: fixture.transport, capability: .insufficientMemory).install(fixture.release)
            XCTFail("installed on unsupported device")
        } catch {
            XCTAssertEqual(error as? NodusModelDownloadError, .deviceUnsupported(.insufficientMemory))
        }
        do {
            try await makeDownloader(transport: fixture.transport, capacity: 1).install(fixture.release)
            XCTFail("installed without space")
        } catch {
            XCTAssertEqual(error as? NodusModelDownloadError, .insufficientStorage(required: fixture.release.totalBytes * 2))
        }
        XCTAssertTrue(fixture.transport.requested.isEmpty)
    }

    func testFetchReleaseDecodesValidatesAndMapsFailures() async throws {
        let fixture = try Fixture()
        let endpoint = URL(string: "https://api.example.test/v1/intelligence/nodus/releases/latest")!
        fixture.transport.payloads[endpoint] = try JSONEncoder().encode(fixture.release)
        let downloader = makeDownloader(transport: fixture.transport)
        let fetched = try await downloader.fetchRelease(from: endpoint)
        XCTAssertEqual(fetched, fixture.release)

        do { _ = try await downloader.fetchRelease(from: nil); XCTFail() }
        catch { XCTAssertEqual(error as? NodusModelDownloadError, .endpointNotConfigured) }

        let missing = URL(string: "https://api.example.test/missing")!
        do { _ = try await downloader.fetchRelease(from: missing); XCTFail() }
        catch { XCTAssertEqual(error as? NodusModelDownloadError, .releaseUnavailable(404)) }

        fixture.transport.payloads[endpoint] = Data("not json".utf8)
        do { _ = try await downloader.fetchRelease(from: endpoint); XCTFail() }
        catch { XCTAssertEqual(error as? NodusModelDownloadError, .unsupportedRelease) }
    }

    // MARK: Helpers

    private func makeDownloader(
        transport: StubTransport,
        capability: NodusDeviceCapability = .supported,
        capacity: Int64? = nil
    ) -> NodusModelDownloader {
        NodusModelDownloader(
            root: root,
            transport: transport,
            capability: { capability },
            availableCapacity: { _ in capacity }
        )
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] { lock.withLock { stored } }
    func record(_ value: Double) { lock.withLock { stored.append(value) } }
}

private final class StubTransport: NodusModelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL: Data] = [:]
    private var log: [URL] = []

    var payloads: [URL: Data] {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
    var requested: [URL] { lock.withLock { log } }

    func data(from url: URL) async throws -> (Data, Int) {
        lock.withLock { log.append(url) }
        guard let data = payloads[url] else { return (Data(), 404) }
        return (data, 200)
    }

    func download(from url: URL) async throws -> URL {
        lock.withLock { log.append(url) }
        guard let data = payloads[url] else { throw NodusModelDownloadError.releaseUnavailable(404) }
        let file = FileManager.default.temporaryDirectory.appending(path: "stub-\(UUID().uuidString)")
        try data.write(to: file)
        return file
    }
}

/// A tiny but fully valid Nodus artifact whose hashes are computed exactly as
/// `NodusArtifactInstaller.verify` does, served through `StubTransport`.
private struct Fixture {
    let release: NodusModelRelease
    let transport = StubTransport()

    init() throws {
        let contents: [(String, Data)] = [
            ("config.json", Data(#"{"model_type":"qwen3"}"#.utf8)),
            ("weights/model.safetensors", Data((0..<4096).map { UInt8($0 % 251) })),
        ]
        let hashes = Dictionary(uniqueKeysWithValues: contents.map { ($0.0, Self.hex($0.1)) })
        func manifest(_ artifactHash: String) -> NodusModelManifest {
            NodusModelManifest(
                schemaVersion: 1, nodusVersion: "1.0.0-test", parameters: 1, baseModel: "test/base",
                baseRevision: "rev", license: "Apache-2.0", fineTuningMethod: "none", datasetRevision: "d1",
                evalSuiteRevision: "e1", quantization: "4-bit", artifactHash: artifactHash,
                trainingDate: "2026-10-01", knowledgeProvenance: ["test"], files: hashes
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var canonical = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(manifest("placeholder"))) as? [String: Any]
        )
        canonical.removeValue(forKey: "artifactHash")
        let artifactHash = "sha256:" + Self.hex(
            try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys, .withoutEscapingSlashes])
        )
        let manifestData = try encoder.encode(manifest(artifactHash))
        let base = URL(string: "https://cdn.example.test/nodus/1.0.0-test/")!
        let manifestURL = base.appending(path: "nodus-manifest.json")
        var payloads: [URL: Data] = [manifestURL: manifestData]
        let files = contents.map { path, data in
            let url = base.appending(path: path)
            payloads[url] = data
            return NodusModelRelease.File(path: path, url: url, sha256: Self.hex(data), bytes: Int64(data.count))
        }
        transport.payloads = payloads
        release = NodusModelRelease(
            schemaVersion: 1, nodusVersion: "1.0.0-test", artifactHash: artifactHash,
            manifestURL: manifestURL, manifestSHA256: Self.hex(manifestData), files: files
        )
    }

    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
