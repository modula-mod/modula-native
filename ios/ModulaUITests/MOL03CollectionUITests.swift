import XCTest

final class MOL03CollectionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-composer.mascot.kind", "pip", "-dev.moliboo.native3D", "NO",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"] + extra
        app.launch()
        return app
    }

    /// Evidence: with TEST_RUNNER_MOL03_SHOTS=<dir>, writes a real screenshot there (simulator shares the host FS).
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// The Moliboo World opens the current 2D Studio and its rewards, custom and assistant controls.
    func testHubStudioCardOpensTheOneStudio() {
        let app = launch()
        XCTAssertFalse(app.buttons["moliboo.settings.collection"].exists, "separate Collection link removed")
        let b = app.buttons["world.nav.studio"]
        XCTAssertTrue(b.waitForExistence(timeout: 20))
        XCTAssertTrue(b.isHittable)
        XCTAssertFalse(app.buttons["moliboo.settings.studio"].exists, "duplicate 'Open …'s Studio' link removed")
        b.tap()
        XCTAssertTrue(app.descendants(matching: .any)["studio.scene"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["moliboo3d.entry"].exists, "no 'Open 3D Studio (dev)' button")
        for section in ["Rewards", "Custom", "Assistant", "Wardrobe"] {
            let tab = app.buttons[section]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing Studio section \(section)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "Studio did not select \(section)")
        }
        XCTAssertTrue(app.descendants(matching: .any)["studio.scene"].exists)
    }
}
