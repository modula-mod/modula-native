import XCTest

/// MOL-01 final acceptance on the simulator. Reads the DEBUG-only `moliboo3d.state` probe (see MOL01DebugHarness).
@MainActor
final class MOL01AcceptanceUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    private func launch(_ extra: [String], flag: Bool = true, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", "pebble",
                               "-dev.moliboo.native3D", flag ? "YES" : "NO"] + extra
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

    private func button(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let b = app.buttons[title]
        if !b.isHittable { app.scrollViews.firstMatch.swipeLeft() }
        return b
    }

    func testRealGeometryExpressionsAndClips() {
        let app = launch(["-MOL01Scene", "front"])
        let s0 = waitState(app) { $0["loaded"] == "1" }
        XCTAssertEqual(s0["failed"], "0")
        XCTAssertGreaterThanOrEqual(Int(s0["meshes"] ?? "0") ?? 0, 10, "real multi-part USDZ geometry")
        XCTAssertGreaterThanOrEqual(Int(s0["anims"] ?? "0") ?? 0, 1, "baked USD timeline present")
        for (title, raw) in [("Happy", "happy"), ("Excited", "excited"), ("Surprised", "surprised"), ("Sleepy", "sleepy"), ("Sad", "sad"), ("Idle", "idle")] {
            var b = app.buttons[title]
            if !b.isHittable { app.scrollViews.firstMatch.swipeLeft(); b = app.buttons[title] }
            if !b.isHittable { app.scrollViews.firstMatch.swipeRight(); b = app.buttons[title] }
            b.tap()
            waitState(app, 5) { $0["expr"] == raw && $0["last"] == "clip:expr_\(raw)" }
        }
        app.buttons["Wobble"].tap(); waitState(app, 5) { $0["last"] == "wobble" }
        app.buttons["Idle bob"].tap(); waitState(app, 5) { $0["last"] == "clip:idle_bob" }
        app.buttons["Bounce"].tap(); waitState(app, 5) { $0["last"] == "clip:tap" }
        let clips = Int(state(app)["clips"] ?? "0") ?? 0
        XCTAssertGreaterThanOrEqual(clips, 9, "baked clips actually played")
    }

    func testRotationAndTapGestures() {
        let app = launch(["-MOL01Scene", "front"])
        waitState(app) { $0["loaded"] == "1" }
        let view = app.descendants(matching: .any)["moliboo3d.view"]
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        let start = view.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: view.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let s = waitState(app, 5) { abs(Double($0["yaw"] ?? "0") ?? 0) > 0.5 }
        XCTAssertNotEqual(s["yaw"], "0.00", "drag rotates the 3D model")
        // Tap the model itself (entity-targeted gesture); probe a few points over Pebble's body.
        var reacted = false
        for dy in [0.62, 0.7, 0.55, 0.78, 0.48] where !reacted {
            view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
            usleep(600_000)
            reacted = (Int(state(app)["reacts"] ?? "0") ?? 0) > 0
        }
        XCTAssertTrue(reacted, "tap on Pebble triggers the react animation: \(state(app))")
    }

    func testCapEquipRemoveAndRestoreAcrossRelaunch() {
        var app = launch(["-MOL01Scene", "front"])
        waitState(app) { $0["loaded"] == "1" }
        let toggle = app.buttons["moliboo3d.hatToggle"]
        if state(app)["cap"] == "1" { toggle.tap(); waitState(app, 5) { $0["cap"] == "0" } }
        toggle.tap(); waitState(app, 10) { $0["cap"] == "1" }
        app.buttons["moliboo3d.save"].tap(); waitState(app, 5) { $0["saved"] == "1" }
        app.terminate()

        app = launch(["-MOL01Scene", "reopen"])
        waitState(app) { $0["loaded"] == "1" && $0["cap"] == "1" && $0["saved"] == "1" }
        app.buttons["moliboo3d.hatToggle"].tap(); waitState(app, 5) { $0["cap"] == "0" }
        app.buttons["moliboo3d.save"].tap(); waitState(app, 5) { $0["saved"] == "0" }
        app.terminate()

        app = launch(["-MOL01Scene", "reopen"])
        waitState(app) { $0["loaded"] == "1" && $0["cap"] == "0" && $0["saved"] == "0" }
    }

    func testFlagOffShows2DStudioOnlyAndFlagOnOffers3D() {
        var app = launch(["-MOL01Studio"], flag: false)
        XCTAssertTrue(app.descendants(matching: .any)["mol01.studio.ready"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Wardrobe"].waitForExistence(timeout: 5) || app.segmentedControls.firstMatch.exists, "2D Studio renders")
        XCTAssertFalse(app.buttons["moliboo3d.entry"].exists, "rollback: no 3D entry when flag off")
        app.terminate()
        app = launch(["-MOL01Studio"], flag: true)
        let entry = app.buttons["moliboo3d.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        entry.tap()
        waitState(app) { $0["loaded"] == "1" }
    }

    func testStudioLifecycle20xMemoryLoadAndFrames() {
        let app = launch(["-MOL01Studio"], flag: true)
        let entry = app.buttons["moliboo3d.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        let studioFP = app.descendants(matching: .any)["mol01.studio.ready"].label
        var fpsAll: [Double] = [], loads: [Int] = [], fps: [Double] = [], firstFP = 0.0, lastFP = 0.0, maxFrame = 0.0
        for i in 0..<21 {
            if !entry.isHittable { app.swipeDown() }
            entry.tap()
            let s = waitState(app) { $0["loaded"] == "1" }
            if i == 0 || i == 20 { sleep(3) }       // collect frame timing on first and last open
            let st = state(app)
            loads.append(Int(st["loadms"] ?? "0") ?? 0)
            let fp = Double(st["footprintMB"] ?? "0") ?? 0
            fpsAll.append(fp)
            if i == 0 { firstFP = fp; fps.append(Double(st["avgms"] ?? "0") ?? 0); maxFrame = Double(st["maxms"] ?? "0") ?? 0 }
            if i == 20 { lastFP = fp; fps.append(Double(st["avgms"] ?? "0") ?? 0) }
            _ = s
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
        }
        let line = "MOL01PERF studio=\(studioFP) open1FootprintMB=\(firstFP) open21FootprintMB=\(lastFP) deltaMB=\(String(format: "%.1f", lastFP - firstFP)) loadms=\(loads) avgFrameMs(first,last)=\(fps) maxFrameMsFirst=\(maxFrame) footprintPerOpen=\(fpsAll)"
        print(line)
        let a = XCTAttachment(string: line); a.lifetime = .keepAlways; add(a)
        XCTAssertLessThan(lastFP - firstFP, 60, "no unbounded growth across 20 open/close cycles")
    }

    /// MOL-03 Workstream B: background → foreground keeps the 3D scene alive and rendering (frame count keeps rising).
    func testBackgroundForegroundKeepsSceneRendering() {
        let app = launch(["-MOL01Scene", "front"])
        let s0 = waitState(app) { $0["loaded"] == "1" }
        let f0 = Int(s0["frames"] ?? "0") ?? 0
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        let s1 = waitState(app, 15) { (Int($0["frames"] ?? "0") ?? 0) > f0 + 30 && $0["loaded"] == "1" }
        XCTAssertEqual(s1["failed"], "0")
        app.buttons["Wobble"].tap()
        waitState(app, 5) { $0["last"] == "wobble" }
    }
}
