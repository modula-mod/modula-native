import WebKit
import XCTest
@testable import Modula

private final class GubicRecordingSchemeTask: NSObject, WKURLSchemeTask {
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
            XCTAssertEqual(csp, WebGamePackageServe.headerContentSecurityPolicy, path)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Cross-Origin-Resource-Policy"), "same-origin", path)
            XCTAssertNil(response.value(forHTTPHeaderField: "Set-Cookie"), path)
            if path == "index.html" {
                XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8", path)
            } else if path == "game.js" {
                XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/javascript; charset=utf-8", path)
            } else if path == "style.css" {
                XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/css; charset=utf-8", path)
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
        XCTAssertEqual(postResponse.statusCode, 404)
        XCTAssertNil(postResponse.value(forHTTPHeaderField: "Allow"))
        XCTAssertNil(postResponse.value(forHTTPHeaderField: "Set-Cookie"))

        for method in ["HEAD", "OPTIONS"] {
            let task = GubicRecordingSchemeTask(file, method: method)
            handler.serve(task)
            XCTAssertTrue(task.finished, method)
            XCTAssertEqual((task.response as? HTTPURLResponse)?.statusCode, 404, method)
            XCTAssertNil((task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Allow"), method)
        }

        var queried = URLComponents(url: file, resolvingAgainstBaseURL: false)
        queried?.query = "cache=1"
        let query = GubicRecordingSchemeTask(try XCTUnwrap(queried?.url))
        handler.serve(query)
        XCTAssertEqual((query.response as? HTTPURLResponse)?.statusCode, 404)

        var root = URLComponents()
        root.scheme = "gubic"
        root.host = handler.origin
        root.path = "/"
        let bare = GubicRecordingSchemeTask(try XCTUnwrap(root.url))
        handler.serve(bare)
        XCTAssertEqual((bare.response as? HTTPURLResponse)?.statusCode, 404)

        let inventory = GubicRecordingSchemeTask(try XCTUnwrap(URL(string: "gubic://\(handler.origin)/game.files.json")))
        handler.serve(inventory)
        XCTAssertEqual((inventory.response as? HTTPURLResponse)?.statusCode, 404)

        let cookie = GubicRecordingSchemeTask(file, headers: ["Cookie": "session=secret"])
        handler.serve(cookie)
        XCTAssertEqual((cookie.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil((cookie.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie"))
        XCTAssertEqual(cookie.body, listed)

        let payload = Data("abcdefgh".utf8)
        let rangedHandler = GubicSchemeHandler(files: ["index.html": Data("<p></p>".utf8), "clip.bin": payload])
        defer { rangedHandler.close() }
        let clip = try XCTUnwrap(URL(string: "gubic://\(rangedHandler.origin)/clip.bin"))
        let partial = GubicRecordingSchemeTask(clip, headers: ["Range": "bytes=0-3"])
        rangedHandler.serve(partial)
        let partialResponse = try XCTUnwrap(partial.response as? HTTPURLResponse)
        XCTAssertEqual(partialResponse.statusCode, 206)
        XCTAssertEqual(partialResponse.value(forHTTPHeaderField: "Content-Range"), "bytes 0-3/8")
        XCTAssertEqual(partial.body, Data("abcd".utf8))
        let multi = GubicRecordingSchemeTask(clip, headers: ["Range": "bytes=0-1,2-3"])
        rangedHandler.serve(multi)
        XCTAssertEqual((multi.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(multi.body, payload)
        let unsat = GubicRecordingSchemeTask(clip, headers: ["Range": "bytes=100-101"])
        rangedHandler.serve(unsat)
        XCTAssertEqual((unsat.response as? HTTPURLResponse)?.statusCode, 416)
        XCTAssertEqual((unsat.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"), "bytes */8")

        let named = Data("ok".utf8)
        let nested = Data("nested".utf8)
        let names = GubicSchemeHandler(files: [
            "index.html": Data("<p></p>".utf8),
            "a b.png": named,
            "café.png": named,
            "dir/file.png": nested,
        ])
        defer { names.close() }
        func namedURL(_ path: String) throws -> URL {
            var components = URLComponents()
            components.scheme = "gubic"
            components.host = names.origin
            components.path = path.hasPrefix("/") ? path : "/" + path
            return try XCTUnwrap(components.url)
        }
        let space = GubicRecordingSchemeTask(try namedURL("a b.png"))
        names.serve(space)
        XCTAssertEqual((space.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(space.body, named)
        let accent = GubicRecordingSchemeTask(try namedURL("café.png"))
        names.serve(accent)
        XCTAssertEqual((accent.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(accent.body, named)
        let encodedSlash = try XCTUnwrap(URL(string: "gubic://\(names.origin)/dir%2Ffile.png"))
        XCTAssertFalse(names.allows(encodedSlash))
        let slash = GubicRecordingSchemeTask(encodedSlash)
        names.serve(slash)
        XCTAssertEqual((slash.response as? HTTPURLResponse)?.statusCode, 404)
        let nestedOK = GubicRecordingSchemeTask(try namedURL("dir/file.png"))
        names.serve(nestedOK)
        XCTAssertEqual((nestedOK.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(nestedOK.body, nested)
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
