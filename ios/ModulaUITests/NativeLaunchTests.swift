import XCTest

final class NativeLaunchTests: XCTestCase {
    @MainActor
    func testNativeLaunchAndDestinations() {
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Modula"].waitForExistence(timeout: 10))
        for destination in ["Product Hub", "Profile", "Settings"] {
            app.buttons[destination].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
