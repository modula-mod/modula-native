import XCTest

final class MOL03CollectionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", "pip", "-dev.moliboo.native3D", "YES",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"] + extra
        app.launch()
        return app
    }

    /// Evidence: with TEST_RUNNER_MOL03_SHOTS=<dir>, writes a real screenshot there (simulator shares the host FS).
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) -> Bool {
        guard app.navigationBars["Moliboo"].waitForExistence(timeout: 20) else { return false }
        for _ in 0..<8 where !(e.exists && e.isHittable) { app.swipeUp() }
        return e.exists && e.isHittable
    }

    func testSettingsCollectionShowsBadgesAndOpensStudio() {
        let app = launch()
        let link = app.buttons["moliboo.settings.collection"]
        XCTAssertTrue(reveal(app, link))
        shot("settings-moliboo-links")
        link.tap()
        XCTAssertTrue(app.staticTexts["collection.summary"].waitForExistence(timeout: 10))
        shot("collection-top")
        let pip = app.buttons["collection.pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 5))
        XCTAssertTrue(pip.label.contains("3D") && !pip.label.contains("coming later"), pip.label)
        let bloop = app.buttons["collection.bloop"]
        if bloop.waitForExistence(timeout: 3) { XCTAssertTrue(bloop.label.contains("coming later"), bloop.label) }
        app.swipeUp(); shot("collection-scrolled"); app.swipeDown()
        pip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["studio.rail.style"].waitForExistence(timeout: 20))
    }

    func testSettingsOpensStudioDirectly() {
        let app = launch()
        let b = app.buttons["moliboo.settings.studio"]
        XCTAssertTrue(reveal(app, b))
        b.tap()
        XCTAssertTrue(app.descendants(matching: .any)["studio.rail.play"].waitForExistence(timeout: 20))
    }
}
