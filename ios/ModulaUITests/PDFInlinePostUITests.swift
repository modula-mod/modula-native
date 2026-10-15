import XCTest

/// Inline (LinkedIn-style) PDF posts in the DEBUG PDF lab.
final class PDFInlinePostUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PDF_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testSwipeThroughPagesAndOpenReader() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "--debug-pdf-lab"]
        app.launch()

        let cover = app.descendants(matching: .any)["pdf.inline.cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "cover page renders inline")
        let counter = app.staticTexts["pdf.inline.counter"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "8 pages")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.inline.progress"].firstMatch.exists, "progress bar")
        XCTAssertTrue(app.buttons["pdf.inline.save"].firstMatch.waitForExistence(timeout: 5), "save/share button")
        sleep(1)
        shot("01-cover")

        let carousel = app.scrollViews["pdf.inline.carousel"].firstMatch
        carousel.swipeLeft()
        let page1 = app.buttons["pdf.inline.page.1"].firstMatch
        XCTAssertTrue(page1.waitForExistence(timeout: 5), "first page slides in")
        XCTAssertTrue(waitForLabel(counter, "1 / 8"))
        carousel.swipeLeft()
        XCTAssertTrue(waitForLabel(counter, "2 / 8"))
        sleep(1)
        shot("02-page")

        app.buttons["pdf.inline.page.2"].firstMatch.tap()
        let reader = app.descendants(matching: .any)["pdf.reader"].firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 10), "full-screen reader opens")
        XCTAssertTrue(app.staticTexts["Page 2 of 8"].waitForExistence(timeout: 5) || app.staticTexts["2 / 8"].waitForExistence(timeout: 2), "reader opens at tapped page")
        reader.pinch(withScale: 2.0, velocity: 1.5)
        sleep(1)
        shot("03-reader")
        app.buttons["Done"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5) || page1.exists)
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if element.label == label { return true }; usleep(200_000) }
        return element.label == label
    }
}
