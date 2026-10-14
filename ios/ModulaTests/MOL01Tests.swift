import XCTest
import RealityKit
@testable import Modula

@MainActor
final class MOL01Tests: XCTestCase {
    private let capID = MolibooCosmetics.signatureCapID

    func testFlagDefaultMatchesBuildAndOverrideWins() {
        UserDefaults.standard.removeObject(forKey: MolibooFeatureFlags.native3DKey)
        XCTAssertEqual(MolibooFeatureFlags.native3DEnabled, MolibooFeatureFlags.native3DDefault)
        MolibooFeatureFlags.native3DEnabled = false
        XCTAssertFalse(MolibooFeatureFlags.native3DEnabled)
        UserDefaults.standard.removeObject(forKey: MolibooFeatureFlags.native3DKey)
    }

    // MARK: Signature Cap — wardrobe catalog

    func testSignatureCapExistsAsCommonFreeHat() throws {
        let cap = try XCTUnwrap(MascotWardrobeCatalog.item(id: "cap.moliboo.signature"))
        XCTAssertEqual(cap.name, "Moliboo Signature Cap")
        XCTAssertEqual(cap.slot, .hat)
        XCTAssertEqual(cap.rarity, .common)
        guard case .free = cap.unlock else { return XCTFail("Signature Cap must be free") }
        XCTAssertTrue(cap.isAvailable())
        XCTAssertTrue(MascotWardrobeStore.shared.owns(cap), "free ⇒ always owned client-side")
        XCTAssertEqual(MascotWardrobeCatalog.all.filter { $0.id == capID }.count, 1, "stable ID must be unique")
    }

    func testHatPartyUnchanged() throws {
        let party = try XCTUnwrap(MascotWardrobeCatalog.item(id: "hat.party"))
        XCTAssertEqual(party.name, "Party cone")
        XCTAssertEqual(party.slot, .hat)
        XCTAssertEqual(party.rarity, .common)
        XCTAssertEqual(party.style, "party")
        guard case .free = party.unlock else { return XCTFail("hat.party unlock changed") }
        let m = try MolibooManifest.bundled(.main)
        XCTAssertNil(m.cosmetic(forWardrobeItem: "hat.party"), "hat.party must not be reinterpreted as a 3D cosmetic")
    }

    // MARK: Manifest & attachment contract

    func testManifestCoversAll25OriginalsAndOnlyBuiltCharactersAreCompatible() throws {
        let m = try MolibooManifest.bundled(.main)
        XCTAssertEqual(m.characters.map(\.id), MolibooCosmetics.originals)
        XCTAssertEqual(m.characters.map(\.canonicalNumber), Array(1...25))
        let p = try XCTUnwrap(m.character(id: "pebble"))
        XCTAssertEqual(p.canonicalNumber, 10)
        XCTAssertEqual(p.sourceVersion, "pebble-v2.2-frozen")
        XCTAssertEqual(m.cosmetic(forWardrobeItem: capID)?.sourceVersion, "pebble-v2.2-frozen")
        XCTAssertEqual(Set(p.expressions), Set(MolibooExpression.allCases))
        for e in MolibooExpression.allCases { XCTAssertNotNil(p.clips[e.clipName], "missing clip \(e.clipName)") }
        XCTAssertNotNil(p.clips["idle_bob"]); XCTAssertNotNil(p.clips["wobble"]); XCTAssertNotNil(p.clips["tap"])
        guard case .compatible(let cfg) = m.compatibility(item: capID, character: "pebble") else { return XCTFail("Pebble must be compatible") }
        XCTAssertEqual(cfg.anchor, "anchor_head")
        XCTAssertEqual(cfg.rotationDegrees.count, 3); XCTAssertEqual(cfg.offset.count, 3); XCTAssertGreaterThan(cfg.scale, 0)
        for id in MolibooCosmetics.originals where !["pebble", "pip", "moss", "tofu"].contains(id) {   // MOL-02 adds Pip, Moss and Tofu; see MOL02Tests
            XCTAssertEqual(m.compatibility(item: capID, character: id), .notCompatible, "\(id) has no config ⇒ not compatible")
        }
        XCTAssertEqual(m.compatibility(item: capID, character: "unknown"), .notCompatible)
        XCTAssertEqual(m.compatibility(item: "hat.beanie", character: "pebble"), .notCompatible)
    }

