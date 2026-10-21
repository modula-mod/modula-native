import XCTest

/// Regression: every control in the Reels viewer must receive taps (a page-wide
/// zero-distance drag gesture used to swallow them all).
final class ReelsTapUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testReelsControlsReceiveTaps() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "--debug-route", "/reels", "--uitest-reels-fixture"]
        app.launch()

        let following = app.buttons["Following"].firstMatch
        if !following.waitForExistence(timeout: 25) {
            print("REELS_TREE_BEGIN\n\(app.debugDescription)\nREELS_TREE_END")
            XCTFail("Reels viewer with tabs")
        }
        following.tap()
        XCTAssertTrue(following.isSelected, "Following tab takes the tap")
        app.buttons["For You"].firstMatch.tap()
        XCTAssertTrue(app.buttons["For You"].firstMatch.isSelected, "For You tab takes the tap")

        for id in ["reels.rail.heart.fill", "reels.rail.bookmark.fill", "reels.avatar", "reels.follow"] {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) exists")
            XCTAssertTrue(button.isHittable, "\(id) is hittable")
        }
        app.buttons["reels.rail.heart.fill"].firstMatch.tap()
        app.buttons["reels.rail.bookmark.fill"].firstMatch.tap()

        // Comment opens the comments sheet.
        app.buttons["reels.rail.ellipsis.bubble.fill"].firstMatch.tap()
let commentsUI = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'post.comments' OR label CONTAINS[c] 'comment'")).firstMatch
        XCTAssertTrue(commentsUI.waitForExistence(timeout: 8), "comment tap presents the comments sheet")
        app.swipeDown(velocity: .fast)
        sleep(1)

        // Create menu with Go Live (DEBUG) opens the DEV PREVIEW live flow.
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let goLive = app.buttons["Go Live (dev preview)"].firstMatch
        XCTAssertTrue(goLive.waitForExistence(timeout: 5), "Create menu offers Go Live")
        goLive.tap()
        XCTAssertTrue(app.buttons["live.setup.go"].firstMatch.waitForExistence(timeout: 8), "Live setup opens")
    }
}
