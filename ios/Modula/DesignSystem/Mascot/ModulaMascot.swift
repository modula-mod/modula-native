import SwiftUI
import CoreMotion

// MARK: - Roster

/// Fifteen original composer mascots, drawn entirely with SwiftUI shapes.
enum ModulaMascotKind: String, CaseIterable, Identifiable, Sendable {
    // Free
    case pip, moss, nimbus, mochi, sprout
    // Premium
    case ember, tuck, bloop, bun, pebble, tofu, comet, puff, bolt, glim
    var id: String { rawValue }

    var isPremium: Bool {
        switch self {
        case .pip, .moss, .nimbus, .mochi, .sprout: false
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
        }
    }

    struct Palette { let light: Color; let mid: Color; let dark: Color; let accent: Color; let iris: Color; let outline: Color }

    var palette: Palette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .pip: return Palette(light: c(1, 0.86, 0.90), mid: c(0.98, 0.64, 0.76), dark: c(0.84, 0.40, 0.58), accent: c(0.96, 0.34, 0.56), iris: c(0.36, 0.20, 0.32), outline: c(0.52, 0.20, 0.36))
        case .moss: return Palette(light: c(0.80, 0.96, 0.64), mid: c(0.48, 0.81, 0.42), dark: c(0.24, 0.58, 0.30), accent: c(0.99, 0.93, 0.70), iris: c(0.62, 0.45, 0.10), outline: c(0.12, 0.36, 0.19))
        case .nimbus: return Palette(light: c(1, 1, 1), mid: c(0.86, 0.91, 1), dark: c(0.60, 0.71, 0.95), accent: c(0.60, 0.76, 1), iris: c(0.22, 0.33, 0.62), outline: c(0.33, 0.43, 0.74))
        case .mochi: return Palette(light: c(0.97, 0.96, 0.99), mid: c(0.80, 0.79, 0.87), dark: c(0.57, 0.56, 0.67), accent: c(1, 0.66, 0.75), iris: c(0.30, 0.58, 0.42), outline: c(0.34, 0.33, 0.45))
        case .sprout: return Palette(light: c(0.99, 0.94, 0.72), mid: c(0.93, 0.80, 0.48), dark: c(0.76, 0.60, 0.30), accent: c(0.45, 0.80, 0.36), iris: c(0.36, 0.24, 0.12), outline: c(0.45, 0.32, 0.14))
        case .ember: return Palette(light: c(1, 0.93, 0.56), mid: c(1, 0.65, 0.28), dark: c(0.92, 0.35, 0.19), accent: c(1, 0.85, 0.35), iris: c(0.42, 0.16, 0.08), outline: c(0.60, 0.19, 0.09))
        case .tuck: return Palette(light: c(0.88, 0.74, 0.58), mid: c(0.67, 0.51, 0.37), dark: c(0.45, 0.32, 0.23), accent: c(0.99, 0.90, 0.74), iris: c(0.95, 0.62, 0.12), outline: c(0.29, 0.19, 0.12))
        case .bloop: return Palette(light: c(0.93, 0.86, 1), mid: c(0.74, 0.60, 0.98), dark: c(0.50, 0.38, 0.86), accent: c(0.98, 0.62, 0.92), iris: c(0.28, 0.18, 0.52), outline: c(0.36, 0.24, 0.64))
        case .bun: return Palette(light: c(1, 0.98, 0.95), mid: c(0.93, 0.88, 0.84), dark: c(0.76, 0.69, 0.66), accent: c(1, 0.72, 0.78), iris: c(0.36, 0.22, 0.20), outline: c(0.46, 0.36, 0.34))
        case .pebble: return Palette(light: c(0.84, 0.88, 0.92), mid: c(0.62, 0.67, 0.74), dark: c(0.42, 0.47, 0.55), accent: c(0.50, 0.76, 0.46), iris: c(0.18, 0.22, 0.30), outline: c(0.25, 0.29, 0.36))
        case .tofu: return Palette(light: c(1, 1, 0.97), mid: c(0.96, 0.95, 0.88), dark: c(0.82, 0.80, 0.70), accent: c(1, 0.70, 0.62), iris: c(0.25, 0.22, 0.20), outline: c(0.52, 0.48, 0.38))
        case .comet: return Palette(light: c(1, 0.98, 0.70), mid: c(1, 0.86, 0.36), dark: c(0.95, 0.64, 0.18), accent: c(0.55, 0.80, 1), iris: c(0.30, 0.20, 0.10), outline: c(0.62, 0.40, 0.08))
        case .puff: return Palette(light: c(0.80, 0.96, 1), mid: c(0.48, 0.82, 0.96), dark: c(0.24, 0.58, 0.82), accent: c(1, 0.80, 0.40), iris: c(0.14, 0.26, 0.40), outline: c(0.12, 0.36, 0.56))
        case .bolt: return Palette(light: c(0.92, 0.95, 0.98), mid: c(0.70, 0.76, 0.84), dark: c(0.46, 0.52, 0.62), accent: c(0.36, 0.90, 0.80), iris: c(0.10, 0.56, 0.64), outline: c(0.24, 0.30, 0.40))
        case .glim: return Palette(light: c(0.78, 0.86, 0.56), mid: c(0.52, 0.66, 0.36), dark: c(0.32, 0.44, 0.24), accent: c(1, 0.96, 0.50), iris: c(0.20, 0.26, 0.12), outline: c(0.20, 0.30, 0.14))
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
        default: CGSize(width: 1.0, height: 0.86)
        }
    }

    var bodyOffsetY: CGFloat {
        switch self {
        case .moss, .pebble: 0.14
        case .ember, .comet: 0.04
        case .bloop: 0.0
        default: 0.10
        }
    }

    /// Distance from the figure's centre to where it rests on a surface (fraction of size).
    var footFraction: CGFloat {
        switch self {
        case .bloop: 0.62   // tentacle tips
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
        default: 0.04
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

enum MascotMood: Equatable { case idle, typing, happy, pleased, surprised, sleepy, thinking, dizzy, sad, laughing, speaking }

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
    enum Style { case sparkle, hearts, pop, confetti, tear }
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
        default:
            reaction = (mood, n, 1.0)
        }
    }

    func celebrate() {
        react(.happy)
        burst(.confetti)
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
        case .happy, .pleased, .laughing: p.eyes = .happy
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

    /// The figure canvas, generous enough for ears, gills, hats and tentacles.
    static func canvas(_ s: CGFloat) -> CGSize { CGSize(width: s * 2.0, height: s * 1.9) }

    var body: some View {
        let s = size
        let pal = kind.palette
        let t = pose.t
        let a = pose.amp
        let c = Self.canvas(s)
        ZStack {
            behind(s: s, pal: pal, t: t, a: a)
            bodyLayer(s: s, pal: pal, t: t, a: a)
            front(s: s, pal: pal, t: t, a: a)
            face(s: s, pal: pal, t: t)
                .rotationEffect(.degrees(kind == .tuck ? 7 * sin(t * 0.8) * Double(a) : 0), anchor: .bottom)
            accessories(s: s, pal: pal, t: t, a: a)
        }
        .frame(width: c.width, height: c.height)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .scaleEffect(x: 1 / sqrt(pose.squash), y: pose.squash, anchor: UnitPoint(x: 0.5, y: 0.5 + kind.footFraction * s / c.height))
        .rotationEffect(.degrees(pose.sway), anchor: UnitPoint(x: 0.5, y: 0.5 + kind.footFraction * s / c.height))
        .offset(x: pose.shiverX, y: -pose.hop)
    }

    private func bodyShape() -> AnyShape {
        switch kind {
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
            if kind == .pebble {
                // Moss cap.
                ForEach(0..<4, id: \.self) { i in
                    Ellipse().fill(pal.accent.opacity(0.95)).frame(width: s * 0.2, height: s * 0.1)
                        .offset(x: CGFloat(i - 2) * s * 0.11 + s * 0.06, y: -h * 0.44 + CGFloat(abs(i - 1)) * s * 0.02)
                }
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
            ForEach(0..<3, id: \.self) { i in
                let base = Double(i - 1) * 30
                let wave = 9 * sin(t * 3.1 + Double(i) * 0.9) * da
                ForEach([-1.0, 1.0], id: \.self) { side in
                    MascotFrond()
                        .fill(LinearGradient(colors: [pal.accent, pal.dark], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotFrond().stroke(pal.outline.opacity(0.55), style: outline))
                        .frame(width: s * 0.15, height: s * 0.36)
                        .offset(y: -s * 0.18)
                        .rotationEffect(.degrees(side * (62 - base + wave)), anchor: .bottom)
                        .offset(x: side * s * 0.40, y: s * 0.04)
                }
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
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle().fill(RadialGradient(colors: [pal.light, pal.mid], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.24))
                    Circle().stroke(pal.outline.opacity(0.55), style: outline)
                }
                .frame(width: s * 0.40, height: s * 0.40)
                .offset(x: side * s * 0.25, y: -s * 0.14)
            }
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
            Circle()
                .fill(RadialGradient(colors: [pal.light, pal.mid], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.12))
                .overlay(Circle().stroke(pal.outline.opacity(0.45), lineWidth: max(s * 0.02, 0.8)))
                .frame(width: s * 0.2, height: s * 0.2)
                .offset(x: -s * 0.62 + CGFloat(sin(t * 0.7)) * s * 0.05 * a, y: -s * 0.22 + CGFloat(cos(t * 0.9)) * s * 0.04 * a)
        case .sprout:
            let lean = 8 * sin(t * 1.2) * da
            ZStack {
                Capsule().fill(pal.accent.opacity(0.9)).frame(width: s * 0.05, height: s * 0.24).offset(y: -s * 0.1)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    MascotLeaf()
                        .fill(LinearGradient(colors: [pal.accent.opacity(0.85), Color(red: 0.25, green: 0.6, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotLeaf().stroke(Color(red: 0.16, green: 0.4, blue: 0.16).opacity(0.6), lineWidth: max(s * 0.02, 0.8)))
                        .frame(width: s * 0.26, height: s * 0.14)
                        .rotationEffect(.degrees(side * -24 + side * 6 * sin(t * 2 + side) * da), anchor: side > 0 ? .leading : .trailing)
                        .offset(x: side * s * 0.13, y: -s * 0.22)
                }
            }
            .rotationEffect(.degrees(lean), anchor: .bottom)
            .offset(y: -s * 0.26)
        case .bloop:
            ForEach(0..<4, id: \.self) { i in
                MascotTentacle(phase: t * 2.4 + Double(i) * 1.3, amp: a)
                    .stroke(LinearGradient(colors: [pal.mid, pal.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                    .frame(width: s * 0.12, height: s * 0.34)
                    .offset(x: CGFloat(i) * s * 0.2 - s * 0.3, y: s * 0.42)
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
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(Color.white.opacity(0.55)).overlay(Ellipse().stroke(pal.outline.opacity(0.35), lineWidth: 0.8))
                    .frame(width: s * 0.3, height: s * 0.42)
                    .rotationEffect(.degrees(side * (35 + 18 * sin(t * 14) * da)), anchor: .bottom)
                    .offset(x: side * s * 0.2, y: -s * 0.18)
            }
            let pulse = 0.7 + 0.3 * sin(t * 2.2)
            Circle().fill(RadialGradient(colors: [pal.accent, pal.accent.opacity(0.0)], center: .center, startRadius: 0, endRadius: s * 0.3))
                .frame(width: s * 0.6).opacity(pulse)
                .offset(x: s * 0.36, y: s * 0.42)
            Circle().fill(pal.accent).frame(width: s * 0.22).overlay(Circle().stroke(pal.outline.opacity(0.4), lineWidth: 0.8))
                .offset(x: s * 0.34, y: s * 0.40)
        case .comet:
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(LinearGradient(colors: [pal.accent.opacity(0.0), pal.accent.opacity(0.8)], startPoint: .trailing, endPoint: .leading))
                    .frame(width: s * (0.5 - CGFloat(i) * 0.1), height: s * 0.07)
                    .offset(x: s * 0.62 + CGFloat(sin(t * 3 + Double(i))) * 2 * a, y: CGFloat(i - 1) * s * 0.13 + s * 0.1)
            }
        case .pebble, .tofu:
            EmptyView()
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
            let puff = 0.65 + 0.35 * max(0, sin(t * 1.4)) * Double(a)
            Ellipse().fill(RadialGradient(colors: [pal.accent, pal.accent.opacity(0.7)], center: .center, startRadius: 0, endRadius: s * 0.2))
                .overlay(Ellipse().stroke(pal.outline.opacity(0.25), lineWidth: 0.8))
                .frame(width: s * 0.36 * puff, height: s * 0.22 * puff)
                .offset(y: s * 0.38)
        case .puff:
            Ellipse().fill(pal.accent.opacity(0.9)).frame(width: s * 0.22, height: s * 0.12)
                .rotationEffect(.degrees(-30 + 12 * sin(t * 5) * Double(a)))
                .offset(x: -s * 0.44, y: s * 0.22)
        case .bun:
            Ellipse().fill(pal.light).frame(width: s * 0.2, height: s * 0.12).offset(y: s * 0.34)
        default:
            EmptyView()
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
        let glowEyes = pose.conditions.dark
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotEye(look: pose.look, blink: pose.blink, style: pose.eyes, spin: t * 6 * side, size: eye * widen, iris: kind == .bolt ? pal.accent : pal.iris, outline: pal.outline, ringed: kind == .tuck ? pal.accent : nil, glow: glowEyes, sad: pose.mood == .sad || pose.conditions.tired)
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
        if pose.conditions.night {
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
        if pose.conditions.offline {
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
