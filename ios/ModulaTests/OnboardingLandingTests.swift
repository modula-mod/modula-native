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

    func testPoolCoversEveryLiveParticleWithoutSlotCollisions() {
        let pool = OnboardingLanding.Emitter.poolSize
        for time in stride(from: 0.0, through: 200, by: 0.37) {
            let range = emitter.liveRange(at: time)
            XCTAssertLessThanOrEqual(range.count, pool, "Live range fits the fixed pool")
            let alive = range.filter { emitter.state(of: emitter.particle($0), at: time) != nil }
            let slots = alive.map(OnboardingLanding.Emitter.slot(for:))
            XCTAssertEqual(Set(slots).count, slots.count, "Two live bubbles never share a slot")
            XCTAssertTrue(slots.allSatisfy { (0..<pool).contains($0) })
        }
    }

    func testStreamIsQuickAndPopIsSnappy() throws {
        XCTAssertLessThanOrEqual(emitter.interval, 0.18, "At least ~5.5 spawns a second")
        XCTAssertLessThanOrEqual(emitter.maxLifetime, 5.5, "Crosses the screen in a few seconds")
        for index in 0..<100 {
            let p = emitter.particle(index)
            let early = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime + 0.4))
            XCTAssertLessThan(early.position.y, -emitter.pop * 0.6, "Mostly clear of the + within 0.4 s (index \(index))")
        }
    }

    func testMotionIsContinuousInTime() throws {
        // At 120 fps nothing should jump: per-frame movement stays small and smooth.
        let dt = 1.0 / 120
        for index in 0..<60 {
            let p = emitter.particle(index)
            var previous = try XCTUnwrap(emitter.state(of: p, at: p.spawnTime))
            var t = p.spawnTime + dt
            while t < p.spawnTime + p.lifetime {
                let s = try XCTUnwrap(emitter.state(of: p, at: t))
                XCTAssertLessThan(hypot(s.position.x - previous.position.x, s.position.y - previous.position.y), 8, "No positional jump")
                XCTAssertLessThan(abs(s.scale - previous.scale), 0.05)
                XCTAssertLessThan(abs(s.opacity - previous.opacity), 0.08)
                previous = s
                t += dt
            }
        }
    }

    func testLightBackdropIsBrightAndColourful() {
        let backdrop = OnboardingLanding.Backdrop.self
        XCTAssertEqual(backdrop.lightColors.count, backdrop.width * backdrop.height)
        XCTAssertEqual(backdrop.colors(dark: true), backdrop.colors)
        XCTAssertEqual(backdrop.colors(dark: false), backdrop.lightColors)
        func rgb(_ hex: String) -> (Double, Double, Double) {
            let v = UInt32(hex.dropFirst(), radix: 16)!
            return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        func luminance(_ hex: String) -> Double { let c = rgb(hex); return 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
        func saturation(_ hex: String) -> Double { let c = rgb(hex); let hi = max(c.0, c.1, c.2), lo = min(c.0, c.1, c.2); return hi == 0 ? 0 : (hi - lo) / hi }
        // Bottom row stays near-white for the dark headline and button.
        for hex in backdrop.lightColors.suffix(backdrop.width) { XCTAssertGreaterThan(luminance(hex), 0.9) }
        // Middle rows carry colour for the glass to refract.
        let middle = backdrop.lightColors[backdrop.width..<(backdrop.width * 3)]
        XCTAssertGreaterThan(middle.map(saturation).reduce(0, +) / Double(middle.count), 0.25)
        XCTAssertGreaterThan(backdrop.lightColors.map(luminance).reduce(0, +) / 16, 0.6, "Light mode is bright")
        XCTAssertLessThan(backdrop.colors.map(luminance).reduce(0, +) / 16, 0.2, "Dark mode stays dark")
    }
}
