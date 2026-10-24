import SwiftUI
import CoreMotion

// MARK: - Roster

/// Fifteen original composer mascots, drawn entirely with SwiftUI shapes.
enum ModulaMascotKind: String, CaseIterable, Identifiable, Sendable {
    // Free
    case pip, moss, nimbus, mochi, sprout
    // Premium
    case ember, tuck, bloop, bun, pebble, tofu, comet, puff, bolt, glim
    // Originals 016–025 (Master Bible v1.0)
    case echo, quill, orbit, prism, wisp, doodle, chime, rolo, pogo, fable
    // Family 002 — Angels
    case aura, soli, luma, vela, cheri, hush, haloa, lyra, celio, dovee, twila, gleam, novael, sera, auri
    // Family 003 — Underground
    case riff, graff, nyx, zip, vex, koda, glitch, jinx, `static`, holo, fuse, skid, mica, rumble, flick
    // Family 004 — Enchanted
    case bramble, ferni, truffle, rootle, willow, pollen, mallow, acora, spindle, glade, lichen, thimble, wyrmi, kiko, eldra
    // Family 005 — Stardust
    case astra, nebbi, quori, vesper, pulsa, stellan, cosmi, eclipa, meteo, asteri, zenith, liora, nocta, glint, polaris
    // Family 006 — Dreamers
    case dozi, lulli, moona, nuzzle, drifty, hushby, swayla, snoomi, velvi, minku, tufti, winkle, sonata, comfi, somna
    var id: String { rawValue }

    var isPremium: Bool {
        switch self {
        case .pip, .moss, .nimbus, .mochi, .sprout, .echo, .orbit, .wisp: false
        // Bible "instantly free" picks per family.
        case .aura, .soli, .luma, .cheri, .haloa: false
        case .riff, .graff, .koda, .skid, .flick: false
        case .ferni, .truffle, .mallow, .acora, .thimble: false
        case .astra, .nebbi, .quori, .cosmi, .glint: false
        case .dozi, .lulli, .nuzzle, .tufti, .comfi: false
        default: true
        }
    }

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var personality: String {
        switch self {
        case .pip: "Bubbly axolotl, waves its frills when happy"
        case .moss: "Unbothered pond frog, puffs up to think"
        case .nimbus: "Daydreamy cloud, always drifting"
        case .mochi: "Sleepy cat, secretly listening"
        case .sprout: "Tiny seedling that grows with every word"
        case .ember: "Tiny spark with big energy"
        case .tuck: "Curious owl who reads every word"
        case .bloop: "Gentle jellyfish, floats through your drafts"
        case .bun: "Floppy-eared bunny, hops at good ideas"
        case .pebble: "Steady little stone, few words, big heart"
        case .tofu: "Wobbly cube of pure optimism"
        case .comet: "Star in a hurry, leaves sparkles behind"
        case .puff: "Pufferfish who inflates with excitement"
        case .bolt: "Pocket robot, beeps approvingly"
        case .glim: "Firefly with a glow for late-night writing"
        case .echo: "Big-eared bat who hears what others miss"
        case .quill: "Bashful hedgehog, curls up then peeks out"
        case .orbit: "Tiny planet with a ring and a pocket moon"
        case .prism: "Living crystal that bends light into colours"
        case .wisp: "Friendly little spirit that drifts like mist"
        case .doodle: "Living ink sketch that redraws itself"
        case .chime: "Little bell that rings with every feeling"
        case .rolo: "Slow snail philosopher with a spiral shell"
        case .pogo: "Spring-footed bouncer, always ready to hop"
        case .fable: "Origami spirit that unfolds into stories"
        default: {
            let form = (spec?.form ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if form.isEmpty { return title }
            if form.lowercased() == title.lowercased() { return title }
            return form
        }()
        }
    }

    /// Dense-card blurb: fits a 2-column portrait without mid-word ellipsis.
    var shortPersonality: String {
        switch self {
        case .pip: "Bubbly axolotl"
        case .moss: "Calm pond frog"
        case .nimbus: "Daydreamy cloud"
        case .mochi: "Sleepy listener"
        case .sprout: "Tiny seedling"
        case .ember: "Tiny spark"
        case .tuck: "Curious owl"
        case .bloop: "Gentle jellyfish"
        case .bun: "Floppy-eared bunny"
        case .pebble: "Steady little stone"
        case .tofu: "Wobbly optimist"
        case .comet: "Speedy star"
        case .puff: "Excited pufferfish"
        case .bolt: "Pocket robot"
        case .glim: "Late-night firefly"
        case .echo: "Night-listening bat"
        case .quill: "Shy hedgehog"
        case .orbit: "Tiny planet"
        case .prism: "Living crystal"
        case .wisp: "Friendly spirit"
        case .doodle: "Living sketch"
        case .chime: "Little bell"
        case .rolo: "Wise snail"
        case .pogo: "Springy bouncer"
        case .fable: "Origami storyteller"
        default: spec?.form ?? title
        }
    }

    /// Short catchphrase used by the offline personality responder.
    var tic: String {
        switch self {
        case .pip: "blub!"
        case .moss: "ribbit."
        case .nimbus: "~☁︎"
        case .mochi: "mrrp."
        case .sprout: "🌱"
        case .ember: "✦"
        case .tuck: "hoo!"
        case .bloop: "bloop~"
        case .bun: "*ear wiggle*"
        case .pebble: "…"
        case .tofu: "boing!"
        case .comet: "zoom!"
        case .puff: "puff!"
        case .bolt: "beep boop."
        case .glim: "✧"
        case .echo: "*ear twitch*"
        case .quill: "hff!"
        case .orbit: "whirr~"
        case .prism: "✶"
        case .wisp: "oooh~"
        case .doodle: "*scribble*"
        case .chime: "ding!"
        case .rolo: "…slowly."
        case .pogo: "boing boing!"
        case .fable: "*rustle*"
        default: "✧"
        }
    }

    struct Palette { let light: Color; let mid: Color; let dark: Color; let accent: Color; let iris: Color; let outline: Color }

    var palette: Palette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .pip: return Palette(light: c(1, 0.88, 0.94), mid: c(1, 0.62, 0.78), dark: c(0.86, 0.36, 0.58), accent: c(1, 0.42, 0.7), iris: c(0.28, 0.14, 0.28), outline: c(0.58, 0.22, 0.4))
        case .moss: return Palette(light: c(0.9, 0.98, 0.78), mid: c(0.52, 0.84, 0.42), dark: c(0.22, 0.56, 0.28), accent: c(0.98, 0.96, 0.86), iris: c(0.18, 0.22, 0.14), outline: c(0.12, 0.36, 0.18))
        case .nimbus: return Palette(light: c(1, 1, 1), mid: c(0.88, 0.93, 1), dark: c(0.62, 0.74, 0.96), accent: c(0.62, 0.8, 1), iris: c(0.2, 0.3, 0.56), outline: c(0.36, 0.46, 0.74))
        case .mochi: return Palette(light: c(0.98, 0.96, 1), mid: c(0.86, 0.82, 0.94), dark: c(0.64, 0.6, 0.78), accent: c(1, 0.7, 0.8), iris: c(0.28, 0.2, 0.36), outline: c(0.4, 0.34, 0.5))
        case .sprout: return Palette(light: c(1, 0.96, 0.72), mid: c(0.98, 0.82, 0.38), dark: c(0.82, 0.58, 0.22), accent: c(0.42, 0.78, 0.34), iris: c(0.28, 0.2, 0.1), outline: c(0.5, 0.34, 0.12))
        case .ember: return Palette(light: c(1, 0.94, 0.5), mid: c(1, 0.58, 0.22), dark: c(0.92, 0.3, 0.12), accent: c(1, 0.86, 0.3), iris: c(0.36, 0.12, 0.06), outline: c(0.58, 0.16, 0.08))
        case .tuck: return Palette(light: c(0.94, 0.82, 0.66), mid: c(0.7, 0.5, 0.34), dark: c(0.42, 0.28, 0.18), accent: c(1, 0.72, 0.28), iris: c(0.22, 0.14, 0.1), outline: c(0.28, 0.16, 0.1))
        case .bloop: return Palette(light: c(0.96, 0.88, 1), mid: c(0.78, 0.58, 0.98), dark: c(0.52, 0.34, 0.86), accent: c(1, 0.66, 0.9), iris: c(0.26, 0.14, 0.46), outline: c(0.38, 0.22, 0.62))
        case .bun: return Palette(light: c(1, 1, 1), mid: c(0.96, 0.94, 0.94), dark: c(0.84, 0.8, 0.8), accent: c(1, 0.74, 0.8), iris: c(0.28, 0.18, 0.18), outline: c(0.5, 0.4, 0.4))
        case .pebble: return Palette(light: c(0.92, 0.96, 1), mid: c(0.72, 0.82, 0.9), dark: c(0.5, 0.6, 0.72), accent: c(0.42, 0.78, 0.56), iris: c(0.2, 0.26, 0.34), outline: c(0.3, 0.38, 0.48))
        case .tofu: return Palette(light: c(1, 1, 0.98), mid: c(0.98, 0.96, 0.9), dark: c(0.88, 0.84, 0.74), accent: c(1, 0.72, 0.5), iris: c(0.22, 0.18, 0.16), outline: c(0.56, 0.5, 0.4))
        case .comet: return Palette(light: c(1, 0.98, 0.72), mid: c(1, 0.86, 0.28), dark: c(0.96, 0.6, 0.14), accent: c(0.45, 0.78, 1), iris: c(0.28, 0.18, 0.08), outline: c(0.62, 0.4, 0.08))
        case .puff: return Palette(light: c(0.82, 0.96, 1), mid: c(0.5, 0.84, 0.98), dark: c(0.26, 0.58, 0.84), accent: c(1, 0.82, 0.36), iris: c(0.12, 0.24, 0.38), outline: c(0.12, 0.36, 0.56))
        case .bolt: return Palette(light: c(0.96, 0.98, 1), mid: c(0.82, 0.88, 0.94), dark: c(0.52, 0.6, 0.72), accent: c(0.3, 0.9, 0.95), iris: c(0.1, 0.7, 0.8), outline: c(0.28, 0.36, 0.48))
        case .glim: return Palette(light: c(0.82, 0.94, 0.56), mid: c(0.52, 0.76, 0.34), dark: c(0.3, 0.48, 0.2), accent: c(1, 0.94, 0.36), iris: c(0.16, 0.22, 0.1), outline: c(0.18, 0.32, 0.12))
        // Sheet palettes for Originals 016–025
        case .echo: return Palette(light: c(0.62, 0.46, 0.84), mid: c(0.4, 0.24, 0.62), dark: c(0.22, 0.12, 0.36), accent: c(1, 0.7, 0.84), iris: c(0.12, 0.06, 0.2), outline: c(0.14, 0.06, 0.24))
        case .quill: return Palette(light: c(1, 0.94, 0.86), mid: c(0.98, 0.86, 0.7), dark: c(0.9, 0.62, 0.4), accent: c(0.9, 0.56, 0.3), iris: c(0.24, 0.14, 0.08), outline: c(0.44, 0.28, 0.16))
        case .orbit: return Palette(light: c(0.62, 0.78, 1), mid: c(0.34, 0.5, 0.92), dark: c(0.18, 0.28, 0.64), accent: c(0.96, 0.56, 0.9), iris: c(0.1, 0.12, 0.3), outline: c(0.14, 0.18, 0.42))
        case .prism: return Palette(light: c(0.92, 0.96, 1), mid: c(0.74, 0.78, 1), dark: c(0.7, 0.52, 0.94), accent: c(1, 0.6, 0.9), iris: c(0.24, 0.2, 0.42), outline: c(0.4, 0.36, 0.64))
        case .wisp: return Palette(light: c(1, 1, 1), mid: c(0.86, 0.96, 1), dark: c(0.58, 0.78, 0.96), accent: c(0.7, 0.88, 1), iris: c(0.16, 0.3, 0.42), outline: c(0.36, 0.52, 0.7))
        case .doodle: return Palette(light: c(1, 1, 1), mid: c(0.98, 0.98, 0.99), dark: c(0.9, 0.9, 0.92), accent: c(0.12, 0.12, 0.14), iris: c(0.06, 0.06, 0.08), outline: c(0.08, 0.08, 0.1))
        case .chime: return Palette(light: c(1, 0.94, 0.7), mid: c(0.96, 0.78, 0.34), dark: c(0.72, 0.5, 0.18), accent: c(0.86, 0.62, 0.22), iris: c(0.28, 0.16, 0.06), outline: c(0.48, 0.3, 0.08))
        case .rolo: return Palette(light: c(1, 0.94, 0.84), mid: c(0.94, 0.82, 0.64), dark: c(0.72, 0.52, 0.34), accent: c(0.66, 0.4, 0.2), iris: c(0.26, 0.16, 0.08), outline: c(0.42, 0.26, 0.12))
        case .pogo: return Palette(light: c(1, 0.7, 0.62), mid: c(0.98, 0.36, 0.34), dark: c(0.78, 0.18, 0.2), accent: c(1, 0.5, 0.4), iris: c(0.3, 0.1, 0.1), outline: c(0.52, 0.14, 0.14))
        case .fable: return Palette(light: c(1, 1, 0.98), mid: c(0.97, 0.94, 0.88), dark: c(0.88, 0.82, 0.72), accent: c(1, 0.82, 0.3), iris: c(0.24, 0.18, 0.14), outline: c(0.5, 0.42, 0.32))
        default: return spec?.palette ?? Palette(light: .white, mid: .gray, dark: .gray, accent: .pink, iris: .black, outline: .black)
        }
    }

    // Geometry (fractions of size).
    var bodySize: CGSize {
        switch self {
        case .moss: CGSize(width: 1.06, height: 0.80)
        case .nimbus: CGSize(width: 1.16, height: 0.84)
        case .ember: CGSize(width: 0.92, height: 1.02)
        case .tuck: CGSize(width: 0.94, height: 0.92)
        case .sprout: CGSize(width: 0.90, height: 0.90)
        case .bloop: CGSize(width: 1.04, height: 0.76)
        case .bun: CGSize(width: 0.96, height: 0.86)
        case .pebble: CGSize(width: 1.06, height: 0.78)
        case .tofu: CGSize(width: 0.94, height: 0.84)
        case .comet: CGSize(width: 1.04, height: 1.0)
        case .puff: CGSize(width: 0.94, height: 0.90)
        case .bolt: CGSize(width: 0.98, height: 0.84)
        case .glim: CGSize(width: 0.86, height: 0.84)
        case .echo: CGSize(width: 0.92, height: 0.82)
        case .quill: CGSize(width: 0.98, height: 0.84)
        case .orbit: CGSize(width: 0.88, height: 0.88)
        case .prism: CGSize(width: 0.86, height: 0.98)
        case .wisp: CGSize(width: 0.90, height: 1.04)
        case .doodle: CGSize(width: 1.0, height: 0.86)
        case .chime: CGSize(width: 0.94, height: 0.92)
        case .rolo: CGSize(width: 0.86, height: 0.80)
        case .pogo: CGSize(width: 0.84, height: 0.90)
        case .fable: CGSize(width: 0.96, height: 0.88)
        default: spec?.size ?? CGSize(width: 1.0, height: 0.86)
        }
    }

    var bodyOffsetY: CGFloat {
        switch self {
        case .moss, .pebble: 0.14
        case .ember, .comet, .wisp: 0.04
        case .pogo: -0.02
        case .bloop: 0.0
        default: spec.map { [.drop, .star].contains($0.body) ? 0.04 : 0.10 } ?? 0.10
        }
    }

    /// Distance from the figure's centre to where it rests on a surface (fraction of size).
    var footFraction: CGFloat {
        switch self {
        case .bloop: 0.62   // tentacle tips
        case .pogo: 0.68    // spring feet
        case .wisp: 0.56
        default: bodyOffsetY + bodySize.height / 2
        }
    }

    var eyeSize: CGFloat {
        switch self {
        case .tuck: 0.25
        case .moss: 0.23
        case .bolt: 0.22
        case .tofu, .pebble: 0.18
        default: 0.21
        }
    }
    var eyeY: CGFloat {
        switch self {
        case .moss: -0.13
        case .ember: 0.10
        case .comet: 0.06
        case .bloop: -0.02
        case .pebble: 0.10
        case .wisp: -0.06
        case .prism, .chime: 0.08
        case .pogo: -0.04
        case .fable: 0.06
        default: spec.map { [.drop, .star].contains($0.body) ? 0.10 : 0.04 } ?? 0.04
        }
    }
    var eyeSpread: CGFloat {
        switch self {
        case .moss: 0.25
        case .tuck: 0.18
        case .tofu, .pebble: 0.20
        default: 0.19
        }
    }
    var mouthY: CGFloat {
        switch self {
        case .moss: 0.13
        case .ember: 0.30
        case .bloop: 0.16
        case .comet: 0.26
        case .pebble: 0.27
        default: 0.22
        }
    }
}

enum ModulaMascotPlacement: String, Sendable { case nodus, comments, other }

/// AppStorage keys for the composer mascot (Settings → Chats → Composer).
enum ModulaMascotSettings {
    static let kindKey = "composer.mascot.kind"           // ModulaMascotKind rawValue, or "off"
    static let nodusKey = "composer.mascot.show.nodus"
    static let commentsKey = "composer.mascot.show.comments"
    static let otherKey = "composer.mascot.show.other"
    /// Home companion (walks the bottom edge of Home). On by default.
    static let homeCompanionKey = "composer.mascot.show.homeCompanion"
    static let soundsKey = "composer.mascot.sounds"
    static let debugPremiumKey = "composer.mascot.debugPremium"
    static let celebrationKey = "composer.mascot.lastCelebration"
    static let off = "off"

    static func key(for placement: ModulaMascotPlacement) -> String {
        switch placement {
        case .nodus: nodusKey
        case .comments: commentsKey
        case .other: otherKey
        }
    }
    static func defaultShown(_ placement: ModulaMascotPlacement) -> Bool { placement == .nodus }
}

/// Single entitlement switch for Premium mascots. No payments yet; DEBUG builds can unlock
/// via the hidden toggle in Settings → Chats → Composer.
enum MascotEntitlements {
    static var isPremium: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: ModulaMascotSettings.debugPremiumKey)
        #else
        false
        #endif
    }
    static func canUse(_ kind: ModulaMascotKind) -> Bool { !kind.isPremium || isPremium }
}

// MARK: - Tilt + shake (CoreMotion, shared, ref-counted)

@MainActor
final class ModulaMascotMotion {
    static let shared = ModulaMascotMotion()
    /// -1…1 look offset from device tilt (read each frame by visible mascots; not observed).
    private(set) var tilt: CGSize = .zero
    private(set) var lastShake: Double = 0
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let g = motion.gravity, a = motion.userAcceleration
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tilt = CGSize(width: max(-1, min(1, g.x * 1.8)), height: max(-1, min(1, (g.z + 0.55) * 1.6)))
                if sqrt(a.x * a.x + a.y * a.y + a.z * a.z) > 2.2 { self.lastShake = Date.timeIntervalSinceReferenceDate }
            }
        }
    }

    func stop() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        tilt = .zero
    }
}

// MARK: - Pose & brain

enum MascotMood: Equatable { case idle, typing, happy, pleased, surprised, sleepy, thinking, dizzy, sad, laughing, speaking, wave, dance, celebrate, shy, excited, curious, sit }

/// Ambient, context-driven looks (battery, time, power, network, capture, appearance).
struct MascotConditions: Equatable {
    var tired = false
    var night = false
    var morning = false
    var lowPower = false
    var offline = false
    var shy = false
    var dark = false
}

enum MascotEyeStyle { case normal, happy, spiral }

struct MascotPose {
    var t: Double = 0
    var look: CGSize = .zero
    var blink: CGFloat = 0
    var mood: MascotMood = .idle
    var eyes: MascotEyeStyle = .normal
    var mouthOpen: CGFloat = 0
    var yawning = false
    var breathe: CGFloat = 0
    var sway: Double = 0
    var hop: CGFloat = 0
    var squash: CGFloat = 1
    var shiverX: CGFloat = 0
    var amp: CGFloat = 1
    var conditions = MascotConditions()

    static func still(_ mood: MascotMood = .idle) -> MascotPose { MascotPose(mood: mood, amp: 0) }
}

struct MascotBurst: Identifiable {
    enum Style { case sparkle, hearts, pop, confetti, tear, aura, outfit }
    let id = UUID()
    let start: Double
    let style: Style
    let seed: Double
}

/// Per-mascot behaviour: spring gaze, blinks, glances, hops, reactions, sleep and context moods.
@MainActor
final class MascotBrain {
    private var lookPos = CGSize.zero
    private var lookVel = CGSize.zero
    private var lastStep: Double = 0
    private var nextBlink: Double = 0
    private var blinkStart: Double = -10
    private var glance = CGSize.zero
    private var glanceUntil: Double = 0
    private var nextGlance: Double = 0
    private var nextYawn: Double = Date.timeIntervalSinceReferenceDate + 6
    private var yawnStart: Double = -10
    private(set) var lastInteraction: Double = Date.timeIntervalSinceReferenceDate
    private var reaction: (MascotMood, Double, Double)?   // mood, start, duration
    private var hops: [(Double, CGFloat)] = []
    private(set) var bursts: [MascotBurst] = []
    private var lastKey: Double = -10
    private var seenShake: Double = 0
    private var dizzyUntil: Double = 0
    var typingUntil: Double = 0
    var caret: CGFloat = 0
    var speakingUntil: Double = 0
    private(set) var lastMood: MascotMood = .idle

    static var now: Double { Date.timeIntervalSinceReferenceDate }

    /// Records interaction; returns true if it woke the mascot.
    @discardableResult
    func poke() -> Bool {
        let wasAsleep = lastMood == .sleepy
        lastInteraction = Self.now
        return wasAsleep
    }

    func burst(_ style: MascotBurst.Style) {
        bursts.append(MascotBurst(start: Self.now, style: style, seed: Double.random(in: 0...1000)))
    }

    func hop(burst style: MascotBurst.Style? = .sparkle, height: CGFloat = 11) {
        poke()
        hops.append((Self.now, height))
        if let style { burst(style) }
    }

    func keystroke() {
        poke()
        lastKey = Self.now
        typingUntil = Self.now + 1.3
    }

