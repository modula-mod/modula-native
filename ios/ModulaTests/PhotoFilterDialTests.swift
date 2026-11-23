import CoreImage
import UIKit
import XCTest
@testable import Modula

@MainActor
final class PhotoFilterDialTests: XCTestCase {
    func testDialLooksAreTheFourNamedFilters() {
        XCTAssertEqual(PhotoFilterDialLook.allCases.map(\.title), ["B/W", "Dreamy", "Soft light", "Dither"])
        XCTAssertEqual(PhotoFilterDialLook.allCases.map(\.id), ["bw", "dreamy", "soft-light", "dither"])
        let catalogIDs = Set(StoryFilter.catalog.map(\.id))
        for look in PhotoFilterDialLook.allCases {
            XCTAssertTrue(catalogIDs.contains(look.id))
            XCTAssertEqual(StoryFilter.catalog.first { $0.id == look.id }?.title, look.title)
        }
    }

    func testDialIndexCentresEachLabel() {
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 0, count: 4), 0)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 44, count: 4), 0)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 45, count: 4), 1)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 90, count: 4), 1)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 180, count: 4), 2)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 270, count: 4), 3)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 314, count: 4), 3)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: 315, count: 4), 0)
        XCTAssertEqual(PhotoFilterDialMath.index(degreesClockwiseFromTop: -90, count: 4), 3)
    }

    func testDegreesFromTheTop() {
        XCTAssertEqual(PhotoFilterDialMath.degreesClockwiseFromTop(dx: 0, dy: -10), 0, accuracy: 0.001)
        XCTAssertEqual(PhotoFilterDialMath.degreesClockwiseFromTop(dx: 10, dy: 0), 90, accuracy: 0.001)
        XCTAssertEqual(PhotoFilterDialMath.degreesClockwiseFromTop(dx: 0, dy: 10), 180, accuracy: 0.001)
        XCTAssertEqual(PhotoFilterDialMath.degreesClockwiseFromTop(dx: -10, dy: 0), 270, accuracy: 0.001)
    }

    func testOriginalAndZeroIntensityLeaveThePhotoUntouched() {
        let image = solid(red: 0.9, green: 0.1, blue: 0.2)
        let original = StoryFilter.catalog[0]
        XCTAssertEqual(original.id, "none")
        XCTAssertTrue(StoryFilterEngine.apply(original, to: image) === image)
        let mono = StoryFilter(id: "bw", title: "B/W", systemImage: "circle.lefthalf.filled")
        XCTAssertTrue(StoryFilterEngine.apply(mono, to: image, intensity: 0) === image)
    }

    func testBlackAndWhiteRemovesColour() throws {
        let image = solid(red: 0.85, green: 0.12, blue: 0.2)
        let filtered = StoryFilterEngine.apply(look("bw"), to: image)
        let sample = try sample(filtered)
        XCTAssertEqual(sample.r, sample.g, accuracy: 0.04)
        XCTAssertEqual(sample.g, sample.b, accuracy: 0.04)
        XCTAssertGreaterThan(sample.r, 0.05)
    }

    func testDreamySoftLightAndDitherChangeThePhoto() throws {
        XCTAssertNotNil(CIFilter(name: "CIDither"))
        XCTAssertNotNil(CIFilter(name: "CISoftLightBlendMode"))
        let image = checker()
        let source = try sample(image)
        for id in ["dreamy", "soft-light", "dither"] {
            let filtered = StoryFilterEngine.apply(look(id), to: image)
            let next = try sample(filtered)
            let delta = abs(next.r - source.r) + abs(next.g - source.g) + abs(next.b - source.b)
            XCTAssertGreaterThan(delta, 0.01, id)
        }
    }

    private func look(_ id: String) -> StoryFilter {
        StoryFilter.catalog.first { $0.id == id } ?? StoryFilter(id: id, title: id, systemImage: "circle")
    }

    private func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        return renderer.image { context in
            UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    private func checker() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            context.fill(CGRect(x: 16, y: 16, width: 16, height: 16))
        }
    }

    private func sample(_ image: UIImage) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let ctx = try XCTUnwrap(context)
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
