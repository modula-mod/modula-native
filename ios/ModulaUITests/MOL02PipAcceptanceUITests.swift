import XCTest

/// MOL-02 Milestone A simulator acceptance for Pip (#001). Uses the DEBUG `moliboo3d.state` probe.
@MainActor
final class MOL02PipAcceptanceUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    private func launch(kind: String, _ extra: [String], flag: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", kind, "-dev.moliboo.native3D", flag ? "YES" : "NO"] + extra
        app.launch()
        return app
    }

    private func state(_ app: XCUIApplication) -> [String: String] {
        let e = app.descendants(matching: .any)["moliboo3d.state"]
        guard e.waitForExistence(timeout: 20) else { return [:] }
        var d: [String: String] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { d[String(p[0])] = String(p[1]) }
        }
        return d
    }

    @discardableResult
    private func waitState(_ app: XCUIApplication, _ timeout: TimeInterval = 20, _ cond: ([String: String]) -> Bool) -> [String: String] {
        let end = Date().addingTimeInterval(timeout)
        var s = state(app)
        while !cond(s), Date() < end { usleep(250_000); s = state(app) }
        XCTAssertTrue(cond(s), "state never matched: \(s)")
        return s
    }

    func testPipLoadsExpressesAnimatesAndWearsCap() {
        let app = launch(kind: "pip", ["-MOL01Scene", "front", "-MOL01Character", "pip"])
        XCTAssertTrue(app.navigationBars["Pip 3D"].waitForExistence(timeout: 20), "Pip, not Pebble")
        let s0 = waitState(app) { $0["loaded"] == "1" }
        XCTAssertEqual(s0["failed"], "0")
        XCTAssertGreaterThanOrEqual(Int(s0["meshes"] ?? "0") ?? 0, 10)
        XCTAssertGreaterThanOrEqual(Int(s0["anims"] ?? "0") ?? 0, 1)
        for (title, raw) in [("Happy", "happy"), ("Excited", "excited"), ("Surprised", "surprised"), ("Sleepy", "sleepy"), ("Sad", "sad"), ("Idle", "idle")] {
            var b = app.buttons[title]
            if !b.isHittable { app.scrollViews.firstMatch.swipeLeft(); b = app.buttons[title] }
            if !b.isHittable { app.scrollViews.firstMatch.swipeRight(); b = app.buttons[title] }
            b.tap()
            waitState(app, 5) { $0["expr"] == raw && $0["last"] == "clip:expr_\(raw)" }
        }
        app.buttons["Wobble"].tap(); waitState(app, 5) { $0["last"] == "wobble" }
        app.buttons["Bounce"].tap(); waitState(app, 5) { $0["last"] == "clip:tap" }
        app.descendants(matching: .any)["moliboo3d.view"].tap(); waitState(app, 5) { $0["reacts"] == "1" }
        // Cap toggle round-trip from whatever the persisted outfit restored (tests don't save, so state is not leaked).
        let cap0 = state(app)["cap"] ?? "0", cap1 = cap0 == "1" ? "0" : "1"
        app.buttons["moliboo3d.hatToggle"].tap(); waitState(app, 10) { $0["cap"] == cap1 }
        app.buttons["moliboo3d.hatToggle"].tap(); waitState(app, 10) { $0["cap"] == cap0 }
    }

    func testStudioOffersPipIn3DOnlyWithFlagAndNimbusStays2D() {
        var app = launch(kind: "pip", ["-MOL01Studio"], flag: false)
        XCTAssertTrue(app.descendants(matching: .any)["mol01.studio.ready"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["moliboo3d.entry"].exists, "flag off ⇒ 2D only")
        app.terminate()
        app = launch(kind: "pip", ["-MOL01Studio"])
        let entry = app.buttons["moliboo3d.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Pip"].waitForExistence(timeout: 20))
        waitState(app) { $0["loaded"] == "1" && $0["failed"] == "0" }
        app.terminate()
        app = launch(kind: "nimbus", ["-MOL01Studio"])
        XCTAssertTrue(app.descendants(matching: .any)["mol01.studio.ready"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertFalse(app.buttons["moliboo3d.entry"].exists, "Nimbus has no asset yet ⇒ no 3D entry, no Pebble substitute")
    }
}
