import XCTest
@testable import Modula

/// The String Catalog is bundled and English plural variations resolve.
final class LocalizationCatalogTests: XCTestCase {
    func testCatalogIsCompiledIntoTheAppBundle() {
        let bundle = Bundle.main
        XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
                        ?? bundle.url(forResource: "Localizable", withExtension: "stringsdict", subdirectory: nil, localization: "en"),
                        "Localizable.xcstrings must compile into en.lproj")
    }

    func testCountPluralsResolve() {
        XCTAssertEqual(String(localized: "\(1) likes"), "1 like")
        XCTAssertEqual(String(localized: "\(3) likes"), "3 likes")
        XCTAssertEqual(String(localized: "\(1) replies"), "1 reply")
        XCTAssertEqual(String(localized: "\(1) comments"), "1 comment")
        XCTAssertEqual(String(localized: "\(1) unread items"), "1 unread item")
        XCTAssertEqual(String(localized: "View \(1) replies"), "View 1 reply")
        XCTAssertEqual(String(localized: "View \(2) replies"), "View 2 replies")
        XCTAssertEqual(String(localized: "\(1) items · \("Synced")"), "1 item · Synced")
        XCTAssertEqual(String(localized: "\("Ideas"), \(1) saved items"), "Ideas, 1 saved item")
        XCTAssertEqual(String(localized: "Duration \(1) hours"), "Duration 1 hour")
    }
}