    func react(_ mood: MascotMood) {
        let n = Self.now
        poke()
        switch mood {
        case .happy:
            reaction = (mood, n, 1.5)
            hops.append(contentsOf: [(n, 11), (n + 0.42, 8)])
            burst(.hearts)
        case .pleased:
            reaction = (mood, n, 0.8)
            hops.append((n, 5))
        case .surprised:
            reaction = (mood, n, 1.0)
            hops.append((n, 9))
            burst(.pop)
        case .laughing:
            reaction = (mood, n, 1.4)
            hops.append((n, 6))
        case .sad:
            reaction = (mood, n, 2.0)
            burst(.tear)
        case .wave:
            reaction = (mood, n, 1.2)
            hops.append((n, 4))
        case .dance:
            reaction = (mood, n, 2.0)
            hops.append(contentsOf: [(n, 7), (n + 0.28, 7), (n + 0.56, 7), (n + 0.84, 7)])
            burst(.sparkle)
        case .celebrate:
            reaction = (mood, n, 1.8)
            hops.append(contentsOf: [(n, 12), (n + 0.35, 9)])
            burst(.confetti)
            burst(.aura)
        case .shy:
            reaction = (mood, n, 1.6)
        case .excited:
            reaction = (mood, n, 1.4)
            hops.append(contentsOf: [(n, 10), (n + 0.3, 8)])
            burst(.sparkle)
        case .curious:
            reaction = (mood, n, 1.2)
            hops.append((n, 5))
        case .sit:
            reaction = (mood, n, 2.4)
            hops.append((n, 3))
        default:
            reaction = (mood, n, 1.0)
        }
    }

    func celebrate() {
        react(.celebrate)
        burst(.confetti)
    }

    func wave() { react(.wave) }
    func dance() { react(.dance) }
    func sit() { react(.sit) }
    func outfitChanged() {
        react(.excited)
        burst(.outfit)
        burst(.sparkle)
    }

    func pose(at now: Double, touchLook: CGSize?, tilt: CGSize, busy: Bool, reduceMotion: Bool, conditions: MascotConditions) -> MascotPose {
        var p = MascotPose(t: now, amp: reduceMotion ? 0 : 1, conditions: conditions)
        hops.removeAll { now - $0.0 > 0.6 }
        bursts.removeAll { now - $0.start > 1.6 }
        if let r = reaction, now - r.1 > r.2 { reaction = nil }
        let shake = ModulaMascotMotion.shared.lastShake
        if shake > seenShake { seenShake = shake; if !reduceMotion { dizzyUntil = now + 2.2; poke() } }

        // Mood priority.
        let idleFor = now - lastInteraction
        let asleep = !busy && touchLook == nil && (idleFor > 28 || (conditions.night && idleFor > 14))
        if now < dizzyUntil { p.mood = .dizzy }
        else if let r = reaction { p.mood = r.0 }
        else if now < speakingUntil { p.mood = .speaking }
        else if busy { p.mood = .thinking }
        else if now < typingUntil { p.mood = .typing }
        else if asleep { p.mood = .sleepy }
        lastMood = p.mood

        switch p.mood {
        case .happy, .pleased, .laughing, .excited, .celebrate, .dance: p.eyes = .happy
        case .shy: p.eyes = .happy
        case .dizzy: p.eyes = .spiral
        default: p.eyes = .normal
        }

        // Gaze target.
        if now > nextGlance && p.mood == .idle && touchLook == nil {
            glance = CGSize(width: Double.random(in: -1...1), height: Double.random(in: -0.7...0.6))
            glanceUntil = now + Double.random(in: 0.6...1.2)
            nextGlance = now + Double.random(in: 3.5...7)
        }
        var target: CGSize
        switch p.mood {
        case .thinking: target = CGSize(width: 0.55 + 0.25 * sin(now * 2.1), height: -0.75)
        case .surprised, .dizzy: target = .zero
        case .sleepy: target = CGSize(width: 0, height: 0.5)
        case .sad: target = CGSize(width: -0.2, height: 0.7)
        case .typing: target = CGSize(width: -0.95 + caret * 1.15, height: 0.7)
        case .speaking: target = CGSize(width: -0.3, height: -0.2)
        default:
            if let touchLook { target = touchLook }
            else if conditions.shy { target = CGSize(width: 0.9, height: 0.55) }
            else if now < glanceUntil { target = glance }
            else { target = reduceMotion ? .zero : tilt }
        }

        if reduceMotion || lastStep == 0 {
            lookPos = target; lookVel = .zero
        } else {
            let dt = min(max(now - lastStep, 0), 1.0 / 20.0)
            let k = 170.0, c = 2 * sqrt(k) * 0.72
            let ax = k * (target.width - lookPos.width) - c * lookVel.width
            let ay = k * (target.height - lookPos.height) - c * lookVel.height
            lookVel = CGSize(width: lookVel.width + ax * dt, height: lookVel.height + ay * dt)
            lookPos = CGSize(width: lookPos.width + lookVel.width * dt, height: lookPos.height + lookVel.height * dt)
        }
        lastStep = now
        p.look = lookPos

        // Blinks and lids.
        if now > nextBlink {
            blinkStart = now
            nextBlink = now + Double.random(in: 2.4...5.6) * (Double.random(in: 0...1) < 0.2 ? 0.15 : 1)
        }
        let be = now - blinkStart
        p.blink = be < 0.16 ? CGFloat(sin(be / 0.16 * .pi)) : 0
        if conditions.tired { p.blink = max(p.blink, 0.42) }
        if conditions.night { p.blink = max(p.blink, 0.22) }
        if p.mood == .sleepy { p.blink = max(p.blink, 0.62 + 0.08 * CGFloat(sin(now * 1.3))) }
        if p.mood == .sad { p.blink = max(p.blink, 0.3) }

        // Yawns when tired or late.
        if (conditions.tired || conditions.night) && p.mood == .idle || p.mood == .sleepy {
            if now > nextYawn { yawnStart = now; nextYawn = now + Double.random(in: 9...16) }
        }
        let ye = now - yawnStart
        if ye < 1.6 && (p.mood == .idle || p.mood == .sleepy) {
            p.yawning = true
            p.mouthOpen = CGFloat(sin(ye / 1.6 * .pi))
            p.blink = max(p.blink, 0.85 * p.mouthOpen)
        }
        if p.mood == .speaking { p.mouthOpen = CGFloat(abs(sin(now * 13)) * 0.9 + 0.1) * (reduceMotion ? 0.5 : 1) }
        if p.mood == .laughing { p.mouthOpen = 0.6 + 0.4 * CGFloat(abs(sin(now * 18))) }

        guard !reduceMotion else { return p }

        // Breathing, sway.
        var breathRate = p.mood == .sleepy ? 0.18 : (p.mood == .thinking ? 0.55 : 0.32)
        if conditions.tired { breathRate *= 0.6 }
        if conditions.lowPower { breathRate *= 0.8 }
        if conditions.morning { breathRate *= 1.15 }
        p.breathe = CGFloat(sin(now * 2 * .pi * breathRate))
        p.sway = sin(now * 0.9) * (p.mood == .sleepy ? 3.5 : 2.2)
        if p.mood == .dizzy { p.sway = sin(now * 7) * 9 }
        if p.mood == .laughing { p.sway = sin(now * 28) * 4 }
        if p.mood == .dance { p.sway = sin(now * 10) * 10 }
        if p.mood == .wave { p.sway = sin(now * 5) * 6 }
        if p.mood == .shy { p.sway = sin(now * 1.2) * 1.5; p.look = CGSize(width: -0.4, height: 0.2) }
        if p.mood == .curious { p.look = CGSize(width: 0.55, height: -0.15) }
        if p.mood == .excited { p.sway = sin(now * 14) * 5 }
        // Head bob on keystrokes.
        let ke = now - lastKey
        if ke < 0.35 { p.sway += 4 * exp(-ke * 9) * sin(ke * 30) }

        // Shiver when offline / poor network: brief bursts.
        if conditions.offline {
            let phase = now.truncatingRemainder(dividingBy: 3.2)
            if phase < 0.6 { p.shiverX = CGFloat(sin(now * 70)) * 1.1 }
        }

        var squash: CGFloat = 1 + (kind_jiggle) * p.breathe
        var height: CGFloat = 0
        for (start, h) in hops where now >= start {
            let e = now - start
            if e < 0.07 { squash = min(squash, 1 - 0.14 * CGFloat(e / 0.07)) }
            else if e < 0.43 {
                let u = (e - 0.07) / 0.36
                height = max(height, CGFloat(sin(u * .pi)) * h)
                squash = max(squash, 1 + 0.08 * CGFloat(sin(u * .pi)))
            } else if e < 0.6 {
                let u = (e - 0.43) / 0.17
                squash = min(squash, 1 - 0.12 * CGFloat(sin(u * .pi)))
            }
        }
        if p.mood == .thinking { height = max(height, 2 + 2 * CGFloat(sin(now * 3.2))) }
        if p.mood == .typing { height = max(height, 1 + CGFloat(sin(now * 2.4))) }
        if p.mood == .sit {
            // Settle down: a soft squat with a contented little rock.
            squash = min(squash, 0.84)
            height = 0
            p.sway = sin(now * 1.4) * 1.6
            p.eyes = .happy
        }
        p.hop = height
        p.squash = squash
        return p
    }

    var jiggle: CGFloat = 0.025
    private var kind_jiggle: CGFloat { jiggle }
}

// MARK: - Figure

/// A mascot rendered from a pose. Volumetric toy look: radial shading, AO, rim light,
/// specular, outline, glossy eyes, cheeks, character idles and context accessories.
struct ModulaMascotFigure: View {
    let kind: ModulaMascotKind
    var pose: MascotPose
    var size: CGFloat = 48
    var outfit: MascotOutfit = .empty

    /// The figure canvas, generous enough for ears, gills, hats and tentacles.
    static func canvas(_ s: CGFloat) -> CGSize { CGSize(width: s * 2.0, height: s * 1.9) }

    var body: some View {
        let s = size
        let pal = kind.palette
        let t = pose.t
        let a = pose.amp
        let c = Self.canvas(s)
        let rig = MascotRig.stock(kind)
        let dressed = !outfit.isEmpty
        ZStack {
            // Wardrobe is painted in three passes so it wraps the body: back items behind,
            // garments on the body under the face, and head/hand/face props on top.
            if dressed { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .back, animate: a > 0) }
            behind(s: s, pal: pal, t: t, a: a)
            bodyLayer(s: s, pal: pal, t: t, a: a)
            front(s: s, pal: pal, t: t, a: a)
            if dressed { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .body, animate: a > 0) }
            face(s: s, pal: pal, t: t)
                .rotationEffect(.degrees(kind == .tuck ? 7 * sin(t * 0.8) * Double(a) : 0), anchor: .bottom)
            accessories(s: s, pal: pal, t: t, a: a)
            if dressed { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .front, animate: a > 0) }
        }
        .frame(width: c.width, height: c.height)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .scaleEffect(x: 1 / sqrt(pose.squash), y: pose.squash, anchor: UnitPoint(x: 0.5, y: 0.5 + kind.footFraction * s / c.height))
        .rotationEffect(.degrees(pose.sway), anchor: UnitPoint(x: 0.5, y: 0.5 + kind.footFraction * s / c.height))
        .offset(x: pose.shiverX, y: -pose.hop)
    }

    private func bodyShape() -> AnyShape {
        if let shape = originalsBodyShape() { return shape }
        if let sp = kind.spec { return specBodyShape(sp.body) }
        return switch kind {
        case .nimbus: AnyShape(MascotCloudShape())
        case .ember: AnyShape(MascotDropShape())
        case .bloop: AnyShape(MascotDomeShape())
        case .pebble: AnyShape(MascotPebbleShape())
        case .tofu: AnyShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        case .bolt: AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        case .comet: AnyShape(MascotStarShape())
        default: AnyShape(Ellipse())
        }
    }

    private func bodyLayer(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let shape = bodyShape()
        let inflate: CGFloat = kind == .puff ? 1 + 0.06 * CGFloat(max(0, sin(t * 0.9))) * a : 1
        let w = s * kind.bodySize.width * inflate, h = s * kind.bodySize.height * inflate
        return ZStack {
            shape.fill(RadialGradient(colors: [pal.light, pal.mid, pal.dark], center: UnitPoint(x: 0.36, y: 0.26), startRadius: s * 0.02, endRadius: s * 0.74))
            // Subsurface warmth near the bottom + ambient occlusion.
            shape.fill(LinearGradient(colors: [.clear, .clear, pal.dark.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(colors: [pal.accent.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.95), startRadius: 0, endRadius: s * 0.4))
            // Rim light from the lower right.
            shape.stroke(LinearGradient(colors: [.clear, .clear, pal.light], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: s * 0.06)
                .blur(radius: s * 0.025)
                .mask(shape)
            // Inner top glow.
            shape.stroke(LinearGradient(colors: [.white.opacity(0.7), .clear], startPoint: .top, endPoint: .center), lineWidth: s * 0.03)
                .blur(radius: s * 0.01)
                .mask(shape)
            shape.stroke(pal.outline.opacity(0.6), lineWidth: max(s * 0.03, 1.1))
            // Specular.
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.26, height: s * 0.12)
                .rotationEffect(.degrees(-24))
                .offset(x: -w * 0.22, y: -h * 0.28)
            Circle().fill(.white.opacity(0.95)).frame(width: s * 0.05).offset(x: -w * 0.04, y: -h * 0.37)
            if kind == .bolt {
                // Face screen.
                RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.24), Color(red: 0.06, green: 0.10, blue: 0.14)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.78, height: h * 0.56)
                    .overlay(RoundedRectangle(cornerRadius: s * 0.18, style: .continuous).stroke(pal.accent.opacity(0.4), lineWidth: 1))
                    .offset(y: h * 0.06)
            }
            if kind == .tofu {
                // Soft inner cube glow.
                RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                    .fill(RadialGradient(colors: [pal.accent.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: s * 0.4))
                    .frame(width: w * 0.7, height: h * 0.7)
            }
        }
        .frame(width: w, height: h)
        .offset(y: s * kind.bodyOffsetY)
    }

    @ViewBuilder
    private func behind(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let da = Double(a)
        let outline = StrokeStyle(lineWidth: max(s * 0.026, 1))
        switch kind {
        case .pip:
            // Three frilly gill stalks per side + floating bubbles (sheet 001).
            ForEach(0..<3, id: \.self) { i in
                let base = Double(i - 1) * 28
                let wave = 10 * sin(t * 3.1 + Double(i) * 0.9) * da
                ForEach([-1.0, 1.0], id: \.self) { side in
                    MascotFrond()
                        .fill(LinearGradient(colors: [pal.accent, pal.dark], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotFrond().stroke(pal.outline.opacity(0.55), style: outline))
                        .frame(width: s * 0.16, height: s * 0.4)
                        .offset(y: -s * 0.2)
                        .rotationEffect(.degrees(side * (64 - base + wave)), anchor: .bottom)
                        .offset(x: side * s * 0.42, y: s * 0.02)
                }
            }
            ForEach(0..<4, id: \.self) { i in
                let u = (t * 0.35 + Double(i) * 0.22).truncatingRemainder(dividingBy: 1)
                Circle().stroke(pal.accent.opacity(0.55 * (1 - u)), lineWidth: max(s * 0.018, 0.7))
                    .frame(width: s * (0.08 + CGFloat(i % 2) * 0.04))
                    .offset(x: s * (0.5 + CGFloat(i) * 0.06), y: s * (0.1 - CGFloat(u) * 0.5 * a))
            }
        case .mochi:
            MascotTail()
                .stroke(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
                .frame(width: s * 0.36, height: s * 0.42)
                .rotationEffect(.degrees(12 * sin(t * 1.6) * da), anchor: .bottomLeading)
                .offset(x: s * 0.52, y: s * 0.08)
            let twitch = Double(a) * max(0, sin(t * 1.9) - 0.93) * 14 * 9
            ForEach([-1.0, 1.0], id: \.self) { side in
                ear(pal: pal, s: s, inner: true)
                    .frame(width: s * 0.32, height: s * 0.32)
                    .rotationEffect(.degrees(side * 18 + (side > 0 ? twitch : 0)), anchor: .bottom)
                    .offset(x: side * s * 0.27, y: -s * 0.26)
            }
        case .bun:
            ForEach([-1.0, 1.0], id: \.self) { side in
                let flop = side > 0 ? 10 + 8 * sin(t * 1.3) * da : -6 + 3 * sin(t * 1.7) * da
                ZStack {
                    Capsule().fill(LinearGradient(colors: [pal.light, pal.mid], startPoint: .top, endPoint: .bottom))
                    Capsule().stroke(pal.outline.opacity(0.5), style: outline)
                    Capsule().fill(pal.accent.opacity(0.7)).scaleEffect(x: 0.45, y: 0.75).offset(y: s * 0.03)
                }
                .frame(width: s * 0.2, height: s * 0.52)
                .offset(y: -s * 0.26)
                .rotationEffect(.degrees(side * 12 + flop), anchor: .bottom)
                .offset(x: side * s * 0.16, y: -s * 0.12)
            }
        case .tuck:
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    MascotTriangle().fill(pal.dark)
                    MascotTriangle().stroke(pal.outline.opacity(0.6), style: outline)
                }
                .frame(width: s * 0.22, height: s * 0.28)
                .rotationEffect(.degrees(side * 30), anchor: .bottom)
                .offset(x: side * s * 0.32, y: -s * 0.32)
            }
        case .moss:
            originalsMossBehind(s: s, pal: pal, t: t, a: a)
        case .ember:
            ForEach(0..<3, id: \.self) { i in
                let flick = 1 + 0.18 * sin(t * 9 + Double(i) * 2.1) * da + 0.08 * sin(t * 15.3 + Double(i)) * da
                MascotDropShape()
                    .fill(LinearGradient(colors: [pal.accent, pal.dark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * (i == 1 ? 0.30 : 0.2), height: s * (i == 1 ? 0.44 : 0.3))
                    .scaleEffect(y: flick, anchor: .bottom)
                    .rotationEffect(.degrees(Double(i - 1) * 24))
                    .offset(x: CGFloat(i - 1) * s * 0.17, y: -s * (i == 1 ? 0.40 : 0.30))
            }
        case .nimbus:
            originalsNimbusBehind(s: s, pal: pal, t: t, a: a)
        case .sprout:
            // Large paired leaves on a stem (sheet 005 — bigger than Moss).
            let lean = 8 * sin(t * 1.2) * da
            ZStack {
                Capsule().fill(Color(red: 0.3, green: 0.7, blue: 0.32)).frame(width: s * 0.06, height: s * 0.28).offset(y: -s * 0.1)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    MascotLeaf()
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.9, blue: 0.4), Color(red: 0.22, green: 0.58, blue: 0.24)], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotLeaf().stroke(Color(red: 0.14, green: 0.38, blue: 0.14).opacity(0.6), lineWidth: max(s * 0.02, 0.8)))
                        .frame(width: s * 0.36, height: s * 0.2)
                        .rotationEffect(.degrees(side * -30 + side * 7 * sin(t * 2 + side) * da), anchor: side > 0 ? .leading : .trailing)
                        .offset(x: side * s * 0.16, y: -s * 0.26)
                }
            }
            .rotationEffect(.degrees(lean), anchor: .bottom)
            .offset(y: -s * 0.3)
        case .bloop:
            // Six dangling tentacles + bubbles (sheet 008).
            ForEach(0..<6, id: \.self) { i in
                MascotTentacle(phase: t * 2.4 + Double(i) * 1.05, amp: a)
                    .stroke(LinearGradient(colors: [pal.mid, pal.accent.opacity(0.75)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round))
                    .frame(width: s * 0.11, height: s * 0.36)
                    .offset(x: CGFloat(i) * s * 0.14 - s * 0.35, y: s * 0.44)
            }
            ForEach(0..<4, id: \.self) { i in
                let u = (t * 0.4 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                Circle().stroke(Color(red: 0.55, green: 0.85, blue: 1).opacity(0.55 * (1 - u)), lineWidth: max(s * 0.016, 0.7))
                    .frame(width: s * (0.07 + CGFloat(i % 2) * 0.03))
                    .offset(x: s * (0.42 + CGFloat(i) * 0.05), y: s * (0.05 - CGFloat(u) * 0.45 * a))
            }
        case .puff:
            ForEach(0..<10, id: \.self) { i in
                let ang = Double(i) / 10 * 360
                MascotTriangle().fill(pal.dark).overlay(MascotTriangle().stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                    .frame(width: s * 0.1, height: s * 0.12)
                    .offset(y: -s * 0.5 * (1 + 0.06 * CGFloat(max(0, sin(t * 0.9))) * a))
                    .rotationEffect(.degrees(ang))
                    .offset(y: s * kind.bodyOffsetY)
            }
            // Tail fin.
            MascotTriangle().rotation(.degrees(90)).fill(pal.accent).overlay(MascotTriangle().rotation(.degrees(90)).stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                .frame(width: s * 0.26, height: s * 0.24)
                .rotationEffect(.degrees(10 * sin(t * 4) * da))
                .offset(x: s * 0.56, y: s * 0.12)
        case .bolt:
            // Antenna with a blinking bulb.
            let on = (t * 1.2).truncatingRemainder(dividingBy: 1) < 0.5 || a == 0
            Capsule().fill(pal.dark).frame(width: s * 0.04, height: s * 0.2).offset(y: -s * 0.4)
            Circle().fill(on ? pal.accent : pal.accent.opacity(0.35)).frame(width: s * 0.12)
                .shadow(color: pal.accent.opacity(on ? 0.9 : 0), radius: s * 0.08)
                .overlay(Circle().stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                .offset(y: -s * 0.52)
            ForEach([-1.0, 1.0], id: \.self) { side in
                RoundedRectangle(cornerRadius: s * 0.04).fill(pal.dark).frame(width: s * 0.1, height: s * 0.22)
                    .offset(x: side * s * 0.52, y: s * 0.1)
            }
        case .glim:
            // Translucent wings, glow abdomen, tiny antennae (sheet 015 — keep id `glim`).
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(Color.white.opacity(0.55)).overlay(Ellipse().stroke(pal.outline.opacity(0.35), lineWidth: 0.8))
                    .frame(width: s * 0.32, height: s * 0.44)
                    .rotationEffect(.degrees(side * (35 + 18 * sin(t * 14) * da)), anchor: .bottom)
                    .offset(x: side * s * 0.22, y: -s * 0.16)
            }
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(pal.mid).frame(width: s * 0.03, height: s * 0.14)
                    .overlay(alignment: .top) { Circle().fill(pal.accent).frame(width: s * 0.06).offset(y: -s * 0.02) }
                    .rotationEffect(.degrees(side * 18 + 4 * sin(t * 2 + side) * da), anchor: .bottom)
                    .offset(x: side * s * 0.1, y: -s * 0.42)
            }
            let pulse = 0.7 + 0.3 * sin(t * 2.2)
            Circle().fill(RadialGradient(colors: [pal.accent, pal.accent.opacity(0.0)], center: .center, startRadius: 0, endRadius: s * 0.32))
                .frame(width: s * 0.64).opacity(pulse)
                .offset(x: s * 0.28, y: s * 0.4)
            Circle().fill(pal.accent).frame(width: s * 0.24).overlay(Circle().stroke(pal.outline.opacity(0.4), lineWidth: 0.8))
                .offset(x: s * 0.26, y: s * 0.38)
        case .comet:
            // Blue–gold trail streaks + sparkles (sheet 012).
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(LinearGradient(colors: [pal.accent.opacity(0.0), pal.accent.opacity(0.9)], startPoint: .trailing, endPoint: .leading))
                    .frame(width: s * (0.56 - CGFloat(i) * 0.1), height: s * 0.08)
                    .offset(x: s * 0.64 + CGFloat(sin(t * 3 + Double(i))) * 2 * a, y: CGFloat(i - 1) * s * 0.14 + s * 0.08)
            }
            ForEach(0..<4, id: \.self) { i in
                MascotSparkleShape().fill(Color.white.opacity(0.85))
                    .frame(width: s * 0.1, height: s * 0.1)
                    .offset(x: s * (0.55 + CGFloat(i) * 0.08), y: s * (-0.1 + CGFloat(i % 2) * 0.2))
                    .opacity(0.6 + 0.4 * sin(t * 2 + Double(i)))
            }
        case .pebble:
            originalsPebbleBehind(s: s, pal: pal, t: t, a: a)
        case .tofu:
            EmptyView()
        default:
            originalsBehind(s: s, pal: pal, t: t, a: a)
        }
    }

    private func ear(pal: ModulaMascotKind.Palette, s: CGFloat, inner: Bool) -> some View {
        ZStack {
            MascotTriangle().fill(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .top, endPoint: .bottom))
            MascotTriangle().stroke(pal.outline.opacity(0.55), lineWidth: max(s * 0.026, 1))
            if inner { MascotTriangle().fill(pal.accent.opacity(0.85)).scaleEffect(0.5).offset(y: s * 0.04) }
        }
    }

    @ViewBuilder
    private func front(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        switch kind {
        case .tuck:
            Ellipse().fill(LinearGradient(colors: [pal.accent, pal.accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.5, height: s * 0.36)
                .offset(y: s * 0.36)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(pal.dark).frame(width: s * 0.2, height: s * 0.42)
                    .rotationEffect(.degrees(side * -14 + side * 6 * sin(t * 1.1) * Double(a)))
                    .offset(x: side * s * 0.43, y: s * 0.22)
            }
        case .moss:
            // Pale belly patch (sheet 002).
            Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.95), pal.accent.opacity(0.85)], center: .center, startRadius: 0, endRadius: s * 0.22))
                .frame(width: s * 0.42, height: s * 0.28)
                .offset(y: s * 0.28)
        case .puff:
            Ellipse().fill(pal.accent.opacity(0.9)).frame(width: s * 0.22, height: s * 0.12)
                .rotationEffect(.degrees(-30 + 12 * sin(t * 5) * Double(a)))
                .offset(x: -s * 0.44, y: s * 0.22)
        case .bun:
            Ellipse().fill(pal.light).frame(width: s * 0.2, height: s * 0.12).offset(y: s * 0.34)
        default:
            originalsFront(s: s, pal: pal, t: t, a: a)
        }
        if kind != .tuck && kind != .bolt {
            let blush: Double = pose.conditions.shy ? 0.95 : (pose.eyes == .happy ? 0.85 : (pose.conditions.morning ? 0.7 : 0.5))
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(RadialGradient(colors: [pal.accent.opacity(blush), .clear], center: .center, startRadius: 0, endRadius: s * 0.1))
                    .frame(width: s * 0.22, height: s * 0.14)
                    .offset(x: side * s * 0.31, y: s * (kind.eyeY + 0.17))
            }
        }
    }

    private func face(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double) -> some View {
        let eye = s * kind.eyeSize
        let widen: CGFloat = pose.mood == .surprised ? 1.22 : 1
        // Dark-bodied Moliboos (Nyx, Jinx, Fuse…) get luminous eyes so they read, like the sheets.
        let darkBody = kind.hasDarkBody
        let glowEyes = pose.conditions.dark || darkBody
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotEye(look: pose.look, blink: pose.blink, style: pose.eyes, spin: t * 6 * side, size: eye * widen, iris: kind == .bolt ? pal.accent : (darkBody ? pal.accent : pal.iris), outline: darkBody ? pal.light : pal.outline, ringed: kind == .tuck ? pal.accent : nil, glow: glowEyes, sad: pose.mood == .sad || pose.conditions.tired, bead: kind != .moss && kind != .bolt)
                    .offset(x: side * s * kind.eyeSpread, y: s * kind.eyeY)
            }
            mouth(s: s, pal: pal, t: t)
                .offset(y: s * kind.mouthY)
        }
    }

    @ViewBuilder
    private func mouth(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double) -> some View {
        let line = StrokeStyle(lineWidth: max(s * 0.034, 1), lineCap: .round, lineJoin: .round)
        let ink = kind == .bolt ? pal.accent : pal.outline.opacity(0.85)
        if pose.mouthOpen > 0.05 {
            Ellipse().fill(ink)
                .overlay(Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.5)).scaleEffect(x: 0.6, y: 0.45).offset(y: s * 0.015))
                .frame(width: s * (pose.yawning ? 0.12 : 0.1), height: s * (0.03 + 0.1 * pose.mouthOpen))
        } else {
            switch pose.mood {
            case .surprised:
                Ellipse().fill(ink).frame(width: s * 0.09, height: s * 0.11)
            case .sleepy:
                Capsule().fill(ink.opacity(0.8)).frame(width: s * 0.07, height: s * 0.025)
            case .thinking, .dizzy:
                MascotSquiggle(phase: t * 4).stroke(ink, style: line).frame(width: s * 0.12, height: s * 0.04)
            case .sad:
                MascotSmile().stroke(ink, style: line).frame(width: s * 0.12, height: s * 0.05).rotationEffect(.degrees(180))
            case .happy, .pleased:
                MascotOpenSmile().fill(ink)
                    .overlay(MascotOpenSmile().fill(Color(red: 1, green: 0.45, blue: 0.5)).scaleEffect(x: 0.5, y: 0.45, anchor: .bottom))
                    .frame(width: s * 0.17, height: s * 0.1)
            default:
                if kind == .tuck {
                    MascotTriangle().rotation(.degrees(180)).fill(Color(red: 0.98, green: 0.72, blue: 0.28))
                        .overlay(MascotTriangle().rotation(.degrees(180)).stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                        .frame(width: s * 0.12, height: s * 0.1).offset(y: -s * 0.08)
                } else if kind == .mochi || kind == .bun {
                    MascotCatMouth().stroke(ink, style: line).frame(width: s * 0.16, height: s * 0.06)
                } else if kind.typingFriendly && pose.mood == .typing {
                    Capsule().fill(ink).frame(width: s * 0.08, height: s * 0.03)
                } else {
                    MascotSmile().stroke(ink, style: line).frame(width: s * (pose.conditions.morning ? 0.17 : 0.15), height: s * 0.06)
                }
            }
        }
    }

    @ViewBuilder
    private func accessories(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let top = -s * (kind.bodySize.height / 2 - kind.bodyOffsetY) // top of body
        if let sp = kind.spec { specParts(sp, layer: .top, s: s, pal: pal, t: t, a: a) }
        if kind == .tuck && outfit.item(for: .face) == nil {
            let r = s * kind.eyeSize * 1.5
            let frame = Color(red: 0.36, green: 0.22, blue: 0.12)
            ZStack {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Circle().stroke(frame, lineWidth: max(s * 0.026, 1))
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .frame(width: r, height: r)
                        .offset(x: side * s * kind.eyeSpread)
                }
                Capsule().fill(frame).frame(width: max(s * kind.eyeSpread * 2 - r, s * 0.04), height: max(s * 0.022, 0.9))
            }
            .offset(y: s * kind.eyeY)
            .rotationEffect(.degrees(7 * sin(t * 0.8) * Double(a)), anchor: .bottom)
        }
        if pose.conditions.night && outfit.item(for: .hat) == nil && outfit.item(for: .seasonal) == nil && outfit.item(for: .hair) == nil {
            // Nightcap with a pom-pom.
            ZStack(alignment: .topTrailing) {
                MascotCapShape()
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.85), Color(red: 0.22, green: 0.26, blue: 0.62)], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotCapShape().stroke(Color(red: 0.12, green: 0.14, blue: 0.36).opacity(0.7), lineWidth: max(s * 0.022, 0.9)))
                Circle().fill(.white).frame(width: s * 0.14).overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.6))
                    .offset(x: s * 0.05, y: -s * 0.04)
            }
            .frame(width: s * 0.52, height: s * 0.34)
            .rotationEffect(.degrees(-14 + 3 * sin(t * 0.8) * Double(a)))
            .offset(x: -s * 0.04, y: top - s * 0.05)
        } else if pose.conditions.morning {
            // Morning glint.
            MascotSparkleShape().fill(Color(red: 1, green: 0.9, blue: 0.45))
                .frame(width: s * 0.16, height: s * 0.16)
                .scaleEffect(0.8 + 0.25 * CGFloat(abs(sin(t * 1.6))) * a + (1 - a) * 0.2)
                .offset(x: s * 0.42, y: top - s * 0.02)
        }
        if pose.conditions.offline && outfit.item(for: .accessory) == nil && outfit.item(for: .top) == nil && outfit.item(for: .outerwear) == nil {
            // Little scarf.
            Capsule().fill(LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.78, green: 0.22, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(Color(red: 0.45, green: 0.1, blue: 0.12).opacity(0.6), lineWidth: 0.8))
                .frame(width: s * kind.bodySize.width * 0.8, height: s * 0.1)
                .offset(y: s * (kind.mouthY + 0.1))
        }
        if pose.conditions.lowPower {
            MascotLeaf().fill(Color(red: 0.98, green: 0.82, blue: 0.2))
                .overlay(MascotLeaf().stroke(Color(red: 0.55, green: 0.42, blue: 0.05).opacity(0.6), lineWidth: 0.8))
                .frame(width: s * 0.2, height: s * 0.1)
                .rotationEffect(.degrees(-40))
                .offset(x: -s * 0.4, y: top + s * 0.05)
        }
    }
}

