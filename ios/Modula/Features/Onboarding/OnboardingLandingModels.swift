import CoreGraphics
import Foundation

/// Content and motion model for the signed-out landing screen.
///
/// Bubbles are emitted from the central "+" bubble and fly up and out of the top of
/// the screen in a continuous stream. The emitter is *stateless*: every particle is a
/// pure function of its spawn index and a seed, and its on-screen state is a pure
/// function of time. Rendering a frame allocates nothing and the stream is fully
/// deterministic, which keeps it testable and lets Reduce Motion show one frozen frame.
enum OnboardingLanding {
    static let headline = "A new kind of app, built from modules that get things done"
    static let continueTitle = "Let’s go"

    // MARK: Modules shown in the bubbles

    struct Module: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let symbol: String
        /// Main sphere tint and a second hue for the mesh fill.
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
        /// 0 (far: small, slow, soft) … 1 (near).
        let depth: Double
        /// Birth offset from the + centre, in reference points.
        let birthOffset: CGSize
        /// Final horizontal travel (signed), in reference points.
        let drift: Double
        let swayAmplitude: Double
        let swayFrequency: Double
        let swayPhase: Double
    }

    /// Per-frame state of one particle, relative to the + centre (reference points, y up is negative).
    struct ParticleState: Equatable, Sendable {
        var position: CGPoint
        var scale: Double
        var opacity: Double
        var blur: Double
    }

    struct Emitter: Sendable {
        var seed: UInt64 = 0x6D6F_6475_6C61 // "modula"
        /// Mean time between spawns (seconds).
        var interval: Double = 0.24
        var minLifetime: Double = 6.0
        var maxLifetime: Double = 9.6
        /// Distance from the + centre to just past the top edge (reference points).
        var rise: Double = 560
        /// Fraction of particles that are tiny empty droplets.
        var dropletShare: Double = 0.3

        /// Smallest scale at birth.
        static let birthScale = 0.2

        func particle(_ index: Int) -> Particle {
            var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)
            let jitter = rng.unit()
            let isDroplet = rng.unit() < dropletShare
            let moduleIndex = Int(rng.next() % UInt64(OnboardingLanding.modules.count))
            let depth = isDroplet ? 0.15 + 0.45 * rng.unit() : 0.25 + 0.75 * rng.unit()
            let diameter = isDroplet ? 9 + 17 * rng.unit() : 46 + 74 * depth * (0.75 + 0.25 * rng.unit())
            // Far particles rise slower.
            let lifetime = maxLifetime - (maxLifetime - minLifetime) * depth * (0.8 + 0.2 * rng.unit())
            // Alternate sides (with the odd surprise) so the stream fans out evenly.
            let side = (index.isMultiple(of: 2) ? 1.0 : -1.0) * (rng.unit() < 0.18 ? -1 : 1)
            let spread = side * (20 + 165 * pow(rng.unit(), 0.75))
            return Particle(
                index: index,
                spawnTime: Double(index) * interval + jitter * interval * 0.7,
                lifetime: lifetime,
                kind: isDroplet ? .droplet : .module(moduleIndex),
                diameter: diameter,
                depth: depth,
                birthOffset: CGSize(width: (rng.unit() - 0.5) * 34, height: (rng.unit() - 0.5) * 14),
                drift: spread,
                swayAmplitude: 6 + 16 * rng.unit(),
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
            // Linger just above the + (dense stream), then accelerate upwards and out.
            let climb = pow(t, 1.7)
            // Fan out sideways early, then keep going.
            let fan = 1 - pow(1 - min(1, t * 1.5), 2.4)
            let sway = p.swayAmplitude * sin(age * p.swayFrequency * 2 * .pi / 2 + p.swayPhase) * min(1, t * 3)
            let x = Double(p.birthOffset.width) * (1 - fan) + p.drift * fan + sway
            let y = Double(p.birthOffset.height) - rise * climb - 18 * fan
            // Born small at the +, grow as they leave it.
            let grow = smoothstep(0, 0.32, t)
            let scale = Emitter.birthScale + (1 - Emitter.birthScale) * grow
            let fadeIn = smoothstep(0, 0.06, t)
            let fadeOut = 1 - smoothstep(0.86, 1, t)
            let depthAlpha = 0.55 + 0.45 * p.depth
            return ParticleState(
                position: CGPoint(x: x, y: y),
                scale: scale,
                opacity: fadeIn * fadeOut * depthAlpha,
                // Droplets stay crisp (they read as glass); far module bubbles go soft.
                blur: p.kind == .droplet ? 0 : max(0, (0.45 - p.depth) * 4)
            )
        }

        /// Fraction (0…1) of an emission pulse for the + bubble: peaks right after a spawn.
        func emitPulse(at time: Double) -> Double {
            let index = Int(floor(time / interval))
            var best = 0.0
            for i in max(0, index - 1)...index + 1 {
                let since = time - particle(i).spawnTime
                if since >= 0 { best = max(best, exp(-since * 7)) }
            }
            return best
        }
    }

    /// Frozen frame shown under Reduce Motion (a well-populated moment of the stream).
    static let staticTime: Double = 41.3
    /// The live stream starts this far in, so the screen is already full on appear.
    static let warmUp: Double = 6.5

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
