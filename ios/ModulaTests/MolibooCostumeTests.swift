import XCTest
@testable import Modula

@MainActor
final class MolibooCostumeTests: XCTestCase {
    private let freeCostumeID = "costume.sproutsaur"
    private let secondFreeID = "costume.cottonhop"
    private let partyHatID = "hat.party"
    private let scarfID = "acc.rainbowscarf"

    func testCatalogHasAtLeastSixteenOriginalCostumes() {
        let items = MascotWardrobeCatalog.items(in: .costume)
        XCTAssertGreaterThanOrEqual(items.count, 16, "ship a full costume rack")
        XCTAssertEqual(items.count, Set(items.map(\.id)).count, "costume IDs must be unique")
        XCTAssertEqual(items.count, MascotCostumeCatalog.all.count)
        let catalogIDs = MascotWardrobeCatalog.all.map(\.id)
        XCTAssertEqual(catalogIDs.count, Set(catalogIDs).count, "wardrobe IDs must stay unique after adding costumes")
        for item in items {
            XCTAssertEqual(item.slot, .costume)
            XCTAssertEqual(item.need, .body)
            XCTAssertFalse(item.name.isEmpty)
            XCTAssertFalse(item.blurb.isEmpty)
            XCTAssertFalse(item.style.isEmpty)
            XCTAssertFalse(item.dyes.isEmpty)
            // Original names only — never ship trademarked characters.
            let lowered = (item.name + " " + item.blurb + " " + item.id).lowercased()
            for banned in ["superman", "spiderman", "spider-man", "batman", "marvel", "dc comics", "wonder woman"] {
                XCTAssertFalse(lowered.contains(banned), "\(item.id) mentions \(banned)")
            }
        }
        XCTAssertNotNil(MascotWardrobeCatalog.item(id: freeCostumeID))
        XCTAssertEqual(MascotWardrobeSlot.costume.title, "Costumes")
    }

    func testEquipCostumeParksConflictingSlots() throws {
        var outfit = MascotOutfit.empty
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        outfit.equip(hat, dye: 1)
        // Scarf may be coin-locked in the store, but the outfit model still records it.
        if let scarf = MascotWardrobeCatalog.item(id: scarfID) {
            outfit.equip(scarf)
        }
        XCTAssertEqual(outfit.item(for: .hat)?.id, partyHatID)
        outfit.equip(costume)
        XCTAssertEqual(outfit.item(for: .costume)?.id, freeCostumeID)
        XCTAssertNil(outfit.item(for: .hat), "covered slots are hidden while a costume is on")
        XCTAssertEqual(outfit.parkedItems[MascotWardrobeSlot.hat.rawValue], partyHatID)
        XCTAssertEqual(outfit.parkedDyes[MascotWardrobeSlot.hat.rawValue], 1)
        XCTAssertTrue(outfit.hasCostume)
        let worn = outfit.wearables(on: MascotRig.stock(.pip))
        XCTAssertTrue(worn.contains { $0.item.id == freeCostumeID })
        XCTAssertFalse(worn.contains { $0.item.id == partyHatID })
    }

    func testUnequipCostumeRestoresParkedSlots() throws {
        var outfit = MascotOutfit.empty
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        outfit.equip(hat, dye: 2)
        outfit.equip(costume)
        outfit.unequip(.costume)
        XCTAssertNil(outfit.item(for: .costume))
        XCTAssertEqual(outfit.item(for: .hat)?.id, partyHatID)
        XCTAssertEqual(outfit.dye(for: .hat), 2)
        XCTAssertTrue(outfit.parkedItems.isEmpty)
        XCTAssertTrue(outfit.parkedDyes.isEmpty)
    }

    func testSwitchingCostumesKeepsTheParkedLook() throws {
        var outfit = MascotOutfit.empty
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let first = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        let second = try XCTUnwrap(MascotWardrobeCatalog.item(id: secondFreeID))
        outfit.equip(hat)
        outfit.equip(first)
        outfit.equip(second)
        XCTAssertEqual(outfit.item(for: .costume)?.id, secondFreeID)
        XCTAssertEqual(outfit.parkedItems[MascotWardrobeSlot.hat.rawValue], partyHatID)
        outfit.unequip(.costume)
        XCTAssertEqual(outfit.item(for: .hat)?.id, partyHatID)
    }

    func testEquippingACoveredSlotDropsTheCostumeAndRestoresTheRest() throws {
        var outfit = MascotOutfit.empty
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let cap = try XCTUnwrap(MascotWardrobeCatalog.item(id: "hat.beanie"))
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        outfit.equip(hat, dye: 1)
        outfit.equip(costume)
        outfit.equip(cap, dye: 0)
        XCTAssertNil(outfit.item(for: .costume), "choosing a hat takes the costume off")
        XCTAssertEqual(outfit.item(for: .hat)?.id, cap.id)
        XCTAssertTrue(outfit.parkedItems.isEmpty)
    }

