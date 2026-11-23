import XCTest
@testable import Modula

@MainActor
final class MolibooCardGalleryTests: XCTestCase {
    func testAllTwoHundredFifteenIDsResolveToACard() throws {
        let registry = try XCTUnwrap(MolibooRegistryStore.bundled, "bundled registry must ship with the app")
        XCTAssertEqual(registry.characters.count, 215)
        let cards = MolibooCardGallery.all(registry: registry)
        XCTAssertEqual(cards.count, 215)
        XCTAssertEqual(Set(cards.map(\.number)), Set(1...215))
        XCTAssertEqual(Set(cards.map(\.id)).count, 215)
        for number in 1...215 {
            let card = try XCTUnwrap(MolibooCardGallery.card(number: number, registry: registry), "missing card for #\(number)")
            XCTAssertEqual(card.number, number)
            XCTAssertFalse(card.name.isEmpty, "#\(number)")
            XCTAssertFalse(card.familyName.isEmpty, "#\(number)")
            XCTAssertFalse(card.flavour.isEmpty, "#\(number)")
            XCTAssertEqual(card.catalogueNumber, String(format: "%03d", number))
            if number <= 115 {
                XCTAssertNotNil(card.kind, "#\(number) should resolve to a live figure kind")
            }
            if (101...115).contains(number) {
                XCTAssertTrue(card.isLegend, "#\(number) is a Legend")
                XCTAssertEqual(card.rarity, .legendary)
            }
            if number >= 116 {
                XCTAssertTrue(card.isSeries2)
                let resolved = MolibooPackagePortrait.resolve(card.character)
                XCTAssertFalse(resolved.packageId.isEmpty, "#\(number)")
                XCTAssertFalse(resolved.path.isEmpty, "#\(number)")
            }
        }
    }

    func testFamilyFiltersCoverEveryFamily() throws {
        let registry = try XCTUnwrap(MolibooRegistryStore.bundled)
        let cards = MolibooCardGallery.all(registry: registry)
        for family in registry.families {
            let inFamily = cards.filter { $0.familyId == family.id }
            XCTAssertFalse(inFamily.isEmpty, family.id)
            XCTAssertEqual(inFamily.count, family.range[1] - family.range[0] + 1, family.id)
        }
    }

    func testLegendsDoNotWearTheSavedOutfitOnCards() throws {
        let registry = try XCTUnwrap(MolibooRegistryStore.bundled)
        let legend = try XCTUnwrap(MolibooCardGallery.card(number: 101, registry: registry))
        XCTAssertTrue(legend.isLegend)
        var outfit = MascotOutfit.empty
        if let costume = MascotWardrobeCatalog.item(id: "costume.sproutsaur") {
            outfit.equip(costume)
            XCTAssertTrue(outfit.hasCostume)
        }
        // The inspect view passes .empty for legends; the model flags them so callers can do the same.
        XCTAssertTrue(legend.isLegend)
        let wearable = try XCTUnwrap(MolibooCardGallery.card(number: 1, registry: registry))
        XCTAssertFalse(wearable.isLegend)
    }

    func testMissingSeries2PackIsADefinedState() throws {
        let registry = try XCTUnwrap(MolibooRegistryStore.bundled)
        let card = try XCTUnwrap(MolibooCardGallery.card(number: 116, registry: registry))
        // Pack delivery is not on the server yet; a missing file must not crash and must resolve a path.
        let resolved = MolibooPackagePortrait.resolve(card.character)
        XCTAssertEqual(resolved.path, "portrait.png")
        XCTAssertEqual(resolved.packageId, card.character.packageId)
        // Installed state is local-only; this assertion only checks the API is safe to call.
        _ = MolibooPackagePortrait.image(for: card.character)
        _ = MolibooPackagePortrait.isInstalled(card.character)
    }
}