private extension ModulaMascotKind {
    var typingFriendly: Bool { self == .pebble }
    /// True when the body colour is too dark for dark bead eyes to read.
    var hasDarkBody: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        guard UIColor(palette.mid).getRed(&r, green: &g, blue: &b, alpha: &al) else { return false }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.26
    }
}

struct MascotEye: View {
    var look: CGSize
    var blink: CGFloat
    var style: MascotEyeStyle = .normal
    var spin: Double = 0
    var size: CGFloat
    var iris: Color
    var outline: Color
    var ringed: Color? = nil
    var glow = false
    var sad = false
    /// Mockup-style glossy eye: one deep, dark bead with two catch-lights (no white sclera).
    var bead = false

    var body: some View {
        let travel = size * 0.2
        let lx = max(-1, min(1, look.width)), ly = max(-1, min(1, look.height))
        ZStack {
            if let ringed {
                Circle().fill(ringed).frame(width: size * 1.32, height: size * 1.32)
                    .overlay(Circle().stroke(outline.opacity(0.35), lineWidth: 0.8))
            }
            switch style {
            case .happy:
                MascotHappyEye().stroke(outline, style: StrokeStyle(lineWidth: max(size * 0.16, 1.2), lineCap: .round))
                    .frame(width: size * 0.8, height: size * 0.4)
            case .spiral:
                MascotSpiral().stroke(outline, style: StrokeStyle(lineWidth: max(size * 0.1, 1), lineCap: .round))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .rotationEffect(.radians(spin))
                    .background(Circle().fill(.white))
            case .normal where bead:
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.24, green: 0.19, blue: 0.30), Color(red: 0.06, green: 0.05, blue: 0.09)],
                                                 center: UnitPoint(x: 0.45, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                    // A hint of the character's iris colour glowing up from the bottom of the bead.
                    Circle().fill(RadialGradient(colors: [iris.opacity(glow ? 0.95 : 0.55), .clear], center: UnitPoint(x: 0.5, y: 0.9), startRadius: 0, endRadius: size * (glow ? 0.62 : 0.45)))
                    Circle().fill(.white).frame(width: size * (glow ? 0.42 : 0.38)).offset(x: -size * 0.15 + lx * travel * 0.3, y: -size * 0.16 + ly * travel * 0.3)
                    Circle().fill(.white.opacity(0.9)).frame(width: size * 0.14).offset(x: size * 0.16, y: size * 0.15)
                    Circle().stroke(outline.opacity(0.35), lineWidth: max(size * 0.05, 0.7))
                }
                .clipShape(Circle())
                .frame(width: size * 1.04, height: size * 1.12)
                .offset(x: lx * travel * 0.5, y: ly * travel * 0.5)
                .shadow(color: glow ? iris.opacity(0.6) : .clear, radius: glow ? size * 0.25 : 0)
                .overlay(alignment: .top) {
                    if sad {
                        Capsule().fill(outline.opacity(0.7)).frame(width: size * 0.7, height: max(size * 0.1, 1))
                            .rotationEffect(.degrees(-12)).offset(y: -size * 0.2)
                    }
                }
                .scaleEffect(x: 1, y: max(1 - blink * 0.9, 0.08))
            case .normal:
                ZStack {
                    Circle().fill(RadialGradient(colors: [.white, Color(white: 0.88)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                    ZStack {
                        Circle().fill(RadialGradient(colors: [iris.opacity(0.7), iris], center: UnitPoint(x: 0.5, y: 0.72), startRadius: 0, endRadius: size * 0.3))
                            .frame(width: size * 0.66, height: size * 0.66)
                        Circle().fill(Color(red: 0.05, green: 0.05, blue: 0.08)).frame(width: size * 0.38, height: size * 0.38)
                        Circle().fill(.white).frame(width: size * (glow ? 0.24 : 0.2)).offset(x: -size * 0.11, y: -size * 0.12)
                        Circle().fill(.white.opacity(0.85)).frame(width: size * 0.08).offset(x: size * 0.1, y: size * 0.1)
                    }
                    .offset(x: lx * travel, y: ly * travel)
                    // Upper lid shadow for depth.
                    Circle().fill(LinearGradient(colors: [outline.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                    Circle().stroke(outline.opacity(0.65), lineWidth: max(size * 0.07, 0.9))
                }
                .clipShape(Circle())
                .frame(width: size, height: size)
                .shadow(color: glow ? iris.opacity(0.6) : .clear, radius: glow ? size * 0.25 : 0)
                .overlay(alignment: .top) {
                    if sad {
                        Capsule().fill(outline.opacity(0.7)).frame(width: size * 0.7, height: max(size * 0.1, 1))
                            .rotationEffect(.degrees(-12)).offset(y: -size * 0.16)
                    }
                }
                .scaleEffect(x: 1, y: max(1 - blink * 0.9, 0.08))
            }
        }
    }
}

// MARK: - Shapes

struct MascotTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.15, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.15, y: r.midY))
        p.closeSubpath()
        return p
    }
}

struct MascotFrond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX - r.width * 0.3, y: r.maxY * 0.7), control2: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY), control2: CGPoint(x: r.maxX + r.width * 0.3, y: r.maxY * 0.7))
        return p
    }
}

struct MascotLeaf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.4))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.4))
        p.closeSubpath()
        return p
    }
}

struct MascotTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX * 0.8, y: r.minY), control1: CGPoint(x: r.maxX, y: r.maxY), control2: CGPoint(x: r.maxX * 1.1, y: r.midY))
        return p
    }
}

struct MascotTentacle: Shape {
    var phase: Double
    var amp: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...10 {
            let u = Double(i) / 10
            let x = r.midX + CGFloat(sin(phase + u * 4)) * r.width * 0.5 * CGFloat(u) * max(amp, 0.3)
            let pt = CGPoint(x: x, y: r.minY + r.height * CGFloat(u))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct MascotSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.8))
        return p
    }
}

struct MascotOpenSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.9))
        p.closeSubpath()
        return p
    }
}

struct MascotHappyEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.8))
        return p
    }
}

struct MascotSpiral: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        for i in 0...40 {
            let u = Double(i) / 40
            let a = u * 4 * .pi
            let rad = r.width * 0.45 * CGFloat(u)
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct MascotSquiggle: Shape {
    var phase: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...12 {
            let u = Double(i) / 12
            let pt = CGPoint(x: r.minX + r.width * u, y: r.midY + r.height * 0.5 * sin(u * .pi * 2 + phase))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct MascotCatMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY * 1.4))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY * 1.4))
        return p
    }
}

struct MascotCloudShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + h * 0.32, width: w * 0.48, height: h * 0.6))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.2, y: r.minY, width: w * 0.6, height: h * 0.82))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.52, y: r.minY + h * 0.26, width: w * 0.48, height: h * 0.64))
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.1, y: r.minY + h * 0.48, width: w * 0.8, height: h * 0.52), cornerSize: CGSize(width: h * 0.26, height: h * 0.26))
        return p.normalized(eoFill: false)
    }
}

struct MascotDropShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX + w * 0.56, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.66), control1: CGPoint(x: r.minX + w * 0.72, y: r.minY + h * 0.24), control2: CGPoint(x: r.maxX, y: r.minY + h * 0.38))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.66), control1: CGPoint(x: r.maxX, y: r.maxY + h * 0.07), control2: CGPoint(x: r.minX, y: r.maxY + h * 0.07))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.56, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + h * 0.4), control2: CGPoint(x: r.minX + w * 0.4, y: r.minY + h * 0.24))
        p.closeSubpath()
        return p
    }
}

struct MascotDomeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX, y: r.minY + h * 0.78))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.78), control1: CGPoint(x: r.minX, y: r.minY - h * 0.25), control2: CGPoint(x: r.maxX, y: r.minY - h * 0.25))
        // Scalloped skirt.
        let scallops = 5
        for i in 0..<scallops {
            let x0 = r.maxX - w * CGFloat(i) / CGFloat(scallops)
            let x1 = r.maxX - w * CGFloat(i + 1) / CGFloat(scallops)
            p.addQuadCurve(to: CGPoint(x: x1, y: r.minY + h * 0.78), control: CGPoint(x: (x0 + x1) / 2, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

struct MascotPebbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.58), control1: CGPoint(x: r.minX + w * 0.86, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + h * 0.22))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.46, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + h * 0.92), control2: CGPoint(x: r.minX + w * 0.76, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55), control1: CGPoint(x: r.minX + w * 0.14, y: r.maxY), control2: CGPoint(x: r.minX, y: r.minY + h * 0.86))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + h * 0.2), control2: CGPoint(x: r.minX + w * 0.2, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct MascotStarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.04)
        let outer = min(r.width, r.height) * 0.52, inner = outer * 0.62
        var pts: [CGPoint] = []
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rad = i % 2 == 0 ? outer : inner
            pts.append(CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad))
        }
        // Rounded joins via quad curves through midpoints.
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(pts[9], pts[0]))
        for i in 0..<10 { p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % 10]), control: pts[i]) }
        p.closeSubpath()
        return p
    }
}

struct MascotCapShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.minY + r.height * 0.1), control: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX * 0.92, y: r.maxY), control: CGPoint(x: r.maxX * 0.82, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.15))
        p.closeSubpath()
        return p
    }
}

struct MascotSparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = r.width / 2
        p.move(to: CGPoint(x: c.x, y: c.y - R))
        p.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - R, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: c)
        return p
    }
}


// MARK: - App-wide mascot reactions

/// Lightweight event bus so every on-screen mascot reacts to what the user just did.
enum ModulaMascotEvent: String, Sendable {
    case like, save, repost, share, follow, published, refresh, comment, failure

    static let notification = Notification.Name("modulaMascotEvent")

    static func post(_ event: ModulaMascotEvent) {
        let raw = event.rawValue
        Task { @MainActor in
            NotificationCenter.default.post(name: notification, object: nil, userInfo: ["event": raw])
        }
    }
}

extension MascotBrain {
    func handle(_ event: ModulaMascotEvent) {
        switch event {
        case .like: hop(burst: .hearts); react(.pleased)
        case .save: hop(burst: .sparkle); react(.happy)
        case .repost, .share: hop(burst: .pop); react(.excited)
        case .follow: hop(burst: .confetti, height: 14); react(.celebrate)
        case .published: celebrate()
        case .refresh: hop(burst: nil, height: 7); react(.curious)
        case .comment: hop(burst: .pop, height: 6); react(.speaking)
        case .failure: burst(.tear); react(.sad)
        }
    }
}

// MARK: - Originals 016–025 art

// Native 2D art for Originals 016–025 (Master Bible v1.0): body shapes plus the silhouette parts that sit
// behind and in front of the shared body/face renderer. All sizes are fractions of the figure size `s`.

extension ModulaMascotFigure {
    /// Body outline for the new Originals; nil means the shared default.
    @ViewBuilder
    func originalsMossBehind(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let da = Double(a)
        let outline = StrokeStyle(lineWidth: max(s * 0.026, 1))
        let pad = Color(red: 0.16, green: 0.46, blue: 0.28)
        Ellipse().fill(RadialGradient(colors: [Color(red: 0.28, green: 0.62, blue: 0.36), pad], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.55))
            .overlay(Ellipse().stroke(Color(red: 0.08, green: 0.28, blue: 0.16).opacity(0.7), style: outline))
            .frame(width: s * 1.18, height: s * 0.34)
            .offset(y: s * 0.52)
        ZStack {
            Capsule().fill(Color(red: 0.3, green: 0.7, blue: 0.32)).frame(width: s * 0.035, height: s * 0.12).offset(y: -s * 0.04)
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotLeaf()
                    .fill(LinearGradient(colors: [Color(red: 0.5, green: 0.86, blue: 0.4), Color(red: 0.22, green: 0.56, blue: 0.26)], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotLeaf().stroke(Color(red: 0.12, green: 0.36, blue: 0.16).opacity(0.55), lineWidth: max(s * 0.016, 0.7)))
                    .frame(width: s * 0.16, height: s * 0.1)
                    .rotationEffect(.degrees(side * -28 + 4 * sin(t * 1.6 + side) * da), anchor: side > 0 ? .leading : .trailing)
                    .offset(x: side * s * 0.08, y: -s * 0.1)
            }
        }
        .offset(y: -s * 0.34)
    }

