import XCTest
@testable import Modula

@MainActor
final class MOL03CollectionTests: XCTestCase {
    func testCollectionCoversAll25Originals() {
        XCTAssertEqual(MolibooCosmetics.originals.count, 25)
        XCTAssertEqual(Set(MolibooCosmetics.originals).count, 25)
        XCTAssertTrue(MolibooRegistry.available3D.allSatisfy { MolibooCosmetics.originals.contains($0.id) })
    }
}
