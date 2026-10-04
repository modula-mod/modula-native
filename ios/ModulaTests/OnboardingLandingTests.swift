import UIKit
import XCTest
@testable import Modula

final class OnboardingLandingTests: XCTestCase {
    private let emitter = OnboardingLanding.Emitter()

    func testModulesUseRealSymbolsAndIncludeCoreModules() {
        let modules = OnboardingLanding.modules
        XCTAssertEqual(Set(modules.map(\.id)).count, modules.count)
        for module in modules {
            XCTAssertNotNil(UIImage(systemName: module.symbol), "Missing SF Symbol \(module.symbol)")
        }
        let titles = Set(modules.map(\.title))
        for name in ["Vault Notes", "Tasks", "CRM", "Camera Director"] {
            XCTAssertTrue(titles.contains(name), "\(name) bubble missing")
            XCTAssertTrue(OnboardingLanding.accessibilitySummary.contains(name))
        }
    }

    func testEmitterIsDeterministicPerSeed() {
        for index in [0, 1, 7, 250, 10_000] {
            XCTAssertEqual(emitter.particle(index), emitter.particle(index))
        }
        var other = emitter
        other.seed = 42
        let differs = (0..<20).contains { emitter.particle($0).diameter != other.particle($0).diameter }
        XCTAssertTrue(differs, "A different seed should give a different stream")
    }

    func testBubblesAreBornSmallAtThePlusAndExitOffTheTop() throws {
        for index in 0..<200 {
            let p = emitter.particle(index)
            let birth = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime))
            XCTAssertEqual(birth.scale, OnboardingLanding.Emitter.birthScale, accuracy: 0.0001)
            XCTAssertLessThan(hypot(birth.position.x, birth.position.y), 30, "Born on the + (index \(index))")
            XCTAssertEqual(birth.opacity, 0, accuracy: 0.0001, "Fades in")

