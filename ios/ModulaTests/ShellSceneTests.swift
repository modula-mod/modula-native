import XCTest
@testable import Modula

final class ShellSceneTests: XCTestCase {
    func testCoverChoicesAreTheOpaqueLandscapes() {
        XCTAssertEqual(ShellScene.coverChoices.map(\.title), [
            "Meadow", "Studio", "Mountain lake", "Library", "Moon lake", "Unit lake", "Sunrise lake",
        ])
        XCTAssertFalse(ShellScene.coverChoices.contains(.misty))
        XCTAssertFalse(ShellScene.coverChoices.contains(.storageCloud))
    }

    func testAssetNamesAreUniqueAndDoNotUseARibbonMark() {
        let names = ShellScene.allCases.map(\.assetName)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertFalse(name.localizedCaseInsensitiveContains("ribbon"))
            XCTAssertTrue(name.hasPrefix("Scene"))
        }
    }
}
