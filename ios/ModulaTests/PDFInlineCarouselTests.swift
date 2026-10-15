import PDFKit
import UIKit
import XCTest
@testable import Modula

final class PDFInlineCarouselTests: XCTestCase {
    func testPageWidthLeavesSidePeek() {
        XCTAssertEqual(PDFCarouselMath.pageWidth(containerWidth: 390), 302)
        XCTAssertEqual(PDFCarouselMath.pageWidth(containerWidth: 390, peek: 40), 310)
        XCTAssertEqual(PDFCarouselMath.pageWidth(containerWidth: 100, peek: 44), 100)
        XCTAssertGreaterThan(PDFCarouselMath.sidePeek, 18)
    }

    func testSlideMappingIncludesCover() {
        XCTAssertEqual(PDFCarouselMath.slideCount(pageCount: 8), 9)
        XCTAssertEqual(PDFCarouselMath.slideCount(pageCount: 0), 1)
        XCTAssertNil(PDFCarouselMath.pageIndex(forSlide: 0))
        XCTAssertEqual(PDFCarouselMath.pageIndex(forSlide: 1), 0)
        XCTAssertEqual(PDFCarouselMath.pageIndex(forSlide: 8), 7)
    }

    func testCounterAndProgress() {
        XCTAssertEqual(PDFCarouselMath.counterText(slide: 0, pageCount: 8), "8 pages")
        XCTAssertEqual(PDFCarouselMath.counterText(slide: 3, pageCount: 8), "3 / 8")
        XCTAssertEqual(PDFCarouselMath.counterText(slide: 20, pageCount: 8), "8 / 8")
        XCTAssertEqual(PDFCarouselMath.counterText(slide: 0, pageCount: 0), "PDF")
        XCTAssertEqual(PDFCarouselMath.progress(slide: 0, pageCount: 8), 0)
        XCTAssertEqual(PDFCarouselMath.progress(slide: 4, pageCount: 8), 0.5)
        XCTAssertEqual(PDFCarouselMath.progress(slide: 99, pageCount: 8), 1)
        XCTAssertEqual(PDFCarouselMath.progress(slide: 3, pageCount: 0), 0)
    }

    func testRenderWidthsAreBounded() {
        XCTAssertEqual(PDFCarouselMath.pixelWidth(for: .thumbnail, pointWidth: 400, scale: 3), PDFCarouselMath.thumbnailPixelWidth)
        XCTAssertEqual(PDFCarouselMath.pixelWidth(for: .sharp, pointWidth: 400, scale: 3), 1_200)
        XCTAssertEqual(PDFCarouselMath.pixelWidth(for: .sharp, pointWidth: 2_000, scale: 3), PDFCarouselMath.maxSharpPixelWidth)
        XCTAssertEqual(PDFCarouselMath.pixelWidth(for: .sharp, pointWidth: 10, scale: 1), PDFCarouselMath.thumbnailPixelWidth)
        XCTAssertEqual(PDFCarouselMath.cost(width: 100, height: 50), 20_000)
    }

    func testCacheKeysSeparateQualityAndPage() {
        let url = URL(fileURLWithPath: "/tmp/a.pdf")
        let a = PDFCarouselMath.cacheKey(url: url, page: 0, quality: .thumbnail, pixelWidth: 180)
        let b = PDFCarouselMath.cacheKey(url: url, page: 0, quality: .sharp, pixelWidth: 1_200)
        let c = PDFCarouselMath.cacheKey(url: url, page: 1, quality: .thumbnail, pixelWidth: 180)
        XCTAssertEqual(Set([a, b, c]).count, 3)
    }

    func testImageCacheIsCostBounded() {
        let cache = PDFPageImageCache(costLimit: 1_000_000, countLimit: 100)
        XCTAssertEqual(cache.costLimit, 1_000_000)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { _ in }
        cache.insert(image, for: "k")
        XCTAssertNotNil(cache.image(for: "k"))
        cache.removeAll()
        XCTAssertNil(cache.image(for: "k"))
    }

    func testRendererProducesThumbnailThenSharpPages() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-inline-test-\(UUID().uuidString).pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            for _ in 0..<3 { context.beginPage(); UIColor.systemTeal.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 600, height: 200)) }
        }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = PDFPageImageCache(costLimit: 32 * 1_024 * 1_024)
        let renderer = PDFPageRenderer(cache: cache)
        let count = await renderer.pageCount(url: url)
        XCTAssertEqual(count, 3)
        let ratio = await renderer.aspectRatio(url: url, page: 0)
        XCTAssertEqual(ratio, 800.0 / 600.0, accuracy: 0.01)

        let thumb = try await renderer.render(url: url, page: 1, quality: .thumbnail, pixelWidth: 180)
        let sharp = try await renderer.render(url: url, page: 1, quality: .sharp, pixelWidth: 900)
        XCTAssertNotNil(thumb); XCTAssertNotNil(sharp)
        XCTAssertLessThan((thumb?.size.width ?? 0) * (thumb?.scale ?? 1), (sharp?.size.width ?? 0) * (sharp?.scale ?? 1))
        XCTAssertNotNil(cache.image(for: PDFCarouselMath.cacheKey(url: url, page: 1, quality: .sharp, pixelWidth: 900)), "sharp render cached")
        let missing = try await renderer.render(url: url, page: 9, quality: .thumbnail, pixelWidth: 180)
        XCTAssertNil(missing)
    }

    func testRenderHonoursCancellation() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-cancel-\(UUID().uuidString).pdf")
        try? UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { $0.beginPage() }.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = PDFPageRenderer(cache: PDFPageImageCache())
        let task = Task { try await renderer.render(url: url, page: 0, quality: .sharp, pixelWidth: 1_000) }
        task.cancel()
        let result = await task.result
        if case .success(let image) = result { XCTAssertNil(image, "cancelled render should not produce an image") }
    }

    @MainActor
    func testReaderStartPageIsConsumedOnce() {
        PDFReaderStartPage.set(4, for: "pdf-x")
        XCTAssertEqual(PDFReaderStartPage.take(for: "pdf-x"), 4)
        XCTAssertEqual(PDFReaderStartPage.take(for: "pdf-x"), 0)
    }
}
