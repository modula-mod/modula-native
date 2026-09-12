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

final class ModuleRuntimeUITests: XCTestCase {
    @MainActor
    func testDiagnosticRemountFailureAndNativeRequest() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Product Hub"].firstMatch.tap()
        for _ in 0..<2 {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Runtime Diagnostic")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 25))
            app.buttons["Reject invalid action"].tap()
            XCTAssertTrue(app.staticTexts["Invalid action safely rejected"].waitForExistence(timeout: 5))
            app.buttons["Close"].firstMatch.tap()
        }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Runtime Diagnostic")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 10))
        app.buttons["Throw module error"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 10))
        app.buttons["Open native Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }
}
