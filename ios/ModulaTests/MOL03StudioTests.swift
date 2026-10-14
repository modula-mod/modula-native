import XCTest
@testable import Modula

@MainActor
final class MOL03StudioTests: XCTestCase {
    private let ids3D = ["pip", "moss", "pebble", "tofu", "bolt", "nimbus", "mochi", "sprout", "ember", "tuck"]

    func testFourDistinctEnvironments() {
        XCTAssertEqual(MolibooEnvironment.allCases.count, 4)
        XCTAssertEqual(Set(MolibooEnvironment.allCases.map(\.title)).count, 4)
        XCTAssertEqual(MolibooEnvironment(rawValue: "nightSky"), .nightSky)
    }

    func testPerCharacterFraming() {
        XCTAssertGreaterThan(MolibooFraming.for("bolt").target.y, MolibooFraming.for("moss").target.y, "Bolt is tall, Moss is flat")
        XCTAssertGreaterThan(MolibooFraming.for("bolt").eye.z, MolibooFraming.for("pip").eye.z)
        XCTAssertEqual(MolibooFraming.for("unknown"), .standard)
        for id in ids3D { XCTAssertGreaterThan(MolibooFraming.for(id).eye.z, 0.3) }
    }

    func testIdlePersonalitiesUseOnlyRealClips() throws {
        let m = try MolibooManifest.bundled(.main)
        for id in ids3D {
            let d = try XCTUnwrap(m.character(id: id))
            let p = MolibooIdlePersonality.for(d)
            XCTAssertFalse(p.clips.isEmpty, id)
            for c in p.clips where c != "wobble" { XCTAssertNotNil(d.clips[c], "\(id) has no clip \(c)") }
        }
        let pip = MolibooIdlePersonality.for(try XCTUnwrap(m.character(id: "pip")))
        let moss = MolibooIdlePersonality.for(try XCTUnwrap(m.character(id: "moss")))
        XCTAssertLessThan(pip.interval.upperBound, moss.interval.lowerBound, "Pip is busier than calm Moss")
    }

    func testReactionCooldownsAndGlobalGap() {
        var g = MolibooReactionGate()
        XCTAssertEqual(g.request(.tap, at: 0), .tap)
        XCTAssertNil(g.request(.tap, at: 0.3), "tap cooldown")
        XCTAssertNil(g.request(.pet, at: 0.2), "global gap")
        XCTAssertEqual(g.request(.pet, at: 0.5), .pet)
        XCTAssertNil(g.request(.pet, at: 1.2), "pet cooldown")
        XCTAssertEqual(g.request(.tap, at: 1.3), .tap)
        XCTAssertEqual(g.request(.dance, at: 2.0), .dance)
        XCTAssertNil(g.request(.dance, at: 3.0))
        XCTAssertEqual(g.request(.dance, at: 4.6), .dance)
    }

    func testTapSpamBecomesOneDizzy() {
        var g = MolibooReactionGate()
        var got: [MolibooReaction?] = []
        for i in 0..<5 { got.append(g.request(.tap, at: Double(i) * 0.7)) }
        XCTAssertEqual(got.last, .dizzy)
        XCTAssertEqual(got.compactMap { $0 }.filter { $0 == .dizzy }.count, 1)
        XCTAssertNotEqual(g.request(.tap, at: 3.6), .dizzy, "dizzy has its own cooldown and resets the spam window")
    }

    func testReducedMotionPolicy() {
        let rm = MolibooMotionPolicy(reduceMotion: true)
        XCTAssertFalse(rm.idlePersonality); XCTAssertFalse(rm.bodyMotion); XCTAssertTrue(rm.autoBlink)
        let full = MolibooMotionPolicy(reduceMotion: false)
        XCTAssertTrue(full.idlePersonality); XCTAssertTrue(full.bodyMotion)
    }

    func testDirectorSchedulesIdleRespectsReduceMotionAndNap() async throws {
        let m = try MolibooManifest.bundled(.main)
        let d = try XCTUnwrap(MolibooRegistry.descriptor(for: "pip", manifest: m))
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        await c.load()
        var now = 100.0
        let dir = MolibooStudioDirector(controller: c, reduceMotion: false, clock: { now })
        defer { dir.stop(); c.stop() }
        XCTAssertTrue(dir.fireIdle())
        XCTAssertEqual(dir.idleFired, 1)
        XCTAssertEqual(dir.request(.tap), .tap)
        XCTAssertFalse(dir.fireIdle(), "idle waits while the user's reaction plays")
        now += 2.5
        XCTAssertTrue(dir.fireIdle())
        dir.setReduceMotion(true)
        now += 5
        XCTAssertFalse(dir.fireIdle(), "no idle personality under Reduced Motion")
        XCTAssertEqual(dir.request(.peekaboo), .peekaboo, "reactions still work under Reduced Motion")
        now += 5
        XCTAssertEqual(dir.request(.nap), .nap)
        XCTAssertTrue(dir.napping)
        XCTAssertEqual(c.expression, .sleepy)
        XCTAssertEqual(dir.request(.tap), .tap)
        XCTAssertFalse(dir.napping, "tap wakes a napping Moliboo")
        dir.setPaused(true); dir.setReduceMotion(false); now += 30
        XCTAssertFalse(dir.fireIdle(), "paused (background / Style sheet)")
    }
}