    @ViewBuilder
    func originalsNimbusBehind(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        ForEach(0..<4, id: \.self) { i in
            let x: CGFloat = i == 0 ? -0.52 : (i == 1 ? 0.5 : (i == 2 ? -0.38 : 0.4))
            let y: CGFloat = i == 0 ? -0.18 : (i == 1 ? -0.12 : (i == 2 ? 0.22 : 0.26))
            let r: CGFloat = i == 0 ? 0.28 : (i == 1 ? 0.24 : (i == 2 ? 0.22 : 0.2))
            Circle().fill(RadialGradient(colors: [pal.light, pal.mid], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * r * 0.6))
                .overlay(Circle().stroke(pal.outline.opacity(0.35), lineWidth: max(s * 0.016, 0.7)))
                .frame(width: s * r, height: s * r)
                .offset(x: s * x + CGFloat(sin(t * 0.8 + Double(x))) * s * 0.02 * a, y: s * y)
        }
        ForEach(0..<5, id: \.self) { i in
            let u = (t * 0.28 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
            Circle().fill(pal.accent.opacity(0.45 * (1 - u)))
                .frame(width: s * (0.06 + CGFloat(i % 3) * 0.02))
                .offset(x: s * (0.46 + CGFloat(i) * 0.05), y: s * (-0.1 - CGFloat(u) * 0.4 * a))
        }
    }

    @ViewBuilder
    func originalsPebbleBehind(s: CGFloat, pal: ModulaMascotKind.Palette, t _: Double, a _: CGFloat) -> some View {
        ZStack {
            MascotCapShape()
                .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.7, blue: 0.95), Color(red: 0.28, green: 0.5, blue: 0.82)], startPoint: .top, endPoint: .bottom))
                .overlay(MascotCapShape().stroke(Color(red: 0.16, green: 0.3, blue: 0.52).opacity(0.7), lineWidth: max(s * 0.018, 0.7)))
                .frame(width: s * 0.28, height: s * 0.18)
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotLeaf()
                    .fill(LinearGradient(colors: [Color(red: 0.5, green: 0.86, blue: 0.42), Color(red: 0.22, green: 0.56, blue: 0.26)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.14, height: s * 0.08)
                    .rotationEffect(.degrees(side * -40), anchor: side > 0 ? .leading : .trailing)
                    .offset(x: side * s * 0.08, y: -s * 0.08)
            }
        }
        .offset(x: -s * 0.06, y: -s * 0.38)
        Ellipse().fill(LinearGradient(colors: [pal.light, pal.dark], startPoint: .top, endPoint: .bottom))
            .overlay(Ellipse().stroke(pal.outline.opacity(0.45), lineWidth: 0.7))
            .frame(width: s * 0.12, height: s * 0.084)
            .offset(x: -s * 0.55, y: s * 0.42)
        Ellipse().fill(LinearGradient(colors: [pal.light, pal.dark], startPoint: .top, endPoint: .bottom))
            .overlay(Ellipse().stroke(pal.outline.opacity(0.45), lineWidth: 0.7))
            .frame(width: s * 0.08, height: s * 0.056)
            .offset(x: -s * 0.42, y: s * 0.48)
    }

    func originalsBodyShape() -> AnyShape? {
        switch kind {
        case .prism: AnyShape(MascotCrystalShape())
        case .wisp: AnyShape(MascotWispShape())
        case .doodle: AnyShape(MascotInkShape())
        case .chime: AnyShape(MascotBellShape())
        case .pogo: AnyShape(MascotPearShape())
        case .fable: AnyShape(MascotOrigamiShape())
        default: nil
        }
    }

    @ViewBuilder
    func originalsBehind(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let da = Double(a)
        let line = max(s * 0.026, 1)
        switch kind {
        case .echo:
            // Scalloped wings, oversized pink-inner ears, floating crescent (sheet 016).
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotBatWing()
                    .fill(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotBatWing().stroke(pal.outline.opacity(0.6), lineWidth: line))
                    .frame(width: s * 0.52, height: s * 0.44)
                    .scaleEffect(x: side, y: 1)
                    .rotationEffect(.degrees(side * (8 + 10 * sin(t * 2.4) * da)), anchor: side > 0 ? .leading : .trailing)
                    .offset(x: side * s * 0.54, y: s * 0.06)
                let twitch = da * max(0, sin(t * 1.7 + side) - 0.9) * 90
                ZStack {
                    MascotTriangle().fill(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .top, endPoint: .bottom))
                    MascotTriangle().stroke(pal.outline.opacity(0.6), lineWidth: line)
                    MascotTriangle().fill(pal.accent.opacity(0.95)).scaleEffect(x: 0.52, y: 0.64).offset(y: s * 0.06)
                }
                .frame(width: s * 0.36, height: s * 0.52)
                .rotationEffect(.degrees(side * (16 + twitch)), anchor: .bottom)
                .offset(x: side * s * 0.24, y: -s * 0.42)
            }
            MascotCrescentShape()
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .overlay(MascotCrescentShape().stroke(pal.outline.opacity(0.25), lineWidth: 0.7))
                .frame(width: s * 0.18, height: s * 0.18)
                .offset(x: s * 0.42, y: -s * 0.48)
                .opacity(0.85 + 0.15 * sin(t * 1.4))
        case .quill:
            // Hedgehog mane: two rows of soft spines around the crown and back (sheet 017).
            ForEach(0..<2, id: \.self) { row in
                ForEach(0..<11, id: \.self) { i in
                    let ang = Double(i) * 21 - 105 + Double(row) * 10
                    MascotTriangle()
                        .fill(LinearGradient(colors: row == 0 ? [pal.dark, pal.accent] : [pal.accent, pal.mid], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotTriangle().stroke(pal.outline.opacity(0.5), lineWidth: line))
                        .frame(width: s * (row == 0 ? 0.2 : 0.17), height: s * (row == 0 ? 0.3 : 0.24))
                        .offset(y: -s * (row == 0 ? 0.48 : 0.42))
                        .rotationEffect(.degrees(ang + 2 * sin(t * 1.5 + Double(i)) * da))
                        .offset(y: s * kind.bodyOffsetY)
                }
            }
        case .orbit:
            // Multicolour Saturn ring (sheet 018).
            MascotRingHalf(front: false)
                .stroke(LinearGradient(colors: [Color(red: 0.7, green: 0.4, blue: 1), Color(red: 1, green: 0.6, blue: 0.35), .white], startPoint: .leading, endPoint: .trailing), lineWidth: s * 0.08)
                .frame(width: s * 1.55, height: s * 0.36)
                .rotationEffect(.degrees(-12))
                .offset(y: s * 0.26)
        case .wisp:
            Circle().fill(RadialGradient(colors: [pal.accent.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: s * 0.7))
                .frame(width: s * 1.4).offset(y: s * 0.02)
                .opacity(0.7 + 0.3 * sin(t * 1.3))
        case .chime:
            // Top loop.
            Circle().stroke(LinearGradient(colors: [pal.accent, pal.dark], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.06)
                .frame(width: s * 0.22).offset(y: -s * 0.42)
        case .rolo:
            // The big spiral shell sits behind, to the right; eye stalks rise from the head.
            ZStack {
                Circle().fill(RadialGradient(colors: [pal.accent.opacity(0.75), pal.accent, pal.dark], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.5))
                Circle().stroke(pal.outline.opacity(0.6), lineWidth: line)
                MascotSpiral().stroke(pal.light.opacity(0.85), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
                    .rotationEffect(.radians(t * 0.15 * da))
            }
            .frame(width: s * 0.78, height: s * 0.78)
            .offset(x: s * 0.38, y: -s * 0.08)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(pal.mid).overlay(Capsule().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.06, height: s * 0.26)
                    .overlay(alignment: .top) { Circle().fill(pal.mid).overlay(Circle().stroke(pal.outline.opacity(0.5), lineWidth: line)).frame(width: s * 0.1).offset(y: -s * 0.04) }
                    .rotationEffect(.degrees(side * 14 + 5 * sin(t * 1.2 + side) * da), anchor: .bottom)
                    .offset(x: side * s * 0.12 - s * 0.04, y: -s * 0.4)
            }
        case .pogo:
            // Antenna eyes-stalks (crab-like, per the founding sheet).
            ForEach([-1.0, 1.0], id: \.self) { side in
                VStack(spacing: 0) {
                    Circle().fill(pal.mid).overlay(Circle().stroke(pal.outline.opacity(0.5), lineWidth: line)).frame(width: s * 0.1)
                    Capsule().fill(pal.dark).frame(width: s * 0.03, height: s * 0.18)
                }
                .rotationEffect(.degrees(side * 24 + 6 * sin(t * 2.2 + side) * da), anchor: .bottom)
                .offset(x: side * s * 0.14, y: -s * 0.46)
            }
            // Crab claws on short arms.
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Capsule().fill(pal.dark).frame(width: s * 0.2, height: s * 0.06).offset(x: -side * s * 0.1)
                    MascotClawShape()
                        .fill(RadialGradient(colors: [pal.light, pal.mid, pal.dark], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.2))
                        .overlay(MascotClawShape().stroke(pal.outline.opacity(0.55), lineWidth: line))
                        .frame(width: s * 0.26, height: s * 0.26)
                        .scaleEffect(x: side, y: 1)
                        .rotationEffect(.degrees(side * (-20 + 8 * sin(t * 2.6) * da)))
                        .offset(x: side * s * 0.06, y: -s * 0.04)
                }
                .offset(x: side * s * 0.52, y: s * 0.06)
            }
            // Spring feet.
            ForEach([-1.0, 1.0], id: \.self) { side in
                let squash = 1 + 0.18 * CGFloat(sin(t * 3.2)) * a
                MascotSpring()
                    .stroke(LinearGradient(colors: [pal.accent, pal.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round, lineJoin: .round))
                    .frame(width: s * 0.16, height: s * 0.26 * squash)
                    .overlay(alignment: .bottom) { Capsule().fill(pal.dark).frame(width: s * 0.22, height: s * 0.07).offset(y: s * 0.03) }
                    .offset(x: side * s * 0.18, y: s * 0.52)
            }
        case .fable:
            // Paper flaps + gold origami crown (sheet 025).
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().fill(LinearGradient(colors: [pal.light, pal.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(MascotTriangle().stroke(pal.outline.opacity(0.55), lineWidth: line))
                    .frame(width: s * 0.26, height: s * 0.3)
                    .rotationEffect(.degrees(side * 22), anchor: .bottom)
                    .offset(x: side * s * 0.26, y: -s * 0.36)
                MascotTriangle().fill(Color(red: 0.96, green: 0.9, blue: 0.78).opacity(0.95))
                    .overlay(MascotTriangle().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.24, height: s * 0.34)
                    .rotationEffect(.degrees(side * (100 + 10 * sin(t * 1.8) * da)), anchor: .bottom)
                    .offset(x: side * s * 0.38, y: s * 0.02)
            }
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    MascotTriangle().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.4), Color(red: 0.9, green: 0.65, blue: 0.2)], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotTriangle().stroke(Color(red: 0.55, green: 0.35, blue: 0.08).opacity(0.55), lineWidth: line))
                        .frame(width: s * 0.12, height: s * 0.16)
                        .offset(x: CGFloat(i - 1) * s * 0.1)
                }
            }
            .rotationEffect(.degrees(-8))
            .offset(y: -s * 0.48)
        default:
            if let sp = kind.spec { specParts(sp, layer: .back, s: s, pal: pal, t: t, a: a) }
        }
    }

    @ViewBuilder
    func originalsFront(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let da = Double(a) + 0
        switch kind {
        case .quill:
            // Tiny nose.
            Circle().fill(pal.accent).frame(width: s * 0.07).offset(y: s * 0.17)
        case .orbit:
            MascotRingHalf(front: true)
                .stroke(LinearGradient(colors: [Color(red: 0.7, green: 0.4, blue: 1), Color(red: 1, green: 0.6, blue: 0.35), .white], startPoint: .leading, endPoint: .trailing), lineWidth: s * 0.08)
                .frame(width: s * 1.55, height: s * 0.36)
                .rotationEffect(.degrees(-12))
                .offset(y: s * 0.26)
            ForEach(0..<3, id: \.self) { i in
                let phase = Double(i) * 2.1
                let ang = t * 0.7 * da + phase
                let col: Color = i == 0 ? Color(red: 0.55, green: 0.85, blue: 1) : (i == 1 ? Color(red: 0.55, green: 0.95, blue: 0.6) : Color(red: 0.86, green: 0.6, blue: 1))
                let rad: CGFloat = i == 0 ? 0.11 : (i == 1 ? 0.09 : 0.08)
                Circle().fill(RadialGradient(colors: [col, col.opacity(0.7)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.08))
                    .overlay(Circle().stroke(pal.outline.opacity(0.35), lineWidth: 0.7))
                    .frame(width: s * rad)
                    .offset(x: CGFloat(cos(ang)) * s * 0.64, y: -s * 0.3 + CGFloat(sin(ang)) * s * 0.14)
            }
        case .prism:
            // Facet lines and a rainbow glint.
            MascotCrystalFacets().stroke(.white.opacity(0.6), lineWidth: max(s * 0.014, 0.6))
                .frame(width: s * kind.bodySize.width, height: s * kind.bodySize.height).offset(y: s * kind.bodyOffsetY)
            Capsule().fill(LinearGradient(colors: ([Color.red, .orange, .yellow, .green, .blue, .purple] as [Color]).map { $0.opacity(0.55) }, startPoint: .leading, endPoint: .trailing))
                .frame(width: s * 0.36, height: s * 0.05).rotationEffect(.degrees(-28 + 6 * sin(t) * da))
                .offset(x: s * 0.2, y: -s * 0.26)
        case .doodle:
            // Sketchy outline + floating hearts (sheet 021).
            let j = CGFloat(floor(t * 4).truncatingRemainder(dividingBy: 3)) * a
            MascotInkShape().stroke(pal.outline.opacity(0.75), style: StrokeStyle(lineWidth: max(s * 0.018, 0.8), dash: [s * 0.06, s * 0.025]))
                .frame(width: s * kind.bodySize.width * 1.05, height: s * kind.bodySize.height * 1.05)
                .offset(x: j * 0.8, y: s * kind.bodyOffsetY - j * 0.6)
            ForEach(0..<3, id: \.self) { i in
                MascotHeartShape()
                    .fill(Color.white.opacity(0.95))
                    .overlay(MascotHeartShape().stroke(pal.outline.opacity(0.35), lineWidth: 0.6))
                    .frame(width: s * (0.1 - CGFloat(i) * 0.015), height: s * (0.1 - CGFloat(i) * 0.015))
                    .offset(x: s * (0.42 + CGFloat(i) * 0.08), y: -s * (0.28 + CGFloat(i) * 0.08) - CGFloat(sin(t + Double(i))) * s * 0.02 * a)
            }
        case .chime:
            // Clapper + floating notes and sparkles (sheet 022).
            Circle().fill(pal.accent).overlay(Circle().stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                .frame(width: s * 0.14)
                .offset(x: CGFloat(sin(t * 2.4)) * s * 0.05 * a, y: s * 0.56)
            ForEach(0..<3, id: \.self) { i in
                let u = (t * 0.45 + Double(i) * 0.28).truncatingRemainder(dividingBy: 1)
                Text(i == 1 ? "♫" : "♪").font(.system(size: s * (0.18 - CGFloat(i) * 0.02), weight: .bold)).foregroundStyle(pal.accent.opacity(1 - u * 0.5))
                    .offset(x: s * (0.42 + CGFloat(i) * 0.08), y: -s * (0.2 + CGFloat(u) * 0.28 * a) + CGFloat(i) * s * 0.06)
            }
            ForEach(0..<3, id: \.self) { i in
                MascotSparkleShape().fill(pal.light.opacity(0.9))
                    .frame(width: s * 0.08, height: s * 0.08)
                    .offset(x: -s * (0.4 + CGFloat(i) * 0.06), y: -s * (0.1 + CGFloat(i) * 0.08))
            }
        case .fable:
            MascotOrigamiFolds().stroke(pal.outline.opacity(0.35), lineWidth: max(s * 0.012, 0.6))
                .frame(width: s * kind.bodySize.width, height: s * kind.bodySize.height).offset(y: s * kind.bodyOffsetY)
        case .wisp:
            ForEach(0..<3, id: \.self) { i in
                let u = (t * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle().fill(.white.opacity(0.7 * (1 - u)))
                    .frame(width: s * 0.06)
                    .offset(x: s * (CGFloat(i) - 1) * 0.22, y: s * (0.5 - CGFloat(u) * 0.4 * a))
            }
        default:
            if let sp = kind.spec { specParts(sp, layer: .front, s: s, pal: pal, t: t, a: a) }
        }
    }
}

// MARK: - Shapes

struct MascotBatWing: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.maxY * 0.9))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.66, y: r.minY + r.height * 0.72), control: CGPoint(x: r.minX + r.width * 0.84, y: r.minY + r.height * 0.62))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.34, y: r.minY + r.height * 0.78), control: CGPoint(x: r.minX + r.width * 0.5, y: r.minY + r.height * 0.6))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.7), control: CGPoint(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

struct MascotRingHalf: Shape {
    var front: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(front ? 0 : 180), endAngle: .degrees(front ? 180 : 360), clockwise: false)
        return p.applying(CGAffineTransform(translationX: -r.midX, y: -r.midY).concatenating(CGAffineTransform(scaleX: 1, y: r.height / r.width)).concatenating(CGAffineTransform(translationX: r.midX, y: r.midY)))
    }
}

struct MascotCrystalShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let pts = [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.92, y: 0.2), CGPoint(x: 1, y: 0.64), CGPoint(x: 0.62, y: 1), CGPoint(x: 0.3, y: 0.98), CGPoint(x: 0, y: 0.62), CGPoint(x: 0.1, y: 0.18)]
            .map { CGPoint(x: r.minX + $0.x * w, y: r.minY + $0.y * h) }
        return Path(roundedPolygon: pts, radius: min(w, h) * 0.08)
    }
}

struct MascotCrystalFacets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        p.move(to: pt(0.1, 0.18)); p.addLine(to: pt(0.36, 0.26)); p.addLine(to: pt(0.5, 0.02))
        p.move(to: pt(0.36, 0.26)); p.addLine(to: pt(0.72, 0.24)); p.addLine(to: pt(0.92, 0.2))
        p.move(to: pt(0.72, 0.24)); p.addLine(to: pt(0.5, 0.02))
        return p
    }
}

struct MascotWispShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.42), control1: CGPoint(x: r.minX + w * 0.82, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + h * 0.18))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.66, y: r.maxY - h * 0.12), control1: CGPoint(x: r.maxX, y: r.minY + h * 0.66), control2: CGPoint(x: r.minX + w * 0.82, y: r.minY + h * 0.78))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.58, y: r.maxY), control: CGPoint(x: r.minX + w * 0.56, y: r.maxY - h * 0.04))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.4, y: r.maxY - h * 0.1), control: CGPoint(x: r.minX + w * 0.5, y: r.maxY - h * 0.12))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.24, y: r.maxY - h * 0.04), control: CGPoint(x: r.minX + w * 0.32, y: r.maxY - h * 0.02))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.42), control1: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.74), control2: CGPoint(x: r.minX, y: r.minY + h * 0.62))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + h * 0.18), control2: CGPoint(x: r.minX + w * 0.18, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct MascotInkShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let radii: [CGFloat] = [1, 0.9, 1.04, 0.86, 0.98, 1.06, 0.88, 0.96]
        let pts: [CGPoint] = radii.enumerated().map { i, k in
            let a = Double(i) / Double(radii.count) * 2 * .pi - .pi / 2
            return CGPoint(x: c.x + CGFloat(cos(a)) * r.width / 2 * k, y: c.y + CGFloat(sin(a)) * r.height / 2 * k)
        }
        var p = Path()
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if i == 0 { p.move(to: CGPoint(x: (pts.last!.x + a.x) / 2, y: (pts.last!.y + a.y) / 2)) }
            p.addQuadCurve(to: mid, control: a)
        }
        p.closeSubpath()
        return p
    }
}

struct MascotBellShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.86, y: r.minY + h * 0.62), control1: CGPoint(x: r.minX + w * 0.84, y: r.minY), control2: CGPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.36))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - h * 0.06), control: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.84))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - h * 0.06), control: CGPoint(x: r.midX, y: r.maxY + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.14, y: r.minY + h * 0.62), control: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.84))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.36), control2: CGPoint(x: r.minX + w * 0.16, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct MascotPearShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.68), control1: CGPoint(x: r.minX + w * 0.8, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + h * 0.36))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.68), control1: CGPoint(x: r.maxX, y: r.maxY + h * 0.04), control2: CGPoint(x: r.minX, y: r.maxY + h * 0.04))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + h * 0.36), control2: CGPoint(x: r.minX + w * 0.2, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct MascotOrigamiShape: Shape {
    func path(in r: CGRect) -> Path {
        let pts = [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.88, y: 0.14), CGPoint(x: 1, y: 0.56), CGPoint(x: 0.78, y: 1), CGPoint(x: 0.22, y: 1), CGPoint(x: 0, y: 0.56), CGPoint(x: 0.12, y: 0.14)]
            .map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        return Path(roundedPolygon: pts, radius: min(r.width, r.height) * 0.03)
    }
}

struct MascotOrigamiFolds: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        p.move(to: pt(0.5, 0)); p.addLine(to: pt(0.5, 0.3))
        p.move(to: pt(0.12, 0.14)); p.addLine(to: pt(0.5, 0.3)); p.addLine(to: pt(0.88, 0.14))
        p.move(to: pt(0.22, 1)); p.addLine(to: pt(0.36, 0.78))
        p.move(to: pt(0.78, 1)); p.addLine(to: pt(0.64, 0.78))
        return p
    }
}

