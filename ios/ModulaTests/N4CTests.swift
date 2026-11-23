import CryptoKit
import ImageIO
import Network
import UIKit
import WebKit
import XCTest
import zlib
@testable import Modula

private final class RecordingGameSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: URLResponse?
    var body = Data()
    var finished = false
    var failure: Error?

    init(_ url: URL, method: String = "GET", headers: [String: String] = [:]) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        self.request = request
    }
    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { body.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { failure = error }
}

private final class RecordingGameNavigation: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    var failure: Error?

    init(finished: XCTestExpectation) { self.finished = finished }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished.fulfill() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error
        finished.fulfill()
    }
}

private final class LockedConnectionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}

final class N4CRouteTests: XCTestCase {
    func testMessagesCanonicalDefaultsAndRoundTrips() throws {
        XCTAssertEqual(RouteParser.parse("/messages"), .messages(.inbox))
        XCTAssertEqual(RouteSerializer.serialize(.messages(.inbox)), "/messages/inbox")
        let paths = [
            "/messages/inbox",
            "/messages/requests",
            "/messages/in-mail",
            "/messages/new",
            "/messages/to/andrei.modula",
            "/messages/conversation-1",
            "/messages/in-mail/new",
            "/messages/in-mail/thread-1",
            "/stories/story-1",
            "/stories/create",
            "/reels",
            "/reels/reel-1"
        ]
        for path in paths {
            let route = try XCTUnwrap(RouteParser.parse(path), path)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route, path)
        }
        XCTAssertEqual(RouteSerializer.serialize(.stories(.story("story-1"))), "/stories/story-1")
        XCTAssertEqual(RouteSerializer.serialize(.reels(.feed)), "/reels")
        XCTAssertNil(RouteParser.parse("/messages/inbox/extra"))
        XCTAssertEqual(RouteParser.parse("/stories/"), .stories(.root))
        XCTAssertEqual(RouteParser.parse("/stories"), .stories(.root))
        XCTAssertEqual(RouteParser.parse("/messages/inbox"), .messages(.inbox))
        XCTAssertNotEqual(RouteParser.parse("/messages/inbox"), .messages(.conversation("inbox")))
    }

    func testNotificationRouteResolver() {
        XCTAssertEqual(
            NotificationRouteResolver.route(kind: "conversation", identifier: "c1"),
            .messages(.conversation("c1"))
        )
        XCTAssertEqual(
            NotificationRouteResolver.route(kind: "in-mail", identifier: "t1"),
            .messages(.inMail(.thread("t1")))
        )
        XCTAssertEqual(NotificationRouteResolver.route(kind: "story", identifier: "s1"), .stories(.story("s1")))
        XCTAssertEqual(NotificationRouteResolver.route(kind: "reel", identifier: "r1"), .reels(.reel("r1")))
        XCTAssertNil(NotificationRouteResolver.route(kind: "conversation", identifier: "../x"))
        XCTAssertNil(NotificationRouteResolver.route(kind: "unknown", identifier: "x"))
    }
}

final class WebGameInstalledIsolationTests: XCTestCase {
    func testRollbackClosureRejectsRevokedGameOrRuntimeAndWrongBytes() {
        let gameID = "digital.modula.rollback-qa"
        let runtimeID = "digital.modula.runtime.phaser"
        let gameDigest = String(repeating: "a", count: 64)
        let runtimeDigest = String(repeating: "b", count: 64)
        let release = ModuleCachedRelease(
            moduleId: gameID, version: "0.1.0", releaseId: "module-release:\(gameID):0.1.0",
            accountID: "qa-account", frontendSha256: String(repeating: "c", count: 64),
            frontendMediaType: ProductUIDocument.mediaType, gameSha256: gameDigest,
            runtimeSha256: runtimeDigest,
            hostManifest: ModuleManifest(id: gameID, name: "Rollback QA", version: "0.1.0",
                                         runtime: "web-game", entry: "index.html", permissions: [],
                                         minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: []),
            descriptor: nil, slot: .previousGood, directory: FileManager.default.temporaryDirectory)
        func package(_ id: String, category: String, digest: String, revoked: Bool,
                     dependencies: [String]) -> JSONValue {
            .object([
                "packageId": .string(id), "version": .string(id == gameID ? "0.1.0" : "4.2.1"),
                "releaseId": .string("module-release:\(id):\(id == gameID ? "0.1.0" : "4.2.1")"),
                "category": .string(category), "artifact": .object(["sha256": .string(digest)]),
                "trust": .object(["verified": .bool(true), "publisherVerified": .bool(true),
                                  "revoked": .bool(revoked)]),
                "signature": .object(["algorithm": .string("Ed25519")]),
                "dependencies": .array(dependencies.map { .object(["packageId": .string($0)]) }),
            ])
        }
        func plan(gameRevoked: Bool = false, runtimeRevoked: Bool = false,
                  runtimeBytes: String = runtimeDigest) -> JSONValue {
            let lock: JSONValue = .object([
                "schemaVersion": .string("modula.package-lock.1"),
                "requested": .array([.string(gameID)]),
                "packages": .array([
                    package(gameID, category: "game-content", digest: gameDigest,
                            revoked: gameRevoked, dependencies: [runtimeID]),
                    package(runtimeID, category: "web-runtime", digest: runtimeBytes,
                            revoked: runtimeRevoked, dependencies: []),
                ]),
            ])
            return .object(["lock": lock, "lockSha256": .string(CanonicalJSON.sha256Hex(lock))])
        }
        XCTAssertTrue(RollbackPackageClosure.isEligible(plan(), for: release))
        XCTAssertFalse(RollbackPackageClosure.isEligible(plan(gameRevoked: true), for: release))
        XCTAssertFalse(RollbackPackageClosure.isEligible(plan(runtimeRevoked: true), for: release))
        XCTAssertFalse(RollbackPackageClosure.isEligible(plan(runtimeBytes: String(repeating: "d", count: 64)), for: release))
    }
    func testPinnedRegistryArtifactUsesConfiguredOriginAcrossQANetworks() throws {
        let digest = String(repeating: "a", count: 64)
        let base = try XCTUnwrap(URL(string: "https://192.168.4.38:8443"))
        let internalRef = "https://127.0.0.1:8443/v1/registry/artifacts/\(digest)"
        let url = try GreenfieldClient.registryArtifactURL(ref: internalRef, expectedSha256: digest, baseURL: base)
        XCTAssertEqual(url.absoluteString, "https://192.168.4.38:8443/v1/registry/artifacts/\(digest)")
        XCTAssertThrowsError(try GreenfieldClient.registryArtifactURL(
            ref: "https://127.0.0.1:8443/v1/registry/artifacts/\(String(repeating: "b", count: 64))",
            expectedSha256: digest, baseURL: base))
        XCTAssertThrowsError(try GreenfieldClient.registryArtifactURL(
            ref: internalRef + "?token=leak", expectedSha256: digest, baseURL: base))
    }
    @MainActor
    func testSharedRuntimeHasOneVerifiedCopyAndSurvivesUntilLastGameIsRemoved() throws {
        let gameEncoded = "H4sIAAAAAAAC/+3VwW6DMAwGYB4F5dLLQAQIsG7dZS8waU8QEmdQQeggTKuqvvuydqrUnrf2sP+72HIs5RBbaa2mz7hxfRf8mcQr8vwQvcuYpEl6yo/1sszyIEyCK5gnJ0d/ZfA/PfbkZNg4t4nofW4/Vux5sI6si15JzWPrttHL0LVqy0J1PFgxTUbOnYumUYULO1haPISTGtvNT2mizviS77ekztuGen1eYk8B3NCb7Ck2bUdTvJ4Ge5P95+XF/vOkECn2/xp2bFIN9ZItWT/ouZPx90REx4ng7I4dMrbcsfb0U/heRfeq0iZLJBniRghDWV2LLBNFqmvNOelEC1GYjJeiqnmdllqbvKJKluTfm+332D0AAAAAAAAAAAAAAAAAAACA3/AFxMM1iwAoAAA="
        let runtimeEncoded = "H4sIAAAAAAAC/+3VyUrFMBQG4K59ipK1lsSkQ+rTZDi5gx0uTQtC6bsbqii6FbvQ/4NwDiGQzfkTGk6XgYr+GrNfw5NKqb0m3yvnsv7s9/26fiyznGcHWOJspnRl9j/Ry22c5txTMEs352s8m4l8m8/TQtvTXQZ/2824Z3OiIlw6isU1jsPx+Rd1+TX/Qsj0JCD/B1hZdGfqDWtZP/qlM8X7RDy8TYRg92zvWLsy+vgs0nErtVBEwYdANnBZUSO5MyS1Ii+oUrJxkishRKUbl5YVWnJjdalqbblh24b4AQAAAAAAAAAAAAAAAAAAAPzYK/FtDLwAKAAA"
        let game = try XCTUnwrap(Data(base64Encoded: gameEncoded))
        let runtime = try XCTUnwrap(Data(base64Encoded: runtimeEncoded))
        let gameDigest = WebGamePackage.digest(game)
        let runtimeDigest = WebGamePackage.digest(runtime)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shared-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        let shared = SharedWebRuntimeStore(moduleCacheRoot: root)
        let account = "account-runtime-reuse"
        let ids = ["digital.modula.orbit-arena", "digital.modula.orbit-dash"]
        var runningBrowser: WebGameBrowserProbe?
        for (index, id) in ids.enumerated() {
            let frontend = Data("""
                {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(id)","releaseVersion":"0.1.0","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","children":[{"type":"text","text":"Ready"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
                """.utf8)
            let manifest = ModuleManifest(id: id, name: id, version: "0.1.0", runtime: "web-game", entry: "index.html",
                                          permissions: [], minHostVersion: ">=1.1.0", minBridgeVersion: "0.1.0", collections: [])
            try controller.stageVerified(accountID: account, moduleId: id, version: "0.1.0", releaseId: "\(id)@0.1.0",
                                         frontend: frontend, frontendSha256: WebGamePackage.digest(frontend),
                                         mediaType: ProductUIDocument.mediaType, hostManifest: manifest, descriptor: nil,
                                         gameArchive: game, gameSha256: gameDigest,
                                         runtimeArchive: index == 0 ? runtime : nil, runtimeSha256: runtimeDigest)
            let active = try controller.activate(accountID: account, moduleId: id)
            let entry = try controller.store.verifiedGameEntry(for: active)
            let url = try WebGameResourceProbe.entryURL(entry: entry)
            let runtimeURL = try XCTUnwrap(URL(string: "/__runtime/engine.mjs", relativeTo: url)?.absoluteURL)
            let task = RecordingGameSchemeTask(runtimeURL)
            try WebGameResourceProbe.serve(entry: entry, task: task)
            XCTAssertTrue(task.finished)
            XCTAssertEqual(task.body, try WebRuntimePackage(archive: runtime, expectedSha256: runtimeDigest).engine)
            if index == 0 { runningBrowser = try WebGameResourceProbe.browser(entry: entry) { _ in } }
        }
        XCTAssertEqual(shared.installedDigests(), [runtimeDigest])
        let engineFile = root.appendingPathComponent("SharedWebRuntimes/\(runtimeDigest)/engine.mjs")
        try Data("corrupted".utf8).write(to: engineFile, options: .atomic)
        XCTAssertThrowsError(try shared.verifiedEngine(sha256: runtimeDigest))
        try shared.installVerified(WebRuntimePackage(archive: runtime, expectedSha256: runtimeDigest))
        XCTAssertNoThrow(try shared.verifiedEngine(sha256: runtimeDigest))
        XCTAssertEqual(shared.installedDigests(), [runtimeDigest], "Repair must not leave a second runtime copy")
        try controller.store.removeModule(accountID: account, moduleId: ids[1])
        XCTAssertEqual(try shared.reclaimUnused(), [])
        XCTAssertNoThrow(try controller.store.verifiedGameEntry(for: XCTUnwrap(controller.active(accountID: account, moduleId: ids[0]))))
        XCTAssertThrowsError(try controller.store.removeModule(accountID: account, moduleId: ids[0])) {
            XCTAssertEqual($0 as? ModuleActivationError, .activeSession)
        }
        runningBrowser?.close()
        runningBrowser = nil
        try controller.store.removeModule(accountID: account, moduleId: ids[0])
        let uncertainSlot = controller.store.slotURL(accountID: account, moduleId: "digital.modula.incomplete", slot: .staged)
        try FileManager.default.createDirectory(at: uncertainSlot, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: uncertainSlot.appendingPathComponent("release.json"))
        XCTAssertEqual(try shared.reclaimUnused(), [], "Corrupt staged metadata must block reclamation")
        try controller.store.removeModule(accountID: account, moduleId: "digital.modula.incomplete")
        XCTAssertEqual(try shared.reclaimUnused(), [runtimeDigest])
        XCTAssertEqual(shared.installedDigests(), [])
    }

