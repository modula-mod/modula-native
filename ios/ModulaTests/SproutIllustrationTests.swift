import XCTest
@testable import Modula

final class SproutIllustrationTests: XCTestCase {
    func testEachPoseHasAStableAssetName() {
        let names = SproutIllustration.allCases.map(\.assetName)
        XCTAssertEqual(names, [
            "SproutFinance", "SproutCrypto", "SproutScience", "SproutBuilder",
            "SproutRewards", "SproutModules", "SproutPainter", "SproutDoctor", "SproutAI",
        ])
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testCategoryWordsPickTheMatchingPose() {
        XCTAssertEqual(SproutIllustration.matching(text: "Personal finance"), .finance)
        XCTAssertEqual(SproutIllustration.matching(text: "digital.modula.crypto"), .crypto)
        XCTAssertEqual(SproutIllustration.matching(text: "Chemistry lab"), .science)
        XCTAssertEqual(SproutIllustration.matching(text: "Module builder"), .builder)
        XCTAssertEqual(SproutIllustration.matching(text: "Daily rewards"), .rewards)
        XCTAssertEqual(SproutIllustration.matching(text: "Product designer"), .painter)
        XCTAssertEqual(SproutIllustration.matching(text: "Health clinic"), .doctor)
        XCTAssertEqual(SproutIllustration.matching(text: "Nodus intelligence"), .ai)
    }

    func testLookalikeWordsDoNotMatch() {
        XCTAssertNil(SproutIllustration.matching(text: "available email"))
        XCTAssertNil(SproutIllustration.matching(text: "Vault Notes"))
        XCTAssertNil(SproutIllustration.matching(text: "module"))
        XCTAssertNil(SproutIllustration.matching(text: "Tasks"))
        XCTAssertNil(SproutIllustration.matching(text: ""))
    }

    func testMoreSpecificMoneyWordsPreferCryptoOverFinance() {
        XCTAssertEqual(SproutIllustration.matching(text: "crypto wallet"), .crypto)
        XCTAssertEqual(SproutIllustration.matching(text: "payouts"), .finance)
    }
}