struct MascotSpring: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let coils = 4
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        for i in 0..<coils {
            let y0 = r.minY + r.height * CGFloat(i) / CGFloat(coils)
            let y1 = r.minY + r.height * (CGFloat(i) + 0.5) / CGFloat(coils)
            let y2 = r.minY + r.height * CGFloat(i + 1) / CGFloat(coils)
            _ = y0
            p.addLine(to: CGPoint(x: r.maxX, y: y1))
            p.addLine(to: CGPoint(x: r.minX, y: (y1 + y2) / 2 + r.height * 0.04))
        }
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

extension Path {
    /// Closed polygon with softly rounded corners.
    init(roundedPolygon pts: [CGPoint], radius: CGFloat) {
        self.init()
        guard pts.count > 2 else { return }
        let n = pts.count
        let start = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
        move(to: start)
        for i in 0..<n {
            let next = pts[(i + 1) % n]
            addArc(tangent1End: pts[i], tangent2End: CGPoint(x: (pts[i].x + next.x) / 2, y: (pts[i].y + next.y) / 2), radius: radius)
        }
        closeSubpath()
    }
}

// MARK: - Roster: families, worlds and catalogue profiles (Master Bible v1.0 + family bibles)

enum MolibooFamily: String, CaseIterable, Identifiable, Sendable {
    case originals, angels, underground, enchanted, stardust, dreamers
    var id: String { rawValue }
    var name: String {
        switch self {
        case .originals: "The Originals"
        case .angels: "Moliboo Angels"
        case .underground: "Moliboo Underground"
        case .enchanted: "Moliboo Enchanted"
        case .stardust: "Moliboo Stardust"
        case .dreamers: "Moliboo Dreamers"
        }
    }
    /// Working world names from the family bibles (Originals live in the home world).
    var world: String {
        switch self {
        case .originals: "Home"
        case .angels: "Celestia"
        case .underground: "The Underground"
        case .enchanted: "The Luminous Wilds"
        case .stardust: "The Stardust Reach"
        case .dreamers: "The Dreaming Vale"
        }
    }
    var range: ClosedRange<Int> {
        switch self {
        case .originals: 1...25
        case .angels: 26...40
        case .underground: 41...55
        case .enchanted: 56...70
        case .stardust: 71...85
        case .dreamers: 86...100
        }
    }
    /// Precomputed once — filtering allCases on every World body eval was O(families × kinds).
    var kinds: [ModulaMascotKind] { Self.kindsByFamily[self] ?? [] }
    private static let kindsByFamily: [MolibooFamily: [ModulaMascotKind]] = {
        var map: [MolibooFamily: [ModulaMascotKind]] = [:]
        for k in ModulaMascotKind.allCases {
            map[k.family, default: []].append(k)
        }
        for f in MolibooFamily.allCases {
            map[f] = (map[f] ?? []).sorted { $0.number < $1.number }
        }
        return map
    }()
}

extension ModulaMascotKind {
    struct Profile: Sendable { let number: Int; let title: String; let traits: [String] }
    var profile: Profile {
        switch self {
        case .pip: Profile(number: 1, title: "Social Spark", traits: ["Outgoing", "Affectionate", "Excitable"])
        case .moss: Profile(number: 2, title: "The Unbothered One", traits: ["Unbothered", "Patient", "Dry humour"])
        case .nimbus: Profile(number: 3, title: "Wandering Dreamer", traits: ["Dreamy", "Imaginative", "Gentle"])
        case .mochi: Profile(number: 4, title: "Sleepy Observer", traits: ["Sleepy", "Independent", "Secretly affectionate"])
        case .sprout: Profile(number: 5, title: "Little Optimist", traits: ["Hopeful", "Nurturing", "Optimistic"])
        case .ember: Profile(number: 6, title: "Tiny Firecracker", traits: ["Brave", "Impatient", "Passionate"])
        case .tuck: Profile(number: 7, title: "Curious Scholar", traits: ["Curious", "Bookish", "Precise"])
        case .bloop: Profile(number: 8, title: "Gentle Drifter", traits: ["Gentle", "Sensitive", "Shy"])
        case .bun: Profile(number: 9, title: "Little Adventurer", traits: ["Adventurous", "Friendly", "Impulsive"])
        case .pebble: Profile(number: 10, title: "Quiet Guardian", traits: ["Reserved", "Reliable", "Quietly protective"])
        case .tofu: Profile(number: 11, title: "Wobbly Optimist", traits: ["Cheerful", "Innocent", "Optimistic"])
        case .comet: Profile(number: 12, title: "Restless Star", traits: ["Impatient", "Competitive", "Generous"])
        case .puff: Profile(number: 13, title: "Little Defender", traits: ["Dramatic", "Nervous", "Funny"])
        case .bolt: Profile(number: 14, title: "Pocket Inventor", traits: ["Analytical", "Inventive", "Curious"])
        case .glim: Profile(number: 15, title: "Keeper of Little Lights", traits: ["Kind", "Shy", "Guiding"])
        case .echo: Profile(number: 16, title: "Night Listener", traits: ["Perceptive", "Cautious", "Gentle"])
        case .quill: Profile(number: 17, title: "Little Protector", traits: ["Protective", "Careful", "Sincere"])
        case .orbit: Profile(number: 18, title: "Little Explorer", traits: ["Curious", "Philosophical", "Adventurous"])
        case .prism: Profile(number: 19, title: "Keeper of Colours", traits: ["Mysterious", "Calm", "Artistic"])
        case .wisp: Profile(number: 20, title: "Friendly Mystery", traits: ["Mischievous", "Elusive", "Kind"])
        case .doodle: Profile(number: 21, title: "Living Imagination", traits: ["Inventive", "Spontaneous", "Mischievous"])
        case .chime: Profile(number: 22, title: "Little Music Maker", traits: ["Musical", "Cheerful", "Sensitive"])
        case .rolo: Profile(number: 23, title: "Slow Philosopher", traits: ["Wise", "Patient", "Quietly funny"])
        case .pogo: Profile(number: 24, title: "Unstoppable Bouncer", traits: ["Restless", "Playful", "Fearless"])
        case .fable: Profile(number: 25, title: "Keeper of Stories", traits: ["Thoughtful", "Imaginative", "Reflective"])
        default: MolibooFamilySpecs.profiles[self] ?? Profile(number: 999, title: name, traits: [])
        }
    }
    var number: Int { profile.number }
    var title: String { profile.title }
    var traits: [String] { profile.traits }
    var catalogueNumber: String { String(format: "%03d", number) }
    var family: MolibooFamily { MolibooFamily.allCases.first { $0.range.contains(number) } ?? .originals }
}

// MARK: - Family parts kit (Families 002–006)
//
// Data-driven 2D characters: a body outline, a palette and a list of silhouette parts. Every part is a
// native SwiftUI shape scaled to the figure size `s`, so the shared face, expressions, idle motion, wardrobe
// rig (head anchor + hat scale) and ground shadow work for every family member.

enum MolibooSpecBody: Sendable {
    case round, wide, tall, pear, drop, heart, star, cloud, crystal, ink, bell, wisp, origami, square, dome, pebble
}

enum MolibooEar: Sendable { case cat, fox, bat, bunny, round, mouse, tufts, floppy, ring }
enum MolibooWing: Sendable { case feather, bat, moth, insect, fairy, leaf, dart, round }
enum MolibooTail: Sendable { case fluffy, ribbon, curl, lizard, whale, fox, comet, disk, plume, spring }

enum MolibooPart: Sendable {
    case halo, starCrest, heartAntenna, nightcap(Color), crown
    case wings(MolibooWing, Color?), ears(MolibooEar), tail(MolibooTail, Color?)
    case rays(Int, Color?), mane(Int), crescent(Color?), ring(Color?), harp, sparkles(Int), notes
    case antennae(Color?), leaves(Int, Color?), petals(Int, Color?), mushroomCap(Color, spots: Bool), thorns(Color?)
    case antlers(Color?), starAntlers, shell(Color?), speakers, headphones(Color?), pixels(Color?), lightning
    case wheels, fins(Color?), orbiters(Int, Color?), compass, flame(Color?), mask(Color), hood(Color), roots
    case paintDrips([Color]), goggles(Color), whiskers, bowtie(Color), scarf(Color), blanket(Color), lantern(Color)
    case glow(Color), feet(Color?), beak, berries(Color), feathers(Color?), frill(Color?), visor(Color), cheeksStars
    // Part-2 fidelity parts (sheet details). Head-top props hide when a hat is worn so wardrobe always fits.
    case skateboard(Color), cap(Color), tendrils(Color), puddle(Color), rockSeams(Color), arms(Color), crystals(Color), nose(Color), paws(Color)
    case cloudSeat(Color), shield(Color), wreath(Color, Color?), legs(Color), moonMark(Color)
}

struct MolibooSpec: Sendable {
    var body: MolibooSpecBody = .round
    var size = CGSize(width: 0.98, height: 0.86)
    var palette: ModulaMascotKind.Palette
    var parts: [MolibooPart] = []
    var floats = false
    var feet = true
    var hatScale: CGFloat = 1
    var hatMaxWidth: CGFloat? = nil
    var headTopExtra: CGFloat? = nil
    var form: String = ""
}

extension ModulaMascotKind.Palette {
    /// Builds a full shading palette from a main colour, an accent and an eye colour.
    static func spec(_ mid: Color, accent: Color, iris: Color = Color(red: 0.16, green: 0.12, blue: 0.24), light: Color? = nil, dark: Color? = nil, outline: Color? = nil) -> Self {
        let ui = UIColor(mid)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let l = light ?? Color(hue: h, saturation: s * 0.45, brightness: min(1, b * 1.12 + 0.08))
        let d = dark ?? Color(hue: h, saturation: min(1, s * 1.15 + 0.05), brightness: b * 0.72)
        let o = outline ?? Color(hue: h, saturation: min(1, s * 0.9 + 0.2), brightness: b * 0.42)
        return .init(light: l, mid: mid, dark: d, accent: accent, iris: iris, outline: o)
    }
}

struct MascotHeartShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32), control1: CGPoint(x: r.minX + w * 0.22, y: r.maxY - h * 0.16), control2: CGPoint(x: r.minX, y: r.minY + h * 0.58))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.2), control1: CGPoint(x: r.minX, y: r.minY), control2: CGPoint(x: r.minX + w * 0.42, y: r.minY - h * 0.02))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.32), control1: CGPoint(x: r.minX + w * 0.58, y: r.minY - h * 0.02), control2: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + h * 0.58), control2: CGPoint(x: r.maxX - w * 0.22, y: r.maxY - h * 0.16))
        p.closeSubpath()
        return p
    }
}

struct MascotCrescentShape: Shape {
    func path(in r: CGRect) -> Path {
        var outer = Path(ellipseIn: r)
        let inner = Path(ellipseIn: r.offsetBy(dx: r.width * 0.3, dy: -r.height * 0.12))
        outer = outer.subtracting(inner)
        return outer
    }
}

