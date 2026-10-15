import XCTest
@testable import Modula

/// MOL-04 trading cards: catalogue, model and free pack logic (no UI).
@MainActor
final class MOL04CardsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "mol04cards.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d
    }

    func testCatalogueCoversRegisteredCharactersOnly() {
        let cards = MolibooCardCatalogue.cards
        XCTAssertEqual(cards.count, 10, "JSON decodes")
        XCTAssertEqual(Set(cards.map(\.characterID)), Set(MolibooCardCatalogue.registeredCharacterIDs))
        XCTAssertEqual(Set(MolibooCardCatalogue.registeredCharacterIDs),
                       ["pebble", "pip", "moss", "tofu", "bolt", "nimbus", "mochi", "sprout", "ember", "tuck"])
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count, "unique ids")
        for c in cards {
            XCTAssertNotNil(c.kind, "\(c.id) maps to a real character")
            XCTAssertEqual(c.moves.count, 3, c.id)
            XCTAssertTrue(c.moves.allSatisfy { $0.power > 0 }, c.id)
            XCTAssertFalse(c.tagline.isEmpty)
            XCTAssertTrue((1...5).contains(c.hearts))
            XCTAssertGreaterThan(c.level, 0)
        }
        XCTAssertEqual(Set(cards.map(\.rarity)), Set(MolibooCardRarity.allCases), "every rarity used")
        XCTAssertEqual(Set(cards.map(\.element)), Set(MolibooElement.allCases), "every element used")
        XCTAssertEqual(MolibooCardCatalogue.card(id: "founding.pebble")?.rarity, .legendary)
    }

    func testRarityOrderingAndWeights() {
        XCTAssertLessThan(MolibooCardRarity.common, .rare)
        XCTAssertLessThan(MolibooCardRarity.epic, .legendary)
        XCTAssertEqual(MolibooCardRarity.allCases.map(\.weight).reduce(0, +), 100)
        XCTAssertLessThan(MolibooCardRarity.common.sparkleCount, MolibooCardRarity.legendary.sparkleCount)
    }

    func testRollIsDeterministicAndGuaranteesRarePlus() {
        for seed in UInt64(1)...200 {
            let a = MolibooPackRoller.roll(seed: seed)
            XCTAssertEqual(a, MolibooPackRoller.roll(seed: seed))
            XCTAssertEqual(a.count, MolibooCardCatalogue.packSize)
            XCTAssertGreaterThanOrEqual(a.last!.rarity, .rare, "best card revealed last, rare or better")
            XCTAssertEqual(a.map(\.rarity), a.map(\.rarity).sorted())
        }
    }

    func testWelcomePackEndsWithLegendaryAndStorePersists() {
        let d = defaults()
        let store = MolibooCardStore(defaults: d)
        XCTAssertEqual(store.uniqueOwned, 0)
        let first = store.openFoundingPack()
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first.last?.characterID, "pebble")
        XCTAssertEqual(first.last?.rarity, .legendary)
        XCTAssertEqual(store.uniqueOwned, 5)
        _ = store.openFoundingPack(seed: 42)
        XCTAssertEqual(store.packsOpened, 2)
        let reloaded = MolibooCardStore(defaults: d)
        XCTAssertEqual(reloaded.packsOpened, 2)
        XCTAssertEqual(reloaded.owned, store.owned)
        XCTAssertEqual(reloaded.owned.values.reduce(0, +), 10)
    }
}
