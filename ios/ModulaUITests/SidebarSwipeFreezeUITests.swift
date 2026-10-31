import XCTest

/// Regression: a fast edge flick on Home froze the app (feed rows re-laid out every frame of the
/// sidebar settle spring). Opens/closes the sidebar 20× fast and 20× slow and checks the app responds.
@MainActor
final class SidebarSwipeFreezeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func swipes(velocity: XCUIGestureVelocity, count: Int) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run"]
        app.launch()
        sleep(4)
        let win = app.windows.firstMatch
        for i in 0..<count {
            let start = win.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = win.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0)
            let scrim = app.descendants(matching: .any)["shell.sidebar.scrim"].firstMatch
            XCTAssertTrue(scrim.waitForExistence(timeout: 5), "sidebar did not open / app hung on swipe \(i)")
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: scrim)
            waitForExpectations(timeout: 5)
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testFastEdgeSwipesOnHome() { swipes(velocity: .fast, count: 20) }
    func testSlowEdgeSwipesOnHome() { swipes(velocity: .slow, count: 20) }
}