struct MascotFeatherWing: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY * 0.75 + r.minY * 0.25))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.8, y: r.minY + r.height * 0.42), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.62, y: r.minY + r.height * 0.7), control: CGPoint(x: r.minX + r.width * 0.84, y: r.minY + r.height * 0.62))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.32, y: r.maxY), control: CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.92))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY * 0.75 + r.minY * 0.25), control: CGPoint(x: r.minX + r.width * 0.1, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

extension ModulaMascotFigure {
    func specBodyShape(_ b: MolibooSpecBody) -> AnyShape {
        switch b {
        case .round, .wide, .tall: AnyShape(Ellipse())
        case .pear: AnyShape(MascotPearShape())
        case .drop: AnyShape(MascotDropShape())
        case .heart: AnyShape(MascotHeartShape())
        case .star: AnyShape(MascotStarShape())
        case .cloud: AnyShape(MascotCloudShape())
        case .crystal: AnyShape(MascotCrystalShape())
        case .ink: AnyShape(MascotInkShape())
        case .bell: AnyShape(MascotBellShape())
        case .wisp: AnyShape(MascotWispShape())
        case .origami: AnyShape(MascotOrigamiShape())
        case .square: AnyShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        case .dome: AnyShape(MascotDomeShape())
        case .pebble: AnyShape(MascotPebbleShape())
        }
    }

    enum SpecLayer { case back, front, top }

    @ViewBuilder
    func specParts(_ spec: MolibooSpec, layer: SpecLayer, s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        ForEach(Array(spec.parts.enumerated()), id: \.offset) { i, part in
            specPart(part, spec: spec, layer: layer, s: s, pal: pal, t: t, a: a, seed: Double(i))
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @ViewBuilder
    private func specPart(_ part: MolibooPart, spec: MolibooSpec, layer: SpecLayer, s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat, seed: Double) -> some View {
        let da = Double(a)
        let line = max(s * 0.024, 0.9)
        let bw = s * spec.size.width, bh = s * spec.size.height
        let top = -s * (spec.size.height / 2 - kind.bodyOffsetY)
        let cy = s * kind.bodyOffsetY
        let gold = Color(red: 1, green: 0.84, blue: 0.42)
        switch (part, layer) {
        // ── Back layer ───────────────────────────────────────────
        case (.glow(let c), .back):
            Circle().fill(RadialGradient(colors: [c.opacity(0.55), c.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.8))
                .frame(width: s * 1.6).offset(y: cy).opacity(0.75 + 0.25 * sin(t * 1.4 + seed))
        case (.rays(let n, let c), .back):
            ForEach(0..<n, id: \.self) { k in
                MascotTriangle().fill(LinearGradient(colors: [c ?? pal.accent, (c ?? pal.accent).opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(pal.outline.opacity(0.35), lineWidth: line))
                    .frame(width: s * 0.2, height: s * 0.24)
                    .offset(y: -max(bw, bh) * 0.5 - s * 0.08)
                    .rotationEffect(.degrees(Double(k) / Double(n) * 360 + 6 * sin(t * 0.8) * da))
                    .offset(y: cy)
            }
        case (.mane(let n), .back):
            ForEach(0..<n, id: \.self) { k in
                Ellipse().fill(LinearGradient(colors: [pal.accent, pal.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(pal.outline.opacity(0.4), lineWidth: line))
                    .frame(width: s * 0.22, height: s * 0.36)
                    .offset(y: -s * 0.42)
                    .rotationEffect(.degrees(Double(k) / Double(n) * 360))
                    .offset(y: cy - s * 0.06)
            }
        case (.wings(let style, let c), .back):
            let col = c ?? .white
            ForEach([-1.0, 1.0], id: \.self) { side in
                let flap = (style == .insect || style == .dart || style == .fairy ? 16 * sin(t * 12) : 10 * sin(t * 2.2)) * da
                Group {
                    switch style {
                    case .feather:
                        MascotFeatherWing().fill(LinearGradient(colors: [col, col.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            .overlay(MascotFeatherWing().stroke(pal.outline.opacity(0.3), lineWidth: line))
                            .frame(width: s * 0.46, height: s * 0.4)
                    case .bat:
                        MascotBatWing().fill(LinearGradient(colors: [col, pal.dark], startPoint: .top, endPoint: .bottom))
                            .overlay(MascotBatWing().stroke(pal.outline.opacity(0.55), lineWidth: line))
                            .frame(width: s * 0.5, height: s * 0.42)
                    case .moth, .round:
                        ZStack {
                            Ellipse().fill(LinearGradient(colors: [col, pal.dark], startPoint: .top, endPoint: .bottom))
                            Ellipse().stroke(pal.outline.opacity(0.5), lineWidth: line)
                            Circle().fill(style == .moth ? pal.accent.opacity(0.9) : .clear).frame(width: s * 0.12).offset(x: s * 0.04, y: -s * 0.04)
                        }
                        .frame(width: s * 0.44, height: s * 0.5)
                    case .insect, .fairy:
                        Ellipse().fill(col.opacity(style == .fairy ? 0.6 : 0.5))
                            .overlay(Ellipse().stroke(pal.outline.opacity(0.3), lineWidth: line * 0.7))
                            .frame(width: s * 0.3, height: s * 0.46)
                    case .leaf:
                        MascotLeaf().fill(LinearGradient(colors: [col, pal.dark], startPoint: .leading, endPoint: .trailing))
                            .overlay(MascotLeaf().stroke(pal.outline.opacity(0.5), lineWidth: line))
                            .frame(width: s * 0.46, height: s * 0.24)
                    case .dart:
                        VStack(spacing: s * 0.01) {
                            ForEach(0..<3, id: \.self) { _ in MascotTriangle().rotation(.degrees(90)).fill(col.opacity(0.75)).frame(width: s * 0.22, height: s * 0.09) }
                        }
                    }
                }
                .scaleEffect(x: side, y: 1)
                .rotationEffect(.degrees(side * (style == .insect || style == .fairy || style == .moth ? 30 : 6) + side * flap), anchor: side > 0 ? .leading : .trailing)
                .offset(x: side * (bw * 0.5 + s * 0.14), y: cy - s * 0.04)
            }
        case (.ears(let style), .back):
            ForEach([-1.0, 1.0], id: \.self) { side in
                let twitch = da * max(0, sin(t * 1.7 + side) - 0.92) * 80
                Group {
                    switch style {
                    case .cat, .fox, .bat:
                        ZStack {
                            MascotTriangle().fill(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .top, endPoint: .bottom))
                            MascotTriangle().stroke(pal.outline.opacity(0.55), lineWidth: line)
                            MascotTriangle().fill(pal.accent.opacity(0.85)).scaleEffect(0.5).offset(y: s * 0.04)
                        }
                        .frame(width: s * (style == .bat ? 0.32 : 0.28), height: s * (style == .fox ? 0.38 : style == .bat ? 0.46 : 0.3))
                    case .bunny, .floppy:
                        ZStack {
                            Capsule().fill(LinearGradient(colors: [pal.light, pal.mid], startPoint: .top, endPoint: .bottom))
                            Capsule().stroke(pal.outline.opacity(0.5), lineWidth: line)
                            Capsule().fill(pal.accent.opacity(0.7)).scaleEffect(x: 0.45, y: 0.75)
                        }
                        .frame(width: s * 0.18, height: s * 0.46)
                        .rotationEffect(.degrees(style == .floppy ? side * 60 : 0), anchor: .bottom)
                    case .round, .mouse:
                        ZStack {
                            Circle().fill(pal.mid)
                            Circle().stroke(pal.outline.opacity(0.5), lineWidth: line)
                            Circle().fill(pal.accent.opacity(0.7)).scaleEffect(0.55)
                        }
                        .frame(width: s * (style == .mouse ? 0.34 : 0.22))
                    case .tufts:
                        MascotTriangle().fill(pal.dark).overlay(MascotTriangle().stroke(pal.outline.opacity(0.5), lineWidth: line))
                            .frame(width: s * 0.16, height: s * 0.24)
                    case .ring:
                        Circle().stroke(LinearGradient(colors: [pal.accent, gold], startPoint: .top, endPoint: .bottom), lineWidth: s * 0.05)
                            .frame(width: s * 0.26)
                            .rotation3DEffect(.degrees(30 * sin(t * 2) * da), axis: (x: 0, y: 1, z: 0))
                    }
                }
                .rotationEffect(.degrees(side * (style == .round || style == .mouse ? 0 : 18) + side * twitch), anchor: .bottom)
                .offset(x: side * bw * (style == .mouse || style == .round ? 0.36 : 0.26), y: top + s * (style == .bunny || style == .floppy ? -0.16 : style == .round || style == .mouse ? 0.02 : -0.06))
            }
        case (.tail(let style, let c), .back):
            let col = c ?? pal.mid
            let wag = 10 * sin(t * 1.6 + seed) * da
            Group {
                switch style {
                case .fluffy, .fox:
                    Ellipse().fill(LinearGradient(colors: [col, style == .fox ? .white : pal.dark], startPoint: .leading, endPoint: .trailing))
                        .overlay(Ellipse().stroke(pal.outline.opacity(0.45), lineWidth: line))
                        .frame(width: s * 0.42, height: s * 0.26)
                case .ribbon, .comet, .plume:
                    MascotTail().stroke(LinearGradient(colors: [col, (c ?? pal.accent).opacity(0.1)], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: s * (style == .plume ? 0.16 : 0.1), lineCap: .round))
                        .frame(width: s * 0.6, height: s * 0.4)
                case .curl:
                    MascotTail().stroke(col, style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round)).frame(width: s * 0.34, height: s * 0.4)
                case .lizard:
                    MascotTriangle().rotation(.degrees(90)).fill(col).overlay(MascotTriangle().rotation(.degrees(90)).stroke(pal.outline.opacity(0.5), lineWidth: line))
                        .frame(width: s * 0.42, height: s * 0.16)
                case .whale:
                    MascotHeartShape().rotation(.degrees(-90)).fill(col).overlay(MascotHeartShape().rotation(.degrees(-90)).stroke(pal.outline.opacity(0.5), lineWidth: line))
                        .frame(width: s * 0.26, height: s * 0.26)
                case .disk:
                    Circle().fill(RadialGradient(colors: [gold, col], center: .center, startRadius: 0, endRadius: s * 0.12)).frame(width: s * 0.22)
                case .spring:
                    MascotSpring().stroke(col, style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round)).frame(width: s * 0.12, height: s * 0.24).rotationEffect(.degrees(-60))
                }
            }
            .rotationEffect(.degrees(wag), anchor: .leading)
            .offset(x: bw * 0.5 + s * 0.16, y: cy + s * 0.08)
        case (.crescent(let c), .back):
            MascotCrescentShape().fill(LinearGradient(colors: [c ?? .white, (c ?? pal.accent).opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .overlay(MascotCrescentShape().stroke(pal.outline.opacity(0.35), lineWidth: line))
                .frame(width: s * 1.25, height: s * 1.25)
                .rotationEffect(.degrees(-20 + 4 * sin(t * 0.7) * da))
                .offset(x: -s * 0.12, y: cy - s * 0.04)
        case (.ring(let c), .back):
            MascotRingHalf(front: false).stroke(c ?? gold, lineWidth: s * 0.06)
                .frame(width: bw * 1.5, height: s * 0.32).rotationEffect(.degrees(-14)).offset(y: cy + s * 0.08)
        case (.harp, .back):
            ZStack {
                MascotTail().stroke(gold, style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round)).frame(width: s * 0.42, height: s * 0.7)
                ForEach(0..<4, id: \.self) { k in Capsule().fill(Color.white.opacity(0.8)).frame(width: 1, height: s * (0.36 + CGFloat(k) * 0.06)).offset(x: s * (-0.08 + CGFloat(k) * 0.06)) }
            }
            .offset(x: bw * 0.42, y: cy - s * 0.06)
        case (.shell(let c), .back):
            ZStack {
                Circle().fill(RadialGradient(colors: [(c ?? pal.accent).opacity(0.75), c ?? pal.accent, pal.dark], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.5))
                Circle().stroke(pal.outline.opacity(0.55), lineWidth: line)
                MascotSpiral().stroke(pal.light.opacity(0.8), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
            }
            .frame(width: s * 0.74, height: s * 0.74).offset(x: s * 0.34, y: cy - s * 0.16)
        case (.thorns(let c), .back), (.feathers(let c), .back):
            ForEach(0..<7, id: \.self) { k in
                MascotTriangle().fill(c ?? pal.dark).overlay(MascotTriangle().stroke(pal.outline.opacity(0.45), lineWidth: line))
                    .frame(width: s * 0.14, height: s * 0.24).offset(y: -max(bw, bh) * 0.48 - s * 0.04)
                    .rotationEffect(.degrees(Double(k) * 24 - 72 + 3 * sin(t + Double(k)) * da)).offset(y: cy)
            }
        case (.frill(let c), .back):
            ForEach([-1.0, 1.0], id: \.self) { side in
                ForEach(0..<3, id: \.self) { k in
                    MascotFrond().fill(c ?? pal.accent).overlay(MascotFrond().stroke(pal.outline.opacity(0.5), lineWidth: line))
                        .frame(width: s * 0.13, height: s * 0.3).offset(y: -s * 0.15)
                        .rotationEffect(.degrees(side * (50 + Double(k - 1) * 28 + 7 * sin(t * 3 + Double(k)) * da)), anchor: .bottom)
                        .offset(x: side * bw * 0.4, y: cy)
                }
            }
        case (.fins(let c), .back):
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().rotation(.degrees(side * 90)).fill(c ?? pal.accent).overlay(MascotTriangle().rotation(.degrees(side * 90)).stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.26, height: s * 0.2)
                    .rotationEffect(.degrees(side * 10 * sin(t * 2.4) * da))
                    .offset(x: side * (bw * 0.5 + s * 0.08), y: cy + s * 0.06)
            }
        case (.flame(let c), .back):
            MascotDropShape().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.4), c ?? .orange], startPoint: .bottom, endPoint: .top))
                .frame(width: s * 0.4, height: s * 0.62).rotationEffect(.degrees(-70 + 6 * sin(t * 6) * da))
                .offset(x: -bw * 0.5 - s * 0.12, y: cy)
        case (.blanket(let c), .back):
            RoundedRectangle(cornerRadius: s * 0.12).fill(c).overlay(RoundedRectangle(cornerRadius: s * 0.12).stroke(pal.outline.opacity(0.4), lineWidth: line))
                .frame(width: bw * 1.25, height: bh * 0.6).rotationEffect(.degrees(-6)).offset(y: cy + bh * 0.22)
        case (.roots, .back):
            ForEach(0..<4, id: \.self) { k in
                Capsule().fill(pal.dark).frame(width: s * 0.05, height: s * 0.2)
                    .rotationEffect(.degrees(Double(k - 2) * 18 + 9)).offset(x: s * (CGFloat(k) - 1.5) * 0.12, y: cy + bh * 0.5 + s * 0.04)
            }
        case (.tendrils(let c), .back):
            // Ink-like tendrils curling out from the sides of a shadow pool.
            ForEach(0..<4, id: \.self) { k in
                let side: Double = k < 2 ? -1 : 1
                let ang = side * (k % 2 == 0 ? 62 : 96)
                MascotTentacle(phase: t * 1.4 + Double(k) * 1.3, amp: max(a, 0.35))
                    .stroke(LinearGradient(colors: [c, c.opacity(0.15)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: s * 0.075, lineCap: .round))
                    .frame(width: s * 0.12, height: s * 0.36)
                    .rotationEffect(.degrees(-ang + 6 * sin(t * 1.1 + Double(k)) * da), anchor: .top)
                    .offset(x: CGFloat(side) * bw * 0.36, y: cy + bh * 0.14)
            }
        case (.puddle(let c), .back):
            ZStack {
                Ellipse().fill(RadialGradient(colors: [c, c.opacity(0.75), c.opacity(0)], center: .center, startRadius: 0, endRadius: bw * 0.8))
                Ellipse().stroke(pal.accent.opacity(0.35), lineWidth: line)
                    .padding(s * 0.04)
            }
            .frame(width: bw * 1.55, height: s * 0.26)
            .scaleEffect(x: 1 + 0.03 * CGFloat(sin(t * 1.2)) * a, y: 1)
            .offset(y: cy + bh * 0.44)
        case (.legs(let c), .back):
            // Spider legs, four per side (Spindle).
            ForEach([-1.0, 1.0], id: \.self) { side in
                ForEach(0..<4, id: \.self) { k in
                    Capsule().fill(LinearGradient(colors: [pal.light, c], startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().stroke(pal.outline.opacity(0.4), lineWidth: line * 0.8))
                        .frame(width: s * 0.36, height: s * 0.05)
                        .offset(x: s * 0.18)
                        .rotationEffect(.degrees(Double([-38, -12, 14, 40][k]) + 4 * sin(t * 3 + Double(k)) * da))
                        .scaleEffect(x: side, y: 1)
                        .offset(x: side * bw * 0.34, y: cy + bh * 0.12)
                }
            }
        case (.arms(let c), .back):
            // Chunky stone forearms with fists.
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                        .fill(LinearGradient(colors: [pal.light, c], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: s * 0.08, style: .continuous).stroke(pal.outline.opacity(0.55), lineWidth: line))
                        .frame(width: s * 0.2, height: s * 0.32)
                    Ellipse().fill(LinearGradient(colors: [pal.mid, c], startPoint: .top, endPoint: .bottom))
                        .overlay(Ellipse().stroke(pal.outline.opacity(0.55), lineWidth: line))
                        .frame(width: s * 0.27, height: s * 0.2)
                        .offset(y: s * 0.06)
                }
                .rotationEffect(.degrees(side * (-12 + 4 * sin(t * 1.3) * da)), anchor: .top)
                .offset(x: side * (bw * 0.5 + s * 0.02), y: cy + s * 0.06)
            }
        case (.wheels, .back):
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(Color(white: 0.2)).overlay(Circle().stroke(pal.accent, lineWidth: s * 0.03)).frame(width: s * 0.2)
                    .rotationEffect(.radians(t * 4 * da)).offset(x: side * bw * 0.3, y: cy + bh * 0.5)
            }
        case (.feet(let c), .back):
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(c ?? pal.dark).overlay(Ellipse().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.2, height: s * 0.1).offset(x: side * bw * 0.22, y: cy + bh * 0.48)
            }
        case (.antlers, .back), (.starAntlers, .back):
            let col = Self.antlerColor(part)
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Capsule().fill(col).frame(width: s * 0.045, height: s * 0.34)
                    Capsule().fill(col).frame(width: s * 0.04, height: s * 0.16).rotationEffect(.degrees(side * 40)).offset(x: side * s * 0.05, y: -s * 0.06)
                    if Self.isStarAntlers(part) { MascotSparkleShape().fill(gold).frame(width: s * 0.1, height: s * 0.1).offset(y: -s * 0.18) }
                }
                .rotationEffect(.degrees(side * 20), anchor: .bottom)
                .offset(x: side * bw * 0.2, y: top - s * 0.12)
            }
        // ── Front layer (under the face) ─────────────────────────
        case (.ring(let c), .front):
            MascotRingHalf(front: true).stroke(c ?? gold, lineWidth: s * 0.06)
                .frame(width: bw * 1.5, height: s * 0.32).rotationEffect(.degrees(-14)).offset(y: cy + s * 0.08)
        case (.moonMark(let c), .front):
            // Small glowing crescent on the forehead (Eclipa, Vesper).
            MascotCrescentShape().fill(LinearGradient(colors: [.white, c], startPoint: .top, endPoint: .bottom))
                .shadow(color: c.opacity(0.9), radius: s * 0.035)
                .frame(width: s * 0.17, height: s * 0.17)
                .rotationEffect(.degrees(-20))
                .offset(y: top + bh * 0.17)
        case (.cloudSeat(let c), .front):
            // Soft cloud cushion the character sits in (Hush).
            ZStack {
                ForEach(0..<5, id: \.self) { k in
                    Circle().fill(LinearGradient(colors: [.white, c], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(pal.outline.opacity(0.18), lineWidth: line * 0.8))
                        .frame(width: s * [0.3, 0.38, 0.44, 0.38, 0.3][k])
                        .offset(x: bw * [-0.52, -0.28, 0, 0.28, 0.52][k], y: s * [0.04, -0.02, 0.02, -0.02, 0.04][k])
                }
            }
            .offset(y: cy + bh * 0.42 + CGFloat(sin(t * 1.3)) * s * 0.01 * a)
        case (.shield(let c), .front):
            // Small golden guardian crest on the chest, clear of the mouth (Sera).
            let shieldShape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: s * 0.03, bottomLeading: s * 0.11, bottomTrailing: s * 0.11, topTrailing: s * 0.03), style: .continuous)
            ZStack {
                shieldShape.fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), c], startPoint: .top, endPoint: .bottom))
                shieldShape.stroke(Color(red: 0.7, green: 0.5, blue: 0.1).opacity(0.7), lineWidth: line)
                MascotStarShape().fill(.white.opacity(0.9)).frame(width: s * 0.09, height: s * 0.09)
            }
            .frame(width: s * 0.19, height: s * 0.21)
            .shadow(color: c.opacity(0.6), radius: s * 0.03)
            .offset(y: cy + bh * 0.3)
        case (.skateboard(let c), .front):
            ZStack {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Circle().fill(Color(white: 0.22))
                        .overlay(Circle().stroke(Color(red: 1, green: 0.6, blue: 0.25), lineWidth: s * 0.022))
                        .frame(width: s * 0.11)
                        .offset(x: side * bw * 0.44, y: s * 0.07)
                }
                Capsule().fill(LinearGradient(colors: [c, c.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(pal.outline.opacity(0.55), lineWidth: line))
                    .overlay(Capsule().fill(Color(red: 1, green: 0.6, blue: 0.25)).frame(width: bw * 0.5, height: s * 0.018))
                    .frame(width: bw * 1.3, height: s * 0.085)
            }
            .rotationEffect(.degrees(3 * sin(t * 2) * da))
            .offset(y: cy + bh * 0.5 + s * 0.05)
        case (.rockSeams(let c), .front):
            // Glowing crystalline seams between the stone plates (kept clear of the face).
            ForEach(0..<4, id: \.self) { k in
                Capsule().fill(c)
                    .shadow(color: c.opacity(0.9), radius: s * 0.03)
                    .frame(width: s * [0.22, 0.16, 0.2, 0.14][k], height: max(s * 0.022, 1))
                    .rotationEffect(.degrees([28, -40, -18, 52][k]))
                    .offset(x: bw * [-0.3, -0.18, 0.28, 0.36][k], y: cy + bh * [0.24, -0.26, 0.28, -0.12][k])
                    .opacity(0.75 + 0.25 * sin(t * 2 + Double(k)))
            }
        case (.nose(let c), .front):
            Circle().fill(RadialGradient(colors: [.white, c], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.06))
                .shadow(color: c.opacity(0.9), radius: s * 0.04)
                .frame(width: s * 0.1)
                .offset(y: s * (kind.mouthY - 0.07))
        case (.paws(let c), .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack(alignment: .bottom) {
                    Ellipse().fill(c).overlay(Ellipse().stroke(pal.outline.opacity(0.45), lineWidth: line))
                    HStack(spacing: s * 0.02) {
                        ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.9)).frame(width: s * 0.025, height: s * 0.05) }
                    }
                    .offset(y: s * 0.03)
                }
                .frame(width: s * 0.18, height: s * 0.12)
                .rotationEffect(.degrees(side * -18))
                .offset(x: side * bw * 0.36, y: cy + bh * 0.24)
            }
        case (.speakers, .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle().fill(Color(white: 0.12))
                    Circle().stroke(pal.accent, lineWidth: s * 0.02).scaleEffect(0.78 + 0.08 * CGFloat(sin(t * 6)) * a)
                    Circle().fill(pal.accent.opacity(0.7)).scaleEffect(0.3)
                }
                .frame(width: s * 0.2).offset(x: side * bw * 0.34, y: cy + bh * 0.2)
            }
        case (.pixels(let c), .front):
            ForEach(0..<5, id: \.self) { k in
                Rectangle().fill((c ?? pal.accent).opacity(0.8)).frame(width: s * 0.07, height: s * 0.07)
                    .offset(x: s * (CGFloat(k % 3) - 1) * 0.3 + s * 0.05, y: cy + s * (CGFloat(k / 3) * 0.24 - 0.3))
                    .opacity(0.5 + 0.5 * sin(t * 3 + Double(k)))
            }
        case (.paintDrips(let cs), .front):
            ForEach(Array(cs.enumerated()), id: \.offset) { k, c in
                Capsule().fill(c).frame(width: s * 0.08, height: s * (0.14 + CGFloat(k % 2) * 0.08))
                    .offset(x: s * (CGFloat(k) - CGFloat(cs.count - 1) / 2) * 0.16, y: cy + bh * 0.42)
            }
        case (.berries(let c), .front):
            ForEach(0..<6, id: \.self) { k in
                Circle().fill(c.opacity(0.85)).overlay(Circle().stroke(pal.outline.opacity(0.3), lineWidth: 0.6)).frame(width: s * 0.12)
                    .offset(x: s * [-0.3, 0.32, -0.36, 0.36, -0.2, 0.24][k], y: cy + s * [0.22, 0.18, -0.06, -0.02, 0.34, 0.32][k])
            }
        case (.lightning, .front):
            Image(systemName: "bolt.fill").font(.system(size: s * 0.18)).foregroundStyle(Color(red: 1, green: 0.9, blue: 0.3))
                .offset(x: bw * 0.42, y: top + s * 0.04).opacity(0.6 + 0.4 * sin(t * 5))
        case (.scarf(let c), .front):
            Capsule().fill(c).overlay(Capsule().stroke(pal.outline.opacity(0.4), lineWidth: line))
                .frame(width: bw * 0.78, height: s * 0.09).offset(y: s * (kind.mouthY + 0.1))
        case (.bowtie(let c), .front):
            HStack(spacing: 0) { MascotTriangle().rotation(.degrees(90)).fill(c); MascotTriangle().rotation(.degrees(-90)).fill(c) }
                .frame(width: s * 0.22, height: s * 0.1).offset(y: s * (kind.mouthY + 0.1))
        case (.whiskers, .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                ForEach(0..<2, id: \.self) { k in
                    Capsule().fill(pal.outline.opacity(0.5)).frame(width: s * 0.16, height: 1)
                        .rotationEffect(.degrees(side * (Double(k) * 14 - 7))).offset(x: side * s * 0.34, y: s * (kind.mouthY - 0.02) + CGFloat(k) * s * 0.04)
                }
            }
        case (.beak, .front):
            MascotTriangle().rotation(.degrees(180)).fill(Color(red: 0.98, green: 0.72, blue: 0.3))
                .frame(width: s * 0.1, height: s * 0.08).offset(y: s * (kind.mouthY - 0.08))
        case (.cheeksStars, .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotSparkleShape().fill(pal.accent.opacity(0.9)).frame(width: s * 0.08, height: s * 0.08).offset(x: side * s * 0.3, y: s * (kind.eyeY + 0.16))
            }
        // ── Top layer (over the face) ───────────────────────────
        case (.halo, .top):
            Ellipse().stroke(LinearGradient(colors: [gold, Color(red: 1, green: 0.96, blue: 0.7)], startPoint: .leading, endPoint: .trailing), lineWidth: s * 0.045)
                .shadow(color: gold.opacity(0.8), radius: s * 0.05)
                .frame(width: s * 0.5, height: s * 0.13)
                .offset(y: top - s * 0.2 - CGFloat(sin(t * 1.5)) * s * 0.02 * a)
        case (.starCrest, .top):
            MascotStarShape().fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), gold], startPoint: .top, endPoint: .bottom))
                .overlay(MascotStarShape().stroke(Color(red: 0.7, green: 0.5, blue: 0.1).opacity(0.6), lineWidth: line * 0.8))
                .frame(width: s * 0.2, height: s * 0.2).offset(y: top - s * 0.04)
        case (.heartAntenna, .top):
            VStack(spacing: 0) {
                MascotHeartShape().fill(pal.accent).frame(width: s * 0.13, height: s * 0.12)
                Capsule().fill(pal.dark).frame(width: s * 0.025, height: s * 0.12)
            }
            .rotationEffect(.degrees(8 * sin(t * 2) * da), anchor: .bottom).offset(y: top - s * 0.1)
        case (.antennae(let c), .top):
            ForEach([-1.0, 1.0], id: \.self) { side in
                VStack(spacing: 0) {
                    Circle().fill(c ?? pal.accent).frame(width: s * 0.09)
                    Capsule().fill(pal.dark).frame(width: s * 0.025, height: s * 0.18)
                }
                .rotationEffect(.degrees(side * 22 + 6 * sin(t * 2 + side) * da), anchor: .bottom)
                .offset(x: side * s * 0.12, y: top - s * 0.1)
            }
        case (.nightcap(let c), .top):
            ZStack(alignment: .topTrailing) {
                MascotCapShape().fill(LinearGradient(colors: [c, c.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotCapShape().stroke(pal.outline.opacity(0.5), lineWidth: line))
                Circle().fill(.white).frame(width: s * 0.12).offset(x: s * 0.04, y: -s * 0.03)
            }
            .frame(width: s * 0.5, height: s * 0.34).rotationEffect(.degrees(-14 + 3 * sin(t * 0.8) * da)).offset(x: -s * 0.04, y: top - s * 0.06)
        case (.crown, .top):
            Image(systemName: "crown.fill").font(.system(size: s * 0.2)).foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), gold], startPoint: .top, endPoint: .bottom))
                .offset(y: top - s * 0.06)
        case (.leaves(let n, let c), .top):
            ForEach(0..<n, id: \.self) { k in
                MascotLeaf().fill(LinearGradient(colors: [c ?? Color(red: 0.5, green: 0.8, blue: 0.4), (c ?? Color(red: 0.3, green: 0.6, blue: 0.3)).opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    .overlay(MascotLeaf().stroke(pal.outline.opacity(0.4), lineWidth: line * 0.8))
                    .frame(width: s * 0.24, height: s * 0.11)
                    .offset(x: s * 0.1)
                    .rotationEffect(.degrees(-90 + (Double(k) - Double(n - 1) / 2) * 40 + 4 * sin(t * 1.3 + Double(k)) * da), anchor: .leading)
                    .offset(y: top)
            }
        case (.petals(let n, let c), .top):
            ZStack {
                ForEach(0..<n, id: \.self) { k in
                    Ellipse().fill(c ?? pal.accent).overlay(Ellipse().stroke(pal.outline.opacity(0.35), lineWidth: line * 0.7))
                        .frame(width: s * 0.1, height: s * 0.18).offset(y: -s * 0.08).rotationEffect(.degrees(Double(k) / Double(n) * 360))
                }
                Circle().fill(Color(red: 1, green: 0.88, blue: 0.4)).frame(width: s * 0.09)
            }
            .offset(x: s * 0.16, y: top - s * 0.02)
        case (.mushroomCap(let c, let spots), .top):
            ZStack {
                MascotDomeShape().fill(LinearGradient(colors: [c.opacity(0.85), c], startPoint: .top, endPoint: .bottom))
                MascotDomeShape().stroke(pal.outline.opacity(0.5), lineWidth: line)
                if spots { ForEach(0..<3, id: \.self) { k in Circle().fill(.white.opacity(0.9)).frame(width: s * 0.08).offset(x: s * (CGFloat(k) - 1) * 0.18, y: -s * (k == 1 ? 0.07 : 0.0)) } }
            }
            .frame(width: bw * 1.18, height: s * 0.36).offset(y: top + s * 0.02)
        case (.hood(let c), .top):
            MascotDomeShape().fill(c).overlay(MascotDomeShape().stroke(pal.outline.opacity(0.4), lineWidth: line))
                .frame(width: bw * 1.04, height: s * 0.3).offset(y: top + s * 0.06)
        case (.mask(let c), .top):
            Capsule().fill(c.opacity(0.92)).frame(width: s * 0.66, height: s * 0.2).offset(y: s * kind.eyeY)
                .blendMode(.multiply)
        case (.goggles(let c), .top):
            HStack(spacing: s * 0.02) { Circle().stroke(c, lineWidth: s * 0.04); Circle().stroke(c, lineWidth: s * 0.04) }
                .frame(width: s * 0.56, height: s * 0.27).offset(y: top + s * 0.02)
        case (.visor(let c), .top):
            Capsule().fill(LinearGradient(colors: [c.opacity(0.7), c.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.62, height: s * 0.16).offset(y: top + s * 0.06)
        case (.headphones(let c), .top):
            ZStack {
                MascotRingHalf(front: false).stroke(c ?? pal.accent, lineWidth: s * 0.05).frame(width: bw * 0.98, height: bh * 0.8)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule().fill(c ?? pal.accent).frame(width: s * 0.12, height: s * 0.22).offset(x: side * bw * 0.49)
                }
            }
            .offset(y: cy - bh * 0.06)
        case (.lantern(let c), .top):
            VStack(spacing: 0) {
                Capsule().fill(pal.dark).frame(width: s * 0.02, height: s * 0.14)
                RoundedRectangle(cornerRadius: s * 0.03).fill(c).frame(width: s * 0.12, height: s * 0.14).shadow(color: c, radius: s * 0.06)
            }
            .offset(x: bw * 0.52, y: cy + s * 0.04)
        case (.compass, .top):
            ZStack {
                Circle().stroke(Color(red: 0.86, green: 0.9, blue: 1), lineWidth: s * 0.025).frame(width: s * 0.36)
                ForEach(0..<4, id: \.self) { k in MascotTriangle().fill(k == 0 ? gold : Color(red: 0.7, green: 0.8, blue: 1)).frame(width: s * 0.08, height: s * 0.14).offset(y: -s * 0.12).rotationEffect(.degrees(Double(k) * 90)) }
            }
            .rotationEffect(.degrees(20 * sin(t * 0.6) * da)).offset(y: top - s * 0.14)
        case (.orbiters(let n, let c), .top):
            ForEach(0..<n, id: \.self) { k in
                let ang = t * 0.9 * da + Double(k) / Double(n) * 2 * .pi
                MascotSparkleShape().fill(c ?? gold).frame(width: s * 0.1, height: s * 0.1)
                    .offset(x: CGFloat(cos(ang)) * s * 0.66, y: cy - s * 0.16 + CGFloat(sin(ang)) * s * 0.14)
            }
        case (.sparkles(let n), .top):
            ForEach(0..<n, id: \.self) { k in
                MascotSparkleShape().fill(gold.opacity(0.9)).frame(width: s * 0.08, height: s * 0.08)
                    .offset(x: s * [0.56, -0.58, 0.48, -0.44, 0.0][k % 5], y: cy + s * [-0.42, -0.3, 0.3, 0.38, -0.62][k % 5])
                    .opacity(0.4 + 0.6 * abs(sin(t * 1.4 + Double(k))))
            }
        case (.cap(let c), .top) where outfit.item(for: .hat) == nil && outfit.item(for: .seasonal) == nil:
            // Backwards street cap.
            ZStack {
                Capsule().fill(c.opacity(0.9)).overlay(Capsule().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.3, height: s * 0.07)
                    .offset(x: bw * 0.3, y: s * 0.09)
                MascotCapDome().fill(LinearGradient(colors: [c.opacity(0.85), c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotCapDome().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: bw * 0.66, height: s * 0.24)
                Circle().fill(Color.white.opacity(0.9)).frame(width: s * 0.045).offset(y: -s * 0.11)
            }
            .rotationEffect(.degrees(-5))
            .offset(y: top + s * 0.02)
        case (.wreath(let c, let flower), .top) where outfit.item(for: .hat) == nil && outfit.item(for: .seasonal) == nil:
            // Leaf crown across the top of the head, with optional blossoms or berries.
            ZStack {
                ForEach(0..<9, id: \.self) { k in
                    let ang = (Double(k) / 8 - 0.5) * 150
                    MascotLeaf().fill(LinearGradient(colors: [c, c.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                        .overlay(MascotLeaf().stroke(Color(red: 0.12, green: 0.24, blue: 0.1).opacity(0.55), lineWidth: line * 0.9))
                        .frame(width: s * 0.28, height: s * 0.17)
                        .rotationEffect(.degrees(-90))
                        .offset(y: -bh * 0.46 - s * 0.02)
                        .rotationEffect(.degrees(ang))
                }
                if let flower {
                    ForEach(0..<3, id: \.self) { k in
                        let ang = Double(k - 1) * 45
                        Circle().fill(RadialGradient(colors: [.white, flower], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.05))
                            .overlay(Circle().stroke(pal.outline.opacity(0.3), lineWidth: line * 0.7))
                            .frame(width: s * 0.09)
                            .offset(y: -bh * 0.5)
                            .rotationEffect(.degrees(ang))
                    }
                }
            }
            .offset(y: cy)
        case (.crystals(let c), .top) where outfit.item(for: .hat) == nil && outfit.item(for: .seasonal) == nil:
            ForEach(0..<3, id: \.self) { k in
                MascotCrystalShape()
                    .fill(LinearGradient(colors: [.white.opacity(0.9), c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotCrystalShape().stroke(pal.outline.opacity(0.5), lineWidth: line * 0.8))
                    .shadow(color: c.opacity(0.7), radius: s * 0.03)
                    .frame(width: s * [0.12, 0.16, 0.1][k], height: s * [0.2, 0.28, 0.16][k])
                    .rotationEffect(.degrees([-18, 4, 22][k]), anchor: .bottom)
                    .offset(x: s * [-0.14, 0.02, 0.17][k], y: top - s * [0.04, 0.08, 0.02][k])
            }
        case (.notes, .top):
            Text("♪").font(.system(size: s * 0.2, weight: .bold)).foregroundStyle(pal.accent)
                .offset(x: s * 0.56, y: top - CGFloat((t * 0.6).truncatingRemainder(dividingBy: 1)) * s * 0.16 * a)
        default:
            EmptyView()
        }
    }

    static func isStarAntlers(_ part: MolibooPart) -> Bool { if case .starAntlers = part { return true }; return false }

    static func antlerColor(_ part: MolibooPart) -> Color {
        if case .antlers(let c) = part { return c ?? Color(red: 0.62, green: 0.44, blue: 0.3) }
        return Color(red: 0.86, green: 0.94, blue: 1)
    }
}

// MARK: - Family specs and profiles

extension ModulaMascotKind {
    var spec: MolibooSpec? { MolibooFamilySpecs.table[self] }
}

enum MolibooFamilySpecs {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    static let pearl = c(0.97, 0.95, 0.99), gold = c(1, 0.82, 0.38)

    static let table: [ModulaMascotKind: MolibooSpec] = {
        var t: [ModulaMascotKind: MolibooSpec] = [:]
        // Family 002 — Angels (Celestia)
        t[.aura] = MolibooSpec(body: .pear, size: CGSize(width: 0.9, height: 0.9), palette: .spec(pearl, accent: gold, light: .white), parts: [.glow(gold), .wings(.feather, nil), .starCrest, .halo, .sparkles(4)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "Celestial light guardian")
        t[.soli] = MolibooSpec(body: .round, size: CGSize(width: 0.94, height: 0.9), palette: .spec(c(1, 0.8, 0.32), accent: c(1, 0.62, 0.3), light: c(1, 0.95, 0.7)), parts: [.glow(c(1, 0.78, 0.3)), .rays(8, c(1, 0.72, 0.28)), .cheeksStars], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.05, form: "Miniature living sun")
        t[.luma] = MolibooSpec(body: .round, size: CGSize(width: 0.78, height: 0.76), palette: .spec(c(0.88, 0.9, 0.99), accent: c(0.7, 0.72, 0.98)), parts: [.glow(c(0.8, 0.82, 1)), .crescent(c(0.96, 0.95, 0.88)), .starCrest, .sparkles(3)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.54, headTopExtra: 0.06, form: "Living moon pearl")
        t[.vela] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.82), palette: .spec(c(0.98, 0.95, 0.97), accent: c(1, 0.74, 0.84), light: .white), parts: [.tail(.fox, c(0.86, 0.8, 0.98)), .ears(.fox), .halo, .sparkles(2)], hatScale: 0.82, hatMaxWidth: 0.46, headTopExtra: 0.06, form: "Tiny magical sky fox")
        t[.cheri] = MolibooSpec(body: .round, size: CGSize(width: 0.98, height: 0.9), palette: .spec(c(1, 0.78, 0.84), accent: c(0.96, 0.44, 0.6)), parts: [.wings(.feather, nil), .heartAntenna], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "Heart-shaped cherub")
        t[.hush] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.84), palette: .spec(c(0.96, 0.96, 1), accent: c(0.8, 0.84, 1), light: .white), parts: [.wings(.feather, nil), .cloudSeat(c(0.86, 0.88, 1)), .starCrest], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "Feather-cloud being")
        t[.haloa] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.84), palette: .spec(c(0.98, 0.96, 0.92), accent: gold, light: .white), parts: [.glow(gold), .halo, .starCrest, .sparkles(4)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.54, headTopExtra: 0.06, form: "Celestial ring spirit")
        t[.lyra] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.97, 0.95, 0.99), accent: c(0.72, 0.6, 0.96), light: .white), parts: [.harp, .wings(.feather, c(0.9, 0.86, 1)), .starCrest, .notes], hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "Living miniature harp")
        t[.celio] = MolibooSpec(body: .wide, size: CGSize(width: 1.12, height: 0.78), palette: .spec(c(0.62, 0.8, 0.98), accent: gold, light: c(0.9, 0.96, 1)), parts: [.tail(.whale, c(0.5, 0.7, 0.96)), .fins(c(0.52, 0.72, 0.96)), .starCrest, .sparkles(2)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.58, headTopExtra: 0.06, form: "Floating celestial whale")
        t[.dovee] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(c(0.98, 0.98, 1), accent: c(0.7, 0.86, 0.6), light: .white), parts: [.wings(.feather, nil), .leaves(2, c(0.56, 0.74, 0.42)), .beak, .halo], hatScale: 0.95, hatMaxWidth: 0.52, form: "Pearl-white dove")
        t[.twila] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.84), palette: .spec(c(0.36, 0.3, 0.52), accent: c(0.9, 0.78, 0.5), iris: c(0.9, 0.8, 0.5)), parts: [.glow(c(0.6, 0.45, 0.9)), .wings(.moth, c(0.62, 0.48, 0.92)), .antennae(gold), .sparkles(2)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "Celestial moth")
        t[.gleam] = MolibooSpec(body: .drop, size: CGSize(width: 0.84, height: 0.98), palette: .spec(c(0.9, 0.94, 1), accent: c(0.72, 0.84, 1), light: .white), parts: [.glow(c(0.8, 0.9, 1)), .wings(.feather, nil), .halo], floats: true, feet: false, hatScale: 0.8, hatMaxWidth: 0.52, headTopExtra: 0.17, form: "Living droplet of light")
        t[.novael] = MolibooSpec(body: .star, size: CGSize(width: 1.04, height: 1.0), palette: .spec(c(0.92, 0.94, 1), accent: c(0.6, 0.72, 1), light: .white), parts: [.glow(c(0.7, 0.8, 1)), .wings(.feather, nil), .halo, .orbiters(3, gold), .sparkles(2)], floats: true, feet: false, hatScale: 0.62, hatMaxWidth: 0.48, headTopExtra: 0.12, form: "Living celestial star")
        t[.sera] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.88), palette: .spec(c(0.98, 0.97, 0.95), accent: gold, light: .white), parts: [.wings(.feather, nil), .starCrest, .shield(gold), .halo], hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "Winged celestial shield")
        t[.auri] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.82), palette: .spec(c(0.88, 0.84, 0.98), accent: c(0.56, 0.9, 0.86), light: c(0.98, 0.96, 1)), parts: [.glow(c(0.8, 0.7, 1)), .wings(.fairy, c(0.95, 0.7, 1)), .wings(.fairy, c(0.62, 0.92, 1)), .antennae(c(1, 0.7, 0.9)), .crown, .sparkles(3)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "Iridescent celestial sprite")
        addUnderground(&t)
        addEnchanted(&t)
        addStardust(&t)
        addDreamers(&t)
        return t
    }()

    static let profiles: [ModulaMascotKind: ModulaMascotKind.Profile] = angelProfiles.merging(undergroundProfiles) { a, _ in a }.merging(enchantedProfiles) { a, _ in a }.merging(stardustProfiles) { a, _ in a }.merging(dreamerProfiles) { a, _ in a }

    static let angelProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .aura: .init(number: 26, title: "The Guiding Light", traits: ["Light", "Leader", "Calm"]),
        .soli: .init(number: 27, title: "The Little Sun", traits: ["Sun", "Energetic", "Joyful"]),
        .luma: .init(number: 28, title: "The Moon Pearl", traits: ["Moon", "Gentle", "Dreamy"]),
        .vela: .init(number: 29, title: "The Celestial Fox", traits: ["Sky", "Elegant", "Wise"]),
        .cheri: .init(number: 30, title: "The Heart Spirit", traits: ["Love", "Kind", "Playful"]),
        .hush: .init(number: 31, title: "The Feather Guardian", traits: ["Cloud", "Protective", "Peaceful"]),
        .haloa: .init(number: 32, title: "The Halo Keeper", traits: ["Light", "Holy", "Serene"]),
        .lyra: .init(number: 33, title: "The Musical Spirit", traits: ["Music", "Creative", "Inspiring"]),
        .celio: .init(number: 34, title: "The Sky Whale", traits: ["Sky", "Adventurous", "Friendly"]),
        .dovee: .init(number: 35, title: "The Celestial Dove", traits: ["Peace", "Loyal", "Brave"]),
        .twila: .init(number: 36, title: "The Twilight Moth", traits: ["Twilight", "Mysterious", "Curious"]),
        .gleam: .init(number: 37, title: "The Radiant Droplet", traits: ["Light", "Pure", "Optimistic"]),
        .novael: .init(number: 38, title: "The Cosmic Star", traits: ["Stars", "Powerful", "Majestic"]),
        .sera: .init(number: 39, title: "The Little Sentinel", traits: ["Guardian", "Brave", "Caring"]),
        .auri: .init(number: 40, title: "The Iridescent Spirit", traits: ["Aurora", "Magical", "Unique"]),
    ]
}

