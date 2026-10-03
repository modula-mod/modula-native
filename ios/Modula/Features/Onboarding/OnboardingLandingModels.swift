import CoreGraphics
import Foundation

/// Content and motion model for the signed-out landing screen.
///
/// Liquid Glass bubbles are emitted from the central glass "+" and float up and out of
/// the top of the screen in a continuous stream over a slowly living backdrop. The
/// emitter is *stateless*: every particle is a pure function of its spawn index and a
/// seed, and its on-screen state is a pure function of time. The stream is fully
/// deterministic, which keeps it testable and lets Reduce Motion show one composed frame.
enum OnboardingLanding {
    static let headline = "A new kind of app, built from modules that get things done"
    static let continueTitle = "Let’s go"

    // MARK: Modules shown in the bubbles

    struct Module: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let symbol: String
        /// Identity colour (glass tint and symbol shade) and a lighter companion hue.
        let tint: String
        let glow: String
    }

    static let modules: [Module] = [
        Module(id: "vault-notes", title: "Vault Notes", symbol: "note.text", tint: "#2A9AA8", glow: "#9BF1E6"),
        Module(id: "tasks", title: "Tasks", symbol: "checklist", tint: "#2FA866", glow: "#C8F7A1"),
        Module(id: "crm", title: "CRM", symbol: "person.2.fill", tint: "#4A5CF0", glow: "#B7A8FF"),
        Module(id: "camera-director", title: "Camera Director", symbol: "camera.aperture", tint: "#EE7A2A", glow: "#FFD28A"),
        Module(id: "nodus", title: "Nodus intelligence", symbol: "sparkles", tint: "#8A55F2", glow: "#FFA8E8"),
        Module(id: "messages", title: "Messages", symbol: "bubble.left.and.bubble.right.fill", tint: "#2479F2", glow: "#8FE3FF"),
        Module(id: "profile", title: "Profile", symbol: "person.crop.circle.fill", tint: "#2CB39C", glow: "#B4FFD8"),
        Module(id: "games", title: "Games", symbol: "gamecontroller.fill", tint: "#E8405F", glow: "#FFB38A"),
        Module(id: "places", title: "Places", symbol: "mappin.and.ellipse", tint: "#D9A21C", glow: "#FFF3A0"),
        Module(id: "links", title: "Links", symbol: "link", tint: "#1FA9BE", glow: "#A9C8FF"),
        Module(id: "music", title: "Music", symbol: "music.note", tint: "#E0457B", glow: "#FFC2E0"),
        Module(id: "files", title: "Files", symbol: "folder.fill", tint: "#3C7BD8", glow: "#BFE1FF"),
    ]

    /// Spoken summary of the stream (it is one accessibility element).
    static var accessibilitySummary: String {
        "Modula modules flowing out of the add button: " + modules.map(\.title).joined(separator: ", ")
    }

    // MARK: Emitter

    enum Kind: Hashable, Sendable {
        case module(Int)
        case droplet
    }

    /// Immutable spawn properties of one particle.
    struct Particle: Hashable, Sendable {
        let index: Int
        let spawnTime: Double
        let lifetime: Double
        let kind: Kind
        /// Full-grown diameter on a 390 pt wide reference screen.
        let diameter: Double
        /// 0 (far: small, slow, faint) … 1 (near: big, fast, crisp).
        let depth: Double
        /// Birth offset from the + centre, in reference points.
        let birthOffset: CGSize
        /// Final horizontal travel (signed), in reference points.
        let drift: Double
        let swayAmplitude: Double
        let swayFrequency: Double
        let swayPhase: Double
    }

    /// Per-frame state of one particle, relative to the + centre (reference points, up is negative y).
    struct ParticleState: Equatable, Sendable {
        var position: CGPoint
        var scale: Double
        var opacity: Double
        /// Softening for far particles (used by the non-glass fallback only; glass stays sharp).
        var blur: Double
        /// Vertical stretch of the bubble (>1 tall, <1 squashed); the view scales height by
        /// `sqrt(stretch)` and width by `1 / sqrt(stretch)`, so area is preserved. Pinches off the + stretched, then wobbles and settles to 1.
        var stretch: Double
        /// Tilt (radians) of the stretch axis, following the direction of travel.
        var tilt: Double
    }

    struct Emitter: Sendable {
        var seed: UInt64 = 0x6D6F_6475_6C61 // "modula"
        /// Mean time between spawns (seconds).
        var interval: Double = 0.24
        var minLifetime: Double = 6.0
        var maxLifetime: Double = 9.6
        /// Distance from the + centre to just past the top edge (reference points).
        var rise: Double = 560
        /// How far a newborn bubble pops out of the + before it starts to float (reference points).
        var pop: Double = 70
        /// Fraction of particles that are tiny clear droplets.
        var dropletShare: Double = 0.34

        /// Step between the modules of consecutive spawns (coprime with the module count).
        static let moduleStride = 5
        /// Smallest scale at birth.
        static let birthScale = 0.2
        /// Largest squash/stretch either way.
        static let maxStretch = 0.2
        /// While younger than this a bubble is still emerging from the + (the view draws
        /// it underneath the +, so it is first seen through the +'s glass).
        static let birthWindow = 0.95

        func particle(_ index: Int) -> Particle {
            var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)
            let jitter = rng.unit()
            let isDroplet = rng.unit() < dropletShare
            _ = rng.next()
            // Walk the modules in a fixed stride (coprime with the count) so neighbours in
            // the stream are always different modules and every module keeps appearing.
            let count = OnboardingLanding.modules.count
            let moduleIndex = (index * Emitter.moduleStride) % count
            let depth = isDroplet ? 0.15 + 0.6 * rng.unit() : 0.2 + 0.8 * rng.unit()
            let diameter = isDroplet ? 10 + 18 * rng.unit() : 38 + 74 * depth * (0.78 + 0.22 * rng.unit())
            // Far particles rise slower.
            let lifetime = maxLifetime - (maxLifetime - minLifetime) * depth * (0.8 + 0.2 * rng.unit())
            // Alternate sides (with the odd surprise) so the stream fans out evenly.
            let side = (index.isMultiple(of: 2) ? 1.0 : -1.0) * (rng.unit() < 0.18 ? -1 : 1)
            let spread = side * (16 + 160 * pow(rng.unit(), 0.8))
            return Particle(
                index: index,
                spawnTime: Double(index) * interval + jitter * interval * 0.7,
                lifetime: lifetime,
                kind: isDroplet ? .droplet : .module(moduleIndex),
                diameter: diameter,
                depth: depth,
                birthOffset: CGSize(width: (rng.unit() - 0.5) * 30, height: (rng.unit() - 0.5) * 12),
                drift: spread,
                swayAmplitude: 5 + 14 * rng.unit(),
                swayFrequency: 0.35 + 0.5 * rng.unit(),
                swayPhase: rng.unit() * 2 * .pi
            )
        }

        /// Spawn indices that can be alive at `time`.
        func liveRange(at time: Double) -> ClosedRange<Int> {
            let upper = max(0, Int(floor(time / interval)))
            let lower = max(0, Int(floor((time - maxLifetime) / interval)) - 1)
            return lower...upper
        }

        /// State at `time`, or `nil` before birth / after exit.
        func state(of p: Particle, at time: Double) -> ParticleState? {
            let age = time - p.spawnTime
            guard age >= 0, age <= p.lifetime else { return nil }
            let t = age / p.lifetime
            // Buoyant: pops out of the + with an ease-out, lingers just above it (dense
            // stream), then accelerates up and out of the top.
            let popOut = pop * (1 - exp(-age * 2.6))
            let climb = pow(t, 1.75)
            // Rise as a column straight out of the +, then spread wider as they climb.
            let fan = smoothstep(0.03, 0.78, t)
            let swayIn = smoothstep(0.04, 0.3, t)
            let sway = p.swayAmplitude * sin(age * p.swayFrequency * .pi + p.swayPhase) * swayIn
            let x = Double(p.birthOffset.width) * (1 - fan) + p.drift * fan + sway
            let y = Double(p.birthOffset.height) - popOut - (rise - pop) * climb - 14 * fan
            // Born small at the +, grow as they leave it.
            let grow = smoothstep(0, 0.24, t)
            let scale = Emitter.birthScale + (1 - Emitter.birthScale) * grow
            // Pinches off the + stretched, then a damped squash/stretch wobble and a faint
            // living jiggle.
            let pinch = 0.17 * exp(-age * 1.9) * cos(age * 8.6)
            let jiggle = 0.025 * sin(age * (2.4 + p.swayFrequency) + p.swayPhase)
            let stretch = 1 + max(-Emitter.maxStretch, min(Emitter.maxStretch, pinch + jiggle))
            // Lean slightly into the sideways motion.
            let tilt = 0.22 * (p.drift / 176) * (1 - smoothstep(0.2, 0.7, t)) + 0.04 * sin(age * 1.3 + p.swayPhase)
            let fadeIn = smoothstep(0, 0.05, t)
            let fadeOut = 1 - smoothstep(0.88, 1, t)
            let depthAlpha = 0.6 + 0.4 * p.depth
            return ParticleState(
                position: CGPoint(x: x, y: y),
                scale: scale,
                opacity: fadeIn * fadeOut * depthAlpha,
                blur: p.kind == .droplet ? 0 : max(0, (0.45 - p.depth) * 4),
                stretch: stretch,
                tilt: tilt
            )
        }

        /// Fraction (0…1) of an emission pulse for the + bubble: peaks right after a spawn.
        func emitPulse(at time: Double) -> Double {
            let index = Int(floor(time / interval))
            var best = 0.0
            for i in max(0, index - 1)...index + 1 {
                let since = time - particle(i).spawnTime
                if since >= 0 { best = max(best, exp(-since * 6)) }
            }
            return best
        }

        /// Slow breathing of the + (−1…1) layered under the emission pulses.
        static func breath(at time: Double) -> Double { sin(time * 2 * .pi / 3.6) }
    }

    /// Composed frame shown under Reduce Motion (a well-populated moment of the stream).
    static let staticTime: Double = 41.3
    /// The live stream starts this far in, so the screen is already full on appear.
    static let warmUp: Double = 6.5

    // MARK: Backdrop

    /// The living mesh-gradient backdrop the glass refracts: a 4×4 mesh whose inner
    /// points drift slowly on Lissajous paths. Edge points stay on the edges.
    enum Backdrop {
        static let width = 4
        static let height = 4

        /// Dark Modula palette, row by row (top → bottom). Deep ink at the top, colour
        /// fields through the middle, a teal/violet glow pooling behind the +, dark at the
        /// bottom so the white headline and button keep strong contrast.
        static let colors: [String] = [
            "#05080F", "#0B1030", "#150B2A", "#05080F",
            "#0A2A3A", "#1B2C7A", "#4A1F6E", "#0B1A3A",
            "#0E5A5E", "#2A3FA8", "#7A2C7E", "#173E80",
            "#030608", "#071417", "#0A0D1C", "#030608",
        ]

        static func points(at time: Double) -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            result.reserveCapacity(width * height)
            for row in 0..<height {
                for column in 0..<width {
                    var x = Double(column) / Double(width - 1)
                    var y = Double(row) / Double(height - 1)
                    let seed = Double(row * width + column)
                    let isEdgeX = column == 0 || column == width - 1
                    let isEdgeY = row == 0 || row == height - 1
                    if !isEdgeX { x += 0.09 * sin(time * (0.11 + 0.013 * seed) + seed * 1.7) }
                    if !isEdgeY { y += 0.07 * cos(time * (0.09 + 0.011 * seed) + seed * 2.3) }
                    result.append(SIMD2(Float(x), Float(y)))
                }
            }
            return result
        }
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

/// Small, fast, seedable RNG (SplitMix64) so the stream is deterministic.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
