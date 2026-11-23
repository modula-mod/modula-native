import XCTest
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

    func testMissingAssetFailsLoadInsteadOfFallingBackToPebble() async {
        let ghost = MolibooCharacterDescriptor(id: "ghost", canonicalNumber: 99, displayName: "Ghost", family: "test", asset: "Ghost_NotBundled",
                                               assetSHA256: nil, sourceVersion: nil, anchors: [], expressions: [], fps: 30, clips: [:], attachments: [:])
        let c = MolibooSceneController(descriptor: ghost)
        await c.load()
        XCTAssertTrue(c.loadFailed)
        XCTAssertNil(c.character)
        c.stop()
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

    // MARK: MOL-03 Workstream B: renderer benchmark + lifecycle

}