            // Pops clear of the + quickly (ease-out), then floats.
            let popped = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime + 1.2))
            XCTAssertLessThan(popped.position.y, -emitter.pop * 0.85, "Pops out of the + (index \(index))")

            // Just before the end of life (floating point keeps the exact end ambiguous).
            let exit = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime + p.lifetime - 1e-6))
            XCTAssertLessThan(exit.position.y, -emitter.rise + 30, "Leaves through the top (index \(index))")
            XCTAssertEqual(exit.scale, 1, accuracy: 0.001)
            XCTAssertNil(emitter.state(of: p, at: p.spawnTime - 0.01))
            XCTAssertNil(emitter.state(of: p, at: p.spawnTime + p.lifetime + 0.01))
        }
    }

    func testStateStaysWithinBounds() {
        let maxStretch = OnboardingLanding.Emitter.maxStretch
        for index in 0..<120 {
            let p = emitter.particle(index)
            XCTAssertTrue((0...1).contains(p.depth))
            XCTAssertTrue((emitter.minLifetime * 0.8...emitter.maxLifetime).contains(p.lifetime))
            for step in 0...40 {
                guard let s = emitter.state(of: p, at: p.spawnTime + p.lifetime * Double(step) / 40) else { continue }
                XCTAssertTrue((OnboardingLanding.Emitter.birthScale...1).contains(s.scale))
                XCTAssertTrue((0...1).contains(s.opacity))
                XCTAssertGreaterThanOrEqual(s.blur, 0)
                XCTAssertTrue((1 - maxStretch...1 + maxStretch).contains(s.stretch))
                XCTAssertLessThanOrEqual(abs(s.tilt), 0.3)
                XCTAssertLessThanOrEqual(abs(s.position.x), 230, "Stays near the screen width")
                XCTAssertLessThanOrEqual(s.position.y, 20, "Only flies up")
            }
        }
    }

    func testBirthSquashAndStretchSettles() throws {
        for index in 0..<60 {
            let p = emitter.particle(index)
            let birth = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime))
            XCTAssertGreaterThan(birth.stretch, 1.1, "Pinches off the + stretched")
            let later = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime + 3))
            XCTAssertEqual(later.stretch, 1, accuracy: 0.04, "Wobble settles to a faint jiggle")
        }
    }

    func testDepthMakesNearBubblesBiggerAndFaster() {
        let particles = (0..<400).map(emitter.particle).filter { if case .module = $0.kind { true } else { false } }
        let near = particles.filter { $0.depth > 0.7 }, far = particles.filter { $0.depth < 0.4 }
        XCTAssertFalse(near.isEmpty)
        XCTAssertFalse(far.isEmpty)
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
        XCTAssertGreaterThan(mean(near.map(\.diameter)), mean(far.map(\.diameter)))
        XCTAssertLessThan(mean(near.map(\.lifetime)), mean(far.map(\.lifetime)))
    }

    func testNeighbouringModulesDiffer() {
        let count = OnboardingLanding.modules.count
        XCTAssertEqual(gcd(OnboardingLanding.Emitter.moduleStride, count), 1, "Stride visits every module")
        var seen = Set<Int>()
        var previous: Int?
        for index in 0..<count {
            guard case .module(let module) = emitter.particle(index).kind else { previous = nil; continue }
            seen.insert(module)
            if let previous { XCTAssertNotEqual(previous, module) }
            previous = module
        }
        XCTAssertGreaterThanOrEqual(seen.count, count / 2)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    func testLiveRangeCoversEveryVisibleParticleAndStaysSmall() {
        for time in stride(from: 0.0, through: 120, by: 0.73) {
            let range = emitter.liveRange(at: time)
            XCTAssertLessThanOrEqual(range.count, 48, "Bounded work per frame")
            // Nothing alive outside the range.
            for index in max(0, range.lowerBound - 30)..<range.lowerBound {
                XCTAssertNil(emitter.state(of: emitter.particle(index), at: time))
            }
            let next = range.upperBound + 1
            XCTAssertNil(emitter.state(of: emitter.particle(next), at: time))
        }
    }

    func testStreamIsDenseJustAboveThePlus() {
        // Count visible bubbles in the lower and upper halves of the rise over many frames.
        var low = 0, high = 0
        for time in stride(from: 20.0, through: 80, by: 0.5) {
            for index in emitter.liveRange(at: time) {
                guard let s = emitter.state(of: emitter.particle(index), at: time), s.opacity > 0.05 else { continue }
                if -s.position.y < emitter.rise / 2 { low += 1 } else { high += 1 }
            }
        }
        XCTAssertGreaterThan(low, high, "Bubbles linger near the + before flying off")
    }

    func testStaticFrameForReduceMotionIsPopulatedAndPulseIsBounded() {
        let time = OnboardingLanding.staticTime
        let visible = emitter.liveRange(at: time).filter {
            (emitter.state(of: emitter.particle($0), at: time)?.opacity ?? 0) > 0.2
        }
        XCTAssertGreaterThanOrEqual(visible.count, 8)
        for time in stride(from: 0.0, through: 30, by: 0.05) {
            XCTAssertTrue((0...1).contains(emitter.emitPulse(at: time)))
            XCTAssertTrue((-1...1).contains(OnboardingLanding.Emitter.breath(at: time)))
        }
    }

    func testBackdropMeshKeepsEdgesPinnedAndPointsInside() {
        let backdrop = OnboardingLanding.Backdrop.self
        XCTAssertEqual(backdrop.colors.count, backdrop.width * backdrop.height)
        for time in stride(from: 0.0, through: 600, by: 7.3) {
            let points = backdrop.points(at: time)
            XCTAssertEqual(points.count, backdrop.width * backdrop.height)
            for (i, point) in points.enumerated() {
                let row = i / backdrop.width, column = i % backdrop.width
                XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
                if column == 0 { XCTAssertEqual(point.x, 0) }
                if column == backdrop.width - 1 { XCTAssertEqual(point.x, 1) }
                if row == 0 { XCTAssertEqual(point.y, 0) }
                if row == backdrop.height - 1 { XCTAssertEqual(point.y, 1) }
            }
        }
        XCTAssertNotEqual(backdrop.points(at: 0), backdrop.points(at: 20), "The backdrop drifts")
    }
}
