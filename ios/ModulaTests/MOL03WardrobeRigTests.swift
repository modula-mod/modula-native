import XCTest
import RealityKit
@testable import Modula

@MainActor
final class MOL03WardrobeRigTests: XCTestCase {
    private let json = """
    {"version":1,
     "items":{
       "hat.party":{"asset":"Item_hat_party","slot":"hat","variants":{"wide":"Item_hat_party_wide"},
                    "effect":{"effect":"sparkle","duration":0.4,"overshoot":1.2,"pulses":1}},
       "top.tee":{"asset":"Item_top_tee","slot":"top"},
       "pet.duck":{"asset":"Item_pet_duck","slot":"pet"}},
     "fits":{
       "pip":{"slot:hat":{"anchor":"Pip_Anchor_Head","offset":[0,0.05,0],"scale":0.9},
              "top.tee":{"anchor":"Pip_Anchor_Body","scale":1.1},
              "pet.duck":{"anchor":"Pip_Anchor_Body","hidden":true}},
       "moss":{"slot:hat":{"anchor":"Moss_Anchor_Head","scale":1.3,"variant":"wide"}}},
     "slotEffects":{"top":{"effect":"shimmer","duration":0.5,"overshoot":1.05,"pulses":2}}}
    """

    private func table() throws -> MolibooWardrobeFitTable {
        try JSONDecoder().decode(MolibooWardrobeFitTable.self, from: Data(json.utf8))
    }

    func testResolveUsesItemThenSlotFitVariantsAndEffects() throws {
        let t = try table()
        let pipHat = try XCTUnwrap(t.resolve(itemID: "hat.party", characterID: "pip"))
        XCTAssertEqual(pipHat.asset, "Item_hat_party"); XCTAssertEqual(pipHat.fit.anchor, "Pip_Anchor_Head")
        XCTAssertEqual(pipHat.effect.effect, .sparkle)
        let mossHat = try XCTUnwrap(t.resolve(itemID: "hat.party", characterID: "moss"))
        XCTAssertEqual(mossHat.asset, "Item_hat_party_wide", "per-character variant")
        XCTAssertEqual(mossHat.fit.scale, 1.3)
        let tee = try XCTUnwrap(t.resolve(itemID: "top.tee", characterID: "pip"))
        XCTAssertEqual(tee.effect.effect, .shimmer, "slot default effect")
        XCTAssertNil(t.resolve(itemID: "pet.duck", characterID: "pip"), "hidden = doesn't fit")
        XCTAssertNil(t.resolve(itemID: "top.tee", characterID: "moss"), "no fit for this character")
        XCTAssertNil(t.resolve(itemID: "hat.party", characterID: "tofu"))
        XCTAssertEqual(t.supportedItemIDs(for: "pip"), ["hat.party", "top.tee"])
        XCTAssertEqual(MolibooWardrobeFitTable.empty.supportedItemIDs(for: "pip"), [])
    }

    func testEveryCatalogSlotParsesAndUnknownEffectFallsBackToPopIn() throws {
        let t = MolibooWardrobeFitTable(items: ["x": .init(asset: "X", slot: "hat")], fits: ["pip": ["x": .init(anchor: "A")]])
        XCTAssertEqual(t.resolve(itemID: "x", characterID: "pip")?.effect, .default)
        XCTAssertEqual(MolibooEquipEffectSpec.default.effect, .popIn)
        let odd = try JSONDecoder().decode(MolibooEquipEffectSpec.self, from: Data(#"{"effect":"confetti"}"#.utf8))
        XCTAssertEqual(odd.effect, .popIn)
        XCTAssertEqual(Set(MolibooEquipEffect.allCases.map(\.rawValue)), ["none", "pop_in", "sparkle", "bounce", "shimmer"])
    }

    func testCacheIsSmallDedupesAndClones() async throws {
        var calls: [String] = []
        let cache = MolibooWardrobeAssetCache(capacity: 2) { a in calls.append(a); let e = Entity(); e.name = a; return e }
        let a1 = try await cache.instance("A"); let a2 = try await cache.instance("A")
        XCTAssertFalse(a1 === a2, "each equip gets its own clone")
        _ = try await cache.instance("B"); _ = try await cache.instance("C")
        XCTAssertEqual(cache.cachedAssets, ["B", "C"], "LRU keeps the cache small")
        _ = try await cache.instance("A")
        XCTAssertEqual(calls, ["A", "B", "C", "A"])
    }

    func testRigAttachesToAnchorsLazilyAndSyncs() async throws {
        let character = Entity()
        let head = Entity(); head.name = "Pip_Anchor_Head"; character.addChild(head)
        let body = Entity(); body.name = "Pip_Anchor_Body"; character.addChild(body)
        let cache = MolibooWardrobeAssetCache { _ in Entity() }
        let rig = MolibooWardrobeRig(characterID: "pip", table: try table(), cache: cache) { character.findEntity(named: $0) }
        rig.reduceMotion = true   // exact transforms, no animation
        await rig.sync(["hat.party", "top.tee", "pet.duck", "cap.moliboo.signature"])
        XCTAssertEqual(Set(rig.equipped.keys), ["hat.party", "top.tee"])
        XCTAssertEqual(head.children.first?.name, "Wardrobe_hat.party")
        XCTAssertEqual(head.children.first?.scale.x ?? 0, 0.9, accuracy: 1e-5)
        XCTAssertEqual(head.children.first?.position.y ?? 0, 0.05, accuracy: 1e-5)
        XCTAssertEqual(cache.loads, 2, "lazy: only what's worn is loaded")
        await rig.sync(["top.tee"])
        XCTAssertTrue(head.children.isEmpty); XCTAssertEqual(rig.equipped.count, 1)
        rig.stop()
        XCTAssertTrue(body.children.isEmpty)
        let late = await rig.equip("hat.party")
        XCTAssertFalse(late, "no work after stop")
    }

    func testEffectIsRecordedWhenMotionAllowed() async throws {
        let character = Entity(); let head = Entity(); head.name = "Pip_Anchor_Head"; character.addChild(head)
        let rig = MolibooWardrobeRig(characterID: "pip", table: try table(), cache: .init { _ in Entity() }) { character.findEntity(named: $0) }
        await rig.equip("hat.party")
        XCTAssertEqual(rig.lastEffect, .sparkle)
        XCTAssertLessThan(head.children.first?.scale.x ?? 1, 0.9, "starts small, pops in")
        rig.stop()
    }
}
