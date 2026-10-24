import XCTest
@testable import Modula

@MainActor
final class MOL03CollectionTests: XCTestCase {
    func testEvery3DCharacterHasAPortraitAndOthersDoNot() throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        XCTAssertFalse(MolibooRegistry.available3D.isEmpty)
        for d in MolibooRegistry.available3D {
            let img = MolibooPortrait.image(for: d.id)
            XCTAssertNotNil(img, "portrait for \(d.id)")
            XCTAssertGreaterThanOrEqual(img?.size.width ?? 0, 256)
        }
        for id in MolibooCosmetics.originals where !MolibooRegistry.has3D(id) {
            XCTAssertNil(MolibooPortrait.image(for: id), "\(id) must not claim a portrait")
        }
    }

    func testCollectionCoversAll25Originals() {
        XCTAssertEqual(MolibooCosmetics.originals.count, 25)
        XCTAssertEqual(Set(MolibooCosmetics.originals).count, 25)
        XCTAssertTrue(MolibooRegistry.available3D.allSatisfy { MolibooCosmetics.originals.contains($0.id) })
    }
}
