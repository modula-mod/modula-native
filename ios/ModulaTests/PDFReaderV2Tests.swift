import PDFKit
import UIKit
import XCTest
@testable import Modula

final class PDFReaderV2Tests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PDFReaderV2Tests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makePDF(pages: Int = 6, outline: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v2-\(UUID().uuidString).pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for index in 0..<pages {
                context.beginPage()
                ("Chapter \(index) alpha beta gamma delta" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        if outline {
            let root = PDFOutline()
            for index in 0..<pages {
                let item = PDFOutline(); item.label = "Section \(index)"
                item.destination = PDFDestination(page: document.page(at: index)!, at: .zero)
                root.insertChild(item, at: root.numberOfChildren)
            }
            document.outlineRoot = root
        }
        XCTAssertTrue(document.write(to: url))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testReadingStorePersistsLastPageAndBookmarks() {
        let store = PDFReadingStore(defaults: defaults)
        XCTAssertEqual(store.lastPage(for: "a"), 0)
        store.setLastPage(5, for: "a")
        XCTAssertEqual(PDFReadingStore(defaults: defaults).lastPage(for: "a"), 5, "survives a new store instance")
        XCTAssertTrue(store.toggleBookmark(3, for: "a"))
        XCTAssertTrue(store.toggleBookmark(1, for: "a"))
        XCTAssertEqual(store.bookmarks(for: "a"), [1, 3], "sorted")
        XCTAssertFalse(store.toggleBookmark(3, for: "a"))
        XCTAssertEqual(store.bookmarks(for: "a"), [1])
        XCTAssertEqual(store.lastPage(for: "b"), 0, "per document")
        store.reset("a")
        XCTAssertEqual(store.state(for: "a"), PDFReadingState())
    }

    func testReadingTimeAndLabels() {
        XCTAssertEqual(PDFReadingMath.readingMinutes(sampledWords: 2_300, sampledPages: 5, pageCount: 10), 4)
        XCTAssertEqual(PDFReadingMath.readingMinutes(sampledWords: 0, sampledPages: 5, pageCount: 10), 2, "visual pages ≈ 12 s")
        XCTAssertEqual(PDFReadingMath.readingMinutes(sampledWords: 10, sampledPages: 1, pageCount: 1), 1)
        XCTAssertEqual(PDFReadingMath.readingMinutes(sampledWords: 0, sampledPages: 0, pageCount: 0), 1)
        XCTAssertEqual(PDFReadingMath.readingLabel(minutes: 7), "7 min read")
        XCTAssertEqual(PDFReadingMath.readingLabel(minutes: 75), "1 h 15 min read")
        XCTAssertEqual(PDFReadingMath.wordCount("one  two\nthree"), 3)
    }

    func testScrubberSpreadsAndDots() {
        XCTAssertEqual(PDFReadingMath.page(forFraction: 0, pageCount: 10), 0)
        XCTAssertEqual(PDFReadingMath.page(forFraction: 0.55, pageCount: 10), 5)
        XCTAssertEqual(PDFReadingMath.page(forFraction: 1, pageCount: 10), 9)
        XCTAssertEqual(PDFReadingMath.page(forFraction: -3, pageCount: 10), 0)
        XCTAssertEqual(PDFReadingMath.fraction(forPage: 9, pageCount: 10), 1)
        XCTAssertEqual(PDFReadingMath.fraction(forPage: 0, pageCount: 1), 0)
        XCTAssertEqual(PDFReadingMath.spread(containing: 0, pageCount: 6), [0])
        XCTAssertEqual(PDFReadingMath.spread(containing: 2, pageCount: 6), [1, 2])
        XCTAssertEqual(PDFReadingMath.spread(containing: 3, pageCount: 6), [3, 4])
        XCTAssertEqual(PDFReadingMath.spread(containing: 5, pageCount: 6), [5])
        XCTAssertTrue(PDFReadingMath.usesDots(slideCount: 9))
        XCTAssertFalse(PDFReadingMath.usesDots(slideCount: 43))
        XCTAssertTrue(PDFReadingMath.shouldOfferContinue(lastPage: 3, pageCount: 8))
        XCTAssertFalse(PDFReadingMath.shouldOfferContinue(lastPage: 0, pageCount: 8))
        XCTAssertFalse(PDFReadingMath.shouldOfferContinue(lastPage: 9, pageCount: 8))
    }

    func testDocKindBadge() {
        XCTAssertEqual(PDFDocKind.classify(aspectRatio: 0.5625, pageCount: 20), .slides)
        XCTAssertEqual(PDFDocKind.classify(aspectRatio: 1.0, pageCount: 2), .brochure)
        XCTAssertEqual(PDFDocKind.classify(aspectRatio: 1.294, pageCount: 12), .document)
    }

    func testOutlineFlattens() throws {
        let url = try makePDF(pages: 4)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let outline = PDFOutlineEntry.flatten(document.outlineRoot, in: document)
        XCTAssertEqual(outline.map(\.title), ["Section 0", "Section 1", "Section 2", "Section 3"])
        XCTAssertEqual(outline.map(\.page), [0, 1, 2, 3])
        let none = PDFOutlineEntry.flatten(nil, in: document)
        XCTAssertTrue(none.isEmpty)
    }

    func testRendererReadingEstimate() async throws {
        let url = try makePDF(pages: 6, outline: false)
        let minutes = await PDFPageRenderer(cache: PDFPageImageCache()).readingMinutes(url: url)
        XCTAssertEqual(minutes, 1)
    }

    @MainActor
    func testReaderModelResumesBookmarksAndSearches() async throws {
        let url = try makePDF(pages: 6)
        let store = PDFReadingStore(defaults: defaults)
        store.setLastPage(4, for: "doc")
        let model = PDFReaderModel(url: url, key: "doc", title: "Doc", startPage: nil, store: store)
        XCTAssertEqual(model.pageCount, 6)
        XCTAssertEqual(model.currentPage, 4, "resumes last-read page")
        XCTAssertEqual(model.outline.count, 6)
        XCTAssertEqual(PDFReaderModel(url: url, key: "doc", title: "Doc", startPage: 2, store: store).currentPage, 2, "explicit page wins")

        model.go(to: 1)
        XCTAssertEqual(store.lastPage(for: "doc"), 1, "last-read saved")
        let ticks = model.pageTick
        model.go(to: 99)
        XCTAssertEqual(model.currentPage, 5, "clamped")
        XCTAssertGreaterThan(model.pageTick, ticks, "haptic trigger")

        model.toggleBookmark()
        XCTAssertTrue(model.isBookmarked)
        XCTAssertEqual(store.bookmarks(for: "doc"), [5])
        model.toggleBookmark()
        XCTAssertFalse(model.isBookmarked)

        model.updateSearch("chapter")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(model.searchResults.count, 6)
        XCTAssertEqual(model.searchSummary, "1 of 6")
        XCTAssertEqual(model.currentPage, 0, "jumps to first match")
        model.nextResult()
        XCTAssertEqual(model.searchSummary, "2 of 6")
        XCTAssertEqual(model.currentPage, 1)
        model.nextResult(-2)
        XCTAssertEqual(model.searchSummary, "6 of 6", "wraps around")
        model.updateSearch("zzzz")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(model.searchSummary, "No results")
        model.clearSearch()
        XCTAssertEqual(model.searchSummary, "")

        XCTAssertTrue(model.currentPageText.contains("Chapter"))
        XCTAssertTrue(model.chromeVisible)
        model.toggleChrome()
        XCTAssertFalse(model.chromeVisible)
    }
}