    func testIncompatibleConfigFlagIsRespected() {
        let cfg = MolibooAttachmentConfig(anchor: "anchor_head", offset: [0, 0, 0], rotationDegrees: [0, 0, 0], scale: 1, compatible: false)
        let d = MolibooCharacterDescriptor(id: "x", canonicalNumber: 99, displayName: "X", family: "test", asset: "X", assetSHA256: nil, sourceVersion: nil,
                                           anchors: ["anchor_head"], expressions: [], fps: 30, clips: [:], attachments: [capID: cfg])
        XCTAssertEqual(d.compatibility(forWardrobeItem: capID), .notCompatible)
        let badAnchor = MolibooAttachmentConfig(anchor: "anchor_tail", offset: [0, 0, 0], rotationDegrees: [0, 0, 0], scale: 1, compatible: true)
        let d2 = MolibooCharacterDescriptor(id: "y", canonicalNumber: 98, displayName: "Y", family: "test", asset: "Y", assetSHA256: nil, sourceVersion: nil,
                                            anchors: ["anchor_head"], expressions: [], fps: 30, clips: [:], attachments: [capID: badAnchor])
        XCTAssertEqual(d2.compatibility(forWardrobeItem: capID), .notCompatible, "unknown anchor ⇒ not compatible")
    }

    func testRejectsUnknownSchema() {
        XCTAssertThrowsError(try MolibooManifest.decode(Data(#"{"schemaVersion":1,"cosmetics":[],"characters":[]}"#.utf8)))
    }

    // MARK: Persistence

    func testOutfitPersistenceRoundTripWithSignatureCap() throws {
        var o = MascotOutfit.empty
        o.equip(try XCTUnwrap(MascotWardrobeCatalog.item(id: capID)))
        let back = try JSONDecoder().decode(MascotOutfit.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back, o)
        XCTAssertEqual(back.item(for: .hat)?.id, capID)
    }

    func testLegacyOutfitsStillDecode() throws {
        let legacy = try JSONDecoder().decode(MascotOutfit.self, from: Data(#"{"items":{"hat":"hat.party","top":"top.tee"}}"#.utf8))
        XCTAssertEqual(legacy.items["hat"], "hat.party")
        XCTAssertEqual(legacy.dyes, [:])
        let bare = try JSONDecoder().decode(MascotOutfit.self, from: Data("{}".utf8))
        XCTAssertTrue(bare.isEmpty)
    }

    // MARK: RealityKit (needs the bundled USDZ)

    func testPebbleLoadsAnimatesAndWearsCap() async throws {
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(m.character(id: "pebble"))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        XCTAssertFalse(c.loadFailed)
        for a in d.anchors { XCTAssertNotNil(c.anchor(a), "missing \(a)") }
        XCTAssertFalse(c.character?.availableAnimations.isEmpty ?? true, "baked clips must survive USDZ export")
        XCTAssertTrue(c.playClip("idle_bob"))
        XCTAssertFalse(c.playClip("nope"))

        let ok = await c.equip(wardrobeItemID: capID)
        XCTAssertTrue(ok)
        let cap = try XCTUnwrap(c.equipped[capID])
        XCTAssertEqual(cap.parent?.name, "anchor_head", "cap follows the head anchor (rotation + animation)")
        // Orientation: cap root (authored Z-up) relative to the body (authored Z-up) == configured rotation.
        let capRoot = try XCTUnwrap(cap.findEntity(named: "Accessory_Cap_MolibooSignature"))
        let body = try XCTUnwrap(c.character?.findEntity(named: "Pebble_Body"))
        guard case .compatible(let cfg) = d.compatibility(forWardrobeItem: capID) else { return XCTFail() }
        let r = cfg.rotationDegrees.map { $0 * .pi / 180 }
        let expected = (simd_quatf(angle: r[2], axis: [0, 0, 1]) * simd_quatf(angle: r[1], axis: [0, 1, 0]) * simd_quatf(angle: r[0], axis: [1, 0, 0])).act([0, 0, 1])
        let actual = body.convert(direction: capRoot.convert(direction: [0, 0, 1], to: nil), from: nil)
        XCTAssertGreaterThan(simd_dot(simd_normalize(actual), simd_normalize(expected)), 0.99)

        c.yaw = 1.0   // rotation: cap stays attached
        XCTAssertEqual(cap.parent?.name, "anchor_head")
        c.unequip(wardrobeItemID: capID)
        XCTAssertNil(c.equipped[capID])
        XCTAssertNil(cap.parent)

        await c.sync(outfitItemIDs: [capID, "hat.party", "hat.beanie"])
        XCTAssertEqual(Set(c.equipped.keys), [capID], "non-3D items are ignored, not guessed")
        c.setExpression(.surprised); XCTAssertEqual(c.expression, .surprised)
        c.stop()
    }
}
