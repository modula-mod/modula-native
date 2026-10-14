import XCTest

/// Settings → Moliboo hub (reached from the Living World's More menu).
final class MOL03SettingsHubUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ kind: String = "pebble") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-MOLWorldKind", kind, "-dev.moliboo.native3D", "YES",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        app.launch()
        let more = app.buttons["world.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 25), "World loads")
        more.tap()
        let item = app.buttons["Moliboo settings"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.hub.logo"].waitForExistence(timeout: 15), "hub opens with the real logo")
        return app
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<10 where !(e.exists && e.isHittable) { app.swipeUp(velocity: .slow) }
    }

    func testHubLayoutSelectionTogglesAndNavigation() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.hub.stats"].exists, "glass stats card")
        for s in ["collection", "studio", "settings", "originals"] { XCTAssertTrue(app.buttons["moliboo.hub.segment.\(s)"].exists, s) }
        let pebble = app.buttons["moliboo.hub.char.pebble"]
        XCTAssertTrue(pebble.waitForExistence(timeout: 5))
        XCTAssertTrue(pebble.isSelected, "current Moliboo is checked")
        XCTAssertFalse(app.buttons["moliboo.hub.char.bubbles"].exists, "only registered characters")
        shot("hub-top")

        // Select Moss (free) and see the selection move.
        let moss = app.buttons["moliboo.hub.char.moss"]
        reveal(app, moss); moss.tap()
        XCTAssertTrue(moss.wait(for: \.isSelected, toEqual: true, timeout: 5), "Moss selected")
        XCTAssertFalse(pebble.isSelected)

        // Settings segment scrolls to "Show Moliboo on"; toggles keep working.
        app.buttons["moliboo.hub.segment.settings"].tap()
        let nodus = app.switches["moliboo.hub.show.nodus"]
        XCTAssertTrue(nodus.waitForExistence(timeout: 5))
        let before = nodus.value as? String
        nodus.tap()
        XCTAssertNotEqual(nodus.value as? String, before, "toggle flips")
        nodus.tap()
        shot("hub-settings")

        let sounds = app.switches["moliboo.hub.sounds"]; reveal(app, sounds)
        XCTAssertTrue(sounds.exists, "sounds setting kept")
        #if DEBUG
        XCTAssertTrue(app.switches["moliboo.hub.debugPremium"].exists, "debug premium unlock (Debug only)")
        #endif
        let threeD = app.switches["moliboo.settings.3d"]; reveal(app, threeD)
        XCTAssertTrue(threeD.exists)
        let coll = app.buttons["moliboo.settings.collection"]; reveal(app, coll)
        shot("hub-advanced")
        let replay = app.buttons["moliboo.hub.replay"]; reveal(app, replay)
        XCTAssertTrue(replay.exists, "Replay the welcome kept")
        shot("hub-bottom")

        coll.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15), "Collection opens")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.hub.logo"].waitForExistence(timeout: 10), "back on the hub")
    }

    func testHubSelectionPersistsAcrossLaunch() {
        var app = launch()
        let sprout = app.buttons["moliboo.hub.char.sprout"]
        XCTAssertTrue(sprout.waitForExistence(timeout: 5))
        sprout.tap()
        XCTAssertTrue(sprout.wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-dev.moliboo.native3D", "YES",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["world.more"].waitForExistence(timeout: 25))
        app.buttons["world.more"].tap(); app.buttons["Moliboo settings"].tap()
        XCTAssertTrue(app.buttons["moliboo.hub.char.sprout"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["moliboo.hub.char.sprout"].isSelected, "selection persisted")
    }
}
