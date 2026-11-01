import XCTest
@testable import Modula

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

    func testSampleGameDeclaresAStrictCSPAndUsesTheBridge() throws {
        let html = try XCTUnwrap(String(data: XCTUnwrap(GubicSampleGame.files["index.html"]), encoding: .utf8))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("script-src 'self'"))
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
