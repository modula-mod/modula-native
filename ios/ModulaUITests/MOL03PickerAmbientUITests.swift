import XCTest

/// Moliboo picker (composer avatar) + shared ambient backgrounds.
final class MOL03PickerAmbientUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(route: String, ambience: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-composer.mascot.kind", "pebble", "-dev.moliboo.native3D", "YES",
                               "-moliboo.onboarded.v1", "YES", "--debug-settings-route", route, "-MOLAmbience", ambience] + extra
        app.launch()
        return app
    }

    func testPickerOpensWithHeroCardsAndDressUp() {
        let app = launch(route: "/settings/chats/composer", ambience: "night", extra: ["-MOLPickerOpen", "--debug-moliboo-picker"])
        let picker = app.descendants(matching: .any)["moliboo.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 25), "picker opens from the composer avatar")
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.picker.hero"].exists, "hero preview")
        let pebble = app.buttons["moliboo.picker.tile.pebble"]
        XCTAssertTrue(pebble.exists)
        XCTAssertTrue(pebble.isSelected, "current Moliboo is checked")
        XCTAssertTrue(app.buttons["moliboo.picker.dressup"].exists, "glass Dress up button")
        XCTAssertFalse(app.buttons["moliboo.picker.tile.bubbles"].exists, "registered characters only")
        sleep(1)
        shot("picker-night")
        app.buttons["moliboo.picker.tile.moss"].tap()
        sleep(1)
        XCTAssertTrue(!picker.exists || app.buttons["moliboo.picker.tile.moss"].isSelected, "choosing closes the picker or marks Moss")
    }

    func testPickerMorningLooks() {
        let app = launch(route: "/settings/chats/composer", ambience: "morning", extra: ["-MOLPickerOpen", "--debug-moliboo-picker"])
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.picker"].waitForExistence(timeout: 25))
        sleep(1)
        shot("picker-morning")
    }

    func testHubNightAndMorningBackgrounds() {
        for amb in ["night", "morning"] {
            let app = launch(route: "/settings/moliboo", ambience: amb)
            let more = app.buttons["world.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 25)); more.tap()
            app.buttons["Moliboo settings"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["moliboo.hub.logo"].waitForExistence(timeout: 15))
            sleep(1)
            shot("hub-\(amb)")
            app.terminate()
        }
    }

    func testStudioNightSkyAmbient() {
        let app = launch(route: "/settings/moliboo", ambience: "night", extra: ["-moliboo.studio.environment", "nightSky"])
        let more = app.buttons["world.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 25))
        app.buttons["world.nav.studio"].tap()
        XCTAssertTrue(app.buttons["studio.envMenu"].waitForExistence(timeout: 25), "Studio opens")
        sleep(3)
        shot("studio-env")
    }
}