    @MainActor
    func testBothWebGameSlotsPreserveActiveAcrossRejectedUpdatesAndHealthRollback() async throws {
        continueAfterFailure = false
        let encoded = "H4sIAAAAAAAC/+3VwW6DMAwGYB4F5dLLQAQIsG7dZS8waU8QEmdQQeggTKuqvvuydqrUnrf2sP+72HIs5RBbaa2mz7hxfRf8mcQr8vwQvcuYpEl6yo/1sszyIEyCK5gnJ0d/ZfA/PfbkZNg4t4nofW4/Vux5sI6si15JzWPrttHL0LVqy0J1PFgxTUbOnYumUYULO1haPISTGtvNT2mizviS77ekztuGen1eYk8B3NCb7Ck2bUdTvJ4Ge5P95+XF/vOkECn2/xp2bFIN9ZItWT/ouZPx90REx4ng7I4dMrbcsfb0U/heRfeq0iZLJBniRghDWV2LLBNFqmvNOelEC1GYjJeiqnmdllqbvKJKluTfm+332D0AAAAAAAAAAAAAAAAAAACA3/AFxMM1iwAoAAA="
        let archive = try XCTUnwrap(Data(base64Encoded: encoded))
        func digest(_ bytes: Data) -> String {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        func frontend(_ id: String, _ version: String) -> Data {
            Data("""
            {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(id)","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","children":[{"type":"text","text":"\(version)"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
            """.utf8)
        }
        func manifest(_ id: String, _ version: String, minHostVersion: String = ">=1.0.0") -> ModuleManifest {
            ModuleManifest(id: id, name: id, version: version, runtime: "web-game", entry: "index.html",
                           permissions: [], minHostVersion: minHostVersion,
                           minBridgeVersion: "0.1.0", collections: [])
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("game-rollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        let account = "account-game-rollback"
        var seenOrigins = Set<String>()
        let connections = LockedConnectionCount()
        let listener = try NWListener(using: .tcp, on: .any)
        defer { listener.cancel() }
        let listenerReady = expectation(description: "loopback WebSocket target ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { listenerReady.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connections.increment()
            connection.cancel()
        }
        listener.start(queue: DispatchQueue(label: "game-websocket-probe"))
        await fulfillment(of: [listenerReady], timeout: 5)
        let listenerPort = try XCTUnwrap(listener.port)
        let control = NWConnection(host: "127.0.0.1", port: listenerPort, using: .tcp)
        let controlReady = expectation(description: "native loopback control connected")
        control.stateUpdateHandler = { state in
            if case .ready = state { controlReady.fulfill() }
        }
        control.start(queue: DispatchQueue(label: "game-websocket-control"))
        await fulfillment(of: [controlReady], timeout: 5)
        control.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(connections.value, 0, "native control must reach the WebSocket target")
        for engine in ["phaser", "playcanvas"] {
            let id = "digital.modula.orbit-\(engine)"
            let initial = frontend(id, "0.1.0")
            let update = frontend(id, "0.1.1")
            let host = manifest(id, "0.1.1")
            func stage(_ game: Data, _ gameDigest: String, descriptor: ModuleInstallDescriptor? = nil) throws {
                try controller.stageVerified(accountID: account, moduleId: id, version: "0.1.1", releaseId: "\(engine)-v2",
                                             frontend: update, frontendSha256: digest(update),
                                             mediaType: ProductUIDocument.mediaType, hostManifest: host,
                                             descriptor: descriptor, gameArchive: game, gameSha256: gameDigest)
            }
            try controller.stageVerified(accountID: account, moduleId: id, version: "0.1.0", releaseId: "\(engine)-v1",
                                         frontend: initial, frontendSha256: digest(initial),
                                         mediaType: ProductUIDocument.mediaType, hostManifest: manifest(id, "0.1.0"),
                                         descriptor: nil, gameArchive: archive, gameSha256: digest(archive))
            _ = try controller.activate(accountID: account, moduleId: id)
            let entry = try controller.store.verifiedGameEntry(for: XCTUnwrap(controller.active(accountID: account, moduleId: id)))
            let acceptedURL = try WebGameResourceProbe.entryURL(entry: entry)
            let origin = try XCTUnwrap(acceptedURL.host)
            XCTAssertTrue(seenOrigins.insert(origin).inserted, "Games must have distinct origins even with identical archive bytes")
            XCTAssertTrue(try WebGameResourceProbe.allows(entry: entry, request: acceptedURL))
            let acceptedTask = RecordingGameSchemeTask(acceptedURL)
            try WebGameResourceProbe.serve(entry: entry, task: acceptedTask)
            XCTAssertTrue(acceptedTask.finished)
            XCTAssertNil(acceptedTask.failure)
            let csp = (acceptedTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy")
            XCTAssertTrue(csp?.contains("connect-src 'self'") == true)
            XCTAssertTrue(csp?.contains("frame-src 'none'") == true)
            let permissionsPolicy = (acceptedTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Permissions-Policy")
            XCTAssertTrue(permissionsPolicy?.contains("geolocation=()") == true)
            XCTAssertTrue(permissionsPolicy?.contains("camera=()") == true)
            XCTAssertEqual(acceptedTask.body, try XCTUnwrap(WebGamePackage(archive: archive, expectedSha256: digest(archive)).files["index.html"]))
            let navigationFinished = expectation(description: "\(engine) game document loaded")
            var navigationFailure: Error?
            let browserProbe = try WebGameResourceProbe.browser(entry: entry) { error in
                navigationFailure = error
                navigationFinished.fulfill()
            }
            let browser = browserProbe.browser
            let keyWindow = try XCTUnwrap(UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
            browser.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            keyWindow.addSubview(browser)
            defer { browser.removeFromSuperview() }
            let loadStarted = await browserProbe.load(acceptedURL)
            XCTAssertTrue(loadStarted, "\(engine) game must load only after the local-only rule list is installed")
            await fulfillment(of: [navigationFinished], timeout: 20)
            XCTAssertNil(navigationFailure)
            let nativeHandlers = try await browser.evaluateJavaScript("Object.keys(window.webkit?.messageHandlers || {}).length")
            XCTAssertEqual(nativeHandlers as? Int, 0)
            let cookie = try await browser.evaluateJavaScript("(() => { try { return document.cookie } catch (_) { return '' } })()")
            XCTAssertEqual(cookie as? String, "")
            let priorConnections = connections.value
            _ = try await browser.evaluateJavaScript("""
                (() => {
                window.__gameCSPViolations = [];
                window.__gameCSPBlocked = [];
                document.addEventListener('securitypolicyviolation', event => {
                    window.__gameCSPViolations.push(event.violatedDirective);
                    window.__gameCSPBlocked.push([event.violatedDirective, event.blockedURI]);
                });
                fetch('https://127.0.0.1:9/blocked').catch(() => {});
                const script = document.createElement('script');
                script.src = 'https://127.0.0.1:9/blocked.js';
                document.head.appendChild(script);
                const frame = document.createElement('iframe');
                frame.src = location.href;
                document.body.appendChild(frame);
                window.__socketStatus = 'pending';
                try {
                    const socket = new WebSocket('ws://127.0.0.1:\(listenerPort.rawValue)/blocked-socket');
                    socket.onopen = () => window.__socketStatus = 'allowed';
                    socket.onerror = () => window.__socketStatus = 'blocked';
                } catch (error) { window.__socketStatus = 'blocked:' + error.name; }
                return true;
                })()
                """)
            var blockedNetwork = false
            var blockedScript = false
            var blockedFrame = false
            for _ in 0..<30 {
                let violations = try await browser.evaluateJavaScript("window.__gameCSPViolations") as? [String] ?? []
                blockedNetwork = violations.contains(where: { $0.contains("connect-src") })
                blockedScript = violations.contains(where: { $0.contains("script-src") })
                blockedFrame = violations.contains(where: { $0.contains("frame-src") })
                if blockedNetwork && blockedScript && blockedFrame { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(blockedNetwork, "\(engine) browser did not enforce connect-src CSP")
            XCTAssertTrue(blockedScript, "\(engine) browser did not block an external script")
            let observedBlocks = try await browser.evaluateJavaScript("window.__gameCSPBlocked") as? [[String]] ?? []
            XCTAssertTrue(blockedFrame, "\(engine) browser did not block an external iframe: \(observedBlocks)")
            let socketStatus = try await browser.evaluateJavaScript("window.__socketStatus") as? String ?? "unknown"
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(connections.value, priorConnections,
                           "\(engine) browser reached a WebSocket listener despite its denied connect policy: \(socketStatus), \(observedBlocks)")
            let popupsEnabled = browser.configuration.preferences.javaScriptCanOpenWindowsAutomatically
            XCTAssertFalse(popupsEnabled, "\(engine) popups must be disabled in the production configuration")
            let dataStore = browser.configuration.websiteDataStore
            XCTAssertFalse(dataStore.isPersistent, "\(engine) games must use an ephemeral WebKit data store")
            _ = try await browser.evaluateJavaScript("window.__crossOriginRead = 'pending'; fetch('modula-game://\(String(repeating: "0", count: 64))/index.html').then(() => window.__crossOriginRead = 'allowed', () => window.__crossOriginRead = 'blocked'); true")
            var crossOriginRead = "pending"
            for _ in 0..<30 {
                crossOriginRead = try await browser.evaluateJavaScript("window.__crossOriginRead") as? String ?? "pending"
                if crossOriginRead != "pending" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(crossOriginRead, "blocked")
            let syntheticToken = root.appendingPathComponent("qa-synthetic-auth-token.txt")
            try Data("qa-token-must-stay-private".utf8).write(to: syntheticToken, options: .atomic)
            _ = try await browser.evaluateJavaScript("window.__tokenRead = 'pending'; fetch('\(syntheticToken.absoluteString)').then(() => window.__tokenRead = 'allowed', () => window.__tokenRead = 'blocked'); true")
            var tokenRead = "pending"
            for _ in 0..<30 {
                tokenRead = try await browser.evaluateJavaScript("window.__tokenRead") as? String ?? "pending"
                if tokenRead != "pending" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(tokenRead, "blocked", "\(engine) game accessed a synthetic auth token outside its origin")
            _ = try await browser.evaluateJavaScript("""
                (() => {
                  window.__mediaResult = 'pending';
                  window.__motionResult = 'pending';
                  window.__locationResult = 'pending';
                  window.__prototypeMediaResult = 'pending';
                  window.__prototypeLocationResult = 'pending';
                  window.__popupResult = window.open('https://example.invalid/popup', '_blank') ? 'allowed' : 'blocked';
                  if (navigator.mediaDevices?.getUserMedia) {
                    navigator.mediaDevices.getUserMedia({audio: true, video: true})
                      .then(() => window.__mediaResult = 'allowed', () => window.__mediaResult = 'blocked');
                  } else window.__mediaResult = 'blocked';
                  const mediaPrototype = navigator.mediaDevices && Object.getPrototypeOf(navigator.mediaDevices);
                  if (typeof mediaPrototype?.getUserMedia === 'function') {
                    mediaPrototype.getUserMedia.call(navigator.mediaDevices, {audio: true})
                      .then(() => window.__prototypeMediaResult = 'allowed', () => window.__prototypeMediaResult = 'blocked');
                  } else window.__prototypeMediaResult = 'blocked';
                  if (typeof DeviceMotionEvent !== 'undefined' && DeviceMotionEvent.requestPermission) {
                    DeviceMotionEvent.requestPermission()
                      .then(result => window.__motionResult = result === 'granted' ? 'allowed' : 'blocked',
                            () => window.__motionResult = 'blocked');
                  } else window.__motionResult = 'blocked';
                  if (navigator.geolocation) {
                    navigator.geolocation.getCurrentPosition(
                      () => window.__locationResult = 'allowed',
                      () => window.__locationResult = 'blocked',
                      {timeout: 1000});
                  } else window.__locationResult = 'blocked';
                  const locationPrototype = navigator.geolocation && Object.getPrototypeOf(navigator.geolocation);
                  if (typeof locationPrototype?.getCurrentPosition === 'function') {
                    locationPrototype.getCurrentPosition.call(navigator.geolocation,
                      () => window.__prototypeLocationResult = 'allowed',
                      () => window.__prototypeLocationResult = 'blocked',
                      {timeout: 1000});
                  } else window.__prototypeLocationResult = 'blocked';
                  return true;
                })()
                """)
            var deviceResults = "pending"
            for _ in 0..<35 {
                deviceResults = try await browser.evaluateJavaScript("[window.__mediaResult, window.__motionResult, window.__locationResult, window.__popupResult, window.__prototypeMediaResult, window.__prototypeLocationResult].join(',')") as? String ?? "pending"
                if !deviceResults.contains("pending") { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(deviceResults, "blocked,blocked,blocked,blocked,blocked,blocked", "\(engine) gained a device or popup capability")
            let otherAccount = "qa-isolated-account"
            try controller.stageVerified(accountID: otherAccount, moduleId: id, version: "0.1.0", releaseId: "\(engine)-other-account",
                                         frontend: initial, frontendSha256: digest(initial), mediaType: ProductUIDocument.mediaType,
                                         hostManifest: manifest(id, "0.1.0"), descriptor: nil,
                                         gameArchive: archive, gameSha256: digest(archive))
            let otherRelease = try controller.activate(accountID: otherAccount, moduleId: id)
            let otherEntry = try controller.store.verifiedGameEntry(for: otherRelease)
            let otherURL = try WebGameResourceProbe.entryURL(entry: otherEntry)
            XCTAssertNotEqual(otherURL.host, acceptedURL.host)
            _ = try await browser.evaluateJavaScript("window.__accountRead = 'pending'; fetch('\(otherURL.absoluteString)').then(() => window.__accountRead = 'allowed', () => window.__accountRead = 'blocked'); true")
            var accountRead = "pending"
            for _ in 0..<30 {
                accountRead = try await browser.evaluateJavaScript("window.__accountRead") as? String ?? "pending"
                if accountRead != "pending" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(accountRead, "blocked", "\(engine) game read another account's installed bytes")
            let otherModule = "digital.modula.qa-other-\(engine)"
            let otherModuleFrontend = frontend(otherModule, "0.1.0")
            try controller.stageVerified(accountID: account, moduleId: otherModule, version: "0.1.0",
                                         releaseId: "\(engine)-other-module", frontend: otherModuleFrontend,
                                         frontendSha256: digest(otherModuleFrontend), mediaType: ProductUIDocument.mediaType,
                                         hostManifest: manifest(otherModule, "0.1.0"), descriptor: nil,
                                         gameArchive: archive, gameSha256: digest(archive))
            let otherModuleRelease = try controller.activate(accountID: account, moduleId: otherModule)
            let otherModuleEntry = try controller.store.verifiedGameEntry(for: otherModuleRelease)
            let otherModuleURL = try WebGameResourceProbe.entryURL(entry: otherModuleEntry)
            XCTAssertNotEqual(otherModuleURL.host, acceptedURL.host)
            _ = try await browser.evaluateJavaScript("window.__moduleRead = 'pending'; fetch('\(otherModuleURL.absoluteString)').then(() => window.__moduleRead = 'allowed', () => window.__moduleRead = 'blocked'); true")
            var moduleRead = "pending"
            for _ in 0..<30 {
                moduleRead = try await browser.evaluateJavaScript("window.__moduleRead") as? String ?? "pending"
                if moduleRead != "pending" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(moduleRead, "blocked", "\(engine) game read a different module's installed bytes")
            browser.stopLoading()
            for hostile in [
                "modula-game://\(origin)/../index.html",
                "modula-game://\(origin)/%2e%2e/index.html",
                "modula-game://\(origin)/index.html?other=1",
                "modula-game://\(String(repeating: "0", count: 64))/index.html",
                "file:///private/var/mobile/Containers/Data/index.html",
                "https://example.invalid/index.html",
            ] {
                XCTAssertFalse(try WebGameResourceProbe.allows(entry: entry, request: XCTUnwrap(URL(string: hostile))),
                               "Unexpected game resource: \(hostile)")
                let rejectedTask = RecordingGameSchemeTask(try XCTUnwrap(URL(string: hostile)))
                try WebGameResourceProbe.serve(entry: entry, task: rejectedTask)
                XCTAssertTrue(rejectedTask.finished, hostile)
                XCTAssertNil(rejectedTask.failure, hostile)
                XCTAssertEqual((rejectedTask.response as? HTTPURLResponse)?.statusCode, 404, hostile)
            }

            XCTAssertThrowsError(try stage(archive, String(repeating: "0", count: 64)), "\(engine) wrong digest")
            let incomplete = Data(archive.dropLast(5))
            XCTAssertThrowsError(try stage(incomplete, digest(incomplete)), "\(engine) incomplete download")
            let invalid = Data([0x4d, 0x5a, 0x00])
            XCTAssertThrowsError(try stage(invalid, digest(invalid)), "\(engine) invalid package")
            let revokedJSON: JSONValue = .object([
                "descriptorVersion": .string("1.0.0"), "moduleId": .string(id),
                "version": .string("0.1.1"), "registryReleaseId": .string("\(engine)-v2"),
                "descriptorSha256": .string(String(repeating: "a", count: 64)),
                "trust": .object(["revoked": .bool(true), "quarantined": .bool(false)]),
            ])
            let revoked = try XCTUnwrap(ModuleInstallDescriptor(json: revokedJSON))
            XCTAssertThrowsError(try stage(archive, digest(archive), descriptor: revoked), "\(engine) revoked release")
            XCTAssertNotEqual(ModuleCompatibility.evaluate(manifest(id, "0.1.1", minHostVersion: ">=99.0.0"),
                                                           hostVersions: ModuleCompatibility.advertisedHostVersions,
                                                           bridgeVersion: "0.1.0"), .compatible)
            XCTAssertEqual(controller.active(accountID: account, moduleId: id)?.version, "0.1.0")

            try stage(archive, digest(archive))
            controller.failNextActivationHealth = true
            XCTAssertThrowsError(try controller.activate(accountID: account, moduleId: id))
            XCTAssertEqual(controller.active(accountID: account, moduleId: id)?.version, "0.1.0")
            XCTAssertEqual(controller.store.index(accountID: account, moduleId: id).lastAuditReason, "activation-health")
            let reloaded = ModuleActivationController(store: ModuleArtifactStore(root: root))
            let recovered = try XCTUnwrap(reloaded.active(accountID: account, moduleId: id))
            XCTAssertEqual(recovered.version, "0.1.0")
            XCTAssertNoThrow(try reloaded.store.verifiedGameEntry(for: recovered))
        }
    }

    @MainActor
    func testCorruptActiveRegistryGameRestoresVerifiedPreviousRelease() throws {
        let id = "digital.modula.qa-rollback-game"
        let account = "qa-rollback-account"
        let archive = try XCTUnwrap(Data(base64Encoded:
            "H4sIAAAAAAAC/+3VwW6DMAwGYB4F5dLLQAQIsG7dZS8waU8QEmdQQeggTKuqvvuydqrUnrf2sP+72HIs5RBbaa2mz7hxfRf8mcQr8vwQvcuYpEl6yo/1sszyIEyCK5gnJ0d/ZfA/PfbkZNg4t4nofW4/Vux5sI6si15JzWPrttHL0LVqy0J1PFgxTUbOnYumUYULO1haPISTGtvNT2mizviS77ekztuGen1eYk8B3NCb7Ck2bUdTvJ4Ge5P95+XF/vOkECn2/xp2bFIN9ZItWT/ouZPx90REx4ng7I4dMrbcsfb0U/heRfeq0iZLJBniRghDWV2LLBNFqmvNOelEC1GYjJeiqnmdllqbvKJKluTfm+332D0AAAAAAAAAAAAAAAAAAACA3/AFxMM1iwAoAAA="
        ))
        let runtimeArchive = try XCTUnwrap(Data(base64Encoded:
            "H4sIAAAAAAAC/+3VyUrFMBQG4K59ipK1lsSkQ+rTZDi5gx0uTQtC6bsbqii6FbvQ/4NwDiGQzfkTGk6XgYr+GrNfw5NKqb0m3yvnsv7s9/26fiyznGcHWOJspnRl9j/Ry22c5txTMEs352s8m4l8m8/TQtvTXQZ/2824Z3OiIlw6isU1jsPx+Rd1+TX/Qsj0JCD/B1hZdGfqDWtZP/qlM8X7RDy8TYRg92zvWLsy+vgs0nErtVBEwYdANnBZUSO5MyS1Ii+oUrJxkishRKUbl5YVWnJjdalqbblh24b4AQAAAAAAAAAAAAAAAAAAAPzYK/FtDLwAKAAA"
        ))
        func digest(_ bytes: Data) -> String {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qa-game-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let activation = ModuleActivationController(store: ModuleArtifactStore(root: root))
        for (index, version) in ["0.1.0", "0.1.1"].enumerated() {
            let frontend = Data("""
                {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(id)","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","children":[{"type":"text","text":"Ready"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
                """.utf8)
            let manifest = ModuleManifest(id: id, name: "QA rollback game", version: version,
                                          runtime: "web-game", entry: "index.html", permissions: [],
                                          minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: [])
            try activation.stageVerified(accountID: account, moduleId: id, version: version,
                                         releaseId: "module-release:\(id):\(version)", frontend: frontend,
                                         frontendSha256: digest(frontend), mediaType: ProductUIDocument.mediaType,
                                         hostManifest: manifest, descriptor: nil,
                                         gameArchive: archive, gameSha256: digest(archive),
                                         runtimeArchive: index == 0 ? runtimeArchive : nil,
                                         runtimeSha256: digest(runtimeArchive))
            _ = try activation.activate(accountID: account, moduleId: id)
        }
        let latest = try XCTUnwrap(activation.active(accountID: account, moduleId: id))
        try Data("corrupt downloaded game".utf8).write(
            to: latest.directory.appendingPathComponent("game.tgz"), options: .atomic)
        let runtime = ModuleRuntimeController(manifests: [])
        runtime.setAccount(account)
        runtime.activation = activation
        runtime.installationGate = { _ in .runnable(descriptor: nil) }
        runtime.rollbackEligibility = { _, _ in false }
        let environment = ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)
        let denied = try XCTUnwrap(runtime.prepare(moduleID: id, environment: environment))
        XCTAssertEqual(denied.state, .integrityFailed)
        XCTAssertEqual(activation.active(accountID: account, moduleId: id)?.releaseId, latest.releaseId,
                       "An ineligible PREVIOUS_GOOD must never be made ACTIVE")
        runtime.rollbackEligibility = { _, _ in true }
        let recovered = try XCTUnwrap(runtime.prepare(moduleID: id, environment: environment))
        XCTAssertEqual(recovered.state, .ready)
        XCTAssertEqual(recovered.cachedRelease?.version, "0.1.0")
        XCTAssertEqual(activation.lastRollbackReason, "active-game-integrity")
        XCTAssertNoThrow(try activation.store.verifiedGameEntry(for: XCTUnwrap(activation.active(accountID: account, moduleId: id))))
        runtime.installationGate = { _ in .notInstalled }
        let revoked = try XCTUnwrap(runtime.prepare(moduleID: id, environment: environment))
        XCTAssertEqual(revoked.state, .notInstalled)
    }

    func testArchiveRejectsTraversalLinksNativePayloadAndIncompleteBytes() throws {
        // Tiny deterministic ustar/gzip fixtures exercise the real archive parser.
        let archives = [
            "valid": "H4sIAAAAAAAC/+3VwW6DMAwGYB4F5dLLQAQIsG7dZS8waU8QEmdQQeggTKuqvvuydqrUnrf2sP+72HIs5RBbaa2mz7hxfRf8mcQr8vwQvcuYpEl6yo/1sszyIEyCK5gnJ0d/ZfA/PfbkZNg4t4nofW4/Vux5sI6si15JzWPrttHL0LVqy0J1PFgxTUbOnYumUYULO1haPISTGtvNT2mizviS77ekztuGen1eYk8B3NCb7Ck2bUdTvJ4Ge5P95+XF/vOkECn2/xp2bFIN9ZItWT/ouZPx90REx4ng7I4dMrbcsfb0U/heRfeq0iZLJBniRghDWV2LLBNFqmvNOelEC1GYjJeiqnmdllqbvKJKluTfm+332D0AAAAAAAAAAAAAAAAAAACA3/AFxMM1iwAoAAA=",
            "traversal": "H4sIAAAAAAAC/+3WTU7DMBAF4Bwl8qYbEuIkbkKhbLgAEidw7DFNlZ8SO4iq6t0xDapU2EK76Ps2tsYjeWG/xHWn6SNeubYJ/k3izfP8MHo/xyRN0uN8qhdFlgdhEpzBaJ0c/JbBdXpoyclw5dwmorexfl+yp75z1LnohdQ41G4bPfdNrbYsVNPCkmkycmxcZAcVzrq+o9l9aNVQb75LlhrjS76/I3Xa1lfr0xJ7DOCC4viWrJIbitf2Uvn3q7/yL1Lk/xymw0cOrtWrbCk2dUPWfwD67iL558WP/z9P5sj/eeyYVStqJVuwttdjI+OvGxFNN4KzG3aYscWO1ceXou9VdKdKbbJEkiFuhDCUVZXIMjFPdaU5J51oIeYm44UoK16lhdYmL6mUBfnzZvs9sgcAAAAAAAAAAAAAAAAA8Jc+AZRabE4AKAAA",
            "symlink": "H4sIAAAAAAAC/+3WS26DMBAGYI6CvMmmUAwYaNp00wtU6gmMPS5EPFIwVaMod6+bVJHSLrppkkX+b+PRMJIRY4+oO00fYWXbxjuZyMnSdLc6P9cojuJDvM/neZJ6fuSdwTRaObgtvev00JKVfmXtKqC3qX5fsKe+s9TZ4IXUNNR2HTz3Ta3WzFf7BwumycipscE4KH/W9R3N7v1RDfXqOzVSY1zK1Xekjsv6cnmcYo8eXNCrbClcjifd46/7/yvmsYgzz4/D8La3FQ2BVKqfOnuKF73y+7/rv6kbGt3H7buL9J/nP+Y/jzIRY/6fw4aNqqJWsjlrez01Mvw6EcH+RHB2w3YRm29YffhTcLWK7lShTRJJMsSNEIaSshRJIrJYl5pz0pEWIjMJz0VR8jLOtTZpQYXMyfWbbbeYvQAAAAAAAAAAAAAAAAAAAP/lE107p+gAKAAA",
            "native": "H4sIAAAAAAAC/+3WTW7DIBAFYB/FYpNNbYFtbDdtuukFKvUEGIaGyD+pjaNGUe5eN6kipd22ySLv24CGkVjAE7jW0Ee89E0d/Bs+ybPsME5+jjzhyWl+rBdFmgUhDy5gHLzqpy2D2/TYkFfh0vt1RO+j2yzYc9d6an30Snrsnd9GL13t9JaF+riwYIasGmsfDb0OZ23X0uwhHHTv1t+lgWo7lab+lvR5W1etzkvsKYAroo2rY7OtXXW9/HOe/sp/kiD/l1ApgxDcsDfVUGxdTUO8Grr2KvkXxY/3X/BcIv8XsWODXlKj2Jw1nRlrFX/diOh4IwS7Y4cZm++YO/0Up15N97o0NuWKLAkrpaW0qmSayjwxlRGCDDdS5jYVhSwrUSWFMTYrqVQFTefN9ntkDwAAAAAAAAAAAAAAAADgL30CL2xWwAAoAAA=",
            "caseCollision": "H4sIAAAAAAAC/+3Xy2rcMBQGYD+K0SabeNBdcpIphKy6aCn0CXQ56jj4ko7lkBDy7lUyQ2Cy6SqTljkfGAlZSFrol+VujPCw2uShrz4MLbSUr2XxvqSc8rf6rt0YIauaVkewzNlty5TVaboaILt6k/NdA7+X7n5NbqYxw5ibnxCWbZcfmx9T34VHUofdizWJkNzS52behvpsnEY4u6znsO3u9k0z9Kk0lf4jhMNuk789bCJfKvSJBteNq9v5Q+f4W/4pFe/zzznF/B/Dw5phCE7Yt+uv3//B/FPM/7HyzzEEJ+yXG2CVuh7mcgpM46fkX3J5mH9GteKY/2N4InPYwODIBRmmuPRu9bIjmt2OYOScvNbIxRPp3v4US98AbbAxCeogAUtKJRDeKyGU5tFHxiDSqJROghllPfPcxJikBesMMMPLwPubZxmMJU61ZyxwAdyGwBWNEE0KlLY2CsuFs1Ibp6SQNDEXJCihgrdKStmKVAbbf8bKYK1g1rZKB+HKhKBTWY1ihkrNmQFebpatN6VHlD5qIQy0Ukuvy+OifVnZ8zOeCgghhBBCCCGEEEIIIYQQ+p/9AVJilh4AKAAA",
        ]
        func parse(_ label: String) throws -> WebGamePackage {
            let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(archives[label])))
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return try WebGamePackage(archive: bytes, expectedSha256: digest)
        }
        XCTAssertEqual(try parse("valid").files.keys.sorted(), ["index.html"])
        for label in ["traversal", "symlink", "native", "caseCollision"] {
            XCTAssertThrowsError(try parse(label), "Unsafe archive accepted: \(label)")
        }
        let complete = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(archives["valid"])))
        let incomplete = Data(complete.dropLast(5))
        let digest = SHA256.hash(data: incomplete).map { String(format: "%02x", $0) }.joined()
        XCTAssertThrowsError(try WebGamePackage(archive: incomplete, expectedSha256: digest))
        XCTAssertThrowsError(try WebGamePackage(archive: complete, expectedSha256: String(repeating: "0", count: 64)))
    }

    func testLaunchRejectsSymlinkTamperAndUnexpectedMember() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("web-game-isolation-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        let digest = String(repeating: "a", count: 64)
        let game = root.appendingPathComponent(digest, isDirectory: true)
        try manager.createDirectory(at: game, withIntermediateDirectories: true)
        let html = Data("<html><body>verified</body></html>".utf8)
        let script = Data("window.gameReady = true".utf8)
        let trusted = ["index.html": html, "game.js": script]
        for (path, bytes) in trusted { try bytes.write(to: game.appendingPathComponent(path)) }
        let inventory: [String: Any] = [
            "schema": "modula.game-files.1",
            "files": trusted.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() },
        ]
        try JSONSerialization.data(withJSONObject: inventory)
            .write(to: game.appendingPathComponent("game.files.json"))
        XCTAssertNoThrow(try WebGamePackage.verifyInstalled(at: game, expectedSha256: digest, trustedFiles: trusted))

        let outside = root.appendingPathComponent("other-account.js")
        try script.write(to: outside)
        try manager.removeItem(at: game.appendingPathComponent("game.js"))
        try manager.createSymbolicLink(at: game.appendingPathComponent("game.js"), withDestinationURL: outside)
        XCTAssertThrowsError(try WebGamePackage.verifyInstalled(at: game, expectedSha256: digest, trustedFiles: trusted))

        try manager.removeItem(at: game.appendingPathComponent("game.js"))
        try Data("window.gameReady = false".utf8).write(to: game.appendingPathComponent("game.js"))
        XCTAssertThrowsError(try WebGamePackage.verifyInstalled(at: game, expectedSha256: digest, trustedFiles: trusted))

        try script.write(to: game.appendingPathComponent("game.js"))
        try Data("unlisted".utf8).write(to: game.appendingPathComponent("unlisted.txt"))
        XCTAssertThrowsError(try WebGamePackage.verifyInstalled(at: game, expectedSha256: digest, trustedFiles: trusted))
    }
}

// MARK: - GUBIC host hardening (prism/gubic-host-hardening)

private enum HardeningGameFixture {
    static let strictPolicy = "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'none'"
    /// The exact policy shipped by the bundled Phaser and PlayCanvas fixtures
    /// (ModulaUITests/GameFixtures/*/game.tgz index.html).
    static let samplePolicy = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'none'; media-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'"

    static func document(_ policy: String = strictPolicy, body: String = "<p id=\"ready\">ready</p>") -> String {
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><title>Hardening QA</title></head><body>\(body)</body></html>"
    }

    /// A real ustar archive with a `modula.game-files.1` inventory, zlib-wrapped
    /// (WebGamePackage inflates gzip or zlib), parsed by the production code.
    static func archive(_ files: [String: Data]) throws -> Data {
        var all = files
        let inventory: [String: Any] = ["schema": "modula.game-files.1", "files": files.mapValues(WebGamePackage.digest)]
        all["game.files.json"] = try JSONSerialization.data(withJSONObject: inventory, options: [.sortedKeys])
        var tar = Data()
        for path in all.keys.sorted() {
            let bytes = all[path]!
            tar.append(header(path, size: bytes.count))
            tar.append(bytes)
            tar.append(Data(count: (512 - bytes.count % 512) % 512))
        }
        tar.append(Data(count: 1_024))
        var length = compressBound(uLong(tar.count))
        var output = [UInt8](repeating: 0, count: Int(length))
        let status = tar.withUnsafeBytes { raw in
            compress2(&output, &length, raw.bindMemory(to: Bytef.self).baseAddress, uLong(tar.count), Z_BEST_COMPRESSION)
        }
        guard status == Z_OK else { throw WebGamePackageError.invalid("fixture compression") }
        return Data(output.prefix(Int(length)))
    }

    private static func header(_ path: String, size: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, _ offset: Int) { for (index, byte) in text.utf8.enumerated() { bytes[offset + index] = byte } }
        func octal(_ value: Int, _ width: Int) -> String {
            let digits = String(value, radix: 8)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        put(path, 0)
        put("0000644\0", 100)
        put("0000000\0", 108)
        put("0000000\0", 116)
        put(octal(size, 11) + "\0", 124)
        put("00000000000\0", 136)
        put("        ", 148)
        put("0", 156)
        put("ustar\0", 257)
        put("00", 263)
        let sum = bytes.reduce(0) { $0 + Int($1) }
        put(octal(sum, 6) + "\0 ", 148)
        return Data(bytes)
    }
}

private final class PermissiveRecordingNavigation: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    var requested: [String] = []
    var failure: Error?
    init(finished: XCTestExpectation) { self.finished = finished }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        requested.append(action.request.url?.absoluteString ?? "")
        return .allow
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished.fulfill() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error
        finished.fulfill()
    }
}

private final class NavigationOutcome { var error: Error? }

@MainActor
final class WebGameHostHardeningTests: XCTestCase {
    private var root: URL!
    private var controller: ModuleActivationController!
    private let account = "qa-hardening-account"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("game-hardening-\(UUID().uuidString)")
        controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// `bypassingHygiene` simulates a document that every validator missed, so the
    /// production host (header CSP + rule list) is the only thing in its way.
    private func install(_ files: [String: Data], id: String, bypassingHygiene: Bool = false) throws -> URL {
        try WebGamePackage.$skipsDocumentPolicyHygiene.withValue(bypassingHygiene) {
            try installVerified(files, id: id)
        }
    }

    private func installVerified(_ files: [String: Data], id: String) throws -> URL {
        let archive = try HardeningGameFixture.archive(files)
        let frontend = Data("""
            {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(id)","releaseVersion":"0.1.0","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","children":[{"type":"text","text":"Ready"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
            """.utf8)
        let manifest = ModuleManifest(id: id, name: id, version: "0.1.0", runtime: "web-game", entry: "index.html",
                                      permissions: [], minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: [])
        try controller.stageVerified(accountID: account, moduleId: id, version: "0.1.0", releaseId: "\(id)@0.1.0",
                                     frontend: frontend, frontendSha256: WebGamePackage.digest(frontend),
                                     mediaType: ProductUIDocument.mediaType, hostManifest: manifest, descriptor: nil,
                                     gameArchive: archive, gameSha256: WebGamePackage.digest(archive))
        let active = try controller.activate(accountID: account, moduleId: id)
        return try controller.store.verifiedGameEntry(for: active)
    }

    private func attach(_ view: WKWebView) throws {
        let keyWindow = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        keyWindow.addSubview(view)
    }

    /// Opens a game through the production delegate, rule list and loader.
    private func open(_ entry: URL, bypassingHygiene: Bool = false) async throws -> (probe: WebGameBrowserProbe, url: URL) {
        let finished = expectation(description: "game document loaded")
        finished.assertForOverFulfill = false
        let outcome = NavigationOutcome()
        let (url, probe) = try WebGamePackage.$skipsDocumentPolicyHygiene.withValue(bypassingHygiene) {
            let url = try WebGameResourceProbe.entryURL(entry: entry)
            let probe = try WebGameResourceProbe.browser(entry: entry) { error in
                outcome.error = error
                finished.fulfill()
            }
            return (url, probe)
        }
        try attach(probe.browser)
        let started = await probe.load(url)
        XCTAssertTrue(started, "the local-only rule list must compile before the game loads")
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertNil(outcome.error)
        return (probe, url)
    }

    private func value(_ browser: WKWebView, _ script: String) async throws -> String {
        try await browser.evaluateJavaScript(script) as? String ?? "<non-string>"
    }

    /// `evaluateJavaScript` does not wait for a Promise (WKError.javaScriptResultTypeIsUnsupported).
    /// `callAsyncJavaScript` in the page world treats the body as an async function; use `return await`.
    private func awaitPageJS(_ browser: WKWebView, _ functionBody: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await browser.callAsyncJavaScript(functionBody, arguments: arguments, in: nil, contentWorld: .page)
    }

    private func loopbackListener() async throws -> (NWListener, NWEndpoint.Port, LockedConnectionCount) {
        let connections = LockedConnectionCount()
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "loopback listener ready")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connections.increment()
            connection.cancel()
        }
        listener.start(queue: DispatchQueue(label: "game-hardening-listener"))
        await fulfillment(of: [ready], timeout: 5)
        return (listener, try XCTUnwrap(listener.port), connections)
    }

    func testHTMLHeaderPolicyIsTheBoundaryAndMeetsTheContract() throws {
        let header = try WebGameDocumentPolicy.parse(WebGameResourceProbe.htmlContentSecurityPolicy)
        XCTAssertEqual(WebGameResourceProbe.htmlContentSecurityPolicy, WebGamePackageServe.headerContentSecurityPolicy)
        XCTAssertEqual(header["default-src"], ["'none'"])
        XCTAssertEqual(header["script-src"], ["'self'"])
        XCTAssertEqual(header["connect-src"], ["'self'"])
        XCTAssertEqual(header["font-src"], ["'self'"])
        XCTAssertEqual(Set(header["img-src"] ?? []), Set(["'self'", "data:", "blob:"]))
        XCTAssertEqual(Set(header["media-src"] ?? []), Set(["'self'", "blob:"]))
        for name in ["object-src", "worker-src", "child-src", "frame-src", "base-uri", "form-action", "frame-ancestors"] {
            XCTAssertEqual(header[name], ["'none'"], name)
        }
        // The header is a constant: serving any document yields the same bytes,
        // whatever its own meta policy says.
        let permissive = HardeningGameFixture.document("default-src *; script-src * 'unsafe-inline' 'unsafe-eval'; connect-src *")
        let entry = try install(["index.html": Data(permissive.utf8)], id: "digital.modula.qa-header-constant", bypassingHygiene: true)
        let url = try WebGamePackage.$skipsDocumentPolicyHygiene.withValue(true) { try WebGameResourceProbe.entryURL(entry: entry) }
        let task = RecordingGameSchemeTask(url)
        try WebGamePackage.$skipsDocumentPolicyHygiene.withValue(true) { try WebGameResourceProbe.serve(entry: entry, task: task) }
        let response = try XCTUnwrap(task.response as? HTTPURLResponse)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Security-Policy"), WebGameResourceProbe.htmlContentSecurityPolicy)
    }

    /// Sentinel's #188 bypass classes, loaded through the production loader with
    /// package hygiene switched off. Nothing may reach the network and no
    /// injected script may run.
    func testValidatorBypassPayloadsAreContainedByTheHost() async throws {
        let (listener, port, connections) = try await loopbackListener()
        defer { listener.cancel() }
        let target = "127.0.0.1:\(port.rawValue)"
        let strict = HardeningGameFixture.strictPolicy
        let beacon = """
            <script>
            window.__injected = 'ran';
            fetch('http://\(target)/inline-fetch').catch(() => {});
            try { new WebSocket('ws://\(target)/inline-socket'); } catch (_) {}
            new Image().src = 'http://\(target)/inline-beacon.png';
            </script>
            """
        let permissive = "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; script-src * 'unsafe-inline' 'unsafe-eval'; connect-src *; img-src *"
        let payloads: [(String, String)] = [
            ("comment-trick remote script before meta CSP",
             "<!doctype html><html><head><!--><script src=\"http://\(target)/x.js\"></script><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"><title>t</title></head><body>\(beacon)</body></html>"),
            ("trailing-space http-equiv with a permissive policy",
             "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy \" content=\"\(permissive)\"><title>t</title></head><body><script src=\"http://\(target)/trailing.js\"></script>\(beacon)</body></html>"),
            ("permissive meta CSP trying to loosen the header",
             "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"\(permissive)\"><title>t</title></head><body><img src=\"http://\(target)/loosen.png\"><script src=\"http://\(target)/loosen.js\"></script>\(beacon)</body></html>"),
            ("no meta CSP, inline fetch/WebSocket/image beacon",
             "<!doctype html><html><head><title>t</title></head><body>\(beacon)<script>eval(\"window.__injected = 'eval'\")</script></body></html>"),
        ]
        for (index, payload) in payloads.enumerated() {
            let (label, html) = payload
            XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: html), "hygiene unexpectedly accepted: \(label)")
            let entry = try install(["index.html": Data(html.utf8)], id: "digital.modula.qa-bypass-\(index)", bypassingHygiene: true)
            let before = connections.value
            let (probe, url) = try await open(entry, bypassingHygiene: true)
            try await Task.sleep(for: .milliseconds(1_500))
            let injected = try await value(probe.browser, "String(window.__injected)")
            XCTAssertEqual(injected, "undefined", "injected script ran: \(label)")
            XCTAssertEqual(connections.value, before, "network reached: \(label)")
            XCTAssertEqual(probe.browser.url?.absoluteString, url.absoluteString, label)
            probe.browser.removeFromSuperview()
            probe.close()
        }
    }

    func testDocumentHygieneRejectsCommentTrickAndPaddedHTTPEquiv() {
        let strict = HardeningGameFixture.strictPolicy
        let rejected: [String: String] = [
            "comment trick <!-->": "<!doctype html><html><head><!--><script src=\"http://127.0.0.1:9/x.js\"></script><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>",
            "comment trick <!--->": "<!doctype html><html><head><!---><script src=\"http://127.0.0.1:9/x.js\"></script><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>",
            "comment trick with later close": "<!doctype html><html><head><!--><script src=\"http://127.0.0.1:9/x.js\"></script><!-- note --><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>",
            "--!> closes a comment": "<!doctype html><html><head><!-- a --!><script src=\"http://127.0.0.1:9/x.js\"></script><!-- b --><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>",
            "padded http-equiv, strict content": "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy \" content=\"\(strict)\"></head></html>",
            "padded http-equiv, permissive content": "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy \" content=\"default-src *; script-src *\"></head></html>",
            "padded http-equiv beside a strict one": HardeningGameFixture.document().replacingOccurrences(of: "<title>", with: "<meta http-equiv=\" content-security-policy\" content=\"default-src *\"><title>"),
        ]
        for (label, html) in rejected.sorted(by: { $0.key < $1.key }) {
            XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: html), label)
        }
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: "<!-- build 1 --><!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>"))
    }

