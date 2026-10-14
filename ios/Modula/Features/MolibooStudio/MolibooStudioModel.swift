import Foundation
import SwiftUI

// MOL-03 "The Living Studio" — pure, testable model pieces (no RealityKit here).

/// Backdrop environments for the 3D stage. Persisted by raw value; cosmetic only (never touches the outfit).
enum MolibooEnvironment: String, CaseIterable, Identifiable, Codable, Sendable {
    case meadow, nightSky, cozyRoom, studio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meadow: "Meadow"
        case .nightSky: "Night sky"
        case .cozyRoom: "Cozy room"
        case .studio: "Studio"
        }
    }
    var symbol: String {
        switch self {
        case .meadow: "leaf.fill"
        case .nightSky: "moon.stars.fill"
        case .cozyRoom: "sofa.fill"
        case .studio: "camera.aperture"
        }
    }
    var sky: [Color] {
        switch self {
        case .meadow: [Color(red: 0.62, green: 0.84, blue: 0.98), Color(red: 0.86, green: 0.95, blue: 0.86)]
        case .nightSky: [Color(red: 0.07, green: 0.09, blue: 0.24), Color(red: 0.24, green: 0.20, blue: 0.45)]
        case .cozyRoom: [Color(red: 0.98, green: 0.86, blue: 0.70), Color(red: 0.93, green: 0.74, blue: 0.62)]
        case .studio: [Color(white: 0.96), Color(white: 0.84)]
        }
    }
    var floor: Color {
        switch self {
        case .meadow: Color(red: 0.48, green: 0.74, blue: 0.42)
        case .nightSky: Color(red: 0.16, green: 0.15, blue: 0.32)
        case .cozyRoom: Color(red: 0.72, green: 0.52, blue: 0.40)
        case .studio: Color(white: 0.78)
        }
    }
    var isDark: Bool { self == .nightSky }
}

/// Per-character camera framing. The scene controller normalises every character to ~0.2 m wide sitting at y = -0.05,
/// so framing only compensates for silhouette (gills, antenna, flat frog, cube).
struct MolibooFraming: Equatable, Sendable {
    var target: SIMD3<Float>
    var eye: SIMD3<Float>
    var fov: Float

    static let standard = MolibooFraming(target: [0, 0.03, 0], eye: [0, 0.11, 0.66], fov: 40)

    static func `for`(_ id: String) -> MolibooFraming {
        switch id {
        case "pip": MolibooFraming(target: [0, 0.035, 0], eye: [0, 0.12, 0.70], fov: 40)    // gills widen the box: leave room for them
        case "moss": MolibooFraming(target: [0, 0.02, 0], eye: [0, 0.10, 0.72], fov: 40)    // wide and flat: lower target
        case "tofu": MolibooFraming(target: [0, 0.035, 0], eye: [0, 0.12, 0.64], fov: 40)
        case "bolt": MolibooFraming(target: [0, 0.055, 0], eye: [0, 0.13, 0.74], fov: 40)    // tall body + antenna
        default: .standard
        }
    }
}

/// Idle personality: which personality clips play by themselves, and how often.
struct MolibooIdlePersonality: Equatable, Sendable {
    let clips: [String]
    let interval: ClosedRange<Double>
    let mood: String

    static func `for`(_ d: MolibooCharacterDescriptor) -> MolibooIdlePersonality {
        let p: MolibooIdlePersonality
        switch d.id {
        case "pip": p = .init(clips: ["gill_flutter", "exuberant_bounce", "gill_flutter"], interval: 6...10, mood: "bubbly")
        case "moss": p = .init(clips: ["slow_blink", "cheek_puff", "measured_hop"], interval: 12...20, mood: "unbothered")
        case "tofu": p = .init(clips: ["cube_squash", "wobble", "exuberant_bounce"], interval: 8...14, mood: "clumsy")
        case "bolt": p = .init(clips: ["antenna_flash", "servo_tilt"], interval: 9...15, mood: "analytical")
        default: p = .init(clips: ["idle_bob", "wobble"], interval: 10...16, mood: "steady")
        }
        // Only clips the asset really has; never guess.
        return .init(clips: p.clips.filter { d.clips[$0] != nil }, interval: p.interval, mood: p.mood)
    }
}

/// Reactions the stage can produce. Each has its own cooldown so spamming never stacks animations.
enum MolibooReaction: String, CaseIterable, Sendable {
    case tap, pet, hop, dance, peekaboo, nap, dizzy
    var cooldown: Double {
        switch self {
        case .tap: 0.6
        case .pet: 1.5
        case .hop: 1.2
        case .dance: 2.5
        case .peekaboo: 2.0
        case .nap: 3.0
        case .dizzy: 4.0
        }
    }
}

/// Cooldown gate (time injected for tests). Also turns tap spam into a single "dizzy" reaction.
struct MolibooReactionGate: Sendable {
    static let globalGap = 0.35
    static let spamWindow = 4.0
    static let spamCount = 5
    private(set) var last: [MolibooReaction: Double] = [:]
    private(set) var lastAny = -Double.infinity
    private(set) var recentTaps: [Double] = []

    /// Returns the reaction to perform now (possibly upgraded to `.dizzy`), or nil when cooling down.
    mutating func request(_ r: MolibooReaction, at now: Double) -> MolibooReaction? {
        var r = r
        if r == .tap {
            recentTaps = recentTaps.filter { now - $0 < Self.spamWindow } + [now]
            if recentTaps.count >= Self.spamCount, now - (last[.dizzy] ?? -.infinity) >= MolibooReaction.dizzy.cooldown {
                r = .dizzy; recentTaps.removeAll()
            }
        }
        guard now - lastAny >= Self.globalGap, now - (last[r] ?? -.infinity) >= r.cooldown else { return nil }
        last[r] = now; lastAny = now
        return r
    }
}

/// What the scheduler may do under the current accessibility settings.
struct MolibooMotionPolicy: Equatable, Sendable {
    let reduceMotion: Bool
    var idlePersonality: Bool { !reduceMotion }
    var bodyMotion: Bool { !reduceMotion }          // bounce / wobble / hop
    var autoBlink: Bool { true }                    // blinking is not vestibular motion
}

/// Play-sheet interactions (Play rail).
enum MolibooPlay: String, CaseIterable, Identifiable, Sendable {
    case pet, hop, dance, peekaboo, nap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pet: "Pet"
        case .hop: "Hop"
        case .dance: "Dance"
        case .peekaboo: "Peekaboo"
        case .nap: "Nap"
        }
    }
    var symbol: String {
        switch self {
        case .pet: "hand.raised.fill"
        case .hop: "arrow.up.circle.fill"
        case .dance: "music.note"
        case .peekaboo: "eyes"
        case .nap: "moon.zzz.fill"
        }
    }
    var reaction: MolibooReaction { MolibooReaction(rawValue: rawValue) ?? .tap }
}