// MARK: - Family 003 — Underground (sheet art wins over the PDF)

extension MolibooFamilySpecs {
    static let ink = c(0.12, 0.1, 0.18), cyan = c(0.2, 0.9, 1), magenta = c(1, 0.3, 0.78), neonYellow = c(1, 0.9, 0.25)
    static func addUnderground(_ t: inout [ModulaMascotKind: MolibooSpec]) {
        let snow = c(0.97, 0.97, 1)
        t[.riff] = MolibooSpec(body: .round, size: CGSize(width: 0.94, height: 0.86), palette: .spec(snow, accent: cyan, light: .white), parts: [.glow(cyan), .speakers, .headphones(magenta), .notes], hatScale: 0.95, hatMaxWidth: 0.54, form: "Living pocket speaker")
        t[.graff] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.86), palette: .spec(snow, accent: magenta, light: .white), parts: [.paintDrips([magenta, cyan, c(1, 0.62, 0.2), c(0.6, 0.4, 1)]), .bowtie(magenta)], hatScale: 0.95, hatMaxWidth: 0.54, form: "Living paint splash")
        t[.nyx] = MolibooSpec(body: .wide, size: CGSize(width: 1.12, height: 0.7), palette: .spec(c(0.14, 0.12, 0.24), accent: c(0.62, 0.36, 1), iris: c(0.85, 0.7, 1), light: c(0.3, 0.26, 0.46)), parts: [.glow(c(0.5, 0.3, 0.9)), .puddle(c(0.1, 0.08, 0.2)), .tendrils(c(0.46, 0.32, 0.8)), .sparkles(2)], feet: false, hatScale: 0.95, hatMaxWidth: 0.54, form: "Living little shadow")
        t[.zip] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.82), palette: .spec(c(0.22, 0.22, 0.3), accent: cyan, iris: cyan), parts: [.ears(.bunny), .wheels, .visor(cyan)], feet: false, hatScale: 0.92, hatMaxWidth: 0.5, form: "Roller-wheel sprite")
        t[.vex] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(snow, accent: magenta, light: .white), parts: [.tail(.fox, magenta), .ears(.fox), .crown, .lightning], hatScale: 0.82, hatMaxWidth: 0.46, headTopExtra: 0.06, form: "Streetwise miniature fox")
        t[.koda] = MolibooSpec(body: .round, size: CGSize(width: 0.96, height: 0.86), palette: .spec(c(0.58, 0.44, 0.34), accent: c(1, 0.56, 0.22), light: c(0.95, 0.9, 0.82)), parts: [.tail(.fluffy, c(0.34, 0.26, 0.22)), .ears(.round), .mask(c(0.24, 0.18, 0.16)), .scarf(c(0.2, 0.7, 0.72)), .cap(c(0.2, 0.62, 0.66)), .feet(c(0.34, 0.26, 0.22))], hatScale: 0.92, hatMaxWidth: 0.46, form: "Little raccoon")
        t[.glitch] = MolibooSpec(body: .square, size: CGSize(width: 0.9, height: 0.84), palette: .spec(snow, accent: c(0.4, 0.5, 1), light: .white), parts: [.glow(c(0.6, 0.5, 1)), .pixels(c(0.5, 0.55, 1)), .pixels(magenta)], hatScale: 0.95, hatMaxWidth: 0.54, form: "Living pixel-cluster creature")
        t[.jinx] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.16, 0.13, 0.22), accent: magenta, iris: magenta, light: c(0.32, 0.26, 0.4)), parts: [.tail(.curl, c(0.16, 0.13, 0.22)), .ears(.cat), .crescent(c(1, 0.5, 0.85)), .whiskers], hatScale: 0.92, hatMaxWidth: 0.48, form: "Nocturnal alley cat")
        t[.`static`] = MolibooSpec(body: .cloud, size: CGSize(width: 1.0, height: 0.86), palette: .spec(c(0.9, 0.95, 1), accent: neonYellow, light: .white), parts: [.glow(c(0.6, 0.85, 1)), .lightning, .mane(9), .antennae(neonYellow)], form: "Electric fluff creature")
        t[.holo] = MolibooSpec(body: .drop, size: CGSize(width: 0.86, height: 0.96), palette: .spec(c(0.66, 0.86, 1), accent: c(0.78, 0.6, 1), light: c(0.92, 0.98, 1)), parts: [.glow(cyan), .fins(c(0.6, 0.8, 1)), .orbiters(2, c(0.8, 0.7, 1))], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.54, headTopExtra: 0.16, form: "Translucent light projection")
        t[.fuse] = MolibooSpec(body: .square, size: CGSize(width: 0.86, height: 0.9), palette: .spec(c(0.24, 0.24, 0.3), accent: c(1, 0.78, 0.2), iris: c(1, 0.85, 0.3), light: c(0.42, 0.42, 0.5)), parts: [.lightning, .visor(c(1, 0.8, 0.25)), .feet(c(1, 0.7, 0.2))], hatScale: 0.95, hatMaxWidth: 0.54, form: "Living portable battery")
        t[.skid] = MolibooSpec(body: .pear, size: CGSize(width: 0.86, height: 0.9), palette: .spec(c(0.56, 0.86, 0.32), accent: c(1, 0.56, 0.22), light: c(0.84, 0.96, 0.66)), parts: [.tail(.lizard, c(0.4, 0.7, 0.3)), .feet(c(0.36, 0.64, 0.28)), .skateboard(c(0.62, 0.48, 0.95))], feet: true, hatScale: 0.88, hatMaxWidth: 0.54, form: "Skate-loving lizard")
        t[.mica] = MolibooSpec(body: .pear, size: CGSize(width: 0.96, height: 0.86), palette: .spec(c(0.5, 0.38, 0.3), accent: cyan, light: c(0.84, 0.72, 0.6)), parts: [.goggles(cyan), .whiskers, .nose(cyan), .paws(c(0.96, 0.74, 0.7))], hatScale: 0.88, hatMaxWidth: 0.54, form: "Little tunnelling mole")
        t[.rumble] = MolibooSpec(body: .pebble, size: CGSize(width: 1.08, height: 0.84), palette: .spec(c(0.4, 0.4, 0.46), accent: c(0.3, 0.6, 1), light: c(0.62, 0.62, 0.68)), parts: [.glow(c(0.3, 0.55, 1)), .arms(c(0.3, 0.3, 0.36)), .rockSeams(c(0.4, 0.75, 1)), .crystals(c(0.35, 0.65, 1)), .feet(c(0.3, 0.3, 0.36))], hatScale: 0.95, hatMaxWidth: 0.54, form: "Living rock creature")
        t[.flick] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.82), palette: .spec(snow, accent: magenta, light: .white), parts: [.glow(magenta), .wings(.moth, c(0.9, 0.4, 0.9)), .antennae(c(0.7, 0.4, 1))], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "Little luminous moth")
    }

    static let undergroundProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .riff: .init(number: 41, title: "The Beat Maker", traits: ["Music", "Energetic", "Creative"]),
        .graff: .init(number: 42, title: "The Paint Sprite", traits: ["Art", "Mischievous", "Expressive"]),
        .nyx: .init(number: 43, title: "The Shadow Puddle", traits: ["Shadow", "Mysterious", "Calm"]),
        .zip: .init(number: 44, title: "The Speedster", traits: ["Speed", "Playful", "Adventurous"]),
        .vex: .init(number: 45, title: "The Street Fox", traits: ["Clever", "Bold", "Rebel"]),
        .koda: .init(number: 46, title: "The Urban Explorer", traits: ["Explorer", "Curious", "Loyal"]),
        .glitch: .init(number: 47, title: "The Digital Sprite", traits: ["Tech", "Curious", "Playful"]),
        .jinx: .init(number: 48, title: "The Midnight Cat", traits: ["Stealth", "Mysterious", "Independent"]),
        .`static`: .init(number: 49, title: "The Electric Fuzz", traits: ["Electric", "Energetic", "Chaotic"]),
        .holo: .init(number: 50, title: "The Hologram", traits: ["Illusion", "Adaptive", "Unique"]),
        .fuse: .init(number: 51, title: "The Battery Buddy", traits: ["Energy", "Helpful", "Reliable"]),
        .skid: .init(number: 52, title: "The Skate Lizard", traits: ["Sport", "Reckless", "Fun"]),
        .mica: .init(number: 53, title: "The Crystal Mole", traits: ["Earth", "Collector", "Gentle"]),
        .rumble: .init(number: 54, title: "The Underground Titan", traits: ["Strength", "Brave", "Protective"]),
        .flick: .init(number: 55, title: "The Neon Moth", traits: ["Light", "Dreamy", "Magical"]),
    ]
}

// MARK: - Family 004 — Enchanted (sheet art wins over the PDF)

