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

    func testRepresentativeWardrobeFitsAndBackgroundOrientationAcrossOriginals() async throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        _ = await MolibooWardrobeAssets.ensurePremium()
        let table = MolibooWardrobeFitTable.bundled()
        let manifest = try MolibooManifest.bundled()
        XCTAssertEqual(table.items.count, 195, "wardrobe table should carry all 195 catalog items")

        // Verify all backgrounds use [90, 0, 180] so backdrop domes open toward the camera (never a dome over the character).
        for cid in Self.originals {
            for (k, fit) in table.fits[cid] ?? [:] where k.hasPrefix("bg.") || k == "slot:background" {
                XCTAssertEqual(fit.rotationDegrees, [90, 0, 180], "\(cid) · \(k) should open toward camera")
            }
        }

        var templates: [String: Entity] = [:]
        func load(_ asset: String, manifestURL: URL? = nil) async throws -> Entity {
            if let t = templates[asset] { return t.clone(recursive: true) }
            let e: Entity
            if let u = manifestURL {
                e = try await Entity(contentsOf: u)
            } else {
                e = try await MolibooWardrobeAssets.load(asset)
            }
            if templates.count > 24 { templates.removeAll() }
            templates[asset] = e
            return e.clone(recursive: true)
        }

        var failures: [String] = []
        for cid in Self.coreOriginals {
            let desc = try XCTUnwrap(manifest.character(id: cid), "\(cid) missing from manifest")
            let charURL = try XCTUnwrap(MolibooAssetLoader.url(for: try XCTUnwrap(desc.asset)), "\(cid) USDZ missing")
            let character = try await Entity(contentsOf: charURL)
            let world = Entity(); world.addChild(character)
            let body = MolibooFitBody(character: character)

            for id in Self.representativeItems {
                let slot = table.items[id]?.slot ?? "hat"
                let anchorName: String, assetName: String, manifestURL: URL?, offset: [Float], rotation: [Float], scale: Float, stretch: [Float]?, manifestPath: Bool
                if id == capID, case .compatible(let cfg) = desc.compatibility(forWardrobeItem: id),
                   let cosmetic = manifest.cosmetic(forWardrobeItem: id), let u = MolibooAssetLoader.url(for: cosmetic.asset) {
                    (anchorName, assetName, manifestURL, offset, rotation, scale, stretch, manifestPath) = (cfg.anchor, cosmetic.asset, u, cfg.offset, cfg.rotationDegrees, cfg.scale, nil, true)
                } else if let r = table.resolve(itemID: id, characterID: cid) {
                    (anchorName, assetName, manifestURL, offset, rotation, scale, stretch, manifestPath) = (r.fit.anchor, r.asset, nil, r.fit.offset, r.fit.rotationDegrees, r.fit.scale, r.fit.stretch, false)
                } else {
                    failures.append("\(cid) · \(id): no 3D fit")
                    continue
                }
                guard let anchor = character.findEntity(named: anchorName) else {
                    failures.append("\(cid) · \(id): anchor \(anchorName) missing")
                    continue
                }
                let item = try await load(assetName, manifestURL: manifestURL)
                item.name = "Fit_\(id)"
                MolibooFitValidator.apply(item: item, to: anchor, offset: offset, rotationDegrees: rotation, scale: scale, stretch: stretch, manifestCorrection: manifestPath)
                let kind = MolibooFitKind.of(itemID: id, slot: slot, anchor: anchorName)
                let m = MolibooFitValidator.measure(item: item, body: body, kind: kind, slot: slot, maxPerPart: 600)
                item.removeFromParent()
                if !m.passed {
                    failures.append("\(cid) · \(id) [\(kind.rawValue)]: " + m.failures.joined(separator: ", "))
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Wardrobe fit failures:\n" + failures.joined(separator: "\n"))
    }

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
