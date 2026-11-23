import XCTest
import SwiftUI
@testable import Modula

/// Cosy & Outdoors wardrobe drop: unique IDs, known art styles, painted Scenes, and never worn by Legends.
@MainActor
final class MolibooWardrobeDropTests: XCTestCase {
    static let newWearables = [
        "hat.cocoabeanie", "hat.raincap", "hat.strawhat", "hat.flowercrown", "hat.moonhat", "face.sunnyshades",
        "top.zigzagknit", "top.picnic", "top.starhoodie", "out.cloudcoat", "out.stargazer", "bot.gingham",
        "shoe.pastelkicks", "acc.rainbowscarf", "held.cocoa", "held.journal", "back.leafcape", "back.adventurepack",
        "aura.fireflies",
    ]
    static let newScenes = ["bg.aurora", "bg.rainy", "bg.snowfield", "bg.dunes", "bg.forest", "bg.cloudtop", "bg.lavender"]

    func testCatalogIDsAreUniqueAndNewItemsExist() {
        let ids = MascotWardrobeCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "wardrobe IDs must stay unique")
        for id in Self.newWearables + Self.newScenes {
            XCTAssertNotNil(MascotWardrobeCatalog.item(id: id), "\(id) missing")
        }
        for id in Self.newScenes { XCTAssertEqual(MascotWardrobeCatalog.item(id: id)?.slot, .background) }
    }

    func testNewWearablesReuseExistingArtStyles() {
        let old = Set(MascotWardrobeCatalog.all.filter { !Self.newWearables.contains($0.id) }.map(\.style))
        for id in Self.newWearables {
            let item = MascotWardrobeCatalog.item(id: id)!
            XCTAssertTrue(old.contains(item.style), "\(id) uses an unknown art style \(item.style)")
        }
    }

    func testLegendsNeverWearNewItems() {
        let legends = ModulaMascotKind.allCases.filter { !$0.supportsWardrobe }
        XCTAssertFalse(legends.isEmpty)
        for id in Self.newWearables {
            let item = MascotWardrobeCatalog.item(id: id)!
            let outfit = MascotOutfit.solo(item)
            for kind in legends {
                XCTAssertTrue(ModulaMascotFigure(kind: kind, pose: .still(), outfit: outfit).worn.isEmpty, "\(kind) must not wear \(id)")
                XCTAssertFalse(MascotWardrobeStore.editable(item.slot, supportsWardrobe: kind.supportsWardrobe))
            }
        }
    }

    func testNewScenesPaintSomething() throws {
        for id in Self.newScenes {
            let item = try XCTUnwrap(MascotWardrobeCatalog.item(id: id))
            let r = ImageRenderer(content: MascotSceneView(item: item).frame(width: 120, height: 160))
            r.scale = 1
            let img = try XCTUnwrap(r.cgImage, "\(id) did not render")
            let data = try XCTUnwrap(img.dataProvider?.data as Data?)
            XCTAssertTrue(data.contains { $0 != 0 }, "\(id) painted nothing")
        }
    }
}