extension MolibooFamilySpecs {
    static let leaf = c(0.42, 0.7, 0.36), bark = c(0.5, 0.36, 0.26), moss = c(0.5, 0.66, 0.36)
    static func addEnchanted(_ t: inout [ModulaMascotKind: MolibooSpec]) {
        let cream = c(0.97, 0.94, 0.88)
        t[.bramble] = MolibooSpec(body: .round, size: CGSize(width: 0.94, height: 0.86), palette: .spec(c(0.62, 0.46, 0.36), accent: c(0.8, 0.18, 0.3), light: c(0.86, 0.74, 0.62)), parts: [.thorns(leaf), .wreath(leaf, c(0.82, 0.16, 0.3))], hatScale: 0.95, hatMaxWidth: 0.54, form: "Thorny guardian")
        t[.ferni] = MolibooSpec(body: .pear, size: CGSize(width: 0.86, height: 0.9), palette: .spec(c(0.66, 0.84, 0.5), accent: c(1, 0.86, 0.5), light: c(0.88, 0.96, 0.78)), parts: [.wreath(leaf, c(1, 0.8, 0.9))], hatScale: 0.88, hatMaxWidth: 0.54, form: "Leafy sprout")
        t[.truffle] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.8), palette: .spec(cream, accent: c(0.86, 0.3, 0.26), light: .white), parts: [.mushroomCap(c(0.86, 0.32, 0.26), spots: true)], hatScale: 0.8, hatMaxWidth: 0.54, headTopExtra: 0.14, form: "Mushroom forager")
        t[.rootle] = MolibooSpec(body: .round, size: CGSize(width: 0.94, height: 0.86), palette: .spec(bark, accent: c(0.95, 0.68, 0.3), light: c(0.76, 0.62, 0.48)), parts: [.roots, .ears(.tufts), .leaves(2, leaf)], hatScale: 0.92, hatMaxWidth: 0.46, form: "Root burrower")
        t[.willow] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(c(0.78, 0.84, 0.7), accent: c(0.96, 0.84, 0.9), light: c(0.92, 0.96, 0.88)), parts: [.wreath(c(0.56, 0.74, 0.46), c(1, 0.86, 0.92)), .antlers(bark)], hatScale: 0.95, hatMaxWidth: 0.54, form: "Elegant keeper")
        t[.pollen] = MolibooSpec(body: .round, size: CGSize(width: 0.82, height: 0.8), palette: .spec(c(1, 0.94, 0.78), accent: c(1, 0.78, 0.3), light: .white), parts: [.glow(c(1, 0.84, 0.4)), .wings(.fairy, c(0.9, 0.96, 1)), .petals(5, c(1, 0.86, 0.4)), .sparkles(3)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "Golden pixie")
        t[.mallow] = MolibooSpec(body: .cloud, size: CGSize(width: 1.04, height: 0.86), palette: .spec(c(1, 0.84, 0.9), accent: c(0.94, 0.4, 0.6), light: c(1, 0.95, 0.97)), parts: [.wreath(c(1, 0.72, 0.84), c(1, 0.92, 0.96)), .sparkles(2)], hatScale: 0.92, hatMaxWidth: 0.46, headTopExtra: 0.04, form: "Dreamy blossom")
        t[.acora] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(c(0.72, 0.54, 0.36), accent: leaf, light: c(0.9, 0.78, 0.6)), parts: [.tail(.fluffy, c(0.6, 0.42, 0.28)), .mushroomCap(c(0.5, 0.34, 0.22), spots: false), .leaves(1, leaf)], hatScale: 0.82, hatMaxWidth: 0.54, headTopExtra: 0.1, form: "Acorn guardian")
        t[.spindle] = MolibooSpec(body: .cloud, size: CGSize(width: 0.98, height: 0.84), palette: .spec(c(0.94, 0.92, 0.98), accent: c(0.7, 0.6, 0.94), light: .white), parts: [.glow(c(0.8, 0.7, 1)), .legs(c(0.8, 0.74, 0.92)), .antennae(c(0.8, 0.7, 1)), .sparkles(2)], hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.04, form: "Silk weaver")
        t[.glade] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(cream, accent: c(0.6, 0.86, 0.7), light: .white), parts: [.ears(.fox), .wreath(c(0.6, 0.82, 0.5), c(1, 0.84, 0.9))], hatScale: 0.92, hatMaxWidth: 0.48, form: "Meadow spirit")
        t[.lichen] = MolibooSpec(body: .dome, size: CGSize(width: 1.08, height: 0.82), palette: .spec(c(0.8, 0.84, 0.74), accent: c(0.36, 0.8, 0.78), light: c(0.94, 0.96, 0.9)), parts: [.shell(moss), .leaves(4, moss), .petals(3, c(0.7, 0.6, 0.95))], hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.04, form: "Moss companion")
        t[.thimble] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.84), palette: .spec(cream, accent: c(0.82, 0.28, 0.24), light: .white), parts: [.mushroomCap(c(0.82, 0.3, 0.24), spots: true), .scarf(moss), .lantern(c(1, 0.8, 0.4))], hatScale: 0.8, hatMaxWidth: 0.54, headTopExtra: 0.14, form: "The herbalist")
        t[.wyrmi] = MolibooSpec(body: .pear, size: CGSize(width: 0.9, height: 0.88), palette: .spec(c(0.52, 0.76, 0.5), accent: c(0.95, 0.7, 0.3), light: c(0.8, 0.92, 0.74)), parts: [.tail(.lizard, c(0.4, 0.62, 0.38)), .wings(.bat, c(0.46, 0.72, 0.44)), .wreath(leaf, nil)], hatScale: 0.88, hatMaxWidth: 0.52, form: "Forest wyrm")
        t[.kiko] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.92, 0.6, 0.34), accent: cream, light: c(1, 0.86, 0.7)), parts: [.tail(.fluffy, c(0.9, 0.56, 0.3)), .ears(.fox), .leaves(2, leaf)], hatScale: 0.92, hatMaxWidth: 0.48, form: "Curious critter")
        t[.eldra] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.88), palette: .spec(c(0.95, 0.96, 0.98), accent: c(0.5, 0.8, 0.9), light: .white), parts: [.glow(c(0.6, 0.86, 1)), .mane(8), .antlers(c(0.86, 0.82, 0.72)), .leaves(3, c(0.56, 0.78, 0.6)), .sparkles(3)], hatScale: 0.95, hatMaxWidth: 0.54, form: "Ancient spirit")
    }

    static let enchantedProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .bramble: .init(number: 56, title: "The Thorny Guardian", traits: ["Thorn", "Brave", "Protective"]),
        .ferni: .init(number: 57, title: "The Leafy Sprout", traits: ["Plant", "Gentle", "Bright"]),
        .truffle: .init(number: 58, title: "The Mushroom Forager", traits: ["Fungi", "Curious", "Cozy"]),
        .rootle: .init(number: 59, title: "The Root Burrower", traits: ["Earth", "Playful", "Determined"]),
        .willow: .init(number: 60, title: "The Elegant Keeper", traits: ["Nature", "Graceful", "Wise"]),
        .pollen: .init(number: 61, title: "The Golden Pixie", traits: ["Light", "Airy", "Joyful"]),
        .mallow: .init(number: 62, title: "The Dreamy Blossom", traits: ["Flower", "Sweet", "Dreamy"]),
        .acora: .init(number: 63, title: "The Acorn Guardian", traits: ["Wood", "Nimble", "Adventurous"]),
        .spindle: .init(number: 64, title: "The Silk Weaver", traits: ["Silk", "Clever", "Delicate"]),
        .glade: .init(number: 65, title: "The Meadow Spirit", traits: ["Grass", "Peaceful", "Harmonious"]),
        .lichen: .init(number: 66, title: "The Moss Companion", traits: ["Earth", "Calm", "Wise"]),
        .thimble: .init(number: 67, title: "The Herbalist", traits: ["Herb", "Inventive", "Friendly"]),
        .wyrmi: .init(number: 68, title: "The Forest Wyrm", traits: ["Dragon", "Magical", "Mischievous"]),
        .kiko: .init(number: 69, title: "The Curious Critter", traits: ["Agile", "Curious", "Energetic"]),
        .eldra: .init(number: 70, title: "The Ancient Spirit", traits: ["Spirit", "Majestic", "Mysterious"]),
    ]
}

// MARK: - Family 005 — Stardust (The Stardust Reach)

extension MolibooFamilySpecs {
    static let starGold = c(1, 0.84, 0.44), nightViolet = c(0.26, 0.2, 0.42), starBlue = c(0.56, 0.74, 1)
    static func addStardust(_ t: inout [ModulaMascotKind: MolibooSpec]) {
        let w = c(0.97, 0.96, 1)
        t[.astra] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.82), palette: .spec(w, accent: starGold, light: .white), parts: [.glow(starGold), .rays(10, starGold), .wings(.fairy, c(0.9, 0.92, 1)), .starCrest, .sparkles(3)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "The star sprite")
        t[.nebbi] = MolibooSpec(body: .cloud, size: CGSize(width: 1.06, height: 0.86), palette: .spec(c(0.88, 0.8, 0.98), accent: c(0.96, 0.6, 0.86), light: c(0.97, 0.94, 1)), parts: [.glow(c(0.8, 0.6, 1)), .wreath(c(0.8, 0.62, 0.98), c(0.98, 0.66, 0.88)), .sparkles(4)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.04, form: "The nebula dreamer")
        t[.quori] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.84), palette: .spec(w, accent: starGold, light: .white), parts: [.ring(starGold), .ears(.cat), .sparkles(2)], hatScale: 0.92, hatMaxWidth: 0.48, form: "The ringed wanderer")
        t[.vesper] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.82), palette: .spec(nightViolet, accent: c(0.75, 0.7, 1), iris: c(0.85, 0.85, 1), light: c(0.44, 0.36, 0.64)), parts: [.tail(.comet, c(0.5, 0.4, 0.9)), .ears(.fox), .glow(c(0.5, 0.4, 0.9)), .moonMark(c(1, 0.9, 0.6)), .sparkles(3)], floats: true, feet: false, hatScale: 0.92, hatMaxWidth: 0.46, headTopExtra: 0.05, form: "The twilight comet")
        t[.pulsa] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.84), palette: .spec(c(1, 0.92, 0.66), accent: c(1, 0.7, 0.24), light: .white), parts: [.glow(c(1, 0.78, 0.3)), .rays(14, c(1, 0.8, 0.3)), .lightning], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.05, form: "The pulse nova")
        t[.stellan] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(w, accent: starBlue, light: .white), parts: [.ears(.fox), .starAntlers, .mane(6), .sparkles(2)], hatScale: 0.92, hatMaxWidth: 0.46, form: "The cosmic fawn")
        t[.cosmi] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(w, accent: c(0.6, 0.5, 1), light: .white), parts: [.glow(c(0.6, 0.5, 1)), .ears(.bunny), .orbiters(3, starGold), .tail(.fluffy, w)], hatScale: 0.92, hatMaxWidth: 0.5, form: "The galaxy hopper")
        t[.eclipa] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.84), palette: .spec(c(0.16, 0.13, 0.22), accent: c(1, 0.86, 0.5), iris: c(1, 0.86, 0.5), light: c(0.3, 0.26, 0.4)), parts: [.tail(.curl, c(0.16, 0.13, 0.22)), .ears(.cat), .moonMark(c(1, 0.88, 0.55)), .sparkles(3)], hatScale: 0.92, hatMaxWidth: 0.48, form: "The moon shadow")
        t[.meteo] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.98, 0.6, 0.3), accent: c(1, 0.86, 0.3), light: c(1, 0.84, 0.6)), parts: [.glow(c(1, 0.5, 0.2)), .flame(c(1, 0.46, 0.18)), .ears(.tufts)], hatScale: 0.92, hatMaxWidth: 0.46, form: "The meteor scout")
        t[.asteri] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.84), palette: .spec(w, accent: c(0.7, 0.8, 1), light: .white), parts: [.glow(c(0.7, 0.8, 1)), .wings(.fairy, c(0.82, 0.9, 1)), .crystals(c(0.7, 0.84, 1)), .sparkles(3)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "The crystal constellation")
        t[.zenith] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.86), palette: .spec(c(1, 0.9, 0.66), accent: c(0.9, 0.56, 0.24), light: c(1, 0.97, 0.86)), parts: [.glow(starGold), .mane(12), .wings(.feather, c(1, 0.86, 0.5)), .ears(.round)], hatScale: 0.92, hatMaxWidth: 0.46, form: "The solar guardian")
        t[.liora] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.84), palette: .spec(w, accent: c(0.5, 0.9, 0.8), light: .white), parts: [.glow(c(0.5, 0.95, 0.85)), .wings(.fairy, c(0.6, 0.94, 0.86)), .petals(5, c(0.94, 0.7, 0.96)), .tail(.ribbon, c(0.6, 0.9, 0.9))], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "The aurora bloom")
        t[.nocta] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.82), palette: .spec(c(0.3, 0.26, 0.44), accent: c(0.9, 0.8, 0.5), iris: c(0.9, 0.8, 0.5), light: c(0.46, 0.4, 0.62)), parts: [.wings(.moth, nightViolet), .antennae(c(0.7, 0.6, 1)), .sparkles(3)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "The midnight moth")
        t[.glint] = MolibooSpec(body: .drop, size: CGSize(width: 0.8, height: 0.92), palette: .spec(w, accent: c(0.4, 0.86, 1), light: .white), parts: [.glow(c(0.5, 0.9, 1)), .wings(.dart, c(0.6, 0.9, 1)), .antennae(starGold), .sparkles(4)], floats: true, feet: false, hatScale: 0.8, hatMaxWidth: 0.52, headTopExtra: 0.16, form: "The stardust pixie")
        t[.polaris] = MolibooSpec(body: .bell, size: CGSize(width: 0.9, height: 0.92), palette: .spec(w, accent: c(0.36, 0.5, 0.94), light: .white), parts: [.glow(starBlue), .wings(.feather, c(0.86, 0.9, 1)), .starCrest, .sparkles(3)], floats: true, feet: false, hatScale: 0.82, hatMaxWidth: 0.52, headTopExtra: 0.06, form: "The guiding star")
    }

    static let stardustProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .astra: .init(number: 71, title: "The Star Sprite", traits: ["Light", "Bright", "Brave"]),
        .nebbi: .init(number: 72, title: "The Nebula Dreamer", traits: ["Cosmic", "Dreamy", "Gentle"]),
        .quori: .init(number: 73, title: "The Ringed Wanderer", traits: ["Orbit", "Curious", "Playful"]),
        .vesper: .init(number: 74, title: "The Twilight Comet", traits: ["Night", "Swift", "Mysterious"]),
        .pulsa: .init(number: 75, title: "The Pulse Nova", traits: ["Energy", "Bold", "Electric"]),
        .stellan: .init(number: 76, title: "The Cosmic Fawn", traits: ["Starlight", "Noble", "Graceful"]),
        .cosmi: .init(number: 77, title: "The Galaxy Hopper", traits: ["Space", "Cheerful", "Adventurous"]),
        .eclipa: .init(number: 78, title: "The Moon Shadow", traits: ["Eclipse", "Calm", "Enigmatic"]),
        .meteo: .init(number: 79, title: "The Meteor Scout", traits: ["Fire", "Fast", "Fearless"]),
        .asteri: .init(number: 80, title: "The Crystal Constellation", traits: ["Crystal", "Wise", "Magical"]),
        .zenith: .init(number: 81, title: "The Solar Guardian", traits: ["Sun", "Loyal", "Majestic"]),
        .liora: .init(number: 82, title: "The Aurora Bloom", traits: ["Aurora", "Kind", "Radiant"]),
        .nocta: .init(number: 83, title: "The Midnight Moth", traits: ["Shadow", "Dreamy", "Quiet"]),
        .glint: .init(number: 84, title: "The Stardust Pixie", traits: ["Spark", "Tiny", "Energetic"]),
        .polaris: .init(number: 85, title: "The Guiding Star", traits: ["Guide", "Hopeful", "Serene"]),
    ]
}

// MARK: - Family 006 — Dreamers (The Dreaming Vale)

extension MolibooFamilySpecs {
    static let dreamBlue = c(0.4, 0.44, 0.8), dreamLilac = c(0.84, 0.78, 0.98)
    static func addDreamers(_ t: inout [ModulaMascotKind: MolibooSpec]) {
        let w = c(0.98, 0.96, 1)
        t[.dozi] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.82), palette: .spec(c(0.92, 0.88, 1), accent: c(1, 0.74, 0.86), light: .white), parts: [.wings(.fairy, c(0.86, 0.8, 1)), .nightcap(dreamBlue), .sparkles(2)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "The sleepy sprite")
        t[.lulli] = MolibooSpec(body: .cloud, size: CGSize(width: 1.08, height: 0.84), palette: .spec(w, accent: c(1, 0.8, 0.5), light: .white), parts: [.glow(dreamLilac), .notes, .sparkles(4)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.54, headTopExtra: 0.04, form: "The lullaby cloud")
        t[.moona] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.82), palette: .spec(c(0.94, 0.9, 1), accent: starGold, light: .white), parts: [.crescent(c(1, 0.9, 0.6)), .nightcap(c(0.56, 0.5, 0.86)), .ears(.round)], hatScale: 0.92, hatMaxWidth: 0.46, form: "The crescent dreamer")
        t[.nuzzle] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(1, 0.86, 0.88), accent: c(0.96, 0.6, 0.7), light: c(1, 0.96, 0.96)), parts: [.tail(.fluffy, c(1, 0.92, 0.94)), .ears(.fox), .petals(3, c(1, 0.8, 0.86))], hatScale: 0.92, hatMaxWidth: 0.48, form: "The pillow fox")
        t[.drifty] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(w, accent: dreamBlue, light: .white), parts: [.ears(.floppy), .blanket(c(0.5, 0.56, 0.9)), .sparkles(2)], hatScale: 0.92, hatMaxWidth: 0.46, form: "The blanket hopper")
        t[.hushby] = MolibooSpec(body: .cloud, size: CGSize(width: 1.06, height: 0.86), palette: .spec(w, accent: starGold, light: .white), parts: [.shell(c(0.98, 0.96, 1)), .ears(.floppy), .sparkles(2)], hatScale: 0.92, hatMaxWidth: 0.46, headTopExtra: 0.04, form: "The cloud sheep")
        t[.swayla] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.82), palette: .spec(c(0.82, 0.76, 0.96), accent: c(1, 0.78, 0.4), light: c(0.96, 0.94, 1)), parts: [.antennae(c(0.6, 0.5, 0.9)), .lantern(c(1, 0.8, 0.4)), .wings(.round, c(0.6, 0.5, 0.86))], hatScale: 0.95, hatMaxWidth: 0.52, form: "The night lantern")
        t[.snoomi] = MolibooSpec(body: .round, size: CGSize(width: 0.96, height: 0.82), palette: .spec(w, accent: c(0.64, 0.7, 0.96), light: .white), parts: [.nightcap(c(0.64, 0.7, 0.96)), .feet(w)], hatScale: 0.95, hatMaxWidth: 0.54, form: "The marshmallow napper")
        t[.velvi] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.82), palette: .spec(w, accent: c(0.74, 0.56, 0.96), light: .white), parts: [.wings(.moth, c(0.8, 0.62, 0.98)), .antennae(starGold), .mane(6)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.52, headTopExtra: 0.05, form: "The dream moth")
        t[.minku] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.82), palette: .spec(c(0.5, 0.42, 0.62), accent: c(1, 0.84, 0.86), light: c(0.72, 0.64, 0.84)), parts: [.wings(.bat, c(0.4, 0.32, 0.54)), .ears(.bat), .sparkles(2)], floats: true, feet: false, hatScale: 0.92, hatMaxWidth: 0.46, headTopExtra: 0.05, form: "The sleepy bat")
        t[.tufti] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.82), palette: .spec(c(1, 0.94, 0.88), accent: starGold, light: .white), parts: [.ears(.floppy), .starCrest], hatScale: 0.82, hatMaxWidth: 0.46, headTopExtra: 0.06, form: "The drowsy bunny")
        t[.winkle] = MolibooSpec(body: .wide, size: CGSize(width: 1.14, height: 0.78), palette: .spec(c(0.5, 0.5, 0.86), accent: starGold, light: c(0.84, 0.84, 1)), parts: [.tail(.whale, c(0.42, 0.42, 0.78)), .fins(c(0.44, 0.44, 0.8)), .sparkles(4)], floats: true, feet: false, hatScale: 0.95, hatMaxWidth: 0.58, form: "The dream whale")
        t[.sonata] = MolibooSpec(body: .round, size: CGSize(width: 0.84, height: 0.82), palette: .spec(c(0.92, 0.86, 1), accent: starGold, light: .white), parts: [.petals(6, c(0.84, 0.74, 0.98)), .notes, .bowtie(starGold)], hatScale: 0.95, hatMaxWidth: 0.54, form: "The music box spirit")
        t[.comfi] = MolibooSpec(body: .round, size: CGSize(width: 0.96, height: 0.86), palette: .spec(c(0.82, 0.62, 0.42), accent: c(0.96, 0.88, 0.74), light: c(0.96, 0.84, 0.68)), parts: [.ears(.round), .nightcap(dreamBlue), .blanket(c(0.56, 0.5, 0.86))], hatScale: 0.92, hatMaxWidth: 0.46, form: "The cozy bear")
        t[.somna] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.86), palette: .spec(w, accent: c(0.6, 0.76, 1), light: .white), parts: [.glow(c(0.7, 0.8, 1)), .antlers(c(0.94, 0.9, 0.78)), .mane(8), .sparkles(3)], hatScale: 0.95, hatMaxWidth: 0.54, form: "The keeper of dreams")
    }

    static let dreamerProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .dozi: .init(number: 86, title: "The Sleepy Sprite", traits: ["Sleep", "Gentle", "Cozy"]),
        .lulli: .init(number: 87, title: "The Lullaby Cloud", traits: ["Song", "Dreamy", "Calm"]),
        .moona: .init(number: 88, title: "The Crescent Dreamer", traits: ["Moon", "Quiet", "Magical"]),
        .nuzzle: .init(number: 89, title: "The Pillow Fox", traits: ["Comfort", "Sweet", "Loyal"]),
        .drifty: .init(number: 90, title: "The Blanket Hopper", traits: ["Plush", "Bouncy", "Playful"]),
        .hushby: .init(number: 91, title: "The Cloud Sheep", traits: ["Rest", "Soft", "Peaceful"]),
        .swayla: .init(number: 92, title: "The Night Lantern", traits: ["Glow", "Soothing", "Wise"]),
        .snoomi: .init(number: 93, title: "The Marshmallow Napper", traits: ["Nap", "Tender", "Friendly"]),
        .velvi: .init(number: 94, title: "The Dream Moth", traits: ["Twilight", "Elegant", "Gentle"]),
        .minku: .init(number: 95, title: "The Sleepy Bat", traits: ["Night", "Shy", "Curious"]),
        .tufti: .init(number: 96, title: "The Drowsy Bunny", traits: ["Snuggle", "Tiny", "Cheerful"]),
        .winkle: .init(number: 97, title: "The Dream Whale", traits: ["Float", "Wonder", "Calm"]),
        .sonata: .init(number: 98, title: "The Music Box Spirit", traits: ["Melody", "Graceful", "Enchanting"]),
        .comfi: .init(number: 99, title: "The Cozy Bear", traits: ["Warm", "Protective", "Kind"]),
        .somna: .init(number: 100, title: "The Keeper of Dreams", traits: ["Dream", "Guardian", "Serene"]),
    ]
}

/// Crab pincer: a round claw with a wedge cut out (opening up and outward).
struct MascotClawShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(r.width, r.height) / 2, startAngle: .degrees(-50), endAngle: .degrees(-100), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Rounded cap crown (flat bottom), used by the backwards street cap.
struct MascotCapDome: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY), control1: CGPoint(x: r.minX, y: r.minY - r.height * 0.3), control2: CGPoint(x: r.maxX, y: r.minY - r.height * 0.3))
        p.closeSubpath()
        return p
    }
}
