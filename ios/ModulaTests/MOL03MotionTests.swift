import XCTest
import SwiftUI
@testable import Modula

/// MOL-03C: one shared engine, family motion languages, deterministic, interruptible, Reduce Motion-safe, bounded.
@MainActor
final class MOL03MotionTests: XCTestCase {
    private var reg: MolibooCharacterRegistry { MolibooRegistryStore.bundled! }

    func testEveryCharacterAnimatesFromItsFamilyProfile() throws {
        for c in reg.characters {
            let p = try XCTUnwrap(reg.motionProfiles[c.motionProfile], c.key)
            let frames = stride(from: 0.0, to: 6.0, by: 0.25).map { MolibooMotionEngine.frame(profile: p, t: $0, seed: Double(c.number), reduceMotion: false) }
            XCTAssertGreaterThan(Set(frames.map { "\($0.offset)\($0.rotation)\($0.scale)\($0.squash)" }).count, 4, "\(c.key) idle must move")
        }
    }

    func testFamiliesHaveDistinctMotionLanguages() {
        var signatures: [String: [Double]] = [:]
        for f in reg.families {
            let p = reg.motionProfiles[f.motionProfile]!
            signatures[f.id] = stride(from: 0.0, to: 8.0, by: 0.2).map {
                let fr = MolibooMotionEngine.frame(profile: p, t: $0, reduceMotion: false)
                return Double(fr.offset.height) * 10 + fr.rotation + Double(fr.scale - 1) * 100 + Double(fr.offset.width) * 7
            }
        }
        let ids = Array(signatures.keys)
        for i in ids.indices { for j in ids.indices where j > i {
            XCTAssertNotEqual(signatures[ids[i]], signatures[ids[j]], "\(ids[i]) and \(ids[j]) move identically")
        } }
    }

    func testDeterministicForTests() {
        let p = reg.motionProfiles["stardust.orbit"]!
        XCTAssertEqual(MolibooMotionEngine.frame(profile: p, t: 2.5, seed: 3, reduceMotion: false), MolibooMotionEngine.frame(profile: p, t: 2.5, seed: 3, reduceMotion: false))
    }

    func testReduceMotionNeverMovesTheBody() {
        for c in reg.characters {
            let p = reg.motionProfiles[c.motionProfile]!
            for t in stride(from: 0.0, to: 5.0, by: 0.3) {
                let r = c.reactions["tap"].map { MolibooReactionPlayback(name: "tap", reaction: $0, start: 0) }
                let f = MolibooMotionEngine.frame(profile: p, t: t, seed: 1, reaction: r, reduceMotion: true)
                XCTAssertEqual(f.offset, .zero, c.key); XCTAssertEqual(f.rotation, 0, c.key)
                XCTAssertEqual(f.scale, 1, c.key); XCTAssertEqual(f.squash, 1, c.key)
            }
        }
    }

    func testReactionsInterruptAndReturnToRest() throws {
        let c = try XCTUnwrap(reg.character(key: "pip"))
        let p = reg.motionProfiles[c.motionProfile]!
        let tap = MolibooReactionPlayback(name: "tap", reaction: c.reactions["tap"]!, start: 10)
        XCTAssertEqual(MolibooMotionEngine.frame(profile: p, t: 10.3, reaction: tap, reduceMotion: false).mood, MolibooReactionMoods.mood(named: c.reactions["tap"]!.mood))
        let long = MolibooReactionPlayback(name: "longPress", reaction: c.reactions["longPress"]!, start: 10.4)   // interrupts tap
        XCTAssertEqual(MolibooMotionEngine.frame(profile: p, t: 10.5, reaction: long, reduceMotion: false).mood, MolibooReactionMoods.mood(named: c.reactions["longPress"]!.mood))
        XCTAssertTrue(long.isFinished(at: 10.4 + Double(long.reaction.durationMs) / 1000 + 0.01))
        XCTAssertEqual(MolibooMotionEngine.frame(profile: p, t: 30, reaction: long, reduceMotion: false).mood, .idle, "finished reactions return to idle")
    }

    func testOnlyOneActiveExpensiveRenderer() {
        let b = MolibooActiveRendererBudget()
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { _ = b.claim(id) }
        XCTAssertEqual(b.active, [ids[4]])
        XCTAssertLessThanOrEqual(b.peak, MolibooActiveRendererBudget.limit)
        b.release(ids[4])
        XCTAssertTrue(b.active.isEmpty)
    }

    func testAnimatedFigureRendersForEveryCharacter() {
        for kind in ModulaMascotKind.allCases {
            let r = ImageRenderer(content: MolibooAnimatedFigure(kind: kind, size: 48, greetOnAppear: false))
            r.scale = 1
            XCTAssertNotNil(r.cgImage, kind.rawValue)
        }
    }
}
