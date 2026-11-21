import WebKit
import XCTest
@testable import Modula

private final class GubicRecordingSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: URLResponse?
    var body = Data()
    var finished = false
    var failure: Error?
    init(_ url: URL, method: String = "GET") {
        var request = URLRequest(url: url)
        request.httpMethod = method
        self.request = request
    }
    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { body.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { failure = error }
}

final class GubicBridgeTests: XCTestCase {
    private let caps: Set<String> = ["lifecycle", "score", "achievements"]

    func testParsesAllowedMessages() {
        XCTAssertEqual(GubicBridgeMessage.parse(["type": "ready"], capabilities: caps), .ready)
        XCTAssertEqual(GubicBridgeMessage.parse(["type": "score", "value": 42], capabilities: caps), .score(42))
        XCTAssertEqual(GubicBridgeMessage.parse(["type": "achievement", "key": "first-star"], capabilities: caps), .achievement("first-star"))
        XCTAssertEqual(GubicBridgeMessage.parse(["type": "gameOver", "score": 7], capabilities: caps), .gameOver(7))
    }

    func testDropsUnknownMalformedAndUndeclared() {
        XCTAssertNil(GubicBridgeMessage.parse("ready", capabilities: caps))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "wallet.credit", "amount": 100], capabilities: caps))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "score", "value": -1], capabilities: caps))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "score", "value": "lots"], capabilities: caps))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "achievement", "key": "Bad Key!"], capabilities: caps))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "achievement", "key": "first-star"], capabilities: ["lifecycle"]))
        XCTAssertNil(GubicBridgeMessage.parse(["type": "score", "value": 1, "pad": String(repeating: "x", count: 5000)], capabilities: caps))
    }

    func testRateLimiterCapsPerType() {
        var limiter = GubicBridgeRateLimiter()
        let now = Date()
        for _ in 0..<4 { XCTAssertTrue(limiter.allow("score", now: now)) }
        XCTAssertFalse(limiter.allow("score", now: now))
        XCTAssertTrue(limiter.allow("achievement", now: now))
        XCTAssertTrue(limiter.allow("score", now: now.addingTimeInterval(1.1)))
    }

    func testSchemeHandlerOnlyServesListedFilesOnItsOwnOrigin() {
        let handler = GubicSchemeHandler(files: GubicSampleGame.files)
        XCTAssertTrue(handler.allows(handler.entryURL))
        XCTAssertTrue(handler.allows(URL(string: "gubic://\(handler.origin)/game.js")!))
        XCTAssertFalse(handler.allows(URL(string: "gubic://\(handler.origin)/secret.js")!))
        XCTAssertFalse(handler.allows(URL(string: "gubic://other/index.html")!))
        XCTAssertFalse(handler.allows(URL(string: "gubic://\(handler.origin)/index.html?x=1")!))
        XCTAssertFalse(handler.allows(URL(string: "https://example.com/index.html")!))
        handler.close()
        XCTAssertFalse(handler.allows(handler.entryURL))
    }

    @MainActor
    func testTopNavigationIsAllowedOnlyToTheEntryDocument() throws {
        let handler = GubicSchemeHandler(files: GubicSampleGame.files.merging(
            ["art.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8),
             "other.html": Data("<p>other</p>".utf8)]) { $1 })
        XCTAssertTrue(handler.allowsNavigation(to: handler.entryURL, isMainFrame: true))
        XCTAssertFalse(handler.allowsNavigation(to: handler.entryURL, isMainFrame: false), "subframes are refused")
        for path in ["game.js", "art.svg", "other.html"] {
            let listed = try XCTUnwrap(URL(string: "gubic://\(handler.origin)/\(path)"))
            XCTAssertTrue(handler.allows(listed), "fixture must list \(path)")
            XCTAssertFalse(handler.allowsNavigation(to: listed, isMainFrame: true), "top navigation to \(path)")
        }
        for hostile in ["https://example.com/", "gubic://other/index.html", "gubic://\(handler.origin)/index.html?x=1"] {
            XCTAssertFalse(handler.allowsNavigation(to: try XCTUnwrap(URL(string: hostile)), isMainFrame: true), hostile)
        }
        handler.close()
        XCTAssertFalse(handler.allowsNavigation(to: handler.entryURL, isMainFrame: true))
    }

    @MainActor
    func testEveryGubicResponseCarriesAContentSecurityPolicy() throws {
        let handler = GubicSchemeHandler(files: GubicSampleGame.files.merging(
            ["art.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>1</script></svg>".utf8),
             "style.css": Data("body{}".utf8)]) { $1 })
        defer { handler.close() }
        for path in ["index.html", "game.js", "art.svg", "style.css"] {
            let task = GubicRecordingSchemeTask(try XCTUnwrap(URL(string: "gubic://\(handler.origin)/\(path)")))
            handler.serve(task)
            XCTAssertTrue(task.finished, path)
            let response = try XCTUnwrap(task.response as? HTTPURLResponse, path)
            let csp = try XCTUnwrap(response.value(forHTTPHeaderField: "Content-Security-Policy"), "\(path) has no CSP")
            XCTAssertEqual(response.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff", path)
            if path == "index.html" {
                XCTAssertEqual(csp, GubicSchemeHandler.contentSecurityPolicy)
                for directive in ["connect-src 'self'", "frame-src 'none'", "worker-src 'none'", "object-src 'none'", "script-src 'self';"] {
                    XCTAssertTrue(csp.contains(directive), directive)
                }
                XCTAssertFalse(csp.contains("unsafe-eval"))
            } else {
                XCTAssertEqual(csp, GubicSchemeHandler.resourceContentSecurityPolicy, path)
                XCTAssertFalse(csp.contains("script-src"), path)
                XCTAssertTrue(csp.contains("sandbox"), path)
            }
        }
    }

    func testSameOriginGetOfListedFilesIsAllowedAndPostOrUnlistedIsRejected() throws {
        let listed = Data("{\"ok\":true}".utf8)
        let handler = GubicSchemeHandler(files: GubicSampleGame.files.merging(
            ["level.json": listed]) { $1 })
        defer { handler.close() }
        let file = try XCTUnwrap(URL(string: "gubic://\(handler.origin)/level.json"))
        let missing = try XCTUnwrap(URL(string: "gubic://\(handler.origin)/missing.json"))

        let get = GubicRecordingSchemeTask(file)
        handler.serve(get)
        XCTAssertTrue(get.finished)
        XCTAssertNil(get.failure)
        let getResponse = try XCTUnwrap(get.response as? HTTPURLResponse)
        XCTAssertEqual(getResponse.statusCode, 200)
        XCTAssertEqual(get.body, listed)
        XCTAssertNil(getResponse.value(forHTTPHeaderField: "Set-Cookie"))
        XCTAssertNil(getResponse.value(forHTTPHeaderField: "Access-Control-Allow-Credentials"))

        let notFound = GubicRecordingSchemeTask(missing)
        handler.serve(notFound)
        XCTAssertTrue(notFound.finished)
        XCTAssertNil(notFound.failure)
        XCTAssertEqual((notFound.response as? HTTPURLResponse)?.statusCode, 404)

        let posted = GubicRecordingSchemeTask(file, method: "POST")
        handler.serve(posted)
        XCTAssertTrue(posted.finished)
        XCTAssertNil(posted.failure)
        let postResponse = try XCTUnwrap(posted.response as? HTTPURLResponse)
        XCTAssertEqual(postResponse.statusCode, 405)
        XCTAssertEqual(postResponse.value(forHTTPHeaderField: "Allow"), "GET")
        XCTAssertNil(postResponse.value(forHTTPHeaderField: "Set-Cookie"))
    }

    func testSampleGameDeclaresAStrictCSPAndUsesTheBridge() throws {
        let html = try XCTUnwrap(String(data: XCTUnwrap(GubicSampleGame.files["index.html"]), encoding: .utf8))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("script-src 'self'"))
        XCTAssertTrue(html.contains("worker-src 'none'"))
        let js = try XCTUnwrap(String(data: XCTUnwrap(GubicSampleGame.files["game.js"]), encoding: .utf8))
        XCTAssertTrue(js.contains("bridge.unlockAchievement"))
        XCTAssertEqual(Set(GubicSampleGame.achievements.map(\.key)), ["first-star", "ten-stars", "orbit-master"])
    }

    func testCapabilitiesFailClosedUntilLoaded() {
        XCTAssertFalse(GubicCapabilities().allows("gubic_play"))
        let loaded = GubicCapabilities(json: .object([
            "tier": .string("core"),
            "capabilities": .array([
                .object(["id": .string("gubic_play"), "available": .bool(true)]),
                .object(["id": .string("gubic_creator_monetisation"), "available": .bool(false)]),
                .object(["id": .string("gubic_lobby_size"), "available": .bool(true), "value": .number(8)]),
            ]),
        ]))
        XCTAssertTrue(loaded.allows("gubic_play"))
        XCTAssertFalse(loaded.allows("gubic_creator_monetisation"))
        XCTAssertEqual(loaded.lobbySize, 8)
    }
}
