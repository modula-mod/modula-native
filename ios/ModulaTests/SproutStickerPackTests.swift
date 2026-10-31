import XCTest
@testable import Modula

final class SproutStickerPackTests: XCTestCase {
    func testPackIsSeriesOneAndSeriesTwoWithoutTheCutOffSticker() {
        XCTAssertEqual(SproutStickerPack.all.count, 65)
        XCTAssertEqual(SproutStickerPack.series1Count, 36)
        XCTAssertEqual(SproutStickerPack.series2Count, 29)
        XCTAssertNil(SproutStickerPack.sticker(id: "02_18_space_explorer"))
        XCTAssertEqual(Set(SproutStickerPack.all.map(\.id)).count, 65)
    }

    func testKnownStickerRoundTripsAsACommentToken() {
        let sticker = try XCTUnwrap(SproutStickerPack.sticker(id: "02_21_security_engineer"))
        let parsed = ModulaLocalSticker.extract("Hello \(sticker.local.token)")
        XCTAssertEqual(parsed.stickers.map(\.value), ["02_21_security_engineer"])
        XCTAssertEqual(parsed.stickers.first?.label, "Security Engineer")
        XCTAssertEqual(parsed.text, "Hello")
        XCTAssertEqual(ModulaLocalSticker.from(sticker.local.asSticker)?.value, sticker.id)
    }

    func testCutOffStickerTokenIsNotRendered() {
        let parsed = ModulaLocalSticker.extract("See {{sticker:sprout:02_18_space_explorer}}")
        XCTAssertTrue(parsed.stickers.isEmpty)
    }
}