    func testPetsAurasAndScenesSurviveACostume() throws {
        var outfit = MascotOutfit.empty
        guard let aura = MascotWardrobeCatalog.items(in: .aura).first,
              let scene = MascotWardrobeCatalog.items(in: .background).first else {
            return XCTFail("expected aura and scene items")
        }
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        outfit.equip(aura)
        outfit.equip(scene)
        outfit.equip(costume)
        XCTAssertEqual(outfit.item(for: .aura)?.id, aura.id)
        XCTAssertEqual(outfit.item(for: .background)?.id, scene.id)
        XCTAssertNil(outfit.parkedItems[MascotWardrobeSlot.aura.rawValue])
        XCTAssertNil(outfit.parkedItems[MascotWardrobeSlot.background.rawValue])
    }

    func testOutfitJSONRoundTripKeepsParkedItems() throws {
        var outfit = MascotOutfit.empty
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        outfit.equip(hat, dye: 1)
        outfit.equip(costume, dye: 0)
        let data = try JSONEncoder().encode(outfit)
        let decoded = try JSONDecoder().decode(MascotOutfit.self, from: data)
        XCTAssertEqual(decoded, outfit)
        XCTAssertEqual(decoded.parkedItems[MascotWardrobeSlot.hat.rawValue], partyHatID)
        let legacy = Data(#"{"items":{"hat":"hat.party"},"dyes":{"hat":2}}"#.utf8)
        let old = try JSONDecoder().decode(MascotOutfit.self, from: legacy)
        XCTAssertEqual(old.item(for: .hat)?.id, partyHatID)
        XCTAssertTrue(old.parkedItems.isEmpty)
        XCTAssertEqual(old.dye(for: .hat), 2)
    }

    func testClearDropsCostumeAndParkedItemsTogether() throws {
        var outfit = MascotOutfit.empty
        outfit.equip(try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID)))
        outfit.equip(try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID)))
        outfit.clear()
        XCTAssertTrue(outfit.isEmpty)
        XCTAssertTrue(outfit.parkedItems.isEmpty)
        XCTAssertTrue(outfit.parkedDyes.isEmpty)
    }

    func testStoreEquipRestoreAndLegendBlock() throws {
        let store = MascotWardrobeStore.shared
        let original = store.outfit
        let kindKey = ModulaMascotSettings.kindKey
        let previousKind = UserDefaults.standard.string(forKey: kindKey)
        defer {
            if let previousKind {
                UserDefaults.standard.set(previousKind, forKey: kindKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kindKey)
            }
            store.apply(original)
        }

        UserDefaults.standard.set(ModulaMascotKind.pip.rawValue, forKey: kindKey)
        store.clearOutfit()
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: partyHatID))
        let costume = try XCTUnwrap(MascotWardrobeCatalog.item(id: freeCostumeID))
        XCTAssertTrue(store.canEquip(hat))
        XCTAssertTrue(store.canEquip(costume), "onesies are free so ownership cannot block this test")
        store.equip(hat)
        store.equip(costume)
        XCTAssertEqual(store.outfit.item(for: .costume)?.id, freeCostumeID)
        XCTAssertEqual(store.outfit.parkedItems[MascotWardrobeSlot.hat.rawValue], partyHatID)
        store.unequip(.costume)
        XCTAssertEqual(store.outfit.item(for: .hat)?.id, partyHatID)
        XCTAssertNil(store.outfit.item(for: .costume))

        store.equip(costume)
        UserDefaults.standard.set(ModulaMascotKind.kringle.rawValue, forKey: kindKey)
        XCTAssertFalse(store.selectionSupportsWardrobe)
        store.unequip(.costume)
        XCTAssertEqual(store.outfit.item(for: .costume)?.id, freeCostumeID, "Legends cannot unequip a saved costume")
        store.equip(try XCTUnwrap(MascotWardrobeCatalog.item(id: secondFreeID)))
        XCTAssertEqual(store.outfit.item(for: .costume)?.id, freeCostumeID, "Legends cannot swap costumes")
        store.clearOutfit()
        XCTAssertEqual(store.outfit.item(for: .costume)?.id, freeCostumeID, "Legends cannot clear a saved outfit")
    }

    func testBodyNeedFitsWearableMoliboosAndNotLegends() {
        let pip = MascotRig.stock(.pip)
        XCTAssertEqual(pip.fit(.body), .fits)
        let legend = MascotRig.stock(.kringle)
        XCTAssertEqual(legend.fit(.body), .none(MascotRig.ownLookNote))
        XCTAssertFalse(legend.fit(.body).isWearable)
    }
}
