import XCTest
import CryptoKit
import RealityKit
@testable import Modula

/// MOL-03 E: Nimbus (#003), Mochi (#004), Sprout (#005), Ember (#006), Tuck (#007) + the generated wardrobe trial.
@MainActor
final class MOL03OriginalsTests: XCTestCase {
    private let five: [(id: String, number: Int, name: String, moving: [String])] = [
        ("nimbus", 3, "Nimbus", ["float_drift", "cloud_puff"]),
        ("mochi", 4, "Mochi", ["slow_blink", "tail_curl", "ear_twitch"]),
        ("sprout", 5, "Sprout", ["leaf_sway", "exuberant_bounce"]),
        ("ember", 6, "Ember", ["flicker", "exuberant_bounce"]),
        ("tuck", 7, "Tuck", ["servo_tilt", "wing_flap"]),
    ]
    private let capID = MolibooCosmetics.signatureCapID

    func testManifestEntriesAssetsHashesAndPortraits() throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        let m = try MolibooManifest.bundled(.main)
        XCTAssertEqual(MolibooRegistry.available3D.count, 10)
        for c in five {
            let d = try XCTUnwrap(m.character(id: c.id), c.id)
            XCTAssertEqual(d.canonicalNumber, c.number); XCTAssertEqual(d.asset, c.name); XCTAssertEqual(d.displayName, c.name)
            XCTAssertTrue(MolibooRegistry.has3D(c.id), c.id)
            let url = try XCTUnwrap(MolibooAssetLoader.url(for: c.name))
            let sha = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(sha, d.assetSHA256, "\(c.id) bundled USDZ matches manifest hash")
            for clip in ["idle_bob", "blink", "wobble", "tap"] + c.moving { XCTAssertNotNil(d.clips[clip], "\(c.id).\(clip)") }
            XCTAssertNotNil(MolibooPortrait.image(for: c.id), "portrait \(c.id)")
            XCTAssertFalse(MolibooIdlePersonality.for(d).clips.isEmpty, "idle personality \(c.id)")
        }
        for id in ["nimbus", "mochi", "tuck"] {
            guard case .compatible(let cfg) = m.compatibility(item: capID, character: id) else { return XCTFail("\(id) wears the cap") }
            XCTAssertEqual(cfg.anchor, "anchor_head")
        }
        for id in ["sprout", "ember"] { XCTAssertEqual(m.compatibility(item: capID, character: id), .notCompatible, id) }
    }

    func testEachLoadsWithAnchorsAndPlaysEveryClip() async throws {
        let m = try MolibooManifest.bundled(.main)
        for c in five {
            let d = try XCTUnwrap(MolibooRegistry.descriptor(for: c.id, manifest: m))
            let ctl = MolibooSceneController(descriptor: d)
            ctl.cosmetics = m.cosmetics
            await ctl.load()
            XCTAssertFalse(ctl.loadFailed, c.id)
            XCTAssertGreaterThanOrEqual(ctl.meshCount, 5, c.id)
            XCTAssertGreaterThanOrEqual(ctl.character?.availableAnimations.count ?? 0, 1, c.id)
            for a in d.anchors { XCTAssertNotNil(ctl.anchor(a), "\(c.id) missing \(a)") }
            for clip in d.clips.keys.sorted() { XCTAssertTrue(ctl.playClip(clip), "\(c.id).\(clip)") }
            for x in MolibooExpression.allCases where x != .blink { ctl.setExpression(x); XCTAssertEqual(ctl.lastAction, "clip:" + x.clipName) }
            ctl.stop()
        }
    }

    // MARK: Generated wardrobe (trial)

    func testBundledFitTableCoversAllTenAndFreeAssetsShip() throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        let t = MolibooWardrobeFitTable.bundled()
        XCTAssertGreaterThanOrEqual(t.items.count, 190)
        let ten = MolibooRegistry.available3D.map(\.id)
        var missingFree: [String] = []
        for id in ten {
            let ok = t.supportedItemIDs(for: id)
            XCTAssertGreaterThanOrEqual(ok.count, 180, "\(id) fits")
            for item in ok {
                guard let r = t.resolve(itemID: item, characterID: id) else { continue }
                XCTAssertTrue(r.fit.anchor.hasPrefix("anchor_"), "\(id)/\(item) anchor \(r.fit.anchor)")
                guard let cat = MascotWardrobeCatalog.item(id: item) else { XCTFail("unknown wardrobe id \(item)"); continue }
                if !cat.isPremium, MolibooWardrobeAssets.url(for: r.asset) == nil { missingFree.append(r.asset) }
            }
        }
        XCTAssertEqual(missingFree, [], "free/earnable items must ship in the app")
        // IDs: the table never invents items, and the cap / party cone stay distinct.
        for id in t.items.keys { XCTAssertNotNil(MascotWardrobeCatalog.item(id: id), id) }
        XCTAssertNotEqual(t.items["hat.party"]?.asset, t.items[capID]?.asset)
    }

    func testTrialEquipOnPipAndSprout() async throws {
        let m = try MolibooManifest.bundled(.main)
        let t = MolibooWardrobeFitTable.bundled()
        for id in ["pip", "sprout"] {
            let d = try XCTUnwrap(MolibooRegistry.descriptor(for: id, manifest: m))
            let ctl = MolibooSceneController(descriptor: d)
            await ctl.load()
            let rig = MolibooWardrobeRig(controller: ctl, table: t)
            rig.reduceMotion = true
            let free = ["hat.beanie", "top.tee"].filter { rig.supports($0) }
            XCTAssertEqual(free.count, 2, id)
            await rig.sync(free)
            XCTAssertEqual(Set(rig.equipped.keys), Set(free), id)
            for (item, e) in rig.equipped {
                let r = try XCTUnwrap(t.resolve(itemID: item, characterID: id))
                XCTAssertEqual(e.parent?.name, r.fit.anchor, "\(id)/\(item)")
                XCTAssertEqual(e.scale.x, r.fit.scale, accuracy: 1e-5)
            }
            // Torso garment uses the per-character body variant when the table names one.
            if let v = t.fits[id]?["top.tee"]?.variant, let a = t.items["top.tee"]?.variants?[v] {
                XCTAssertEqual(t.resolve(itemID: "top.tee", characterID: id)?.asset, a)
            }
            XCTAssertEqual(ctl.loadMillis > 0, true)
            rig.stop(); ctl.stop()
        }
    }

    /// Flame pivots must be present in the Ember hierarchy (world-space probe covers flicker motion in UI);
    func testEmberExposesFlamePivots() async throws {
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "ember"))
        let ctl = MolibooSceneController(descriptor: d)
        await ctl.load()
        let root = try XCTUnwrap(ctl.character)
        var names: [String] = []
        func walk(_ e: Entity) { names.append(e.name); for c in e.children { walk(c) } }
        walk(root)
        let flame = names.filter { $0.localizedCaseInsensitiveContains("Flame") }
        XCTAssertFalse(flame.isEmpty, "names=\(names.prefix(50))")
        XCTAssertTrue(ctl.playClip("flicker"), "flicker plays")
        ctl.stop()
    }
}
