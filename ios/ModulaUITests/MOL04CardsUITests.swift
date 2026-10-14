import XCTest

/// MOL-04 trading cards: hub entry → binder → free Founding pack → Legendary reveal → inspect.
final class MOL04CardsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL04_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testBinderPackOpeningAndLegendaryReveal() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-MOLWorldKind", "pebble", "-dev.moliboo.native3D", "YES",
                               "-dev.moliboo.cards", "YES", "--uitest-cards-reset",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        app.launch()
        let more = app.buttons["world.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 25), "World loads")
        more.tap()
        let item = app.buttons["Moliboo settings"]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moliboo.hub.logo"].waitForExistence(timeout: 15))

        let entry = app.buttons["moliboo.hub.cards"]
        for _ in 0..<10 where !(entry.exists && entry.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(entry.exists, "Cards entry in the Moliboo hub")
        entry.tap()

        let open = app.buttons["cards.openPack"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "binder opens")
        XCTAssertTrue(app.descendants(matching: .any)["cards.locked.pebble"].exists, "empty binder")
        open.tap()

        let tear = app.buttons["pack.tear"]
        XCTAssertTrue(tear.waitForExistence(timeout: 10), "sealed pack")
        sleep(1); shot("cards-pack-sealed")
        tear.tap()

        let cont = app.buttons["pack.legendary.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 15), "Legendary reveal")
        sleep(2); shot("cards-legendary-reveal")
        cont.tap()

        let done = app.buttons["pack.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        let pebble = app.buttons["cards.slot.pebble"]
        XCTAssertTrue(pebble.waitForExistence(timeout: 10), "Pebble now in the binder")
        XCTAssertEqual(app.staticTexts["cards.progress"].label, "5 of 10 collected")
        shot("cards-binder")
        pebble.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cards.inspect.card"].waitForExistence(timeout: 10))
        sleep(1); shot("cards-inspect")
    }
}