    /// Mosaic M1: hygiene must not refuse a game the server publishes.
    /// Named entities in non-CSP meta attributes are ignored; http-equiv and
    /// the chosen CSP content are decoded exactly once; object-src is optional.
    func testDocumentHygieneDecodesOnlyCSPMetaAttributesAndAllowsOptionalObjectSrc() throws {
        let policy = "default-src 'none'; script-src 'self'; connect-src 'none'"
        let withObject = policy + "; object-src 'none'"

        // A description (or any non-CSP attribute) with named entities beyond
        // the five XML names must still install. The server accepts these.
        let described = "<!doctype html><html><head><meta name=\"description\" content=\"Caf&eacute; &nbsp;&copy; 2026\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><title>t</title></head><body></body></html>"
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: described))
        let describedArchive = try HardeningGameFixture.archive(["index.html": Data(described.utf8)])
        XCTAssertNoThrow(try WebGamePackage(archive: describedArchive, expectedSha256: WebGamePackage.digest(describedArchive)))

        // http-equiv and CSP content are decoded exactly once.
        let encoded = try WebGameDocumentPolicy.validate(html: "<!doctype html><html><head><meta http-equiv=\"Content&#45;Security&#45;Policy\" content=\"default-src &#39;none&#39;; script-src &#39;self&#39;; connect-src &#39;none&#39;\"></head></html>")
        XCTAssertEqual(encoded["default-src"], ["'none'"])
        XCTAssertEqual(encoded["script-src"], ["'self'"])
        XCTAssertEqual(encoded["connect-src"], ["'none'"])
        XCTAssertNil(encoded["object-src"])

        // A second decode would turn &amp;#39; into a quote and accept this.
        // After one decode the source is still &#39;none&#39;, which is refused.
        XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src &amp;#39;none&amp;#39;; script-src 'self'; connect-src 'none'\"></head></html>"))

        // object-src may be omitted (server web-game-csp.ts); if present it must be 'none'.
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(policy)))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(withObject)))
        let optionalArchive = try HardeningGameFixture.archive(["index.html": Data(HardeningGameFixture.document(policy).utf8)])
        XCTAssertNoThrow(try WebGamePackage(archive: optionalArchive, expectedSha256: WebGamePackage.digest(optionalArchive)))
        XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(
            "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'self'")))
    }

    func testTopNavigationToAnotherListedFileOrRemoteURLIsCancelled() async throws {
        let entry = try install([
            "index.html": Data(HardeningGameFixture.document().utf8),
            "other.html": Data(HardeningGameFixture.document(body: "<p>other</p>").utf8),
            "art.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"></svg>".utf8),
        ], id: "digital.modula.qa-navigation")
        let (probe, url) = try await open(entry)
        defer { probe.browser.removeFromSuperview(); probe.close() }
        let browser = probe.browser
        let origin = try XCTUnwrap(url.host)
        for target in ["other.html", "art.svg", "/art.svg", "https://example.invalid/", "http://127.0.0.1:9/",
                       "modula-game://\(origin)/index.html?again=1",
                       "modula-game://\(String(repeating: "0", count: 64))/index.html"] {
            _ = try await browser.evaluateJavaScript("location.href = '\(target)'; true")
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(browser.url?.absoluteString, url.absoluteString, "top navigation was not cancelled: \(target)")
            let location = try await value(browser, "location.href")
            XCTAssertEqual(location, url.absoluteString, "document changed after navigating to \(target)")
        }
        // Native-initiated loads go through the same policy.
        for target in ["https://example.invalid/", "modula-game://\(origin)/other.html", "modula-game://\(origin)/art.svg"] {
            browser.load(URLRequest(url: try XCTUnwrap(URL(string: target))))
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(browser.url?.absoluteString, url.absoluteString, "load was not cancelled: \(target)")
        }
        // A window.open / target=_blank attempt never produces a new view.
        let popup = try await value(browser, "window.open('other.html', '_blank') ? 'allowed' : 'blocked'")
        XCTAssertEqual(popup, "blocked")
    }

    func testSVGWithScriptCannotRunOrReachTheNetwork() async throws {
        let (listener, port, connections) = try await loopbackListener()
        defer { listener.cancel() }
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><image href="http://127.0.0.1:\(port.rawValue)/svg-image" width="8" height="8"/><script>
            fetch('http://127.0.0.1:\(port.rawValue)/svg-fetch').catch(() => {});
            try { new WebSocket('ws://127.0.0.1:\(port.rawValue)/svg-socket'); } catch (_) {}
            location.href = 'ran.html';
            </script></svg>
            """
        let entry = try install([
            "index.html": Data(HardeningGameFixture.document().utf8),
            "evil.svg": Data(svg.utf8),
        ], id: "digital.modula.qa-svg")
        let (probe, url) = try await open(entry)
        defer { probe.browser.removeFromSuperview(); probe.close() }
        let browser = probe.browser
        let svgURL = try XCTUnwrap(URL(string: "evil.svg", relativeTo: url)?.absoluteURL)

        // 1. The production policy refuses the SVG as a top-level document.
        _ = try await browser.evaluateJavaScript("location.href = 'evil.svg'; true")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(browser.url?.absoluteString, url.absoluteString)

        // 2. The SVG response carries the §4.2 header CSP (no 'unsafe-inline').
        let task = RecordingGameSchemeTask(svgURL)
        try WebGameResourceProbe.serve(entry: entry, task: task)
        let headers = try XCTUnwrap(task.response as? HTTPURLResponse)
        XCTAssertEqual(headers.value(forHTTPHeaderField: "Content-Type"), "image/svg+xml")
        XCTAssertEqual(headers.value(forHTTPHeaderField: "Content-Security-Policy"),
                       WebGameResourceProbe.resourceContentSecurityPolicy)
        XCTAssertEqual(headers.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")

        // 3. Defence in depth: even if a delegate allowed the navigation, the
        //    rendered SVG runs no script and makes no network request.
        let before = connections.value
        let finished = expectation(description: "svg document rendered")
        finished.assertForOverFulfill = false
        let permissive = PermissiveRecordingNavigation(finished: finished)
        browser.navigationDelegate = permissive
        browser.load(URLRequest(url: svgURL))
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertNil(permissive.failure, "the SVG document should render so the test proves its script is inert")
        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertFalse(permissive.requested.contains { $0.hasSuffix("/ran.html") },
                       "SVG script executed: \(permissive.requested)")
        XCTAssertEqual(connections.value, before, "SVG document reached the network")
    }

    func testEveryResponseCarriesAContentSecurityPolicy() throws {
        let files: [String: Data] = [
            "index.html": Data(HardeningGameFixture.document().utf8),
            "levels/menu.html": Data(HardeningGameFixture.document(body: "<p>menu</p>").utf8),
            "art.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8),
            "main.js": Data("window.ready = true".utf8),
            "engine.mjs": Data("export const ready = true".utf8),
            "style.css": Data("body { margin: 0 }".utf8),
            "level.json": Data("{}".utf8),
            "notes.txt": Data("ok".utf8),
            "pixel.png": Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
            "sprite.gif": Data([0x47, 0x49, 0x46, 0x38]),
            "sound.wav": Data("RIFF".utf8),
            "clip.mp4": Data("ftyp".utf8),
            "clip.webm": Data("webm".utf8),
            "tone.m4a": Data("ftyp".utf8),
            "ui.woff": Data("wOFF".utf8),
            "ui.woff2": Data("wOF2".utf8),
            "ui.ttf": Data("ttf".utf8),
            "ui.otf": Data("otf".utf8),
            "map.xml": Data("<root/>".utf8),
            "blob.bin": Data([0x01, 0x02, 0x03]),
        ]
        let expectedType = [
            "index.html": "text/html; charset=utf-8",
            "levels/menu.html": "text/html; charset=utf-8",
            "art.svg": "image/svg+xml",
            "main.js": "text/javascript; charset=utf-8",
            "engine.mjs": "text/javascript; charset=utf-8",
            "style.css": "text/css; charset=utf-8",
            "level.json": "application/json",
            "notes.txt": "text/plain; charset=utf-8",
            "pixel.png": "image/png",
            "sprite.gif": "image/gif",
            "sound.wav": "audio/wav",
            "clip.mp4": "video/mp4",
            "clip.webm": "video/webm",
            "tone.m4a": "audio/mp4",
            "ui.woff": "font/woff",
            "ui.woff2": "font/woff2",
            "ui.ttf": "font/ttf",
            "ui.otf": "font/otf",
            "map.xml": "application/xml",
            "blob.bin": "application/octet-stream",
        ]
        let entry = try install(files, id: "digital.modula.qa-headers")
        let url = try WebGameResourceProbe.entryURL(entry: entry)
        for path in files.keys.sorted() {
            let resource = try XCTUnwrap(URL(string: path, relativeTo: url)?.absoluteURL)
            let task = RecordingGameSchemeTask(resource)
            try WebGameResourceProbe.serve(entry: entry, task: task)
            XCTAssertTrue(task.finished, path)
            let response = try XCTUnwrap(task.response as? HTTPURLResponse, path)
            let csp = try XCTUnwrap(response.value(forHTTPHeaderField: "Content-Security-Policy"), "\(path) has no CSP")
            XCTAssertEqual(response.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff", path)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), expectedType[path], path)
            XCTAssertEqual(csp, WebGamePackageServe.headerContentSecurityPolicy, path)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Cross-Origin-Resource-Policy"), "same-origin", path)
            XCTAssertNil(response.value(forHTTPHeaderField: "Set-Cookie"), path)
        }
    }

    func testStorageIsNotReadableAcrossGamesOrAfterRelaunch() async throws {
        let files = ["index.html": Data(HardeningGameFixture.document().utf8)]
        let first = try install(files, id: "digital.modula.qa-storage-one")
        let second = try install(files, id: "digital.modula.qa-storage-two")
        let read = """
            (() => { try { return String(localStorage.getItem('qa-secret')) + '|' + String(sessionStorage.getItem('qa-secret')); }
                     catch (error) { return 'error:' + error.name; } })()
            """
        let write = """
            (() => { try { localStorage.setItem('qa-secret', 'game-one'); sessionStorage.setItem('qa-secret', 'game-one'); return 'written'; }
                     catch (error) { return 'error:' + error.name; } })()
            """
        let (one, oneURL) = try await open(first)
        let written = try await value(one.browser, write)
        XCTAssertEqual(written, "written")
        let ownRead = try await value(one.browser, read)
        XCTAssertEqual(ownRead, "game-one|game-one", "storage must work within one session for this test to prove isolation")

        let (two, twoURL) = try await open(second)
        XCTAssertNotEqual(oneURL.host, twoURL.host)
        let otherRead = try await value(two.browser, read)
        XCTAssertFalse(otherRead.contains("game-one"), "a second game read the first game's storage: \(otherRead)")
        two.browser.removeFromSuperview()
        two.close()

        one.browser.removeFromSuperview()
        one.close()
        let (relaunched, relaunchedURL) = try await open(first)
        defer { relaunched.browser.removeFromSuperview(); relaunched.close() }
        XCTAssertEqual(relaunchedURL, oneURL)
        let afterRelaunch = try await value(relaunched.browser, read)
        XCTAssertFalse(afterRelaunch.contains("game-one"), "storage survived a relaunch: \(afterRelaunch)")
    }

    func testLocalOnlyRuleListBlocksNetworkBeneathCSP() async throws {
        let (listener, port, connections) = try await loopbackListener()
        defer { listener.cancel() }
        let page = """
            <img src="http://127.0.0.1:\(port.rawValue)/rule-image.png">
            <script>
            fetch('http://127.0.0.1:\(port.rawValue)/rule-fetch').catch(() => {});
            try { new WebSocket('ws://127.0.0.1:\(port.rawValue)/rule-socket'); } catch (_) {}
            </script>
            """
        func attempt(withRules: Bool) async throws -> Int {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            if withRules {
                let installed = await WebGameResourceProbe.installNetworkRules(on: configuration.userContentController)
                XCTAssertTrue(installed)
            }
            let view = WKWebView(frame: .zero, configuration: configuration)
            try attach(view)
            defer { view.removeFromSuperview() }
            let finished = expectation(description: "rule probe loaded (rules: \(withRules))")
            let delegate = RecordingGameNavigation(finished: finished)
            view.navigationDelegate = delegate
            let before = connections.value
            view.loadHTMLString(page, baseURL: URL(string: "http://127.0.0.1:\(port.rawValue)/"))
            await fulfillment(of: [finished], timeout: 20)
            try await Task.sleep(for: .milliseconds(1_500))
            return withExtendedLifetime(delegate) { connections.value - before }
        }
        let control = try await attempt(withRules: false)
        XCTAssertGreaterThan(control, 0, "without the rule list the probe page must reach the listener, or this test proves nothing")
        let ruled = try await attempt(withRules: true)
        XCTAssertEqual(ruled, 0, "the local-only rule list let a page reach the network")
    }

    /// ATLAS: connect-src 'self' is the per-package scheme origin only.
    /// GET of a listed file is allowed; an unlisted path is 404; POST is
    /// rejected; the document policy refuses a remote host or ws:.
    func testSameOriginFetchOfListedFilesIsAllowedAndUnsafeConnectSrcIsRejected() async throws {
        let policy = "default-src 'none'; script-src 'self'; connect-src 'self'; object-src 'none'"
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(policy)))
        for rejected in [
            "default-src 'none'; script-src 'self'; connect-src https://evil.example; object-src 'none'",
            "default-src 'none'; script-src 'self'; connect-src ws://evil.example; object-src 'none'",
            "default-src 'none'; script-src 'self'; connect-src wss:; object-src 'none'",
        ] {
            XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(rejected)), rejected)
        }

        let listedBody = Data("{\"ok\":true}".utf8)
        let entry = try install([
            "index.html": Data(HardeningGameFixture.document(policy).utf8),
            "level.json": listedBody,
        ], id: "digital.modula.qa-connect-self")
        let url = try WebGameResourceProbe.entryURL(entry: entry)
        let listed = try XCTUnwrap(URL(string: "level.json", relativeTo: url)?.absoluteURL)
        let missing = try XCTUnwrap(URL(string: "missing.json", relativeTo: url)?.absoluteURL)

        let get = RecordingGameSchemeTask(listed)
        try WebGameResourceProbe.serve(entry: entry, task: get)
        XCTAssertTrue(get.finished)
        XCTAssertNil(get.failure)
        let getResponse = try XCTUnwrap(get.response as? HTTPURLResponse)
        XCTAssertEqual(getResponse.statusCode, 200)
        XCTAssertEqual(get.body, listedBody)
        XCTAssertNil(getResponse.value(forHTTPHeaderField: "Set-Cookie"))
        XCTAssertNil(getResponse.value(forHTTPHeaderField: "Access-Control-Allow-Credentials"))

        let notFound = RecordingGameSchemeTask(missing)
        try WebGameResourceProbe.serve(entry: entry, task: notFound)
        XCTAssertTrue(notFound.finished)
        XCTAssertNil(notFound.failure)
        XCTAssertEqual((notFound.response as? HTTPURLResponse)?.statusCode, 404)

        let posted = RecordingGameSchemeTask(listed, method: "POST")
        try WebGameResourceProbe.serve(entry: entry, task: posted)
        XCTAssertTrue(posted.finished)
        XCTAssertNil(posted.failure)
        let postResponse = try XCTUnwrap(posted.response as? HTTPURLResponse)
        XCTAssertEqual(postResponse.statusCode, 404)
        XCTAssertNil(postResponse.value(forHTTPHeaderField: "Allow"))
        XCTAssertNil(postResponse.value(forHTTPHeaderField: "Set-Cookie"))

        // The host header CSP must actually allow a same-origin fetch.
        let (probe, _) = try await open(entry)
        defer { probe.browser.removeFromSuperview(); probe.close() }
        let fetched = try await awaitPageJS(probe.browser, """
            const r = await fetch('level.json');
            const t = await r.text();
            return r.status + ':' + t;
            """) as? String
        XCTAssertEqual(fetched, #"200:{"ok":true}"#)
        let unlisted = try await awaitPageJS(probe.browser, """
            const r = await fetch('missing.json');
            return String(r.status);
            """) as? String
        XCTAssertEqual(unlisted, "404")
        let postStatus = try await awaitPageJS(probe.browser, """
            const r = await fetch('level.json', {method: 'POST'});
            return String(r.status);
            """) as? String
        XCTAssertEqual(postStatus, "404")
    }

    /// Mosaic H1 / §4.2: host header allows Phaser-style blob images; the
    /// handler follows the serve contract (GET only, 404 otherwise, Range 206,
    /// no cookies, percent-decode once, never treat %2F as a separator).
    /// WKWebView-level: blob image, package JSON/XML/audio/woff fetches, and
    /// blocked API/remote XHR+fetch. Handler unit tests: HEAD/OPTIONS/query/
    /// bare root/game.files.json/unlisted/Range/%2F/spaces/non-ASCII/cookies.
    func testPlatformSpec42ServeContractAndPhaserStyleBlobLoads() async throws {
        let pixel: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
                              0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
                              0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
                              0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
                              0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
                              0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]
        let policy = "default-src 'none'; script-src 'self'; connect-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self'; object-src 'none'"
        let json = Data("{\"ok\":true}".utf8)
        let xml = Data("<font></font>".utf8)
        let ogg = Data("OggS".utf8)
        let woff = Data("wOFF".utf8)
        let audio = Data("RIFF".utf8)
        let spaced = Data("space".utf8)
        let cafe = Data("cafe".utf8)
        let nested = Data("nested".utf8)
        let entry = try install([
            "index.html": Data(HardeningGameFixture.document(policy).utf8),
            "level.json": json,
            "font.xml": xml,
            "sound.ogg": ogg,
            "sound.mp3": Data("ID3".utf8),
            "sound.m4a": Data("ftyp".utf8),
            "sound.wav": audio,
            "ui.woff": woff,
            "pixel.png": Data(pixel),
            "dir/file.png": nested,
            "notes.txt": Data("ok".utf8),
        ], id: "digital.modula.qa-spec-42")
        let url = try WebGameResourceProbe.entryURL(entry: entry)
        let origin = try XCTUnwrap(url.host)
        func pkg(_ path: String) throws -> URL {
            var components = URLComponents()
            components.scheme = url.scheme
            components.host = origin
            components.path = path.hasPrefix("/") ? path : "/" + path
            return try XCTUnwrap(components.url)
        }
        func serve(_ request: URL, method: String = "GET", headers: [String: String] = [:]) throws -> (HTTPURLResponse, Data, Error?) {
            let task = RecordingGameSchemeTask(request, method: method, headers: headers)
            try WebGameResourceProbe.serve(entry: entry, task: task)
            XCTAssertTrue(task.finished, request.absoluteString)
            let response = try XCTUnwrap(task.response as? HTTPURLResponse, request.absoluteString)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Security-Policy"), WebGamePackageServe.headerContentSecurityPolicy)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Cross-Origin-Resource-Policy"), "same-origin")
            XCTAssertEqual(response.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
            XCTAssertNil(response.value(forHTTPHeaderField: "Set-Cookie"))
            XCTAssertNil(response.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
            XCTAssertNil(response.value(forHTTPHeaderField: "Access-Control-Allow-Credentials"))
            XCTAssertNil(response.value(forHTTPHeaderField: "Allow"))
            return (response, task.body, task.failure)
        }

        // Handler unit tests
        let listed = try pkg("level.json")
        let (get, getBody, getErr) = try serve(listed)
        XCTAssertEqual(get.statusCode, 200)
        XCTAssertEqual(getBody, json)
        XCTAssertNil(getErr)
        XCTAssertEqual(get.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let (missing, _, _) = try serve(try pkg("missing.json"))
        XCTAssertEqual(missing.statusCode, 404)

        for method in ["HEAD", "OPTIONS", "POST", "PUT", "DELETE"] {
            let (rejected, _, _) = try serve(listed, method: method)
            XCTAssertEqual(rejected.statusCode, 404, method)
        }

        var root = URLComponents()
        root.scheme = url.scheme
        root.host = origin
        root.path = "/"
        let (bare, _, _) = try serve(try XCTUnwrap(root.url))
        XCTAssertEqual(bare.statusCode, 404)

        let (inventory, _, _) = try serve(try pkg("game.files.json"))
        XCTAssertEqual(inventory.statusCode, 404)

        var queried = URLComponents(url: listed, resolvingAgainstBaseURL: false)
        queried?.query = "cache=1"
        let (query, _, _) = try serve(try XCTUnwrap(queried?.url))
        XCTAssertEqual(query.statusCode, 404)

        // %2F must not be decoded into a path separator.
        let encodedSlash = try XCTUnwrap(URL(string: "modula-game://\(origin)/dir%2Ffile.png"))
        XCTAssertFalse(try WebGameResourceProbe.allows(entry: entry, request: encodedSlash))
        let (slash, _, _) = try serve(encodedSlash)
        XCTAssertEqual(slash.statusCode, 404)
        let (nestedOK, nestedBody, _) = try serve(try pkg("dir/file.png"))
        XCTAssertEqual(nestedOK.statusCode, 200)
        XCTAssertEqual(nestedBody, nested)
        // One percent-decode: %69ndex.html is index.html and must match the manifest.
        let once = try XCTUnwrap(URL(string: "modula-game://\(origin)/%69ndex.html"))
        let (decoded, decodedBody, _) = try serve(once)
        XCTAssertEqual(decoded.statusCode, 200)
        XCTAssertTrue(WebGamePackageServe.isHTML(decoded.value(forHTTPHeaderField: "Content-Type")))
        XCTAssertFalse(decodedBody.isEmpty)

        // Spaces and non-ASCII names percent-decode once and match the manifest
        // exactly. These names are outside WebGamePackage.safe's path alphabet,
        // so they are served through the shared helper the same way the GUBIC
        // player does, against a synthetic inventory.
        let namedOrigin = String(repeating: "a", count: 64)
        func namedURL(_ path: String) throws -> URL {
            var components = URLComponents()
            components.scheme = "modula-game"
            components.host = namedOrigin
            components.path = path.hasPrefix("/") ? path : "/" + path
            return try XCTUnwrap(components.url)
        }
        func serveNamed(_ request: URL) throws -> (HTTPURLResponse, Data) {
            let task = RecordingGameSchemeTask(request)
            WebGamePackageServe.serve(task, scheme: "modula-game", origin: namedOrigin,
                                      files: ["a b.png": spaced, "café.png": cafe], isOpen: true)
            XCTAssertTrue(task.finished, request.absoluteString)
            return (try XCTUnwrap(task.response as? HTTPURLResponse), task.body)
        }
        let (space, spaceBody) = try serveNamed(try namedURL("a b.png"))
        XCTAssertEqual(space.statusCode, 200)
        XCTAssertEqual(spaceBody, spaced)
        XCTAssertEqual(space.value(forHTTPHeaderField: "Cross-Origin-Resource-Policy"), "same-origin")
        let (accent, accentBody) = try serveNamed(try namedURL("café.png"))
        XCTAssertEqual(accent.statusCode, 200)
        XCTAssertEqual(accentBody, cafe)

        // A single Range is 206; multi-range/malformed is 200 full (spec); unsatisfiable is 416.
        let rangeURL = try pkg("pixel.png")
        let (partial, partialBody, _) = try serve(rangeURL, headers: ["Range": "bytes=0-3"])
        XCTAssertEqual(partial.statusCode, 206)
        XCTAssertEqual(partial.value(forHTTPHeaderField: "Content-Range"), "bytes 0-3/70")
        XCTAssertEqual(partialBody, Data(pixel.prefix(4)))
        let (multi, multiBody, _) = try serve(rangeURL, headers: ["Range": "bytes=0-1,2-3"])
        XCTAssertEqual(multi.statusCode, 200)
        XCTAssertEqual(multiBody, Data(pixel))
        let (bad, badBody, _) = try serve(rangeURL, headers: ["Range": "items=0-1"])
        XCTAssertEqual(bad.statusCode, 200)
        XCTAssertEqual(badBody, Data(pixel))
        let (unsat, _, _) = try serve(rangeURL, headers: ["Range": "bytes=1000-1001"])
        XCTAssertEqual(unsat.statusCode, 416)
        XCTAssertEqual(unsat.value(forHTTPHeaderField: "Content-Range"), "bytes */70")
        XCTAssertEqual(unsat.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")

        let (cookie, _, _) = try serve(listed, headers: ["Cookie": "session=secret", "Authorization": "Bearer x"])
        XCTAssertEqual(cookie.statusCode, 200)
        XCTAssertNil(cookie.value(forHTTPHeaderField: "Set-Cookie"))

        // WKWebView-level: package fetches, Phaser blob image, API/remote blocked.
        let (listener, port, connections) = try await loopbackListener()
        defer { listener.cancel() }
        let (probe, _) = try await open(entry)
        defer { probe.browser.removeFromSuperview(); probe.close() }
        let browser = probe.browser

        let loaded = try await awaitPageJS(browser, """
            const rows = await Promise.all([
              fetch('level.json').then(async r => r.status + ':' + await r.text()),
              fetch('font.xml').then(r => r.status + ':' + (r.headers.get('content-type') || '')),
              fetch('sound.ogg').then(r => r.status + ':' + (r.headers.get('content-type') || '')),
              fetch('sound.mp3').then(r => r.status + ':' + (r.headers.get('content-type') || '')),
              fetch('sound.m4a').then(r => r.status + ':' + (r.headers.get('content-type') || '')),
              fetch('sound.wav').then(r => r.status + ':' + (r.headers.get('content-type') || '')),
              fetch('ui.woff').then(r => r.status + ':' + (r.headers.get('content-type') || ''))
            ]);
            return rows.join('|');
            """) as? String
        XCTAssertEqual(loaded, #"200:{"ok":true}|200:application/xml|200:audio/ogg|200:audio/mpeg|200:audio/mp4|200:audio/wav|200:font/woff"#)

        let blobImage = try await awaitPageJS(browser, """
            const r = await fetch('pixel.png');
            const b = await r.blob();
            return await new Promise(resolve => {
              const img = new Image();
              img.onload = () => resolve('ok:' + img.naturalWidth + 'x' + img.naturalHeight);
              img.onerror = () => resolve('img-error');
              img.src = URL.createObjectURL(b);
            });
            """) as? String
        XCTAssertEqual(blobImage, "ok:1x1")

        let before = connections.value
        let blocked = try await awaitPageJS(browser, """
            const probeFetch = async (url, ok, blocked) => {
              try {
                const r = await fetch(url);
                return ok + ':' + r.status;
              } catch (_) {
                return blocked;
              }
            };
            const probeXHR = (url) => new Promise(resolve => {
              const x = new XMLHttpRequest();
              x.onload = () => resolve('ok:' + x.status);
              x.onerror = () => resolve('blocked');
              x.open('GET', url);
              x.send();
            });
            const rows = await Promise.all([
              probeFetch('https://api.modula.digital/v1/health', 'api-ok', 'api-blocked'),
              probeFetch('http://127.0.0.1:\(port.rawValue)/remote', 'remote-ok', 'remote-blocked'),
              probeXHR('https://api.modula.digital/v1/health'),
              probeXHR('http://127.0.0.1:\(port.rawValue)/remote')
            ]);
            return rows.join(',');
            """) as? String
        XCTAssertEqual(blocked, "api-blocked,remote-blocked,blocked,blocked")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(connections.value, before, "a game fetch or XHR reached the loopback listener")
    }

    func testByteRangeEdgesAndUnsatisfiableEmptyFile() throws {
        let payload = Data("abcdefgh".utf8)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: nil, size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-3", size: 8), .partial(0..<4))
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-", size: 8), .partial(0..<8))
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=-3", size: 8), .partial(5..<8))
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=-0", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=5-3", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-999", size: 8), .partial(0..<8))
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=100-101", size: 8), .unsatisfiable)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=100-", size: 8), .unsatisfiable)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=99999999999999999999-", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-99999999999999999999", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=+0-3", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-+3", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=-+3", size: 8), .complete)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-", size: 0), .unsatisfiable)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=-5", size: 0), .unsatisfiable)
        XCTAssertEqual(WebGamePackageServe.byteRange(header: "bytes=0-1", size: 0), .unsatisfiable)

        let origin = String(repeating: "b", count: 64)
        func url(_ path: String) throws -> URL {
            var components = URLComponents()
            components.scheme = "modula-game"
            components.host = origin
            components.path = "/" + path
            return try XCTUnwrap(components.url)
        }
        func serve(_ path: String, range: String?, files: [String: Data]) throws -> (HTTPURLResponse, Data) {
            var headers: [String: String] = [:]
            if let range { headers["Range"] = range }
            let task = RecordingGameSchemeTask(try url(path), headers: headers)
            WebGamePackageServe.serve(task, scheme: "modula-game", origin: origin, files: files, isOpen: true)
            XCTAssertTrue(task.finished, "\(path) \(range ?? "<none>")")
            return (try XCTUnwrap(task.response as? HTTPURLResponse), task.body)
        }
        let files = ["clip.bin": payload, "empty.bin": Data()]

        let suffix = try serve("clip.bin", range: "bytes=-3", files: files)
        XCTAssertEqual(suffix.0.statusCode, 206)
        XCTAssertEqual(suffix.0.value(forHTTPHeaderField: "Content-Range"), "bytes 5-7/8")
        XCTAssertEqual(suffix.0.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(suffix.1, Data("fgh".utf8))

        let openEnd = try serve("clip.bin", range: "bytes=0-", files: files)
        XCTAssertEqual(openEnd.0.statusCode, 206)
        XCTAssertEqual(openEnd.0.value(forHTTPHeaderField: "Content-Range"), "bytes 0-7/8")
        XCTAssertEqual(openEnd.1, payload)

        let minusZero = try serve("clip.bin", range: "bytes=-0", files: files)
        XCTAssertEqual(minusZero.0.statusCode, 200)
        XCTAssertEqual(minusZero.1, payload)

        let inverted = try serve("clip.bin", range: "bytes=5-3", files: files)
        XCTAssertEqual(inverted.0.statusCode, 200)
        XCTAssertEqual(inverted.1, payload)

        let overflow = try serve("clip.bin", range: "bytes=99999999999999999999-", files: files)
        XCTAssertEqual(overflow.0.statusCode, 200)
        XCTAssertEqual(overflow.1, payload)

        let plus = try serve("clip.bin", range: "bytes=+0-3", files: files)
        XCTAssertEqual(plus.0.statusCode, 200)
        XCTAssertEqual(plus.1, payload)

        for range in ["bytes=0-", "bytes=-5", "bytes=0-1"] {
            let empty = try serve("empty.bin", range: range, files: files)
            XCTAssertEqual(empty.0.statusCode, 416, range)
            XCTAssertEqual(empty.0.value(forHTTPHeaderField: "Content-Range"), "bytes */0", range)
            XCTAssertEqual(empty.0.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8", range)
            XCTAssertTrue(empty.1.isEmpty, range)
        }
    }

    func testParsedPackagePolicyRejectsUnsafeAndRemoteSourcesAndAcceptsSamples() throws {
        // The bundled samples' declared policies still pass.
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(HardeningGameFixture.samplePolicy)))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document()))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(
            html: "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'none'\">"))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(
            html: "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self'; connect-src 'none'\">"))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(
            html: "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self'; connect-src 'self'\">"))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(
            "default-src 'none'; script-src 'self'; connect-src 'self'; img-src 'self' data: blob:; font-src 'self'; media-src 'self' blob:")))
        XCTAssertNoThrow(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(
            "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'")))
        let directives = try WebGameDocumentPolicy.parse(HardeningGameFixture.samplePolicy)
        XCTAssertEqual(directives["default-src"], ["'none'"])
        XCTAssertEqual(directives["img-src"], ["'self'", "data:"])

        let strict = HardeningGameFixture.strictPolicy
        let rejected: [String: String] = [
            "unsafe-inline script": "default-src 'none'; script-src 'self' 'unsafe-inline'; connect-src 'none'; object-src 'none'",
            "unsafe-eval script": "default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'none'; object-src 'none'",
            "wasm-unsafe-eval": "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'none'; object-src 'none'",
            "remote script host": "default-src 'none'; script-src 'self' https://evil.example; connect-src 'none'; object-src 'none'",
            "bare script host": "default-src 'none'; script-src 'self' evil.example; connect-src 'none'; object-src 'none'",
            "script scheme": "default-src 'none'; script-src 'self' https:; connect-src 'none'; object-src 'none'",
            "data script": "default-src 'none'; script-src 'self' data:; connect-src 'none'; object-src 'none'",
            "wildcard script": "default-src 'none'; script-src *; connect-src 'none'; object-src 'none'",
            "remote connect": "default-src 'none'; script-src 'self'; connect-src https://api.example; object-src 'none'",
            "wildcard connect": "default-src 'none'; script-src 'self'; connect-src *; object-src 'none'",
            "ws connect": "default-src 'none'; script-src 'self'; connect-src ws:; object-src 'none'",
            "wss connect": "default-src 'none'; script-src 'self'; connect-src wss:; object-src 'none'",
            "connect-src self plus remote": "default-src 'none'; script-src 'self'; connect-src 'self' https://api.example; object-src 'none'",
            "missing default-src": "script-src 'self'; connect-src 'none'; object-src 'none'",
            "permissive default-src": "default-src 'self'; script-src 'self'; connect-src 'none'; object-src 'none'",
            "missing script-src": "default-src 'none'; connect-src 'none'; object-src 'none'",
            "missing connect-src": "default-src 'none'; script-src 'self'; object-src 'none'",
            "object-src not none": "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'self'",
            "duplicate directive": "\(strict); connect-src *",
            "second policy": "\(strict), script-src *",
            "remote image": "\(strict); img-src https://cdn.example",
            "unknown directive": "\(strict); report-uri https://collector.example",
            "unsafe-inline outside style": "\(strict); img-src 'self' 'unsafe-inline'",
            "none mixed": "default-src 'none' 'self'; script-src 'self'; connect-src 'none'; object-src 'none'",
        ]
        for (label, policy) in rejected.sorted(by: { $0.key < $1.key }) {
            XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: HardeningGameFixture.document(policy)), label)
        }
        // The old substring check accepted these; the parsed check does not.
        let substringBypasses: [String: String] = [
            "policy only in a comment": "<!doctype html><html><head><!-- <meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"> --></head><body></body></html>",
            "policy only as text": "<!doctype html><html><head><title>\(strict) Content-Security-Policy</title></head><body></body></html>",
            "policy after a script": "<!doctype html><html><head><script src=\"main.js\"></script><meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"></head></html>",
            "two policies": HardeningGameFixture.document(strict).replacingOccurrences(of: "<title>", with: "<meta http-equiv=\"Content-Security-Policy\" content=\"\(strict)\"><title>"),
            "unsafe-eval beside required tokens": HardeningGameFixture.document("default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'none'; object-src 'none'"),
        ]
        for (label, html) in substringBypasses.sorted(by: { $0.key < $1.key }) {
            XCTAssertThrowsError(try WebGameDocumentPolicy.validate(html: html), label)
        }
        // And the archive parser applies it before any byte reaches WebKit.
        let weak = try HardeningGameFixture.archive(["index.html": Data(HardeningGameFixture.document(
            "default-src 'none'; script-src 'self' https://evil.example; connect-src 'none'; object-src 'none'").utf8)])
        XCTAssertThrowsError(try WebGamePackage(archive: weak, expectedSha256: WebGamePackage.digest(weak)))
        let sample = try HardeningGameFixture.archive(["index.html": Data(HardeningGameFixture.document(HardeningGameFixture.samplePolicy).utf8)])
        XCTAssertNoThrow(try WebGamePackage(archive: sample, expectedSha256: WebGamePackage.digest(sample)))
    }
}

@MainActor
final class MessagingDomainTests: XCTestCase {
    func testQuoteLinesBecomeQuoteBlock() {
        let split = MessageQuoteText.split("> Hey!\n> second\nSounds good")
        XCTAssertEqual(split.quote, "Hey!\nsecond")
        XCTAssertEqual(split.body, "Sounds good")
        XCTAssertEqual(MessageQuoteText.split(">").quote, "")
        XCTAssertEqual(MessageQuoteText.split(">").body, "")
        XCTAssertNil(MessageQuoteText.split("No quote > here").quote)
    }

    func testPreviewTextNeverShowsRawTokens() {
        XCTAssertFalse(MessagePreviewText.plain("> {{sticker:mascot:meteo}}").contains("{{"))
        XCTAssertFalse(MessagePreviewText.plain("> {{sticker:mascot:meteo}}").hasPrefix(">"))
        XCTAssertEqual(MessagePreviewText.plain("> Hey!\nYes"), "Yes")
        XCTAssertEqual(MessagePreviewText.plain(">"), "Reply")
        XCTAssertEqual(MessagePreviewText.plain("https://www.kl-cc.co.uk/menu?x=1"), "🔗 kl-cc.co.uk")
        XCTAssertEqual(MessagePreviewText.plain("Look https://www.kl-cc.co.uk/menu"), "Look kl-cc.co.uk")
        XCTAssertTrue(MessagePreviewText.plain("{{sticker:mascot:pip}}").hasPrefix("Sticker"))
    }

    func testBubbleLinkShowsDomainFirstButOpensFullURL() {
        let attributed = MessageLinkText.attributed("Menu: https://www.kl-cc.co.uk/menu")
        XCTAssertEqual(String(attributed.characters), "Menu: kl-cc.co.uk/menu")
        XCTAssertEqual(attributed.runs.compactMap(\.link).first?.absoluteString, "https://www.kl-cc.co.uk/menu")
    }

    func testFocusLayoutKeepsBarAndMenuOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        // Bubble at the very top: shifted down so the reaction bar fits under the safe area.
        let top = MessageFocusLayout.resolve(bubble: CGRect(x: 0, y: 40, width: 400, height: 60), menuCount: 5, hasBar: true, container: screen, safeTop: 50, safeBottom: 30)
        XCTAssertGreaterThanOrEqual(40 + top.shift - MessageFocusLayout.barHeight - MessageFocusLayout.gap, 58 - 0.5)
        // Bubble at the bottom: shifted up so the menu fits above the home indicator.
        let bottom = MessageFocusLayout.resolve(bubble: CGRect(x: 0, y: 700, width: 400, height: 60), menuCount: 5, hasBar: true, container: screen, safeTop: 50, safeBottom: 30)
        let menuBottom = 700 + bottom.shift + 60 + MessageFocusLayout.gap + 5 * MessageFocusLayout.rowHeight
        XCTAssertLessThanOrEqual(menuBottom, 800 - 30 - 8 + 0.5)
        // A huge message is clipped rather than pushing the menu off screen.
        let huge = MessageFocusLayout.resolve(bubble: CGRect(x: 0, y: 0, width: 400, height: 2000), menuCount: 5, hasBar: true, container: screen, safeTop: 50, safeBottom: 30)
        XCTAssertLessThan(huge.bubbleHeight, 800)
    }

    func testConversationDecodingAndOrdering() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("c-old"),
                    "kind": .string("direct"),
                    "updatedAt": .string("2026-01-01T00:00:00Z"),
                    "unreadCount": .number(0),
                    "participants": .array([
                        .object(["id": .string("u1"), "handle": .string("sophia.chen"), "displayName": .string("Sophia Chen")])
                    ]),
                    "lastMessage": .object(["id": .string("m1"), "body": .string("Hi"), "sentAt": .string("2026-01-01T00:00:00Z")])
                ]),
                .object([
                    "id": .string("c-new"),
                    "kind": .string("direct"),
                    "updatedAt": .string("2026-09-01T00:00:00Z"),
                    "unreadCount": .number(2),
                    "participants": .array([
                        .object(["id": .string("u2"), "handle": .string("marcus"), "displayName": .string("Marcus")])
                    ])
                ])
            ]),
            "nextCursor": .string("cursor-2"),
            "hasMore": .bool(true)
        ])
        let page = MessagingPayloadDecoder.conversationPage(from: payload)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.nextCursor, "cursor-2")
        XCTAssertTrue(page.hasMore)
        let ordered = MessagingOrdering.conversationsNewestFirst(page.items)
        XCTAssertEqual(ordered.first?.id, "c-new")
        XCTAssertEqual(ordered.first?.unreadCount, 2)
        XCTAssertTrue(ordered.first?.isUnread == true)
        XCTAssertFalse(ordered.last?.isUnread == true)
    }

    func testMessageOrderingAndOwnFlag() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("m2"),
                    "body": .string("Second"),
                    "sentAt": .string("2026-09-01T00:02:00Z"),
                    "sender": .object(["id": .string("me"), "displayName": .string("You")])
                ]),
                .object([
                    "id": .string("m1"),
                    "body": .string("First"),
                    "sentAt": .string("2026-09-01T00:01:00Z"),
                    "sender": .object(["id": .string("u1"), "displayName": .string("Sophia")])
                ])
            ])
        ])
        let page = MessagingPayloadDecoder.messagePage(from: payload, conversationID: "c1", viewerID: "me")
        let ordered = MessagingOrdering.messagesChronological(page.items)
        XCTAssertEqual(ordered.map(\.id), ["m1", "m2"])
        XCTAssertFalse(ordered[0].isOwn)
        XCTAssertTrue(ordered[1].isOwn)
    }

    func testPreparedSendDoesNotTouchTheOpenDraftWhenSendingIsUnavailable() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")),
            capabilities: MessagingBackendCapabilities()
        )
        store.drafts["c1"] = "Keep this"
        let sent = await store.sendPrepared(text: "https://modula.digital/post/p1", conversation: "c1")
        XCTAssertFalse(sent)
        XCTAssertEqual(store.drafts["c1"], "Keep this")
        XCTAssertEqual(store.actionError, "Couldn't send message.")
        XCTAssertEqual(MessagingBackendCapabilities.Paths.send(conversationID: "c1"), "/v1/conversations/c1/messages")
    }

    func testOptimisticSendRollbackPreservesDraft() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")),
            capabilities: MessagingBackendCapabilities()
        )
        store.drafts["c1"] = "Keep this"
        await store.send(conversation: "c1", viewer: MessagingFixtures.me)
        XCTAssertEqual(store.drafts["c1"], "Keep this")
        XCTAssertEqual(store.actionError, "Couldn't send message.")
    }

    func testRequestStateRestoreOnFailure() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        #if DEBUG
        store.installDebugRequests([MessagingFixtures.request])
        #endif
        let result = await store.acceptRequest(MessagingFixtures.request)
        XCTAssertNil(result)
        #if DEBUG
        XCTAssertEqual(store.requests.count, 1)
        #endif
    }

    func testDirectConversationMatchesHandleOrIDNeverInbox() {
        XCTAssertEqual(RouteParser.parse("/messages/to/andrei.modula"), .messages(.direct("andrei.modula")))
        XCTAssertNil(RouteParser.parse("/messages/to"))
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        #if DEBUG
        store.installDebugInbox([MessagingFixtures.unreadConversation, MessagingFixtures.readConversation])
        XCTAssertEqual(store.directConversation(with: "sophia.chen")?.id, "convo-sophia")
        XCTAssertEqual(store.directConversation(with: "@Sophia.Chen")?.id, "convo-sophia")
        XCTAssertEqual(store.directConversation(with: MessagingFixtures.unreadConversation.participants[0].id)?.id, "convo-sophia")
        XCTAssertNil(store.directConversation(with: "nobody.here"))
        XCTAssertNil(store.directConversation(with: ""))
        #endif
    }

    func testGeneratedHandlesAreFilteredFromPeoplePickers() {
        XCTAssertTrue(ModulaFixtureFilter.looksGenerated("b14bmsb2xub7n73r"))
        XCTAssertTrue(ModulaFixtureFilter.looksGenerated("macbf7e269"))
        XCTAssertTrue(ModulaFixtureFilter.looksGenerated("p6smrq8pwcc"))
        XCTAssertTrue(ModulaFixtureFilter.looksGenerated("macb17863988517690"))
        XCTAssertTrue(ModulaFixtureFilter.isFixture(name: "x", handle: "vps-checked-mrpmdo4y"))
        XCTAssertFalse(ModulaFixtureFilter.looksGenerated("andrei.modula"))
        XCTAssertFalse(ModulaFixtureFilter.looksGenerated("sam2024"))
        XCTAssertFalse(ModulaFixtureFilter.looksGenerated("builders"))
        XCTAssertFalse(ModulaFixtureFilter.isFixture(name: "Digital Garden", handle: "garden.modula"))
    }

    func testLocalSearchDoesNotClaimServerHistory() {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        XCTAssertTrue(store.searchIsLocalOnly)
        #if DEBUG
        store.installDebugInbox([MessagingFixtures.unreadConversation, MessagingFixtures.readConversation])
        store.conversationQuery = "sophia"
        XCTAssertEqual(store.visibleConversations.map(\.id), ["convo-sophia"])
        #endif
    }

    func testArchiveHideAndFoldersLeaveTheOpenInbox() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        #if DEBUG
        store.resetInboxOrganisationForTesting()
        store.installDebugInbox([MessagingFixtures.unreadConversation, MessagingFixtures.readConversation])
        let sophia = MessagingFixtures.unreadConversation.id
        let marcus = MessagingFixtures.readConversation.id
        store.archiveLocallyForTesting(sophia)
        XCTAssertFalse(store.visibleConversations.contains(where: { $0.id == sophia }))
        XCTAssertTrue(store.visibleConversations.contains(where: { $0.id == marcus }))
        XCTAssertTrue(store.archivedConversations.contains(where: { $0.id == sophia }))
        store.hide(marcus)
        XCTAssertFalse(store.visibleConversations.contains(where: { $0.id == marcus }))
        XCTAssertTrue(store.hiddenConversations.contains(where: { $0.id == marcus }))
        store.unhide(marcus)
        store.setFolder("Work", for: marcus)
        XCTAssertEqual(store.folder(for: marcus), "Work")
        XCTAssertEqual(store.conversations(inFolder: "Work").map(\.id), [marcus])
        store.setMuteUntilForTesting(marcus, date: Date().addingTimeInterval(-30))
        await store.expireTimedMutesIfNeeded()
        XCTAssertNil(store.muteUntilDate(for: marcus))
        store.resetInboxOrganisationForTesting()
        #endif
    }

    func testThreadSearchScopesAndReplyGrouping() {
        let sophia = MessagingFixtures.sophia
        let me = MessagingFixtures.me
        let now = MessagingFixtures.now
        let original = Message(
            id: "m-origin", conversationID: "c1", sender: sophia,
            body: .text("Look at https://modula.digital/photo.jpg and the docs"),
            sentAt: now, delivery: .sent, isOwn: false
        )
        let reply = Message(
            id: "m-reply", conversationID: "c1", sender: me,
            body: .text("Nice catch"),
            sentAt: now.addingTimeInterval(60), delivery: .sent, isOwn: true,
            replyTo: MessageReplyPreview(id: "m-origin", senderName: sophia.displayName, body: "Look at", deleted: false)
        )
        let link = Message(
            id: "m-link", conversationID: "c1", sender: sophia,
            body: .text("Read https://modula.digital/blog"),
            sentAt: now.addingTimeInterval(90), delivery: .sent, isOwn: false
        )
        let items = [original, reply, link]
        XCTAssertTrue(MessageThreadSearchScope.links.matches(link, query: "", starredIDs: [], senderNeedle: nil))
        XCTAssertTrue(MessageThreadSearchScope.from.matches(original, query: "sophia", starredIDs: [], senderNeedle: nil))
        XCTAssertFalse(MessageThreadSearchScope.from.matches(reply, query: "sophia", starredIDs: [], senderNeedle: nil))
        XCTAssertTrue(MessageThreadSearchScope.starred.matches(reply, query: "", starredIDs: ["m-reply"], senderNeedle: nil))
        XCTAssertFalse(MessageThreadSearchScope.starred.matches(original, query: "", starredIDs: ["m-reply"], senderNeedle: nil))
        XCTAssertEqual(MessageReplyGrouping.counts(in: items)["m-origin"], 1)
        XCTAssertEqual(MessageReplyGrouping.replies(to: "m-origin", in: items).map(\.id), ["m-reply"])
    }

    func testRecentTokensRememberOrderAndLastReaction() {
        let suite = "messages.recentTokens.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        MessageRecentTokenStore.remember("🔥", defaults)
        MessageRecentTokenStore.remember("👍", defaults)
        MessageRecentTokenStore.remember("🔥", defaults)
        XCTAssertEqual(MessageRecentTokenStore.load(defaults), ["🔥", "👍"])
        MessageRecentTokenStore.rememberReaction("😂", defaults)
        XCTAssertEqual(MessageRecentTokenStore.lastReaction(defaults), "😂")
        XCTAssertEqual(MessageRecentTokenStore.load(defaults).first, "😂")
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
final class InMailDomainTests: XCTestCase {
    func testSubjectRecipientAndBodyValidation() {
        XCTAssertNotNil(InMailValidation.subject(" "))
        XCTAssertNil(InMailValidation.subject("Partnership idea"))
        XCTAssertNotNil(InMailValidation.subject(String(repeating: "a", count: 181)))
        XCTAssertNotNil(InMailValidation.recipient(""))
        XCTAssertNil(InMailValidation.recipient("sophia.chen"))
        XCTAssertNotNil(InMailValidation.body("   "))
        XCTAssertNil(InMailValidation.body("Hello"))
    }

    func testThreadOrderingAndUnread() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("t1"),
                    "subject": .string("Partnership idea"),
                    "preview": .string("I wanted to ask"),
                    "unread": .bool(true),
                    "updatedAt": .string("2026-09-01T00:00:00Z"),
                    "participants": .array([
                        .object(["id": .string("u1"), "displayName": .string("Sophia Chen"), "handle": .string("sophia.chen")])
                    ])
                ])
            ])
        ])
        let page = InMailPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.items[0].subject, "Partnership idea")
        XCTAssertTrue(page.items[0].unread)
        let messages = InMailPayloadDecoder.messages(
            from: .object([
                "messages": .array([
                    .object([
                        "id": .string("im2"),
                        "body": .string("Reply"),
                        "createdAt": .string("2026-09-01T01:00:00Z"),
                        "sender": .object(["id": .string("me"), "displayName": .string("You")])
                    ]),
                    .object([
                        "id": .string("im1"),
                        "body": .string("Hello"),
                        "createdAt": .string("2026-09-01T00:00:00Z"),
                        "sender": .object(["id": .string("u1"), "displayName": .string("Sophia")])
                    ])
                ])
            ]),
            viewerID: "me"
        )
        let ordered = messages.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(ordered.map(\.id), ["im1", "im2"])
        XCTAssertTrue(ordered[1].isOwn)
    }

    func testDraftPersistsWhenSendUnavailable() async {
        let store = InMailStore(client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")))
        store.draft = InMailDraft(toHandle: "sophia.chen", subject: "Hi", body: "Body")
        let result = await store.sendDraft()
        XCTAssertNil(result)
        XCTAssertEqual(store.draft.body, "Body")
        XCTAssertEqual(store.sendState, .failed)
        XCTAssertEqual(store.sendError, "Couldn't send message.")
    }
}

@MainActor
final class StoryDomainTests: XCTestCase {
    func testGroupingSeenUnseenAndExpiry() {
        let groups = StoryGrouping.groups(from: [StoryFixtures.unseen, StoryFixtures.seen, StoryFixtures.own])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.author.id == MessagingFixtures.sophia.id }?.ring, .unseen)
        XCTAssertEqual(groups.first { $0.author.id == MessagingFixtures.marcus.id }?.ring, .seen)
        XCTAssertEqual(groups.first { $0.isOwn }?.ring, .own)
        XCTAssertNotNil(StoryFixtures.unseen.expiresAt)
    }

    func testProgressPauseResumeAndAdvance() {
        let engine = StoryProgressEngine(durations: [1, 1])
        XCTAssertEqual(engine.tick(0.5), .none)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        engine.pause()
        XCTAssertEqual(engine.tick(0.5), .none)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        engine.resume()
        XCTAssertEqual(engine.tick(0.5), .advanced)
        XCTAssertEqual(engine.index, 1)
        engine.isAppActive = false
        let pausedAt = engine.progress
        XCTAssertEqual(engine.tick(1), .none)
        XCTAssertEqual(engine.progress, pausedAt, accuracy: 0.001)
        engine.isAppActive = true
        XCTAssertEqual(engine.next(), .finished)
    }

    func testStoryRouteDoesNotInventIdentifiers() {
        XCTAssertNil(RouteParser.parse("/stories/ "))
        XCTAssertEqual(RouteParser.parse("/stories/create"), .stories(.create))
        XCTAssertNotEqual(RouteParser.parse("/stories/create"), .stories(.story("create")))
    }

    func testRailDecoderUsesGreenfieldDTO() {
        let value: JSONValue = .object([
            "items": .array([
                .object([
                    "groupId": .string("add:actor-1"),
                    "ownerActorId": .string("actor-1"),
                    "ownerProfileId": .string("profile-1"),
                    "displayName": .string("Andrei"),
                    "handle": .string("modula_orgggg"),
                    "avatarUrl": .string("https://api.modula.digital/v1/media/profiles/a.jpg"),
                    "ringState": .string("owner"),
                    "itemCount": .number(0),
                    "unviewedCount": .number(0),
                    "isOwner": .bool(true)
                ]),
                .object([
                    "groupId": .string("group-2"),
                    "ownerProfileId": .string("profile-2"),
                    "displayName": .string("Sophia"),
                    "handle": .string("sophia"),
                    "ringState": .string("unviewed"),
                    "itemCount": .number(2),
                    "isOwner": .bool(false)
                ])
            ])
        ])
        let groups = StoryPayloadDecoder.rail(from: value)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[0].isComposerPlaceholder)
        XCTAssertEqual(groups[0].ring, .own)
        XCTAssertEqual(groups[1].id, "group-2")
        XCTAssertEqual(groups[1].ring, .unseen)
        XCTAssertEqual(groups[1].author.displayName, "Sophia")
    }

    func testGroupDecoderUsesItemIdsAndMediaUrl() {
        let value: JSONValue = .object([
            "groupId": .string("group-2"),
            "displayName": .string("Sophia"),
            "handle": .string("sophia"),
            "isOwner": .bool(false),
            "items": .array([
                .object([
                    "itemId": .string("item-1"),
                    "mediaKind": .string("image"),
                    "mediaUrl": .string("https://api.modula.digital/v1/media/stories/item-1.jpg"),
                    "caption": .string("Hello"),
                    "viewed": .bool(false),
                    "createdAt": .string("2026-09-20T19:00:00.000Z")
                ])
            ])
        ])
        let group = StoryPayloadDecoder.group(value)
        XCTAssertEqual(group?.id, "group-2")
        XCTAssertEqual(group?.items.first?.id, "item-1")
        XCTAssertEqual(group?.items.first?.kind, .image)
        XCTAssertEqual(group?.items.first?.text, "Hello")
        XCTAssertEqual(group?.items.first?.media?.url?.lastPathComponent, "item-1.jpg")
        XCTAssertFalse(group?.items.first?.seen ?? true)
    }

    /// Prod regression: `GET /v1/stories/rail` returns the owner's real group as a summary
    /// (`itemCount` > 0, no `items`). It must not be mistaken for the "add:" composer tile.
    func testOwnRailSummaryWithItemsIsALiveStoryNotTheComposer() {
        let value: JSONValue = .object(["items": .array([.object([
            "groupId": .string("66ca2bf3-edfc-4c14-9ab6-307401d8ea47"),
            "ownerActorId": .string("actor-1"),
            "ownerProfileId": .string("profile-1"),
            "displayName": .string("Andrei"),
            "handle": .string("modula_orgggg"),
            "ringState": .string("owner"),
            "itemCount": .number(4),
            "unviewedCount": .number(4),
            "expiresAt": .string("2026-10-02T12:43:59.850Z"),
            "isOwner": .bool(true)
        ])])])
        let own = StoryPayloadDecoder.rail(from: value)[0]
        XCTAssertTrue(own.isOwn)
        XCTAssertEqual(own.itemCount, 4)
        XCTAssertTrue(own.hasStories)
        XCTAssertFalse(own.isComposerPlaceholder, "A posted story must open the viewer, not the composer")
        XCTAssertTrue(own.needsHydration)
    }

    func testStoryInsightRemainingUsesExpiryOnly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(StoryInsightFacts.remaining(until: nil, now: now))
        XCTAssertEqual(StoryInsightFacts.remaining(until: now.addingTimeInterval(3 * 3600), now: now), "3 hours remaining")
        XCTAssertEqual(StoryInsightFacts.remaining(until: now.addingTimeInterval(60), now: now), "1 minute remaining")
        XCTAssertEqual(StoryInsightFacts.remaining(until: now.addingTimeInterval(-10), now: now), "This story has expired")
    }

    /// The exact envelope shape `POST /v1/stories` returns (201, `ok/data/meta`, null fields).
    func testCreateResponseEnvelopeDecodesToOwnGroup() throws {
        let body = """
        {"ok":true,"data":{"groupId":"g-1","ownerActorId":"actor-1","ownerProfileId":"profile-1",
        "displayName":"Andrei","handle":"modula_orgggg","avatarUrl":null,"visibility":"public",
        "expiresAt":"2026-10-02T12:43:59.850Z","isOwner":true,"items":[
        {"itemId":"i-1","groupId":"g-1","mediaKind":"image","mediaUrl":"https://api.modula.digital/v1/media/stories/i-1.jpg",
        "caption":null,"status":"ready","durationMs":5000,"viewed":false,"createdAt":"2026-10-01T12:42:32.745Z"},
        {"itemId":"i-2","groupId":"g-1","mediaKind":"image","mediaUrl":"https://api.modula.digital/v1/media/stories/i-2.jpg",
        "caption":"Hi","status":"ready","durationMs":5000,"viewed":false,"createdAt":"2026-10-01T12:43:59.850Z"}]},
        "meta":{"requestId":"req-1","serverTime":"2026-10-01T12:43:59.900Z"}}
        """
        let url = try XCTUnwrap(URL(string: "https://api.modula.digital/v1/stories"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        let value: JSONValue = try GreenfieldClient.decodeEnvelope(Data(body.utf8), response: response, method: "POST", path: "/v1/stories")
        let group = try XCTUnwrap(StoryPayloadDecoder.group(value))
        XCTAssertEqual(group.id, "g-1")
        XCTAssertTrue(group.isOwn)
        XCTAssertEqual(group.items.map(\.id), ["i-1", "i-2"])
        XCTAssertEqual(group.items.first?.media?.url?.host, "api.modula.digital")
        XCTAssertNil(group.items.first?.text)
        XCTAssertFalse(group.isComposerPlaceholder)
        XCTAssertFalse(group.needsHydration)
    }

    /// After Share the store holds the full group; the follow-up rail refresh must keep it.
    func testRailRefreshKeepsPublishedItemsAndRehydratesWhenCountGrows() {
        let me = ConversationParticipant(id: "profile-1", handle: "me", displayName: "Me", avatarURL: nil)
        let item = StoryItem(id: "i-1", author: me, createdAt: Date(), expiresAt: nil, kind: .image, media: nil,
                             text: nil, background: nil, seen: false, isOwn: true, viewerCount: nil)
        let published = StoryGroup(id: "g-1", author: me, items: [item], isOwn: true, reportedRing: .own, itemCount: 1)
        let summary = StoryGroup(id: "g-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 1)

        let merged = StoryStore.merge(rail: [summary], previous: [published])
        XCTAssertEqual(merged.first?.items.map(\.id), ["i-1"])
        XCTAssertFalse(merged.first?.isComposerPlaceholder ?? true)
        XCTAssertFalse(merged.first?.needsHydration ?? true)

        var grown = summary
        grown.itemCount = 2
        let refreshed = StoryStore.merge(rail: [grown], previous: [published])
        XCTAssertTrue(refreshed.first?.items.isEmpty ?? false, "Stale items are dropped when the rail reports more")
        XCTAssertTrue(refreshed.first?.needsHydration ?? false)
        XCTAssertFalse(refreshed.first?.isComposerPlaceholder ?? true)

        let placeholder = StoryGroup(id: "add:actor-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 0)
        XCTAssertTrue(StoryStore.merge(rail: [placeholder], previous: [published]).first?.isComposerPlaceholder ?? false)
    }
}

@MainActor
final class ReelDomainTests: XCTestCase {
    func testCanonicalVideoPostPowersReelPlaybackAndEngagement() throws {
        let payload: JSONValue = .object(["post": .object([
            "id": .string("video-post"), "createdAt": .string("2026-09-30T12:00:00Z"),
            "author": .object(["id": .string("author"), "handle": .string("author"), "displayName": .string("Author")]),
            "kind": .string("media"), "text": .string("A real video #modula"), "saved": .bool(true),
            "content": .array([.object([
                "id": .string("block"), "type": .string("video"), "order": .number(0),
                "attachment": .object([
                    "id": .string("attachment"), "kind": .string("video"), "status": .string("ready"),
                    "mimeType": .string("video/mp4"), "filename": .string("video.mp4"),
                    "originalURL": .string("https://api.modula.digital/v1/attachments/attachment/content"),
                    "duration": .number(12)
                ])
            ])])
        ])])
        let reel = try XCTUnwrap(ReelPayloadDecoder.reel(payload))
        XCTAssertEqual(reel.postID, "video-post")
        XCTAssertEqual(reel.attachment?.id, "attachment")
        XCTAssertEqual(reel.attachment?.mimeType, "video/mp4")
        XCTAssertTrue(reel.media?.canPlayVideo == true)
        XCTAssertTrue(reel.asSocialPost().saved)
        XCTAssertEqual(reel.asSocialPost().media.first?.duration, 12)
    }

    func testSeedDecodingWithoutFakeVideo() {
        let payload: JSONValue = .object([
            "reels": .array([
                .object([
                    "id": .string("reel-1"),
                    "author": .string("Sophia"),
                    "caption": .string("Hello"),
                    "colour": .string("#369CAA"),
                    "liked": .bool(true),
                    "likeCount": .number(4),
                    "replyCount": .number(1)
                ])
            ])
        ])
        let page = ReelPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].caption, "Hello")
        XCTAssertNil(page.items[0].media?.url)
        XCTAssertNil(page.items[0].audio)
        XCTAssertTrue(page.items[0].engagement.liked)
        let post = page.items[0].asSocialPost()
        XCTAssertEqual(post.id, "reel-1")
        XCTAssertEqual(post.likeCount, 4)
    }

    func testActivePlaybackOwnershipAndRestoration() {
        let store = ReelStore(client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")))
        #if DEBUG
        store.installDebugReels([
            ReelFixtures.preview,
            Reel(
                id: "reel-2",
                postID: "post-2",
                creator: SocialAuthor(id: "m", handle: "marcus", displayName: "Marcus", avatarURL: nil),
                media: nil,
                caption: "Two",
                audio: nil,
                posterColor: "#000000",
                engagement: PostEngagement(
                    liked: false, saved: false, reposted: false, viewerReaction: nil,
                    likeCount: 0, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0
                ),
                createdAt: Date()
            )
        ])
        XCTAssertEqual(store.activeID, "reel-preview")
        store.activate("reel-2")
        XCTAssertEqual(store.activeID, "reel-2")
        XCTAssertEqual(store.restoredID, "reel-2")
        XCTAssertEqual(store.index(of: "reel-2"), 1)
        #endif
        XCTAssertTrue(ReelBackendCapabilities.production.seedList)
        XCTAssertTrue(ReelBackendCapabilities.production.videoPlayback)
        XCTAssertFalse(ReelBackendCapabilities.production.audioAttribution)
    }

    func testDiscoverDashboardDecodesReelsWithoutFabricatingFeed() {
        let payload: JSONValue = .object([
            "suggestedProfiles": .array([]),
            "trendingTopics": .array([]),
            "featuredModules": .array([]),
            "media": .array([]),
            "reels": .array([
                .object(["id": .string("r1"), "caption": .string("Seed"), "colour": .string("#111")])
            ])
        ])
        let dash = DiscoverPayloadDecoder.dashboard(from: payload)
        XCTAssertEqual(dash.reels.count, 1)
        XCTAssertEqual(dash.reels[0].id, "r1")
    }
}

final class ProfileCustomizationTests: XCTestCase {
    func testHeadlineLanguagesAndAccentDecode() {
        let payload: JSONValue = .object([
            "id": .string("p1"),
            "handle": .string("ada"),
            "displayName": .string("Ada"),
            "bio": .string("Notes"),
            "headline": .string("Founder of Modula"),
            "languages": .array([.string("English"), .string("Romanian")]),
            "presentation": .object(["accent": .string("violet")]),
            "location": .object(["label": .string("United Kingdom"), "visibility": .string("public")]),
            "email": .string("hidden@example.com"),
            "links": .array([
                .object([
                    "id": .string("l1"),
                    "label": .string("Site"),
                    "url": .string("https://modula.digital"),
                    "visibility": .string("public")
                ]),
                .object([
                    "id": .string("l2"),
                    "label": .string("Private"),
                    "url": .string("https://secret.example"),
                    "visibility": .string("private")
                ])
            ])
        ])
        let profile = ProfilePayloadDecoder.profile(from: payload)
        XCTAssertEqual(profile?.headline, "Founder of Modula")
        XCTAssertEqual(profile?.languages, ["English", "Romanian"])
        XCTAssertEqual(profile?.presentation.accent, .violet)
        XCTAssertTrue(ProfileFieldPrivacy.blockedKeys.contains("email"))
        let visitor = profile?.visitorVisible
        XCTAssertEqual(visitor?.publicLinks.count, 1)
        XCTAssertFalse(visitor?.links.contains(where: { $0.visibility == .private }) ?? true)
    }

    func testEditDraftIncludesPresentationWithoutClaimingWrites() {
        let profile = ModulaProfile(
            id: "p1",
            handle: "ada",
            displayName: "Ada",
            kind: "person",
            avatarURL: nil,
            coverURL: nil,
            coverColour: nil,
            bio: "Notes",
            headline: "Founder of Modula",
            pronouns: nil,
            location: nil,
            website: nil,
            languages: ["English"],
            presentation: ProfilePresentation(accent: .violet, featuredModuleIDs: ["digital.modula.vault-notes"], featuredLinkIDs: []),
            coverFocalPoint: CoverFocalPoint(x: 0.4, y: 0.6),
            followerCount: 0,
            followingCount: 0,
            moduleCount: 0,
            postCount: 0,
            joinedAt: nil,
            focusStatus: nil,
            identityClaims: [],
            links: [],
            featuredModuleIds: ["digital.modula.vault-notes"],
            isFollowing: false,
            followsViewer: false,
            version: 3,
            visibility: .public
        )
        let draft = ProfileEditDraft.from(profile)
        XCTAssertEqual(draft.headline, "Founder of Modula")
        XCTAssertEqual(draft.accent, .violet)
        XCTAssertEqual(draft.featuredModuleIDs, ["digital.modula.vault-notes"])
        XCTAssertFalse(ProfileCustomizationCapabilities.production.accentWritable)
        XCTAssertFalse(ProfileCustomizationCapabilities.production.featuredModulesWritable)
    }

    func testAppAccentAndProfileAccentRemainDistinct() {
        XCTAssertEqual(AppearanceStore.Accent.violet.hex, ProfileAccent.violet.hex)
        XCTAssertEqual(ProfileAccent.violet.title, "Violet")
    }
}

final class MediaPipelineTests: XCTestCase {
    func testMediaResourceDecoding() {
        let value: JSONValue = .object([
            "id": .string("m1"),
            "kind": .string("video"),
            "url": .string("https://cdn.example/a.mp4"),
            "posterUrl": .string("https://cdn.example/a.jpg"),
            "duration": .number(12),
            "width": .number(1080),
            "height": .number(1920)
        ])
        let media = MediaPayloadDecoder.resource(from: value, fallbackID: "m1")
        XCTAssertEqual(media?.kind, .video)
        XCTAssertTrue(media?.canPlayVideo == true)
        XCTAssertEqual(media?.duration, 12)
        XCTAssertEqual(media?.dimensions?.width, 1080)
    }
}

final class MessagingCapabilityHonestyTests: XCTestCase {
    func testProductionCapabilitiesMatchLiveVPSRoutes() {
        // Live since backend migration 075_greenfield_messaging.
        XCTAssertTrue(MessagingBackendCapabilities.production.listConversations)
        XCTAssertTrue(MessagingBackendCapabilities.production.send)
        XCTAssertTrue(MessagingBackendCapabilities.production.messageRequests)
        XCTAssertTrue(MessagingBackendCapabilities.production.readReceipts)
        XCTAssertTrue(InMailBackendCapabilities.production.list)
        XCTAssertTrue(InMailBackendCapabilities.production.reply)
        // Still not implemented server-side.
        XCTAssertFalse(MessagingBackendCapabilities.production.realtime)
        XCTAssertFalse(MessagingBackendCapabilities.production.attachments)
        XCTAssertFalse(MessagingBackendCapabilities.production.typing)
        // Migration 089 is not on production yet — v3 flags stay off until probeV3 succeeds.
        XCTAssertFalse(MessagingBackendCapabilities.production.groups)
        XCTAssertFalse(MessagingBackendCapabilities.production.mentions)
        XCTAssertFalse(MessagingBackendCapabilities.production.voiceNotes)
        XCTAssertFalse(MessagingBackendCapabilities.production.photoVideo)
        XCTAssertFalse(MessagingBackendCapabilities.production.reactionDetails)
        XCTAssertFalse(MessagingBackendCapabilities.production.groupReadReceipts)
        XCTAssertFalse(MessagingBackendCapabilities.production.historySearch)
        XCTAssertFalse(MessagingBackendCapabilities.production.presence)
        XCTAssertFalse(MessagingBackendCapabilities.production.privacyControls)
        XCTAssertFalse(MessagingBackendCapabilities.production.idempotentSend)
        XCTAssertFalse(MessagingBackendCapabilities.production.notificationReply)
        XCTAssertFalse(MessagingBackendCapabilities.production.notificationMarkRead)
        XCTAssertFalse(InMailBackendCapabilities.production.privacySettings)
        XCTAssertFalse(InMailBackendCapabilities.production.serverSearch)
        XCTAssertTrue(StoryBackendCapabilities.production.list)
        XCTAssertTrue(StoryBackendCapabilities.production.create)
        XCTAssertTrue(ReelBackendCapabilities.production.seedList)
        XCTAssertFalse(ReelBackendCapabilities.production.rankedFeed)
    }
}

// MARK: - Story upload budget and non-JSON HTTP errors

private final class StubHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var contentType = "application/json"
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GreenfieldNonJSONErrorTests: XCTestCase {
    private let nginx413 = Data("""
    <html>
    <head><title>413 Request Entity Too Large</title></head>
    <body>
    <center><h1>413 Request Entity Too Large</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>
    """.utf8)

    private func response(_ status: Int, type: String = "text/html; charset=utf-8") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://native-n1.modula.digital/v1/stories")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    }

    func testNginxHTML413MapsToPayloadTooLarge() {
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(nginx413, response: response(413), method: "POST", path: "/v1/stories") as JSONValue
        ) { error in
            XCTAssertEqual(error as? APIError, .rejected(413, "PAYLOAD_TOO_LARGE"))
            XCTAssertEqual((error as? APIError)?.userFacingMessage, "That file is too large to upload. Try a smaller photo.")
        }
    }

    func testHTML5xxMapsToServerUnavailable() {
        for status in [500, 502, 503, 504] {
            XCTAssertThrowsError(
                try GreenfieldClient.decodeEnvelope(Data("<html>Bad Gateway</html>".utf8), response: response(status),
                                                    method: "GET", path: "/v1/stories/rail") as JSONValue
            ) { error in
                XCTAssertEqual(error as? APIError, .rejected(status, "SERVER_UNAVAILABLE"))
                XCTAssertEqual((error as? APIError)?.userFacingMessage, "Modula is having trouble right now. Try again in a moment.")
            }
        }
    }

    func testNonJSON429AndOtherStatuses() {
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 429), .rejected(429, "RATE_LIMITED"))
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 200), .invalidResponse)
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 404), .invalidResponse)
    }

    func testJSONEnvelopeErrorsKeepServerCode() {
        let body = Data(#"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"x"}}"#.utf8)
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(body, response: response(400, type: "application/json"),
                                                method: "POST", path: "/v1/stories") as JSONValue
        ) { error in
            XCTAssertEqual(error as? APIError, .rejected(400, "VALIDATION_FAILED"))
        }
        let json5xx = Data(#"{"ok":false,"error":{"code":"SERVER_ERROR"}}"#.utf8)
        XCTAssertEqual(
            APIError.rejected(500, "SERVER_ERROR").userFacingMessage,
            "Modula is having trouble right now. Try again in a moment."
        )
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(json5xx, response: response(500, type: "application/json"),
                                                method: "POST", path: "/v1/stories") as JSONValue
        )
    }

    func testClientSurfacesProxy413AsAPIError() async {
        StubHTTPProtocol.status = 413
        StubHTTPProtocol.contentType = "text/html"
        StubHTTPProtocol.body = nginx413
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTPProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://stub.modula.invalid"), transport: URLSession(configuration: configuration))
        do {
            _ = try await client.publicJSON("POST", path: "/v1/stories", body: .object([:]))
            XCTFail("Expected a 413 rejection")
        } catch {
            XCTAssertEqual(error as? APIError, .rejected(413, "PAYLOAD_TOO_LARGE"))
        }
    }
}

final class StoryUploadBudgetTests: XCTestCase {
    func testBudgetDerivesFromSingleBodyConstantUnderServerLimit() {
        XCTAssertEqual(StoryUploadBudget.maximumBodyBytes, 20_000_000)
        XCTAssertLessThan(StoryUploadBudget.maximumBodyBytes, 25 * 1_048_576, "server JSON/edge body limit")
        let budget = StoryUploadBudget.imageByteBudget(captionByteCount: 0)
        XCTAssertGreaterThan(budget, 14_000_000)
        XCTAssertLessThan(Double(budget) * 4 / 3 * 1.02, Double(StoryUploadBudget.maximumBodyBytes))
        XCTAssertLessThan(StoryUploadBudget.imageByteBudget(captionByteCount: 2_000), budget)
        XCTAssertEqual(StoryUploadBudget.targetLongEdge, 3072)
        XCTAssertEqual(StoryUploadBudget.minimumLongEdge, 3072)
        XCTAssertEqual(StoryUploadBudget.preferredQuality, 0.9)
        XCTAssertEqual(StoryUploadBudget.requestTimeout, 120)
    }

    func testLargePreparedPhotoKeepsFullScreenResolutionWithinBudget() async throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG())
        let prepared = try MediaPreparation.jpegStrippingMetadataSync(
            source, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
        )
        XCTAssertEqual(max(prepared.width, prepared.height), 3072)
        XCTAssertGreaterThan(prepared.data.count, 1_048_576, "fixture must exceed the old 1 MiB proxy limit")

        let body = try await StoryBackendRepository.uploadableBody(image: prepared, caption: "Golden hour", visibility: "public")
        let encoded = try JSONEncoder().encode(body)
        XCTAssertLessThanOrEqual(encoded.count, StoryUploadBudget.maximumBodyBytes)
        XCTAssertEqual(body["contentType"]?.string, "image/jpeg")
        XCTAssertEqual(body["caption"]?.string, "Golden hour")
        let data = try XCTUnwrap(body["base64"]?.string.flatMap { Data(base64Encoded: $0) })
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(max(image.width, image.height), 3072, "full-screen long edge is kept")
        XCTAssertEqual(data, prepared.data, "q0.9 3072px fits the budget, so it is sent unchanged")
        XCTAssertEqual(body["width"]?.number, Double(image.width))
        XCTAssertEqual(body["height"]?.number, Double(image.height))
        XCTAssertNil((CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])?[kCGImagePropertyGPSDictionary])
        print("story-fit prepared=\(prepared.data.count)B \(prepared.width)x\(prepared.height) sent=\(data.count)B \(image.width)x\(image.height) body=\(encoded.count)B")
    }

    func testQualityStepsDownBeforeResolution() throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG())
        let full = try MediaPreparation.jpegFittingSync(source, maxBytes: .max)
        XCTAssertEqual(max(full.width, full.height), 3072)
        // A budget just under the q0.9 size must be met at 3072px by lowering quality.
        let fitted = try MediaPreparation.jpegFittingSync(source, maxBytes: full.data.count - 1)
        XCTAssertEqual(max(fitted.width, fitted.height), 3072)
        XCTAssertLessThan(fitted.data.count, full.data.count)
        // Only when 3072px at the lowest quality can't fit does resolution drop.
        let squeezed = try MediaPreparation.jpegFittingSync(source, maxBytes: 1_500_000)
        XCTAssertLessThan(max(squeezed.width, squeezed.height), 3072)
        XCTAssertLessThanOrEqual(squeezed.data.count, 1_500_000)
    }

    func testSmallPhotoIsSentUnchanged() async throws {
        let small = try MediaPreparation.jpegStrippingMetadataSync(
            try XCTUnwrap(StoryUITestPhoto.detailedJPEG(width: 200, height: 300)), maxPixel: 3072, quality: 0.9
        )
        let body = try await StoryBackendRepository.uploadableBody(image: small, caption: "  ", visibility: "followers")
        XCTAssertEqual(body["base64"]?.string, small.data.base64EncodedString())
        XCTAssertNil(body["caption"])
        XCTAssertEqual(body["visibility"]?.string, "followers")
    }

    func testFittingReportsImpossibleBudget() throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG(width: 1200, height: 1600))
        XCTAssertThrowsError(try MediaPreparation.jpegFittingSync(source, maxBytes: 2_000)) { error in
            XCTAssertEqual(error as? MediaPreparationError, .exceedsByteBudget)
        }
        let fitted = try MediaPreparation.jpegFittingSync(source, maxBytes: 1_500_000)
        XCTAssertLessThanOrEqual(fitted.data.count, 1_500_000)
        XCTAssertEqual(max(fitted.width, fitted.height), 1600, "never upscales")
    }
}

// MARK: - Session recovery (prod: POST /v1/stories → 401 after the session was revoked)

private final class SessionRouterProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var log: [String] = []
    nonisolated(unsafe) static var refreshTokens: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.log.append("\(request.httpMethod ?? "GET") \(path) \(request.value(forHTTPHeaderField: "Authorization") ?? "-")")
        if path == "/v1/sessions/refresh", let token = Self.bodyString(request, key: "refreshToken") {
            Self.refreshTokens.append(token)
        }
        let (status, body) = Self.handler?(request) ?? (500, "{}")
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func bodyString(_ request: URLRequest, key: String) -> String? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return object?[key] as? String
    }
}

final class GreenfieldSessionRecoveryTests: XCTestCase {
    private static func tokens(_ n: Int, accessMinutes: Double = 15) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let access = f.string(from: Date().addingTimeInterval(accessMinutes * 60))
        let refresh = f.string(from: Date().addingTimeInterval(30 * 86_400))
        return #"{"ok":true,"data":{"accessToken":"access-\#(n)","refreshToken":"refresh-\#(n)","sessionId":"s","accessExpiresAt":"\#(access)","refreshExpiresAt":"\#(refresh)"}}"#
    }
    private static let me = #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#
    private static let unauthorized = #"{"ok":false,"error":{"code":"UNAUTHENTICATED"}}"#

    private func makeClient(baseURL: URL? = nil) -> GreenfieldClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        SessionRouterProtocol.log = []
        SessionRouterProtocol.refreshTokens = []
        return GreenfieldClient(baseURL: baseURL ?? URL(string: "https://session-test-\(UUID().uuidString.prefix(8)).modula.test")!,
                                transport: URLSession(configuration: config))
    }

    override func tearDown() {
        SessionRouterProtocol.handler = nil
        SessionRouterProtocol.refreshTokens = []
        super.tearDown()
    }

    func testRejectedAccessTokenRefreshesOnceAndRetries() async throws {
        let client = makeClient()
        SessionRouterProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("POST", "/v1/sessions/refresh"): return (200, Self.tokens(2))
            case ("POST", "/v1/stories"):
                return auth == "Bearer access-2" ? (201, #"{"ok":true,"data":{"groupId":"g"}}"#) : (401, Self.unauthorized)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let value = try await client.authenticatedJSON("POST", path: "/v1/stories", body: .object([:]))
        XCTAssertEqual(value["groupId"]?.string, "g")
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 1)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testRevokedSessionSignsOutAndNotifiesInsteadOfLingering() async throws {
        let client = makeClient()
        let notified = expectation(description: "session invalidated")
        await client.setSessionInvalidationHandler { notified.fulfill() }
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            default: return (401, Self.unauthorized) // revoked: refresh is rejected too
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        do {
            _ = try await client.authenticatedJSON("POST", path: "/v1/stories", body: .object([:]))
            XCTFail("expected unauthenticated")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthenticated)
        }
        await fulfillment(of: [notified], timeout: 2)
        let hasSession = await client.hasSession()
        XCTAssertFalse(hasSession)
    }

    func testOfflineRefreshKeepsTheSession() async throws {
        let client = makeClient()
        var offline = false
        SessionRouterProtocol.handler = { request in
            if offline { return (0, "") }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1, accessMinutes: 0))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        offline = true
        do {
            _ = try await client.authenticatedJSON("GET", path: "/v1/stories/rail")
            XCTFail("expected a network error")
        } catch {
            XCTAssertFalse(GreenfieldClient.refreshFailureEndsSession(error))
        }
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "Being offline while the access token expires must not sign the user out")
    }

    func testColdOfflineRestoreUsesOnlyBoundCachedAccountAndRevocationStillEndsSession() async throws {
        let origin = URL(string: "https://offline-\(UUID().uuidString.prefix(8)).modula.test")!
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            default: return (404, "{}")
            }
        }
        _ = try await makeClient(baseURL: origin).signIn(email: "a@b.c", password: "pw")
        SessionRouterProtocol.handler = { _ in (0, "") }
        let offline = makeClient(baseURL: origin)
        let restored = try await offline.restore()
        XCTAssertEqual(restored?.accountId, "acct-1")
        let offlineSession = await offline.hasSession()
        XCTAssertTrue(offlineSession)

        SessionRouterProtocol.handler = { _ in (401, Self.unauthorized) }
        let revoked = makeClient(baseURL: origin)
        do {
            _ = try await revoked.restore()
            XCTFail("A server rejection must not use the offline identity")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthenticated)
        }
        let revokedSession = await revoked.hasSession()
        XCTAssertFalse(revokedSession)
    }

    func testConcurrent401sShareOneRefreshAndNeverReplayTheToken() async throws {
        let client = makeClient()
        SessionRouterProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("POST", "/v1/sessions/refresh"): return (200, Self.tokens(2))
            case ("GET", "/v1/stories/rail"):
                return auth == "Bearer access-2" ? (200, #"{"ok":true,"data":{"items":[]}}"#) : (401, Self.unauthorized)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        SessionRouterProtocol.log = []
        SessionRouterProtocol.refreshTokens = []
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...8 {
                group.addTask {
                    _ = try await client.authenticatedJSON("GET", path: "/v1/stories/rail")
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 1)
        XCTAssertEqual(SessionRouterProtocol.refreshTokens, ["refresh-1"], "the same refresh token must be presented only once")
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testRefreshReuse401SignsOutOnceWithNoRetryLoop() async throws {
        let client = makeClient()
        let reuse = #"{"ok":false,"error":{"code":"UNAUTHENTICATED","message":"Refresh token reuse detected","retryable":false}}"#
        let notified = expectation(description: "session invalidated once")
        notified.expectedFulfillmentCount = 1
        notified.assertForOverFulfill = true
        await client.setSessionInvalidationHandler { notified.fulfill() }
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("POST", "/v1/sessions/refresh"): return (401, reuse)
            default: return (401, Self.unauthorized)
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        SessionRouterProtocol.log = []
        SessionRouterProtocol.refreshTokens = []
        await withTaskGroup(of: Void.self) { group in
            for _ in 1...8 {
                group.addTask {
                    do {
                        _ = try await client.authenticatedJSON("GET", path: "/v1/stories/rail")
                        XCTFail("expected the session to end")
                    } catch {
                        XCTAssertEqual(error as? APIError, .unauthenticated)
                    }
                }
            }
        }
        await fulfillment(of: [notified], timeout: 2)
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 1)
        XCTAssertEqual(SessionRouterProtocol.refreshTokens, ["refresh-1"])
        let hasSession = await client.hasSession()
        XCTAssertFalse(hasSession)
        // A later call must not start another refresh.
        SessionRouterProtocol.log = []
        do { _ = try await client.authenticatedJSON("GET", path: "/v1/stories/rail") } catch { }
        XCTAssertTrue(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.isEmpty)
    }

    func testStepUpRequired401DoesNotRefreshOrSignOut() async throws {
        let client = makeClient()
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("DELETE", let path) where path.hasPrefix("/v1/modules/"):
                return (401, #"{"ok":false,"error":{"code":"STEP_UP_REQUIRED"}}"#)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        SessionRouterProtocol.log = []
        do {
            _ = try await client.authenticatedJSON("DELETE", path: "/v1/modules/modula.example/install", body: .object(["choice": .string("deleteData")]))
            XCTFail("expected STEP_UP_REQUIRED")
        } catch let api as APIError {
            XCTAssertTrue(api.requiresStepUp)
            XCTAssertEqual(api.code, "STEP_UP_REQUIRED")
        }
        XCTAssertTrue(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.isEmpty)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "step-up must not sign the session out")
    }

    func testRevokeSession404IsTreatedAsAlreadyGone() async throws {
        let client = makeClient()
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("DELETE", "/v1/sessions/sess-missing"):
                return (404, #"{"ok":false,"error":{"code":"NOT_FOUND","message":"Session not found"}}"#)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        try await client.revokeSession(id: "sess-missing")
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "a missing other session must not sign this one out")
    }
}


// MARK: - Home pagination vs refresh race

private final class DelayedFeedProtocol: URLProtocol, @unchecked Sendable {
    /// cursor (or "first") → (delay seconds, body)
    nonisolated(unsafe) static var responses: [String: (Double, String)] = [:]
    /// cursor → HTTP status (default 200).
    nonisolated(unsafe) static var statuses: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let key = items.first(where: { $0.name == "cursor" })?.value ?? "first"
        let (delay, body) = Self.responses[key] ?? (0, #"{"ok":true,"data":{"items":[]}}"#)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.statuses[key] ?? 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class HomePaginationRaceTests: XCTestCase {
    private static func page(_ ids: [String], cursor: String?) -> String {
        let posts = ids.map { #"{"id":"\#($0)","createdAt":"2026-10-01T12:00:00.000Z","kind":"text","text":"\#($0)","author":{"id":"a","handle":"a","displayName":"A"}}"# }
        let next = cursor.map { #","nextCursor":"\#($0)","hasMore":true"# } ?? #","hasMore":false"#
        return #"{"ok":true,"data":{"items":[\#(posts.joined(separator: ","))]\#(next)}}"#
    }

    func testRefreshDuringLoadMoreKeepsTheRefreshedFeed() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedFeedProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://home-race.modula.test")!, transport: URLSession(configuration: config))
        let posts = PostStateStore()
        let store = HomeStore(client: client, posts: posts, postActions: PostActionController(client: client, state: posts))

        DelayedFeedProtocol.responses = ["first": (0, Self.page(["old-1", "old-2"], cursor: "c1"))]
        await store.refresh(.forYou, signedIn: false)
        XCTAssertEqual(store.state(for: .forYou).items.map(\.id), ["old-1", "old-2"])

        DelayedFeedProtocol.responses = [
            "c1": (0.6, Self.page(["old-3"], cursor: "c2")),
            "first": (0, Self.page(["new-1"], cursor: "n1"))
        ]
        let more = Task { await store.loadMore(.forYou) }
        try await Task.sleep(for: .milliseconds(100))
        await store.refresh(.forYou, signedIn: false)
        await more.value

        let state = store.state(for: .forYou)
        XCTAssertEqual(state.items.map(\.id), ["new-1"], "A stale next page must not overwrite the refreshed feed")
        XCTAssertEqual(state.nextCursor, "n1")
        XCTAssertEqual(state.loadState, .loaded)
    }

    func testFailedNextPageCanBeRetried() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedFeedProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://home-retry.modula.test")!, transport: URLSession(configuration: config))
        let posts = PostStateStore()
        let store = HomeStore(client: client, posts: posts, postActions: PostActionController(client: client, state: posts))
        defer { DelayedFeedProtocol.statuses = [:] }

        DelayedFeedProtocol.responses = [
            "first": (0, Self.page(["p-1", "p-2"], cursor: "c1")),
            "c1": (0, #"{"ok":false,"error":{"code":"internal","message":"boom"}}"#)
        ]
        DelayedFeedProtocol.statuses = ["c1": 500]
        await store.refresh(.forYou, signedIn: false)
        await store.loadMore(.forYou)
        var state = store.state(for: .forYou)
        XCTAssertNotNil(state.loadMoreError, "a failed page must surface a retryable footer")
        XCTAssertEqual(state.nextCursor, "c1", "the cursor is kept so retry asks for the same page")
        XCTAssertEqual(state.loadState, .loaded)

        DelayedFeedProtocol.statuses = [:]
        DelayedFeedProtocol.responses["c1"] = (0, Self.page(["p-3"], cursor: nil))
        await store.loadMore(.forYou)
        state = store.state(for: .forYou)
        XCTAssertNil(state.loadMoreError)
        XCTAssertEqual(state.items.map(\.id), ["p-1", "p-2", "p-3"])
        XCTAssertFalse(state.hasMore)
    }
}

@MainActor
final class ProductHubInstalledStateTests: XCTestCase {
    func testSigningOutClearsThePreviousAccountsInstalledModules() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://hub-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct","primaryHandle":"me","status":"active"}}"#)
            case ("GET", "/v1/registry/products"): return (200, #"{"ok":true,"data":{"items":[]}}"#)
            case ("GET", "/v1/modules/installed"): return (200, #"{"ok":true,"data":{"items":[{"moduleId":"digital.modula.vault-notes"}]}}"#)
            case ("DELETE", "/v1/sessions/current"): return (200, #"{"ok":true,"data":{"revoked":true}}"#)
            default: return (404, "{}")
            }
        }
        defer { SessionRouterProtocol.handler = nil }
        let store = ProductHubStore(client: client)
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        await store.load()
        XCTAssertEqual(store.installedIDs, ["digital.modula.vault-notes"])
        try await client.signOut()
        await store.load()
        XCTAssertTrue(store.installedIDs.isEmpty, "Signed out must not show another account's modules as installed")
    }
}

final class ModuleHostAvailabilityTests: XCTestCase {
    private func manifest(_ id: String, runtime: String = "react-native", bridge: String = "0.1.0") throws -> ModuleManifest {
        let json = #"{"id":"\#(id)","name":"Vault Notes","version":"1.0.0","runtime":"\#(runtime)","entry":"vault","permissions":[],"minHostVersion":"0.1.0","minBridgeVersion":"\#(bridge)"}"#
        return try JSONDecoder().decode(ModuleManifest.self, from: Data(json.utf8))
    }

    func testUnavailableModulesExplainWhyInsteadOfABareState() throws {
        let manifests = [try manifest("vault"), try manifest("future", bridge: "0.9.0"), try manifest("expo", runtime: "expo")]
        XCTAssertNil(ModuleRuntimeController.unavailableReason(for: "vault", in: manifests))
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "missing", in: manifests), "This module isn’t included in this version of Modula.")
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "future", in: manifests), "Vault Notes needs a newer version of Modula. Update the app to open it.")
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "expo", in: manifests), "Vault Notes uses a runtime this app doesn’t support.")
    }
}

final class StoryViewerSegmentTests: XCTestCase {
    /// Viewer opened on a partial group (1 item); hydration brings 3. The bar must show
    /// 3 segments and keep the item being watched, with its progress.
    func testEngineResizesWhenTheGroupGainsItemsAndKeepsTheCurrentItem() {
        let engine = StoryProgressEngine(count: 1)
        _ = engine.tick(1)
        XCTAssertEqual(engine.segmentCount, 1)
        engine.resize(count: 3, keepingIndex: 2) // the watched item is now third
        XCTAssertEqual(engine.segmentCount, 3)
        XCTAssertEqual(engine.index, 2)
        XCTAssertEqual(engine.progress, 0, accuracy: 0.0001)
        _ = engine.tick(1)
        let progress = engine.progress
        engine.resize(count: 4, keepingIndex: 2)
        XCTAssertEqual(engine.segmentCount, 4)
        XCTAssertEqual(engine.progress, progress, accuracy: 0.0001, "same item keeps its progress")
        XCTAssertEqual(engine.next(), .advanced, "the new trailing item is reachable")
        engine.resize(count: 1, keepingIndex: nil)
        XCTAssertEqual(engine.index, 0, "shrinking clamps the index")
    }
}

final class StoryViewerFailedMediaTests: XCTestCase {
    private func item(_ id: String, kind: StoryKind = .image) -> StoryItem {
        StoryItem(id: id, author: MessagingFixtures.me, createdAt: Date(), expiresAt: nil, kind: kind, media: nil,
                  text: nil, background: nil, seen: false, isOwn: false, viewerCount: nil)
    }

    func testTapNavigationStaysAvailableWhenTheImageFailed() {
        let story = item("s1")
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: nil), "still loading")
        XCTAssertTrue(StoryViewerGate.allowsTapNavigation(item: story, loadedID: "s1", failedID: nil))
        XCTAssertTrue(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: "s1"),
                      "a failed image must not trap the viewer")
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: "other"))
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: item("v", kind: .video), loadedID: "v", failedID: "v"))
    }
}

final class HomeStoryTrayTests: XCTestCase {
    func testHomeTrayHasNoSecondCreateEntry() {
        let me = MessagingFixtures.me
        let friend = ConversationParticipant(id: "f", handle: "f", displayName: "F", avatarURL: nil)
        let placeholder = StoryGroup(id: "add:actor-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 0)
        let ownLive = StoryGroup(id: "g-own", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 2)
        let friendGroup = StoryGroup(id: "g-f", author: friend, items: [], isOwn: false, reportedRing: .unseen, itemCount: 1)
        XCTAssertEqual(StoryStore.homeTrayGroups([placeholder, friendGroup]).map(\.id), ["g-f"],
                       "the header + is Home's only create control")
        XCTAssertEqual(StoryStore.homeTrayGroups([ownLive, friendGroup]).map(\.id), ["g-own", "g-f"],
                       "a live own story stays in the tray")
    }
}

// MARK: - Product Hub: store listing, install state and lifecycle (Phase D)

private func bodyJSON(_ request: URLRequest) -> JSONValue? {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = Data(); var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&chunk, maxLength: chunk.count); if n <= 0 { break }; buffer.append(chunk, count: n) }
        data = buffer
    }
    return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

final class ModuleStoreTests: XCTestCase {
    private static let vault = CatalogueProduct(
        moduleId: "digital.modula.vault-notes", productKind: "module", name: "Vault Notes", description: "Notes",
        publisherId: "modula", publisherName: "Modula", latestVersion: "1.7.0", status: "published", installable: true,
        platforms: ["ios"], betaClassification: nil, installability: .init(status: "available", reasonCode: nil, reason: nil))

    private static let vault180 = CatalogueProduct(
        moduleId: "digital.modula.vault-notes", productKind: "module", name: "Vault Notes", description: "Notes",
        publisherId: "modula", publisherName: "Modula", latestVersion: "1.8.0", status: "published", installable: true,
        platforms: ["ios"], betaClassification: nil, installability: .init(status: "available", reasonCode: nil, reason: nil))

    private func state(_ status: String?, version: String? = "1.7.0", op: ModuleOperation? = nil, bundled: Bool = true,
                       bundledVersion: String? = "1.7.0", signedIn: Bool = true, product: CatalogueProduct = vault,
                       declarativeHost: Bool = false) -> ModulePrimaryAction {
        ModuleDetailPresentation(product: product,
                                 installation: status.map { ModuleInstallation(moduleId: product.moduleId, status: $0, version: version) },
                                 operation: op, bundled: bundled, bundledVersion: bundledVersion, signedIn: signedIn,
                                 declarativeHost: declarativeHost).primaryAction
    }

    func testPrimaryActionFollowsServerInstallState() {
        XCTAssertEqual(state(nil), .install, "Bundled code alone is not an installation")
        XCTAssertEqual(state(nil, signedIn: false), .signIn)
        XCTAssertEqual(state("enabled"), .open)
        XCTAssertEqual(state("installing"), .installing)
        XCTAssertEqual(state("uninstalling"), .uninstalling)
        XCTAssertEqual(state("removed"), .install)
        XCTAssertEqual(state("uninstalled"), .install, "Legacy 'uninstalled' rows are not installs")
        XCTAssertEqual(state("enabled", version: "1.6.0"), .update)
        XCTAssertEqual(state("enabled", version: "1.7.0", product: Self.vault180), .update,
                       "A newer registry release is offered even when the bundled module code is labelled older")
        XCTAssertEqual(state("enabled", version: "1.7.0", bundledVersion: "1.6.0"), .open, "Up to date with the registry's latest")
        XCTAssertEqual(state(nil, op: .installing), .installing)
        XCTAssertEqual(state(nil, bundled: false), .unavailable)
        let local = CatalogueProduct(
            moduleId: "digital.modula.basic-echo", productKind: "module", name: "Basic Echo", description: "Local",
            publisherId: "modula", publisherName: "Modula", latestVersion: "0.1.0", status: "published", installable: true,
            platforms: ["ios"], betaClassification: "local-development", installability: .init(status: "installable", reasonCode: nil, reason: nil))
        XCTAssertEqual(state(nil, bundled: false, product: local, declarativeHost: true), .install,
                       "A declarative local package can install without bundled React Native code")
        XCTAssertEqual(state(nil, bundled: false, signedIn: false, product: local, declarativeHost: true), .signIn)
        XCTAssertEqual(state("enabled", version: "0.1.0", bundled: false, product: local, declarativeHost: true), .open)
        XCTAssertEqual(state("enabled", version: "0.1.0", bundled: false, bundledVersion: nil, product: CatalogueProduct(
            moduleId: local.moduleId, productKind: local.productKind, name: local.name, description: local.description,
            publisherId: local.publisherId, publisherName: local.publisherName, latestVersion: "0.1.1", status: local.status,
            installable: true, platforms: local.platforms, betaClassification: "local-development",
            installability: local.installability), declarativeHost: true), .update)
        XCTAssertTrue(ModuleVersion.isOlder("1.9.2", than: "1.10.0"))
        XCTAssertFalse(ModuleVersion.isOlder("1.7.0", than: "1.7"))
    }

    func testListingDecodesMarketplaceAndToleratesMissingFields() throws {
        let json = #"""
        {"moduleId":"digital.modula.vault-notes","name":"Vault Notes","description":"D","latestVersion":"1.7.0","trust":"firstParty",
         "publisher":{"displayName":"Modula","website":"https://modula.digital"},
         "permissions":[{"permission":"functions:register","risk":"high","reason":"Actions"},{"permission":"events:subscribe","risk":"medium","reason":"Events"}],
         "compatibility":{"platforms":["ios"],"minimumModulaHostVersion":"0.1.0"},
         "marketplace":{"category":{"state":"declared","value":"Productivity"},"ageRating":{"state":"declared","value":"4+"},
           "syncSupport":{"state":"declared","value":true},"privacy":{"state":"undeclared","value":"x"},
           "previews":[{"id":"p1","type":"image","source":"https://cdn.modula.digital/a.png","width":1170,"height":2532},{"id":"bad","type":"image","source":"http://insecure/a.png"}],
           "rating":{"average":4.5,"count":12},"installations":{"count":3},"chart":{"rank":1,"category":"Productivity"},
           "release":{"publishedAt":"2026-08-24T00:00:00.000Z","sizeBytes":4200000,"notes":["One","Two"]},
           "icon":"https://cdn.modula.digital/icon.png"}}
        """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let listing = try XCTUnwrap(ModuleListing(json: value))
        XCTAssertEqual(listing.category, "Productivity")
        XCTAssertNil(listing.privacy, "Undeclared values are not shown as facts")
        XCTAssertEqual(listing.highRiskCount, 1)
        XCTAssertEqual(listing.previews.map(\.id), ["p1"], "Only https previews are loaded")
        XCTAssertEqual(listing.ratingCount, 12)
        XCTAssertEqual(listing.sizeBytes, 4_200_000)
        XCTAssertEqual(listing.releaseNotes, ["One", "Two"])
        XCTAssertNotNil(listing.publishedAt)
        XCTAssertEqual(listing.iconURL?.host, "cdn.modula.digital")
        let minimal = try XCTUnwrap(ModuleListing(json: .object(["moduleId": .string("x.y")])))
        XCTAssertEqual(minimal.permissions, [])
        XCTAssertNil(ModuleListing(json: .object([:])))
    }

    func testArtworkComesOnlyFromTheRegistryListing() throws {
        var listing = try XCTUnwrap(ModuleListing(json: .object(["moduleId": .string("digital.modula.vault-notes")])))
        listing.iconURL = URL(string: "https://cdn.modula.digital/icon.png")
        listing.previews = [.init(id: "p1", source: URL(string: "https://cdn.modula.digital/a.png")!, alt: "List", aspect: nil)]
        let remote = ModuleArtwork(listing: listing)
        XCTAssertEqual(remote.icon, .remote(URL(string: "https://cdn.modula.digital/icon.png")!))
        XCTAssertNil(remote.cover, "Missing cover falls back to the neutral placeholder")
        XCTAssertEqual(remote.screenshots.map(\.alt), ["List"])
        let none = ModuleArtwork(listing: nil)
        XCTAssertNil(none.icon); XCTAssertNil(none.cover); XCTAssertTrue(none.screenshots.isEmpty)
        XCTAssertNil(ModuleArtSource("asset:VaultNotesIcon"), "Bundled asset references are not artwork sources")
        XCTAssertNil(ModuleArtSource("javascript:alert(1)"))
        XCTAssertNotNil(ModuleArtSource("https://cdn.modula.digital/cover.jpg"))
    }

    func testRegistryPresentationFromLatestVersionDrivesArtwork() throws {
        let json = #"""
        {"moduleId":"digital.modula.vault-notes","latestVersion":"1.8.0",
         "presentation":{"version":"1.8.0",
           "icon":{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/icon","sha256":"77bf","width":1024,"height":1024,"available":true},
           "cover":{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/cover","sha256":"cef9","width":1600,"height":900,"available":true},
           "screenshots":[{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/s1","sha256":"s1","width":1280,"height":720,"alt":"Shot"},
                          {"url":"http://insecure/s2","sha256":"s2"}]},
         "marketplace":{"icon":"https://cdn.modula.digital/old-icon.png","cover":"https://cdn.modula.digital/old-cover.png"}}
        """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let listing = try XCTUnwrap(ModuleListing(json: value))
        XCTAssertEqual(listing.iconURL?.lastPathComponent, "icon", "Registry presentation wins over legacy marketplace art")
        XCTAssertEqual(listing.coverURL?.lastPathComponent, "cover")
        XCTAssertEqual(listing.previews.map(\.alt), ["Shot"], "Only https screenshots are loaded")

        let product = try XCTUnwrap(GreenfieldDiscoverRepository.decodeProduct(value))
        XCTAssertEqual(product.presentation?.version, "1.8.0")
        let fromList = ModuleArtwork(listing: nil, product: product)
        XCTAssertEqual(fromList.icon, .remote(URL(string: "https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/icon")!))
        XCTAssertEqual(fromList.cover, .remote(URL(string: "https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/cover")!))
        XCTAssertEqual(fromList.screenshots.count, 1)

        let catalogue = try JSONDecoder().decode(CatalogueProduct.self, from: Data(#"""
        {"moduleId":"m","productKind":"module","name":"M","description":"","publisherId":"p","publisherName":"P","status":"published",
         "installable":true,"platforms":[],"presentation":{"icon":{"url":"https://api.modula.digital/a/icon","available":false},"cover":null}}
        """#.utf8))
        let missing = ModuleArtwork(listing: nil, product: catalogue)
        XCTAssertNil(missing.icon, "Unavailable assets fall back to the placeholder")
        XCTAssertNil(missing.cover)
    }

    func testBundledManifestsCarryNoInventedPresentationBlock() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "manifests", withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertFalse(raw.isEmpty)
        XCTAssertTrue(raw.allSatisfy { $0["presentation"] == nil })
        XCTAssertNoThrow(try JSONDecoder().decode([ModuleManifest].self, from: Data(contentsOf: url)))
        XCTAssertNil(UIImage(named: "VaultNotesIcon"), "The app bundles no module artwork")
    }

    @MainActor
    func testInstallEnablesAndUninstallSettlesAgainstServer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        SessionRouterProtocol.log = []
        defer { SessionRouterProtocol.handler = nil }
        let client = GreenfieldClient(baseURL: URL(string: "https://store-test-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        let lock = NSLock()
        nonisolated(unsafe) var status: String? = nil
        nonisolated(unsafe) var polls = 0
        nonisolated(unsafe) var installBody: JSONValue?
        nonisolated(unsafe) var uninstallBody: JSONValue?
        SessionRouterProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/install"):
                installBody = bodyJSON(request); status = "installing"; polls = 0
                return (202, #"{"ok":true,"data":{"installationId":"i1","status":"installing"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/enable"):
                status = "enabled"; return (202, #"{"ok":true,"data":{"status":"enabling"}}"#)
            case ("DELETE", "/v1/modules/digital.modula.vault-notes/install"):
                uninstallBody = bodyJSON(request); status = "uninstalling"; polls = 0
                return (202, #"{"ok":true,"data":{"status":"uninstalling"}}"#)
            case ("GET", "/v1/modules/installed"):
                polls += 1
                if status == "installing", polls >= 2 { status = "installedDisabled" }
                if status == "uninstalling", polls >= 2 { status = "removed" }
                let items = status == nil || status == "removed" ? "[]" : #"[{"installationId":"i1","moduleId":"digital.modula.vault-notes","status":"\#(status!)","version":"1.7.0"}]"#
                return (200, #"{"ok":true,"data":{"items":\#(items)}}"#)
            default: return (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: client)
        store.settlePollInterval = .milliseconds(5)

        let installed = await store.install("digital.modula.vault-notes", permissions: ["functions:register"])
        XCTAssertTrue(installed, store.lifecycleErrors.description)
        XCTAssertEqual(store.installations["digital.modula.vault-notes"]?.status, "enabled")
        XCTAssertTrue(store.installedIDs.contains("digital.modula.vault-notes"))
        XCTAssertNil(store.operations["digital.modula.vault-notes"])
        XCTAssertEqual(installBody?["platform"]?.string, "ios")
        XCTAssertEqual(installBody?["approvedPermissions"]?.array?.compactMap(\.string), ["functions:register"])
        XCTAssertTrue(installBody?["idempotencyKey"]?.string?.hasPrefix("ios-install-") == true)
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/modules/digital.modula.vault-notes/enable") }.count, 1,
                       "A disabled installation is enabled exactly once")

        let removed = await store.uninstall("digital.modula.vault-notes")
        XCTAssertTrue(removed)
        XCTAssertEqual(uninstallBody?["choice"]?.string, "keepData")
        XCTAssertFalse(store.installedIDs.contains("digital.modula.vault-notes"))
    }

    @MainActor
    func testInstallFailureSurfacesMessageAndClearsOperation() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        defer { SessionRouterProtocol.handler = nil }
        let client = GreenfieldClient(baseURL: URL(string: "https://store-fail-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/install"): return (403, #"{"ok":false,"error":{"code":"CAPABILITY_DISABLED"}}"#)
            case ("GET", "/v1/modules/installed"): return (200, #"{"ok":true,"data":{"items":[]}}"#)
            default: return (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: client)
        let ok = await store.install("digital.modula.vault-notes", permissions: [])
        XCTAssertFalse(ok)
        XCTAssertNil(store.operations["digital.modula.vault-notes"])
        XCTAssertNotNil(store.lifecycleErrors["digital.modula.vault-notes"])
    }
}


final class MessagingV3ContractTests: XCTestCase {
    func testCapabilitiesV3RequiresVersion3() throws {
        XCTAssertNil(MessagingPayloadDecoder.capabilitiesV3(from: try decode(#"{"version":2,"groups":true}"#)))
        XCTAssertNil(MessagingPayloadDecoder.capabilitiesV3(from: try decode(#"{"groups":true}"#)))
    }

    func testCapabilitiesV3ForcesPhotoVideoOffAndKeepsV2Flags() throws {
        let json = """
        {"version":3,"groups":true,"maxGroupMembers":32,"mentions":true,"voiceNotes":true,
         "voiceNoteMaxMs":900000,"voiceNoteMimeTypes":["audio/mp4"],"photoVideo":true,
         "maxAttachmentsPerMessage":1,"reactionDetails":true,"groupReadReceipts":true,
         "historySearch":true,"presence":true,"presenceOnlineWindowMs":70000,
         "realtime":{"socketPath":"/v1/messaging/socket","heartbeatMs":25000,"singleInstance":true},
         "privacyControls":["readReceipts","typingIndicators","presenceVisibility","notificationPreview"],
         "idempotentSend":true,"notificationActions":["reply","markRead"]}
        """
        let caps = try XCTUnwrap(MessagingPayloadDecoder.capabilitiesV3(from: try decode(json)))
        XCTAssertTrue(caps.groups)
        XCTAssertEqual(caps.maxGroupMembers, 32)
        XCTAssertTrue(caps.mentions)
        XCTAssertTrue(caps.voiceNotes)
        XCTAssertFalse(caps.photoVideo)
        XCTAssertTrue(caps.reactionDetails)
        XCTAssertTrue(caps.historySearch)
        XCTAssertTrue(caps.presence)
        XCTAssertTrue(caps.privacyControls)
        XCTAssertTrue(caps.idempotentSend)
        XCTAssertTrue(caps.notificationReply)
        XCTAssertTrue(caps.notificationMarkRead)
        XCTAssertEqual(caps.realtimeSocketPath, "/v1/messaging/socket")
        XCTAssertTrue(caps.realtime)
        XCTAssertTrue(caps.reactions)
        XCTAssertTrue(caps.typing)
        XCTAssertEqual(MessagingBackendCapabilities.Paths.capabilities, "/v1/messaging/capabilities")
    }

    func testSendBodyOmitsV3KeysUntilSet() {
        let plain = MessageDraft(conversationID: "c1", text: "hi")
        XCTAssertEqual(GreenfieldMessagingRepository.sendBody(plain), ["text": .string("hi")])
        let voice = MessageDraft(
            conversationID: "c1",
            text: "",
            kind: .voice,
            clientMessageId: "12345678-1234-1234-1234-1234567890ab",
            attachments: [MessageDraftAttachment(attachmentId: "att1", durationMs: 1200, waveform: [0, 0.5, 1.2, -1])]
        )
        let body = GreenfieldMessagingRepository.sendBody(voice)
        XCTAssertEqual(body["kind"], .string("voice"))
        XCTAssertEqual(body["clientMessageId"]?.string?.count, 36)
        XCTAssertEqual(body["attachments"]?.array?.count, 1)
        XCTAssertEqual(body["attachments"]?.array?.first?["waveform"]?.array, [.number(0), .number(0.5), .number(1), .number(0)])
    }

    func testPrivacyAndReceiptsAndSearchDecoders() throws {
        let privacy = MessagingPayloadDecoder.privacy(try decode(#"{"readReceipts":false,"typingIndicators":false,"presenceVisibility":"nobody","notificationPreview":"name_only","version":4}"#))
        XCTAssertFalse(privacy.readReceipts)
        XCTAssertFalse(privacy.typingIndicators)
        XCTAssertEqual(privacy.presenceVisibility, .nobody)
        XCTAssertEqual(privacy.notificationPreview, .nameOnly)
        XCTAssertEqual(privacy.version, 4)

        let person = #"{"id":"a1","handle":"ada","displayName":"Ada","avatarUrl":null}"#
        let receipts = MessagingPayloadDecoder.receipts(try decode("""
        {"readBy":[{"participant":\(person),"readAt":"2026-11-10T10:00:00Z"}],"notYet":[\(person)],"hiddenCount":1,"receiptsDisabled":false}
        """))
        XCTAssertEqual(receipts.readBy.count, 1)
        XCTAssertEqual(receipts.notYet.count, 1)
        XCTAssertEqual(receipts.hiddenCount, 1)
        XCTAssertFalse(receipts.receiptsDisabled)

        let page = MessagingPayloadDecoder.searchPage(from: try decode(#"{"items":[{"messageId":"m1","conversationId":"c1","conversationKind":"direct","snippet":"hello","kind":"text","sentAt":"2026-11-10T10:00:00Z","isOwn":true}],"nextCursor":"c","hasMore":true}"#))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "m1")
        XCTAssertTrue(page.hasMore)
    }

    func testFlagStorePersistsNotificationActions() {
        UserDefaults.standard.removeObject(forKey: MessagingV3FlagStore.key)
        var caps = MessagingBackendCapabilities.production
        caps.idempotentSend = true
        caps.notificationMarkRead = true
        MessagingV3FlagStore.save(caps)
        XCTAssertTrue(MessagingV3FlagStore.idempotentSend)
        XCTAssertTrue(MessagingV3FlagStore.notificationMarkRead)
        UserDefaults.standard.removeObject(forKey: MessagingV3FlagStore.key)
        XCTAssertFalse(MessagingV3FlagStore.idempotentSend)
    }

    private func decode(_ raw: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    }
}
