import XCTest

/// Inline (LinkedIn-style) PDF posts and the immersive reader, in the DEBUG PDF lab.
final class PDFInlinePostUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if element.label == label { return true }; usleep(200_000) }
        return element.label == label
    }

    func testSwipeThroughPagesAndOpenReader() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "--debug-pdf-lab", "-modula.pdf.reading.lab-pdf-1", ""]
        app.launch()

        let cover = app.descendants(matching: .any)["pdf.inline.cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "cover page renders inline")
        let counter = app.staticTexts["pdf.inline.counter"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "8 pages")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.inline.progress"].firstMatch.exists, "dot scrubber")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.inline.badge"].firstMatch.exists, "doc-type badge")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.inline.readingTime"].firstMatch.waitForExistence(timeout: 8), "reading time")
        XCTAssertTrue(app.buttons["pdf.inline.save"].firstMatch.waitForExistence(timeout: 5), "save/share button")

        let carousel = app.scrollViews["pdf.inline.carousel"].firstMatch
        carousel.swipeLeft()
        XCTAssertTrue(waitForLabel(counter, "1 / 8"))
        carousel.swipeLeft()
        XCTAssertTrue(waitForLabel(counter, "2 / 8"))

        // Open the immersive reader on the tapped page.
        app.buttons["pdf.inline.page.2"].firstMatch.tap()
        let reader = app.descendants(matching: .any)["pdf.reader"].firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 10), "immersive reader opens")
        let readerCounter = app.staticTexts["pdf.reader.counter"].firstMatch
        XCTAssertTrue(readerCounter.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(readerCounter, "Page 2 of 8"), "opens at tapped page, got \(readerCounter.label)")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.reader.thumbnails"].firstMatch.exists, "thumbnail strip")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.reader.scrubber"].firstMatch.exists, "page scrubber")

        // Bookmark + search with highlights.
        app.buttons["pdf.reader.bookmark"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["pdf.reader.search"].firstMatch.tap()
        let field = app.textFields["pdf.reader.searchField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Chapter")
        let summary = app.staticTexts["pdf.reader.searchSummary"].firstMatch
        let end = Date().addingTimeInterval(6)
        while Date() < end, !summary.label.contains(" of ") { usleep(200_000) }
        XCTAssertTrue(summary.label.contains(" of "), "search finds matches, got '\(summary.label)'")
        app.buttons["pdf.reader.search"].firstMatch.tap()

        // Contents sheet from the outline.
        app.buttons["pdf.reader.more"].firstMatch.tap()
        app.buttons["Contents & bookmarks"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Chapter 3, page 4"].firstMatch.waitForExistence(timeout: 4), "outline listed")
        app.buttons["Chapter 3, page 4"].firstMatch.tap()
        XCTAssertTrue(waitForLabel(readerCounter, "Page 4 of 8"))

        // Tap hides chrome, tap shows it again.
        reader.tap()
        XCTAssertTrue(waitForGone(app.buttons["pdf.reader.close"].firstMatch), "chrome auto-hides on tap")
        reader.tap()
        XCTAssertTrue(app.buttons["pdf.reader.close"].firstMatch.waitForExistence(timeout: 4))

        app.buttons["pdf.reader.close"].firstMatch.tap()
        let resume = app.buttons["pdf.inline.continue"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 6), "continue-reading memory")
        XCTAssertEqual(resume.label, "Continue reading from page 4")
    }

    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if !element.exists || !element.isHittable { return true }; usleep(200_000) }
        return !element.exists
    }
}
