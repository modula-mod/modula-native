import XCTest
import RealityKit
@testable import Modula

/// MOL-02 Milestone A: Pip (#001) through the generic, manifest-driven 3D path.
@MainActor
final class MOL02Tests: XCTestCase {
    private let capID = MolibooCosmetics.signatureCapID

    func testPipManifestEntry() throws {
        let m = try MolibooManifest.bundled(.main)
        let p = try XCTUnwrap(m.character(id: "pip"))
        XCTAssertEqual(p.canonicalNumber, 1)
        XCTAssertEqual(p.asset, "Pip")
        XCTAssertEqual(p.sourceVersion, "pip-v1.0")
        XCTAssertEqual(p.assetSHA256, "2c6a54a9a8b6bc690f41bb9afe1355ec30d73b3cf752b73b6a6f5ad9644a08ef")
        XCTAssertEqual(Set(p.expressions), Set(MolibooExpression.allCases))
        for e in MolibooExpression.allCases { XCTAssertNotNil(p.clips[e.clipName], "missing clip \(e.clipName)") }
        for c in ["idle_bob", "wobble", "tap", "gill_flutter", "exuberant_bounce"] { XCTAssertNotNil(p.clips[c], c) }
        guard case .compatible(let cfg) = m.compatibility(item: capID, character: "pip") else { return XCTFail("Pip wears the Signature Cap") }
        XCTAssertEqual(cfg.anchor, "anchor_head")
        XCTAssertEqual(m.compatibility(item: "hat.party", character: "pip"), .notCompatible)
    }

