import XCTest

/// MOL-03 Living World acceptance on the simulator. Reads the DEBUG `world.state` probe; never asserts on pixels alone.
final class MOL03WorldUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func launch(_ kind: String = "pebble", extra: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // Kind via the DEBUG hook (writes the real setting), not the argument domain, so in-app switching sticks.
        var args = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-MOLWorldKind", kind, "-dev.moliboo.native3D", "YES",
                    "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        if reset { args += ["-moliboo.care.v1.\(kind)", ""] }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("world-\(name).png"))
    }

    private func state(_ app: XCUIApplication) -> [String: String] {
        let e = app.descendants(matching: .any)["world.state"]
        guard e.waitForExistence(timeout: 20) else { return [:] }
        var d: [String: String] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { d[String(p[0])] = String(p[1]) }
        }
        return d
    }

    @discardableResult
    private func wait(_ app: XCUIApplication, _ t: Double = 8, _ ok: ([String: String]) -> Bool) -> [String: String] {
        let end = Date().addingTimeInterval(t)
        var s = state(app)
        while !ok(s), Date() < end { usleep(250_000); s = state(app) }
        return s
    }

    private func scrollTo(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<6 where !(e.exists && e.isHittable) { app.swipeUp() }
    }

    func testHomeLayoutLogoStatusIdentityComposerAndCollection() {
        let app = launch()
        XCTAssertTrue(app.images["world.logo"].waitForExistence(timeout: 20), "real Moliboos wordmark in header")
        XCTAssertTrue(app.buttons["world.stage"].exists)
        for s in ["home", "studio", "wardrobe", "stickers", "care"] { XCTAssertTrue(app.buttons["world.nav.\(s)"].exists, s) }
        for s in ["mood", "energy", "bond"] { XCTAssertTrue(app.descendants(matching: .any)["world.stat.\(s)"].exists, s) }
        XCTAssertTrue(app.staticTexts["world.identity.name"].label.contains("Pebble"))
        XCTAssertTrue(app.textFields["world.composer.field"].exists)
        for q in ["sayhi", "play", "treat", "photo"] { XCTAssertTrue(app.buttons["world.quick.\(q)"].exists, q) }
        XCTAssertEqual(state(app)["char"], "pebble")
        shot("home-pebble")
        app.swipeUp()
        for a in ["sleep", "play", "clean", "feed"] { XCTAssertTrue(app.buttons["world.activity.\(a)"].waitForExistence(timeout: 5), a) }
        let pebbleTile = app.buttons["world.collection.pebble"]
        XCTAssertTrue(pebbleTile.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["world.collection.bubbles"].exists, "no unregistered characters")
        shot("home-scrolled")
    }

    func testFourTimeOfDayPeriods() {
        for (h, p) in [(8, "morning"), (14, "afternoon"), (19, "evening"), (23, "night")] {
            let app = launch(extra: ["-moliboo.world.debugHour", "\(h)"])
            let s = wait(app) { $0["period"] == p }
            XCTAssertEqual(s["period"], p)
            shot("period-\(p)")
            app.terminate()
        }
    }

    func testGesturesTapDoubleTapLongPressAndSelectionPersists() {
        let app = launch()
        let stage = app.buttons["world.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        let b0 = Int(state(app)["bounces"] ?? "0") ?? 0
        stage.tap()
        XCTAssertEqual(Int(wait(app) { Int($0["bounces"] ?? "0") ?? 0 > b0 }["bounces"] ?? "0") ?? 0, b0 + 1, "tap bounces")
        stage.doubleTap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "double-tap opens chat (composer focus)")
        app.typeText("hello")
        XCTAssertEqual(wait(app) { $0["emotion"] == "curious" }["emotion"], "curious", "watches the composer while typing")
        shot("typing")
        app.swipeDown()
        stage.press(forDuration: 0.8)
        let sprout = app.buttons["world.switcher.sprout"]
        XCTAssertTrue(sprout.waitForExistence(timeout: 5), "long-press opens switcher")
        shot("switcher")
        sprout.tap()
        XCTAssertEqual(wait(app) { $0["char"] == "sprout" }["char"], "sprout")
        app.terminate()
        let relaunched = XCUIApplication(); relaunched.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-dev.moliboo.native3D", "YES", "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        relaunched.launch()
        XCTAssertEqual(wait(relaunched) { $0["char"] == "sprout" }["char"], "sprout", "selection persists across launches")
    }

    func testCareActivitiesChangeObservableState() {
        let app = launch()
        let s0 = wait(app) { $0["mood"] != nil }
        app.swipeUp()
        let play = app.buttons["world.activity.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let s1 = wait(app) { $0["xp"] != s0["xp"] }
        XCTAssertGreaterThan(Int(s1["xp"] ?? "0")!, Int(s0["xp"] ?? "0")!)
        XCTAssertLessThan(Int(s1["energy"] ?? "0")!, Int(s0["energy"] ?? "0")!)
        XCTAssertTrue(app.descendants(matching: .any)["world.toast"].waitForExistence(timeout: 3) || state(app)["xp"] != s0["xp"], "feedback shown")
        app.buttons["world.activity.sleep"].tap()
        let s2 = wait(app) { $0["asleep"] == "1" }
        XCTAssertEqual(s2["asleep"], "1"); XCTAssertEqual(s2["emotion"], "sleepy")
        shot("care-sleeping")
        app.buttons["world.activity.sleep"].tap()
        XCTAssertEqual(wait(app) { $0["asleep"] == "0" }["asleep"], "0")
        app.buttons["world.activity.feed"].tap(); app.buttons["world.activity.clean"].tap()
        // Persisted across relaunch.
        let xp = wait(app) { _ in true }["xp"]
        app.terminate()
        let relaunched = XCUIApplication(); relaunched.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-dev.moliboo.native3D", "YES", "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        relaunched.launch()
        XCTAssertEqual(wait(relaunched) { $0["xp"] == xp }["xp"], xp, "care state persists")
    }

    func testChatSubmitsAndShowsRealOutcome() {
        let app = launch()
        let field = app.textFields["world.composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["world.composer.send"].isEnabled, "empty draft cannot send")
        field.tap(); field.typeText("Hi Pebble")
        app.buttons["world.composer.send"].tap()
        let s = wait(app, 15) { ["done", "fail", "unavailable"].contains($0["chat"] ?? "") }
        XCTAssertTrue(["done", "fail", "unavailable"].contains(s["chat"] ?? ""), "chat reached a terminal state: \(s)")
        let status = app.descendants(matching: .any)["world.chat.status"]
        XCTAssertTrue(status.exists)
        if s["chat"] == "unavailable" { XCTAssertTrue(status.label.contains("unavailable"), status.label) }
        print("MOL03WORLD chat=\(s["chat"] ?? "?") status=\(status.label)")
        shot("chat-\(s["chat"] ?? "x")")
    }

    func testNavDestinationsOpen() {
        let app = launch()
        XCTAssertTrue(app.buttons["world.nav.studio"].waitForExistence(timeout: 20))
        app.buttons["world.nav.studio"].tap()
        XCTAssertTrue(app.buttons["studio.envMenu"].waitForExistence(timeout: 20), "Studio opens")
        shot("nav-studio")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["world.nav.wardrobe"].waitForExistence(timeout: 10))
        app.buttons["world.nav.wardrobe"].tap()
        XCTAssertTrue(app.buttons["wardrobe.slot.all"].waitForExistence(timeout: 20), "Wardrobe opens on the stage")
        shot("nav-wardrobe")
        app.navigationBars.buttons.firstMatch.tap()
        let stickers = app.buttons["world.nav.stickers"]
        XCTAssertTrue(stickers.waitForExistence(timeout: 10))
        for _ in 0..<20 where !stickers.isHittable { usleep(250_000) }   // back transition settles before tapping
        stickers.tap()
        if !app.buttons["stickers.happy"].waitForExistence(timeout: 5) { stickers.tap() }
        XCTAssertTrue(app.buttons["stickers.happy"].waitForExistence(timeout: 10))
        app.buttons["stickers.happy"].tap()
        shot("nav-stickers")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["world.nav.care"].waitForExistence(timeout: 5))
        app.buttons["world.nav.care"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["care.bar.mood"].waitForExistence(timeout: 5))
        shot("nav-care")
        app.swipeDown(velocity: .fast)
        app.buttons["world.nav.toggle"].tap()
        XCTAssertEqual(wait(app) { $0["nav"] == "collapsed" }["nav"], "collapsed")
        shot("nav-collapsed")
        app.buttons["world.nav.toggle"].tap()
        app.buttons["world.quick.photo"].tap()
        XCTAssertTrue(app.buttons["studio.photo.done"].waitForExistence(timeout: 20), "Take photo opens Studio photo mode")
    }

    func testAnimationSettlesWhenIdleAndStaysOffUnderReducedMotion() {
        let app = launch(extra: ["-moliboo.world.awakeSeconds", "2"])
        let stage = app.buttons["world.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        stage.tap()
        XCTAssertEqual(wait(app, 2) { $0["anim"] == "1" }["anim"], "1", "animates after interaction")
        XCTAssertEqual(wait(app, 6) { $0["anim"] == "0" }["anim"], "0", "settles when idle (no continuous redraw)")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        app.terminate()
        let rm = launch(extra: ["-moliboo.studio.forceReduceMotion", "YES"])
        let st = rm.buttons["world.stage"]; XCTAssertTrue(st.waitForExistence(timeout: 20))
        st.tap()
        XCTAssertEqual(wait(rm, 2) { $0["anim"] == "1" }["anim"], "0", "Reduced Motion keeps the world still")
        XCTAssertEqual(state(rm)["bounces"], "1", "tap still registers")
    }
}
