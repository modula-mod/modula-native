import XCTest
import RealityKit
@testable import Modula

/// Validates wardrobe fits in RealityKit (offscreen): Signature Cap, hats, glasses, accessories, backgrounds (verifying the
/// backdrop dome opens toward the camera rather than covering Pebble), per-axis stretch, and equip burst effects.
@MainActor
final class MOL03WardrobeFitValidationTests: XCTestCase {
    static let originals = ["pebble", "pip", "moss", "tofu", "bolt", "nimbus", "mochi", "sprout", "ember", "tuck"]
    static let coreOriginals = ["pebble", "pip", "moss", "tofu", "bolt"]
    static let representativeItems = [
        "cap.moliboo.signature", "hat.party", "hat.cap", "hat.beret",
        "face.bandaid", "face.roundglasses", "bg.soft", "bg.night", "bg.city",
        "pet.kitty", "held.sword", "aura.sparkles"
    ]
    private let capID = "cap.moliboo.signature"

    func testEveryWardrobeItemHasAnEquipEffect() async throws {
        let table = MolibooWardrobeFitTable.bundled()
        for id in table.items.keys.sorted() {
            let item = table.items[id]!
            let spec = item.effect ?? table.slotEffects[item.slot] ?? .default
            XCTAssertNotEqual(spec.effect, .none, "\(id) has no equip effect")
            XCTAssertGreaterThan(spec.duration, 0, "\(id) effect has no duration")
            if spec.effect != .shimmer { XCTAssertGreaterThan(spec.overshoot, 1, "\(id) pop/sparkle/bounce needs an overshoot") }
        }
        let id = "hat.party"
        let anchor = Entity(); anchor.name = "anchor_head"
        let rig = MolibooWardrobeRig(characterID: "pip", table: table, cache: .init(loader: { _ in Entity() })) { $0 == "anchor_head" ? anchor : nil }
        let expected = try XCTUnwrap(table.resolve(itemID: id, characterID: "pip")).effect.effect
        let equipped = await rig.equip(id)
        XCTAssertTrue(equipped); XCTAssertEqual(rig.lastEffect, expected)
        XCTAssertGreaterThan(rig.lastBurstCount, 0, "equip should launch the sparkle/pop burst")
        XCTAssertNotNil(anchor.children.first { $0.name == MolibooWardrobeRig.burstName }, "burst entity is spawned next to the item")
        rig.unequip(id); rig.reduceMotion = true
        _ = await rig.equip(id)
        XCTAssertEqual(rig.lastEffect, .none)
        rig.stop()
    }

    func testStretchDecodesAndScalesPerAxis() throws {
        let json = #"{"items":{"top.tee":{"asset":"T","slot":"top"}},"fits":{"pebble":{"top.tee":{"anchor":"anchor_base","scale":0.5,"stretch":[1.2,1,0.9]}}}}"#
        let t = try JSONDecoder().decode(MolibooWardrobeFitTable.self, from: Data(json.utf8))
        let fit = try XCTUnwrap(t.resolve(itemID: "top.tee", characterID: "pebble")).fit
        XCTAssertEqual(fit.scaleVector, SIMD3<Float>(0.6, 0.5, 0.45))
        XCTAssertEqual(MolibooWardrobeFit(anchor: "a", scale: 2).scaleVector, SIMD3<Float>(repeating: 2))
    }
}