    func testRegistryIsGenericAndRequiresBundledAsset() throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        XCTAssertTrue(MolibooRegistry.has3D("pip"))
        XCTAssertTrue(MolibooRegistry.has3D("pebble"))
        XCTAssertTrue(MolibooRegistry.has3D("moss"))
        XCTAssertTrue(MolibooRegistry.has3D("tofu"))
        XCTAssertTrue(MolibooRegistry.has3D("bolt"))
        XCTAssertFalse(MolibooRegistry.has3D("bloop"), "no asset yet ⇒ 2D")
        XCTAssertFalse(MolibooRegistry.has3D("unknown"))
        XCTAssertEqual(Set(MolibooRegistry.available3D.map(\.id)), ["pip", "moss", "pebble", "tofu", "bolt", "nimbus", "mochi", "sprout", "ember", "tuck"])
        // Manifest says there is an asset but the file is not bundled ⇒ no 3D (2D fallback), never another character.
        let ghost = MolibooCharacterDescriptor(id: "ghost", canonicalNumber: 99, displayName: "Ghost", family: "test", asset: "Ghost_NotBundled",
                                               assetSHA256: nil, sourceVersion: nil, anchors: [], expressions: [], fps: 30, clips: [:], attachments: [:])
        let m = MolibooManifest(schemaVersion: 2, cosmetics: [], characters: [ghost])
        XCTAssertNil(MolibooRegistry.descriptor(for: "ghost", manifest: m))
    }

    func testMissingAssetFailsLoadInsteadOfFallingBackToPebble() async {
        let ghost = MolibooCharacterDescriptor(id: "ghost", canonicalNumber: 99, displayName: "Ghost", family: "test", asset: "Ghost_NotBundled",
                                               assetSHA256: nil, sourceVersion: nil, anchors: [], expressions: [], fps: 30, clips: [:], attachments: [:])
        let c = MolibooSceneController(descriptor: ghost)
        await c.load()
        XCTAssertTrue(c.loadFailed)
        XCTAssertNil(c.character)
        c.stop()
    }

    func testPipLoadsAnimatesExpressesAndWearsCap() async throws {
        try requireBundledMoliboo3D(["pip"])
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "pip", manifest: m))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        defer { c.stop() }
        XCTAssertFalse(c.loadFailed)
        XCTAssertEqual(c.character?.name, "Pip_Root")
        XCTAssertNotNil(c.character?.findEntity(named: "Pip_Body"))
        XCTAssertNil(c.character?.findEntity(named: "Pebble_Body"), "must be Pip, not Pebble")
        for a in d.anchors { XCTAssertNotNil(c.anchor(a), "missing \(a)") }
        XCTAssertFalse(c.character?.availableAnimations.isEmpty ?? true)
        for clip in ["idle_bob", "blink", "wobble", "tap", "gill_flutter", "exuberant_bounce"] { XCTAssertTrue(c.playClip(clip), clip) }
        for e in MolibooExpression.allCases where e != .blink {
            c.setExpression(e); XCTAssertEqual(c.expression, e); XCTAssertEqual(c.lastAction, "clip:" + e.clipName)
        }
        c.react(); XCTAssertEqual(c.reactCount, 1)

        let ok = await c.equip(wardrobeItemID: capID)
        XCTAssertTrue(ok)
        let cap = try XCTUnwrap(c.equipped[capID])
        XCTAssertEqual(cap.parent?.name, "anchor_head")
        c.yaw = 1.2
        XCTAssertEqual(cap.parent?.name, "anchor_head")
        c.unequip(wardrobeItemID: capID)
        XCTAssertNil(c.equipped[capID])
    }

    // MARK: Moss (#002)

    func testMossManifestEntry() throws {
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(m.character(id: "moss"))
        XCTAssertEqual(d.canonicalNumber, 2)
        XCTAssertEqual(d.asset, "Moss")
        XCTAssertEqual(d.sourceVersion, "moss-v1.0")
        XCTAssertEqual(d.assetSHA256, "9bb82d67d154d166f3e478ebb1d9de5525e1206ed13ef93174fff3c3828225cd")
        XCTAssertEqual(Set(d.expressions), Set(MolibooExpression.allCases))
        for c in ["idle_bob", "wobble", "tap", "slow_blink", "cheek_puff", "measured_hop"] { XCTAssertNotNil(d.clips[c], c) }
        XCTAssertNil(d.clips["gill_flutter"], "Pip's personality must not leak into Moss")
        guard case .compatible(let cfg) = m.compatibility(item: capID, character: "moss") else { return XCTFail("Moss wears the Signature Cap") }
        XCTAssertEqual(cfg.anchor, "anchor_head")
    }

    func testMossLoadsAnimatesExpressesAndWearsCap() async throws {
        try requireBundledMoliboo3D(["moss"])
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "moss", manifest: m))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        defer { c.stop() }
        XCTAssertFalse(c.loadFailed)
        XCTAssertEqual(c.character?.name, "Moss_Root")
        XCTAssertNotNil(c.character?.findEntity(named: "Moss_Body"))
        XCTAssertNil(c.character?.findEntity(named: "Pebble_Body"))
        XCTAssertNil(c.character?.findEntity(named: "Pip_Body"))
        for a in d.anchors { XCTAssertNotNil(c.anchor(a), "missing \(a)") }
        for clip in ["idle_bob", "blink", "wobble", "tap", "slow_blink", "cheek_puff", "measured_hop"] { XCTAssertTrue(c.playClip(clip), clip) }
        for e in MolibooExpression.allCases where e != .blink {
            c.setExpression(e); XCTAssertEqual(c.lastAction, "clip:" + e.clipName)
        }
        let ok = await c.equip(wardrobeItemID: capID)
        XCTAssertTrue(ok)
        XCTAssertEqual(c.equipped[capID]?.parent?.name, "anchor_head")
        c.unequip(wardrobeItemID: capID)
        XCTAssertNil(c.equipped[capID])
    }

    // MARK: Tofu (#011)

    func testTofuManifestEntry() throws {
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(m.character(id: "tofu"))
        XCTAssertEqual(d.canonicalNumber, 11)
        XCTAssertEqual(d.asset, "Tofu")
        XCTAssertEqual(d.sourceVersion, "tofu-v1.0")
        XCTAssertEqual(d.assetSHA256, "dfcca4619f22d33bdf60f13eb44eb33df663927abc20109aa15b16a494834823")
        XCTAssertEqual(Set(d.expressions), Set(MolibooExpression.allCases))
        for c in ["idle_bob", "wobble", "tap", "cube_squash", "exuberant_bounce"] { XCTAssertNotNil(d.clips[c], c) }
        guard case .compatible(let cfg) = m.compatibility(item: capID, character: "tofu") else { return XCTFail("Tofu wears the Signature Cap") }
        XCTAssertEqual(cfg.anchor, "anchor_head")
    }

    func testTofuIsACubeLoadsSquashesAndWearsCap() async throws {
        try requireBundledMoliboo3D(["tofu"])
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "tofu", manifest: m))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        defer { c.stop() }
        XCTAssertFalse(c.loadFailed)
        XCTAssertEqual(c.character?.name, "Tofu_Root")
        let body = try XCTUnwrap(c.character?.findEntity(named: "Tofu_Body"))
        XCTAssertNil(c.character?.findEntity(named: "Pebble_Body"))
        // Cube check: a rounded cube fills most of its bounding box (a sphere fills ~52%).
        let e = body.visualBounds(relativeTo: body).extents
        XCTAssertLessThan(max(e.x, e.y, e.z) / min(e.x, e.y, e.z), 1.35, "roughly equal sides")
        if let mesh = body.components[ModelComponent.self]?.mesh {
            let b = mesh.bounds.extents
            XCTAssertGreaterThan(b.x * b.y * b.z, 0)
        }
        for a in d.anchors { XCTAssertNotNil(c.anchor(a), "missing \(a)") }
        for clip in ["idle_bob", "blink", "wobble", "tap", "cube_squash", "exuberant_bounce"] { XCTAssertTrue(c.playClip(clip), clip) }
        for x in MolibooExpression.allCases where x != .blink { c.setExpression(x); XCTAssertEqual(c.lastAction, "clip:" + x.clipName) }
        let ok = await c.equip(wardrobeItemID: capID)
        XCTAssertTrue(ok)
        XCTAssertEqual(c.equipped[capID]?.parent?.name, "anchor_head")
        c.unequip(wardrobeItemID: capID)
    }

    // MARK: Bolt (#014)

    func testBoltManifestEntry() throws {
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(m.character(id: "bolt"))
        XCTAssertEqual(d.canonicalNumber, 14)
        XCTAssertEqual(d.asset, "Bolt")
        XCTAssertEqual(d.sourceVersion, "bolt-v1.0")
        XCTAssertEqual(d.assetSHA256, "7565bb3e3f5aad138313c615f254b2b14b7426e98131c95b4d93b33951a54ec3")
        XCTAssertEqual(Set(d.expressions), Set(MolibooExpression.allCases))
        for c in ["idle_bob", "wobble", "tap", "antenna_flash", "servo_tilt"] { XCTAssertNotNil(d.clips[c], c) }
        guard case .compatible(let cfg) = m.compatibility(item: capID, character: "bolt") else { return XCTFail("Bolt wears the Signature Cap") }
        XCTAssertEqual(cfg.anchor, "anchor_head")
    }

    func testBoltRobotPartsLoadAnimateAndWearCap() async throws {
        try requireBundledMoliboo3D(["bolt"])
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "bolt", manifest: m))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        defer { c.stop() }
        XCTAssertFalse(c.loadFailed)
        XCTAssertEqual(c.character?.name, "Bolt_Root")
        for part in ["Bolt_Body", "Bolt_Screen", "Bolt_AntennaStalk", "Bolt_AntennaTip", "Bolt_Bolt_L", "Bolt_Bolt_R", "Bolt_Eye_L", "Bolt_Eye_R"] {
            XCTAssertNotNil(c.character?.findEntity(named: part), "missing \(part)")
        }
        XCTAssertNil(c.character?.findEntity(named: "Pebble_Body"))
        for a in d.anchors { XCTAssertNotNil(c.anchor(a), "missing \(a)") }
        for clip in ["idle_bob", "blink", "wobble", "tap", "antenna_flash", "servo_tilt"] { XCTAssertTrue(c.playClip(clip), clip) }
        for x in MolibooExpression.allCases where x != .blink { c.setExpression(x); XCTAssertEqual(c.lastAction, "clip:" + x.clipName) }
        let ok = await c.equip(wardrobeItemID: capID)
        XCTAssertTrue(ok)
        XCTAssertEqual(c.equipped[capID]?.parent?.name, "anchor_head")
        c.unequip(wardrobeItemID: capID)
    }

    // MARK: MOL-03 Workstream B: renderer benchmark + lifecycle

    func testRendererBenchmarkSevenPoints() async throws {
        try requireBundledMoliboo3D(["pip", "moss", "tofu", "bolt"])
        let s = await MolibooRendererBenchmark.run(primary: "pebble", secondary: "pip")
        let json = String(data: try JSONEncoder().encode(s), encoding: .utf8) ?? ""
        print("MOLBENCH " + json)
        XCTAssertGreaterThan(s.coldLoadMs, 0)
        XCTAssertLessThanOrEqual(s.coldLoadMs, 1500, "cold load target")
        XCTAssertLessThanOrEqual(s.warmLoadMs, 750, "warm load target")
        XCTAssertGreaterThanOrEqual(s.cacheHits, 1, "warm reopen must hit the template cache")
    }

    func testTemplateCacheIsBounded() async throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        MolibooAssetLoader.purge()
        for id in ["pebble", "pip", "moss", "tofu", "bolt"] {
            guard let d = MolibooRegistry.descriptor(for: id), let a = d.asset else { continue }
            _ = try await MolibooAssetLoader.loadEntity(a)
        }
        let cached = ["Pebble", "Pip", "Moss", "Tofu", "Bolt"].filter(MolibooAssetLoader.isCached)
        XCTAssertLessThanOrEqual(cached.count, MolibooAssetLoader.characterCapacity)
        XCTAssertTrue(MolibooAssetLoader.isCached("Bolt"), "most recent stays cached")
    }

    func testCharacterSwitchTearsDownPrevious() async throws {
        try requireBundledMoliboo3D(["pip", "moss"])
        let m = try XCTUnwrap(MolibooRegistry.manifest)
        let a = MolibooSceneController(descriptor: try XCTUnwrap(MolibooRegistry.descriptor(for: "pebble", manifest: m)))
        a.cosmetics = m.cosmetics
        await a.load()
        let scene = Entity(); scene.addChild(a.root)
        let b = MolibooSceneController(descriptor: try XCTUnwrap(MolibooRegistry.descriptor(for: "tofu", manifest: m)))
        b.cosmetics = m.cosmetics
        a.stop()
        await b.load()
        XCTAssertNil(a.root.parent, "previous character detached on switch")
        XCTAssertTrue(a.isStopped)
        let before = a.clipsPlayed
        a.react(); a.wobble(); a.setExpression(.happy)
        XCTAssertEqual(a.clipsPlayed, before, "no-op after stop")
        XCTAssertNotNil(b.character)
        b.stop()
    }

    func testLoadAfterStopDoesNotAttach() async throws {
        try requireBundledMoliboo3D(["pip"])
        MolibooAssetLoader.purge()
        let m = try XCTUnwrap(MolibooRegistry.manifest)
        let c = MolibooSceneController(descriptor: try XCTUnwrap(MolibooRegistry.descriptor(for: "moss", manifest: m)))
        let t = Task { await c.load() }
        c.stop()
        t.cancel()
        await t.value
        XCTAssertNil(c.character, "stopped/cancelled load must not attach")
        XCTAssertTrue(c.root.children.isEmpty)
    }

    func testNoPlaybackOrEquipAfterStop() async throws {
        try requireBundledMoliboo3D(["pip"])
        let m = try XCTUnwrap(MolibooRegistry.manifest)
        let c = MolibooSceneController(descriptor: try XCTUnwrap(MolibooRegistry.descriptor(for: "pebble", manifest: m)))
        c.cosmetics = m.cosmetics
        await c.load()
        c.stop()
        XCTAssertFalse(c.playClip("idle_bob"))
        let equipped = await c.equip(wardrobeItemID: MolibooCosmetics.signatureCapID)
        XCTAssertFalse(equipped)
    }
}
