import SwiftUI
import CoreMotion

// MARK: - Model & preferences

/// Six original composer mascots, drawn entirely with SwiftUI shapes.
enum ModulaMascotKind: String, CaseIterable, Identifiable, Sendable {
    case pip, moss, nimbus, ember, tuck, mochi
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pip: "Pip"
        case .moss: "Moss"
        case .nimbus: "Nimbus"
        case .ember: "Ember"
        case .tuck: "Tuck"
        case .mochi: "Mochi"
        }
    }

    var personality: String {
        switch self {
        case .pip: "Bubbly axolotl, waves its frills when happy"
        case .moss: "Unbothered pond frog, puffs up to think"
        case .nimbus: "Daydreamy cloud, always drifting"
        case .ember: "Tiny spark with big energy"
        case .tuck: "Curious owl who reads every word"
        case .mochi: "Sleepy cat, secretly listening"
        }
    }

    struct Palette { let light: Color; let mid: Color; let dark: Color; let accent: Color; let iris: Color; let outline: Color }

    var palette: Palette {
        switch self {
        case .pip: Palette(light: Color(red: 1.0, green: 0.84, blue: 0.89), mid: Color(red: 0.98, green: 0.62, blue: 0.75), dark: Color(red: 0.86, green: 0.42, blue: 0.60), accent: Color(red: 0.95, green: 0.33, blue: 0.55), iris: Color(red: 0.35, green: 0.20, blue: 0.32), outline: Color(red: 0.55, green: 0.22, blue: 0.38))
        case .moss: Palette(light: Color(red: 0.76, green: 0.95, blue: 0.62), mid: Color(red: 0.46, green: 0.80, blue: 0.42), dark: Color(red: 0.25, green: 0.60, blue: 0.32), accent: Color(red: 0.98, green: 0.93, blue: 0.70), iris: Color(red: 0.62, green: 0.45, blue: 0.10), outline: Color(red: 0.13, green: 0.38, blue: 0.20))
        case .nimbus: Palette(light: Color(red: 1.0, green: 1.0, blue: 1.0), mid: Color(red: 0.84, green: 0.90, blue: 1.0), dark: Color(red: 0.60, green: 0.72, blue: 0.96), accent: Color(red: 0.62, green: 0.78, blue: 1.0), iris: Color(red: 0.22, green: 0.33, blue: 0.62), outline: Color(red: 0.36, green: 0.46, blue: 0.76))
        case .ember: Palette(light: Color(red: 1.0, green: 0.92, blue: 0.55), mid: Color(red: 1.0, green: 0.64, blue: 0.28), dark: Color(red: 0.93, green: 0.36, blue: 0.20), accent: Color(red: 1.0, green: 0.85, blue: 0.35), iris: Color(red: 0.42, green: 0.16, blue: 0.08), outline: Color(red: 0.62, green: 0.20, blue: 0.10))
        case .tuck: Palette(light: Color(red: 0.86, green: 0.72, blue: 0.56), mid: Color(red: 0.66, green: 0.50, blue: 0.36), dark: Color(red: 0.45, green: 0.32, blue: 0.23), accent: Color(red: 0.99, green: 0.90, blue: 0.74), iris: Color(red: 0.95, green: 0.62, blue: 0.12), outline: Color(red: 0.30, green: 0.20, blue: 0.13))
        case .mochi: Palette(light: Color(red: 0.95, green: 0.95, blue: 0.98), mid: Color(red: 0.78, green: 0.78, blue: 0.86), dark: Color(red: 0.58, green: 0.58, blue: 0.68), accent: Color(red: 1.0, green: 0.68, blue: 0.76), iris: Color(red: 0.30, green: 0.58, blue: 0.42), outline: Color(red: 0.36, green: 0.36, blue: 0.46))
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

// MARK: - Tilt (CoreMotion, shared, ref-counted)

@MainActor
final class ModulaMascotMotion {
    static let shared = ModulaMascotMotion()
    /// -1…1 look offset from device tilt (read each frame by visible mascots; not observed).
    private(set) var tilt: CGSize = .zero
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let x = max(-1, min(1, g.x * 1.8))
                let y = max(-1, min(1, (g.z + 0.55) * 1.6))
                self.tilt = CGSize(width: x, height: y)
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

enum MascotMood: Equatable { case idle, typing, happy, surprised, sleepy, thinking }

struct MascotPose {
    var t: Double = 0
    var look: CGSize = .zero
    var blink: CGFloat = 0          // 0 open … 1 closed
    var mood: MascotMood = .idle
    var breathe: CGFloat = 0        // -1…1
    var sway: Double = 0            // degrees
    var hop: CGFloat = 0            // points up
    var squash: CGFloat = 1         // y scale (x = 1/sqrt)
    var amp: CGFloat = 1            // idle motion amplitude (0 under Reduce Motion)

    static func still(_ mood: MascotMood = .idle) -> MascotPose { MascotPose(mood: mood, amp: 0) }
}

struct MascotBurst: Identifiable {
    enum Style { case sparkle, hearts, pop }
    let id = UUID()
    let start: Double
    let style: Style
    let seed: Double
}

/// Per-mascot behaviour: spring-smoothed gaze, blinks, glances, hops, reactions and sleep.
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
    private(set) var lastInteraction: Double = Date.timeIntervalSinceReferenceDate
    private var reaction: (MascotMood, Double)?
    private var hops: [Double] = []
    private(set) var bursts: [MascotBurst] = []
    var typingUntil: Double = 0

    static var now: Double { Date.timeIntervalSinceReferenceDate }

    func poke() { lastInteraction = Self.now }

    func hop(burst: MascotBurst.Style? = .sparkle) {
        let n = Self.now
        poke()
        hops.append(n)
        if let burst { bursts.append(MascotBurst(start: n, style: burst, seed: Double.random(in: 0...1000))) }
    }

    func react(_ mood: MascotMood) {
        let n = Self.now
        poke()
        reaction = (mood, n)
        switch mood {
        case .happy:
            hops.append(contentsOf: [n, n + 0.42])
            bursts.append(MascotBurst(start: n, style: .hearts, seed: Double.random(in: 0...1000)))
        case .surprised:
            hops.append(n)
            bursts.append(MascotBurst(start: n, style: .pop, seed: Double.random(in: 0...1000)))
        default: break
        }
    }

    func pose(at now: Double, touchLook: CGSize?, tilt: CGSize, busy: Bool, reduceMotion: Bool) -> MascotPose {
        var p = MascotPose(t: now, amp: reduceMotion ? 0 : 1)
        hops.removeAll { now - $0 > 0.6 }
        bursts.removeAll { now - $0.start > 1.3 }
        if let r = reaction, now - r.1 > (r.0 == .happy ? 1.5 : 1.1) { reaction = nil }

        // Mood.
        let asleep = !busy && touchLook == nil && now - lastInteraction > 28
        if busy { p.mood = .thinking }
        else if let r = reaction { p.mood = r.0 }
        else if asleep { p.mood = .sleepy }
        else if now < typingUntil { p.mood = .typing }

        // Gaze target.
        if now > nextGlance && p.mood == .idle && touchLook == nil {
            glance = CGSize(width: Double.random(in: -1...1), height: Double.random(in: -0.7...0.6))
            glanceUntil = now + Double.random(in: 0.6...1.2)
            nextGlance = now + Double.random(in: 3.5...7)
        }
        var target: CGSize
        switch p.mood {
        case .thinking: target = CGSize(width: 0.55 + 0.25 * sin(now * 2.1), height: -0.75)
        case .surprised: target = .zero
        case .sleepy: target = CGSize(width: 0, height: 0.5)
        case .typing: target = CGSize(width: -0.8, height: 0.6)
        default:
            if let touchLook { target = touchLook }
            else if now < glanceUntil { target = glance }
            else { target = reduceMotion ? .zero : tilt }
        }

        // Critically-ish damped spring for the pupils.
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

        // Blinks.
        if now > nextBlink {
            blinkStart = now
            nextBlink = now + Double.random(in: 2.4...5.6) * (Double.random(in: 0...1) < 0.2 ? 0.15 : 1) // occasional double blink
        }
        let be = now - blinkStart
        p.blink = be < 0.16 ? CGFloat(sin(be / 0.16 * .pi)) : 0
        if p.mood == .sleepy { p.blink = max(p.blink, 0.62 + 0.08 * CGFloat(sin(now * 1.3))) }
        if p.mood == .happy { p.blink = 0 }

        guard !reduceMotion else { return p }

        // Breathing, sway.
        let breathRate = p.mood == .sleepy ? 0.18 : (p.mood == .thinking ? 0.55 : 0.32)
        p.breathe = CGFloat(sin(now * 2 * .pi * breathRate))
        p.sway = sin(now * 0.9) * (p.mood == .sleepy ? 3.5 : 2.2)

        // Hops with anticipation / stretch / landing squash.
        var squash: CGFloat = 1 + 0.025 * p.breathe
        var height: CGFloat = 0
        for start in hops where now >= start {
            let e = now - start
            if e < 0.07 { squash = min(squash, 1 - 0.14 * CGFloat(e / 0.07)) }
            else if e < 0.43 {
                let u = (e - 0.07) / 0.36
                height = max(height, CGFloat(sin(u * .pi)) * 11)
                squash = max(squash, 1 + 0.08 * CGFloat(sin(u * .pi)))
            } else if e < 0.6 {
                let u = (e - 0.43) / 0.17
                squash = min(squash, 1 - 0.12 * CGFloat(sin(u * .pi)))
            }
        }
        if p.mood == .thinking { height = max(height, 2 + 2 * CGFloat(sin(now * 3.2))) }
        p.hop = height
        p.squash = squash
        return p
    }
}

// MARK: - Figure

/// A mascot rendered from a pose. Volumetric toy look: radial body shading, rim light,
/// specular, outline, glossy eyes with catchlights, cheeks and character-specific idle parts.
struct ModulaMascotFigure: View {
    let kind: ModulaMascotKind
    var pose: MascotPose
    var size: CGFloat = 48

    var body: some View {
        let s = size
        let pal = kind.palette
        let t = pose.t
        let a = pose.amp
        ZStack {
            behind(s: s, pal: pal, t: t, a: a)
            bodyLayer(s: s, pal: pal)
            front(s: s, pal: pal, t: t, a: a)
            face(s: s, pal: pal, t: t, a: a)
                .rotationEffect(.degrees(kind == .tuck ? 7 * sin(t * 0.8) * Double(a) : 0), anchor: .bottom)
        }
        .frame(width: s * 1.5, height: s * 1.35)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .scaleEffect(x: 1 / sqrt(pose.squash), y: pose.squash, anchor: .bottom)
        .rotationEffect(.degrees(pose.sway), anchor: .bottom)
        .offset(y: -pose.hop)
    }

    // Body silhouette in a unit-ish rect centred in the frame.
    private func bodyPath(_ s: CGFloat) -> AnyShape {
        switch kind {
        case .pip, .mochi, .tuck: AnyShape(Ellipse())
        case .moss: AnyShape(Ellipse())
        case .nimbus: AnyShape(MascotCloudShape())
        case .ember: AnyShape(MascotDropShape())
        }
    }

    private var bodySize: CGSize {
        switch kind {
        case .moss: CGSize(width: 1.06, height: 0.80)
        case .nimbus: CGSize(width: 1.14, height: 0.84)
        case .ember: CGSize(width: 0.92, height: 1.02)
        case .tuck: CGSize(width: 0.94, height: 0.92)
        default: CGSize(width: 1.0, height: 0.86)
        }
    }

    private var bodyOffsetY: CGFloat {
        switch kind {
        case .moss: 0.14
        case .ember: 0.04
        default: 0.10
        }
    }

    private func bodyLayer(s: CGFloat, pal: ModulaMascotKind.Palette) -> some View {
        let shape = bodyPath(s)
        let w = s * bodySize.width, h = s * bodySize.height
        return ZStack {
            shape.fill(
                RadialGradient(colors: [pal.light, pal.mid, pal.dark], center: UnitPoint(x: 0.36, y: 0.28), startRadius: s * 0.02, endRadius: s * 0.72)
            )
            // Ambient occlusion along the bottom.
            shape.fill(LinearGradient(colors: [.clear, .clear, pal.dark.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            // Rim light (bottom-right bounce).
            shape.stroke(
                LinearGradient(colors: [.clear, pal.light.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: s * 0.05
            )
            .blur(radius: s * 0.02)
            .mask(shape)
            // Outline for contrast on light and dark sheets.
            shape.stroke(pal.outline.opacity(0.55), lineWidth: max(s * 0.028, 1))
            // Specular.
            Ellipse().fill(.white.opacity(0.75))
                .frame(width: s * 0.26, height: s * 0.12)
                .rotationEffect(.degrees(-24))
                .offset(x: -w * 0.22, y: -h * 0.28)
                .blur(radius: s * 0.012)
            Circle().fill(.white.opacity(0.9)).frame(width: s * 0.05).offset(x: -w * 0.05, y: -h * 0.36)
        }
        .frame(width: w, height: h)
        .offset(y: s * bodyOffsetY)
    }

    @ViewBuilder
    private func behind(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        switch kind {
        case .pip:
            // Feathery gills, waving.
            ForEach(0..<3, id: \.self) { i in
                let base = Double(i - 1) * 30
                let wave = 9 * sin(t * 3.1 + Double(i) * 0.9) * Double(a)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    MascotFrond()
                        .fill(LinearGradient(colors: [pal.accent, pal.dark], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotFrond().stroke(pal.outline.opacity(0.5), lineWidth: max(s * 0.02, 0.8)))
                        .frame(width: s * 0.14, height: s * 0.36)
                        .offset(y: -s * 0.18)
                        .rotationEffect(.degrees(side * (62 - base + wave)), anchor: .bottom)
                        .offset(x: side * s * 0.40, y: s * 0.04)
                }
            }
        case .mochi:
            // Tail.
            MascotTail()
                .stroke(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
                .frame(width: s * 0.36, height: s * 0.42)
                .rotationEffect(.degrees(12 * sin(t * 1.6) * Double(a)), anchor: .bottomLeading)
                .offset(x: s * 0.52, y: s * 0.08)
            // Ears with an occasional twitch.
            let twitch = a * CGFloat(max(0, sin(t * 1.9) - 0.93) * 14) * 9
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    MascotTriangle().fill(LinearGradient(colors: [pal.mid, pal.dark], startPoint: .top, endPoint: .bottom))
                    MascotTriangle().stroke(pal.outline.opacity(0.55), lineWidth: max(s * 0.026, 1))
                    MascotTriangle().fill(pal.accent.opacity(0.85)).scaleEffect(0.5).offset(y: s * 0.04)
                }
                .frame(width: s * 0.32, height: s * 0.32)
                .rotationEffect(.degrees(side * 18 + (side > 0 ? Double(twitch) : 0)), anchor: .bottom)
                .offset(x: side * s * 0.27, y: -s * 0.26)
            }
        case .tuck:
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    MascotTriangle().fill(pal.dark)
                    MascotTriangle().stroke(pal.outline.opacity(0.6), lineWidth: max(s * 0.026, 1))
                }
                .frame(width: s * 0.22, height: s * 0.28)
                .rotationEffect(.degrees(side * 30), anchor: .bottom)
                .offset(x: side * s * 0.32, y: -s * 0.32)
            }
        case .moss:
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle().fill(RadialGradient(colors: [pal.light, pal.mid], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.24))
                    Circle().stroke(pal.outline.opacity(0.55), lineWidth: max(s * 0.026, 1))
                }
                .frame(width: s * 0.40, height: s * 0.40)
                .offset(x: side * s * 0.25, y: -s * 0.14)
            }
        case .ember:
            // Flickering flame tongues.
            ForEach(0..<3, id: \.self) { i in
                let flick = 1 + 0.18 * sin(t * 9 + Double(i) * 2.1) * Double(a) + 0.08 * sin(t * 15.3 + Double(i)) * Double(a)
                MascotDropShape()
                    .fill(LinearGradient(colors: [pal.accent, pal.dark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * (i == 1 ? 0.30 : 0.2), height: s * (i == 1 ? 0.44 : 0.3))
                    .scaleEffect(y: flick, anchor: .bottom)
                    .rotationEffect(.degrees(Double(i - 1) * 24))
                    .offset(x: CGFloat(i - 1) * s * 0.17, y: -s * (i == 1 ? 0.40 : 0.30))
                    .blur(radius: s * 0.008)
            }
        case .nimbus:
            // Little drifting puff.
            Circle()
                .fill(RadialGradient(colors: [pal.light, pal.mid], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.12))
                .overlay(Circle().stroke(pal.outline.opacity(0.4), lineWidth: max(s * 0.02, 0.8)))
                .frame(width: s * 0.2, height: s * 0.2)
                .offset(x: -s * 0.56 + CGFloat(sin(t * 0.7)) * s * 0.05 * a, y: -s * 0.22 + CGFloat(cos(t * 0.9)) * s * 0.04 * a)
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
            // Throat puff.
            let puff = 0.65 + 0.35 * max(0, sin(t * 1.4)) * Double(a)
            Ellipse().fill(RadialGradient(colors: [pal.accent, pal.accent.opacity(0.7)], center: .center, startRadius: 0, endRadius: s * 0.2))
                .overlay(Ellipse().stroke(pal.outline.opacity(0.25), lineWidth: 0.8))
                .frame(width: s * 0.36 * puff, height: s * 0.22 * puff)
                .offset(y: s * 0.38)
        case .nimbus:
            EmptyView()
        default:
            EmptyView()
        }
        // Cheeks (all but owl).
        if kind != .tuck {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(RadialGradient(colors: [pal.accent.opacity(pose.mood == .happy ? 0.85 : 0.55), .clear], center: .center, startRadius: 0, endRadius: s * 0.1))
                    .frame(width: s * 0.22, height: s * 0.14)
                    .offset(x: side * s * 0.31, y: s * (kind == .ember ? 0.28 : 0.20))
            }
        }
    }

    private func face(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat) -> some View {
        let eye: CGFloat = kind == .tuck ? s * 0.25 : (kind == .moss ? s * 0.23 : s * 0.21)
        let eyeY: CGFloat = kind == .moss ? -s * 0.13 : (kind == .ember ? s * 0.10 : s * 0.04)
        let spread: CGFloat = kind == .moss ? s * 0.25 : (kind == .tuck ? s * 0.18 : s * 0.19)
        let widen: CGFloat = pose.mood == .surprised ? 1.22 : 1
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotEye(look: pose.look, blink: pose.blink, happy: pose.mood == .happy, size: eye * widen, iris: pal.iris, outline: pal.outline, ringed: kind == .tuck ? pal.accent : nil)
                    .offset(x: side * spread, y: eyeY)
            }
            mouth(s: s, pal: pal, t: t)
                .offset(y: kind == .moss ? s * 0.13 : (kind == .ember ? s * 0.30 : s * 0.22))
        }
    }

    @ViewBuilder
    private func mouth(s: CGFloat, pal: ModulaMascotKind.Palette, t: Double) -> some View {
        let line = StrokeStyle(lineWidth: max(s * 0.034, 1), lineCap: .round, lineJoin: .round)
        switch pose.mood {
        case .surprised:
            Ellipse().fill(pal.outline.opacity(0.85)).frame(width: s * 0.09, height: s * 0.11)
        case .sleepy:
            Capsule().fill(pal.outline.opacity(0.7)).frame(width: s * 0.07, height: s * 0.025)
        case .thinking:
            MascotSquiggle(phase: t * 4).stroke(pal.outline.opacity(0.75), style: line).frame(width: s * 0.12, height: s * 0.04)
        case .happy:
            MascotOpenSmile().fill(pal.outline.opacity(0.85))
                .overlay(MascotOpenSmile().fill(Color(red: 1, green: 0.45, blue: 0.5)).scaleEffect(x: 0.5, y: 0.45, anchor: .bottom))
                .frame(width: s * 0.17, height: s * 0.1)
        default:
            if kind == .tuck {
                MascotTriangle().rotation(.degrees(180)).fill(Color(red: 0.98, green: 0.72, blue: 0.28))
                    .overlay(MascotTriangle().rotation(.degrees(180)).stroke(pal.outline.opacity(0.5), lineWidth: 0.8))
                    .frame(width: s * 0.12, height: s * 0.1).offset(y: -s * 0.08)
            } else if kind == .mochi {
                MascotCatMouth().stroke(pal.outline.opacity(0.8), style: line).frame(width: s * 0.16, height: s * 0.06)
            } else {
                MascotSmile().stroke(pal.outline.opacity(0.8), style: line).frame(width: s * 0.15, height: s * 0.06)
            }
        }
    }
}

struct MascotEye: View {
    var look: CGSize
    var blink: CGFloat
    var happy: Bool
    var size: CGFloat
    var iris: Color
    var outline: Color
    var ringed: Color? = nil

    var body: some View {
        let travel = size * 0.2
        let lx = max(-1, min(1, look.width)), ly = max(-1, min(1, look.height))
        ZStack {
            if let ringed {
                Circle().fill(ringed).frame(width: size * 1.32, height: size * 1.32)
                    .overlay(Circle().stroke(outline.opacity(0.35), lineWidth: 0.8))
            }
            if happy {
                MascotHappyEye().stroke(outline, style: StrokeStyle(lineWidth: max(size * 0.16, 1.2), lineCap: .round))
                    .frame(width: size * 0.8, height: size * 0.4)
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.white, Color(white: 0.9)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                    Circle().stroke(outline.opacity(0.6), lineWidth: max(size * 0.06, 0.8))
                    ZStack {
                        Circle().fill(RadialGradient(colors: [iris.opacity(0.75), iris], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: size * 0.3))
                            .frame(width: size * 0.64, height: size * 0.64)
                        Circle().fill(Color(red: 0.06, green: 0.06, blue: 0.09)).frame(width: size * 0.36, height: size * 0.36)
                        Circle().fill(.white).frame(width: size * 0.2).offset(x: -size * 0.11, y: -size * 0.12)
                        Circle().fill(.white.opacity(0.8)).frame(width: size * 0.08).offset(x: size * 0.1, y: size * 0.1)
                    }
                    .offset(x: lx * travel, y: ly * travel)
                    .clipShape(Circle())
                }
                .frame(width: size, height: size)
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

struct MascotTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX * 0.8, y: r.minY), control1: CGPoint(x: r.maxX, y: r.maxY), control2: CGPoint(x: r.maxX * 1.1, y: r.midY))
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
        // Union so stroke/outline follows the silhouette only.
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

// MARK: - Live mascot (timeline-driven)

/// A living mascot: drives a `MascotBrain` from a TimelineView, paused when offscreen,
/// in the background, or under Reduce Motion. Draws the contact shadow, glow, thinking dots,
/// sleep Zs and particle bursts around the figure.
struct ModulaLiveMascot: View {
    let kind: ModulaMascotKind
    var size: CGFloat = 48
    var busy = false
    var touch: CGPoint? = nil
    var brain: MascotBrain
    var showsShadow = true
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var motionOn = false
    @State private var frame: CGRect = .zero

    private var paused: Bool { !animated || reduceMotion || !visible || scenePhase != .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let pose = brain.pose(at: now, touchLook: touchLook, tilt: ModulaMascotMotion.shared.tilt, busy: busy, reduceMotion: reduceMotion || !animated)
            ZStack {
                if busy { glow(now: now) }
                if showsShadow {
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: size * 0.42))
                        .frame(width: size * 0.95 * (1 - pose.hop / 40), height: size * 0.22)
                        .offset(y: size * 0.58)
                }
                ModulaMascotFigure(kind: kind, pose: pose, size: size)
                if pose.mood == .thinking { thinkingDots(now: now) }
                if pose.mood == .sleepy && !reduceMotion { sleepZs(now: now) }
                if !reduceMotion && !brain.bursts.isEmpty { particles(now: now) }
            }
            .frame(width: size * 1.6, height: size * 1.5)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onAppear { visible = true; syncMotion() }
        .onDisappear { visible = false; syncMotion() }
        .onChange(of: reduceMotion) { _, _ in syncMotion() }
        .onChange(of: animated) { _, _ in syncMotion() }
    }

    /// Tilt updates only while this mascot is on screen and animating (balanced start/stop).
    private func syncMotion() {
        let want = visible && !reduceMotion && animated
        guard want != motionOn else { return }
        motionOn = want
        want ? ModulaMascotMotion.shared.start() : ModulaMascotMotion.shared.stop()
    }

    private var touchLook: CGSize? {
        guard let touch, frame != .zero else { return nil }
        let dx = touch.x - frame.midX, dy = touch.y - frame.midY
        let d = max(hypot(dx, dy), 1)
        let m = min(d / 80, 1)
        return CGSize(width: dx / d * m, height: dy / d * m)
    }

    private func glow(now: Double) -> some View {
        let pulse = reduceMotion ? 0.8 : 0.65 + 0.35 * sin(now * 3.4)
        let pal = kind.palette
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [pal.accent.opacity(0.9), pal.mid.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: size * 0.85))
                .frame(width: size * 1.8, height: size * 1.8)
                .blur(radius: 8)
                .opacity(pulse)
            // Orbiting light.
            if !reduceMotion {
                Circle().fill(.white).frame(width: 4, height: 4).blur(radius: 1)
                    .offset(x: cos(now * 2.6) * size * 0.62, y: sin(now * 2.6) * size * 0.3 - size * 0.05)
                    .opacity(0.9)
            }
        }
    }

    private func thinkingDots(now: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(kind.palette.outline.opacity(0.75))
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: reduceMotion ? 0 : -3 * max(0, sin(now * 6 - Double(i) * 0.9)))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.92)).shadow(color: .black.opacity(0.12), radius: 3, y: 1))
        .offset(x: size * 0.55, y: -size * 0.62)
    }

    private func sleepZs(now: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let u = (now * 0.4 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 9 + CGFloat(u) * 5, weight: .heavy, design: .rounded))
                    .foregroundStyle(kind.palette.outline.opacity(0.8 * (1 - u)))
                    .offset(x: size * 0.45 + CGFloat(u) * 10, y: -size * 0.4 - CGFloat(u) * 18)
            }
        }
    }

    private func particles(now: Double) -> some View {
        let pal = kind.palette
        let bursts = brain.bursts
        return Canvas { ctx, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            for burst in bursts {
                let e = now - burst.start
                guard e >= 0 else { continue }
                let count = burst.style == .hearts ? 6 : 9
                for i in 0..<count {
                    let seed = burst.seed + Double(i) * 12.9898
                    let angle = (Double(i) / Double(count)) * 2 * .pi + sin(seed) * 0.4 - .pi / 2
                    let speed = 34 + 18 * abs(sin(seed * 1.7))
                    let x = c.x + CGFloat(cos(angle) * speed * e)
                    let y = c.y - size * 0.1 + CGFloat(sin(angle) * speed * e + 40 * e * e)
                    let life = max(0, 1 - e / 1.1)
                    let r = CGFloat(burst.style == .pop ? 2.2 : 3.2) * CGFloat(0.6 + 0.4 * life)
                    var path: Path
                    switch burst.style {
                    case .hearts: path = MascotParticle.heart(at: CGPoint(x: x, y: y - CGFloat(e * 20)), r: r * 1.2)
                    case .sparkle: path = MascotParticle.star(at: CGPoint(x: x, y: y), r: r)
                    case .pop: path = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    let color: Color = burst.style == .hearts ? Color(red: 1, green: 0.4, blue: 0.55) : (i % 2 == 0 ? pal.accent : .white)
                    ctx.opacity = life
                    ctx.fill(path, with: .color(color))
                    if burst.style != .hearts { ctx.stroke(path, with: .color(pal.outline.opacity(0.35)), lineWidth: 0.5) }
                }
            }
        }
        .allowsHitTesting(false)
        .frame(width: size * 2.6, height: size * 2.4)
    }
}

enum MascotParticle {
    static func star(at p: CGPoint, r: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let rr = i % 2 == 0 ? r * 1.6 : r * 0.55
            let pt = CGPoint(x: p.x + CGFloat(cos(a)) * rr, y: p.y + CGFloat(sin(a)) * rr)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }

    static func heart(at p: CGPoint, r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y + r))
        path.addCurve(to: CGPoint(x: p.x - r, y: p.y - r * 0.2), control1: CGPoint(x: p.x - r * 0.4, y: p.y + r * 0.6), control2: CGPoint(x: p.x - r, y: p.y + r * 0.3))
        path.addArc(center: CGPoint(x: p.x - r * 0.5, y: p.y - r * 0.3), radius: r * 0.5, startAngle: .degrees(170), endAngle: .degrees(0), clockwise: false)
        path.addArc(center: CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.3), radius: r * 0.5, startAngle: .degrees(180), endAngle: .degrees(10), clockwise: false)
        path.addCurve(to: CGPoint(x: p.x, y: p.y + r), control1: CGPoint(x: p.x + r, y: p.y + r * 0.3), control2: CGPoint(x: p.x + r * 0.4, y: p.y + r * 0.6))
        return path
    }
}

// MARK: - Composer host

/// Perches the chosen mascot on the composer's top-trailing edge when enabled for `placement`.
struct ModulaComposerMascotModifier: ViewModifier {
    let placement: ModulaMascotPlacement
    var busy: Bool
    var text: String
    var attachmentCount: Int
    /// Points in from the trailing edge, so the mascot clears in-field accessories.
    var trailingInset: CGFloat
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage private var shown: Bool
    @State private var touch: CGPoint?

    init(placement: ModulaMascotPlacement, busy: Bool, text: String, attachmentCount: Int, trailingInset: CGFloat) {
        self.placement = placement
        self.busy = busy
        self.text = text
        self.attachmentCount = attachmentCount
        self.trailingInset = trailingInset
        _shown = AppStorage(wrappedValue: ModulaMascotSettings.defaultShown(placement), ModulaMascotSettings.key(for: placement))
    }

    func body(content: Content) -> some View {
        if shown, let kind = ModulaMascotKind(rawValue: kindRaw) {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { touch = $0.location }
                        .onEnded { _ in touch = nil }
                )
                .overlay(alignment: .topTrailing) {
                    ModulaComposerMascot(kind: kind, busy: busy, touch: touch, text: text, attachmentCount: attachmentCount) { kindRaw = $0.rawValue }
                        // Perch: feet overlap the bar's top edge by ~8pt.
                        .alignmentGuide(.top) { d in d[.bottom] - 8 - d.height * 0.16 }
                        .alignmentGuide(.trailing) { d in d[.trailing] - (d.width * 0.18) + trailingInset }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Mascot perched on this composer bar (if enabled in Settings → Chats → Composer for `placement`).
    func modulaComposerMascot(_ placement: ModulaMascotPlacement, busy: Bool = false, text: String = "", attachmentCount: Int = 0, trailingInset: CGFloat = 10) -> some View {
        modifier(ModulaComposerMascotModifier(placement: placement, busy: busy, text: text, attachmentCount: attachmentCount, trailingInset: trailingInset))
    }
}

/// Mascot + its gestures: tap to hop, hold to open the glass picker, slide to preview, release to pick.
struct ModulaComposerMascot: View {
    let kind: ModulaMascotKind
    var busy: Bool
    var touch: CGPoint?
    var text: String = ""
    var attachmentCount: Int = 0
    var size: CGFloat = 48
    var onSelect: (ModulaMascotKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brain = MascotBrain()
    @State private var picking = false
    @State private var hovered: ModulaMascotKind?
    @State private var tileFrames: [ModulaMascotKind: CGRect] = [:]
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var moved = false
    @State private var swapTick = 0

    var body: some View {
        ModulaLiveMascot(kind: kind, size: size, busy: busy, touch: picking ? nil : touch, brain: brain)
            .id(kind)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity), removal: .scale(scale: 1.3).combined(with: .opacity)))
            .scaleEffect(picking ? 1.08 : 1, anchor: .bottom)
            .contentShape(Circle().scale(0.8))
            .gesture(pressGesture)
            .overlay(alignment: .bottomTrailing) {
                if picking {
                    ModulaMascotPicker(selected: kind, hovered: hovered, onFrames: { tileFrames = $0 }) { choice in
                        commit(choice)
                    } onClose: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
                    }
                    .alignmentGuide(.bottom) { d in d[.bottom] + 4 }
                    .alignmentGuide(.trailing) { d in d[.trailing] - 6 }
                    .offset(y: -size * 0.95)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.15, anchor: .bottomTrailing).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: kind)
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: picking)
            .onChange(of: text) { old, new in
                if new.count - old.count > 6 { brain.react(.surprised); HapticEngine.shared.play(.lightImpact) }
                else if !old.isEmpty && new.isEmpty && !busy { brain.react(.happy); HapticEngine.shared.play(.success) }
                else if !new.isEmpty { brain.poke(); brain.typingUntil = MascotBrain.now + 1.4 }
            }
            .onChange(of: attachmentCount) { old, new in if new > old { brain.react(.surprised); HapticEngine.shared.play(.lightImpact) } }
            .onChange(of: busy) { old, new in
                brain.poke()
                if new && !old { brain.react(.happy) }
            }
            .onChange(of: touch != nil) { _, touching in if touching { brain.poke() } }
            .sensoryFeedback(.selection, trigger: hovered)
            .accessibilityElement()
            .accessibilityLabel("\(kind.name), composer mascot")
            .accessibilityHint("Hold to choose a different mascot")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { brain.hop() }
            .accessibilityAction(named: "Choose mascot") { picking = true }
            .accessibilityIdentifier("composer.mascot")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    moved = false
                    holdTask?.cancel()
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(320))
                        guard !Task.isCancelled, !moved, !picking else { return }
                        HapticEngine.shared.play(.contextOpen)
                        brain.poke()
                        picking = true
                    }
                }
                if hypot(value.translation.width, value.translation.height) > 10, !picking { moved = true }
                if picking {
                    hovered = tileFrames.first(where: { $0.value.insetBy(dx: -4, dy: -4).contains(value.location) })?.key
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                defer { pressStart = nil; hovered = nil }
                if picking {
                    if let hovered { commit(hovered) }
                    return
                }
                if !moved, let start = pressStart, Date().timeIntervalSince(start) < 0.32 {
                    brain.hop(burst: reduceMotion ? nil : .sparkle)
                    HapticEngine.shared.play(.lightImpact)
                }
            }
    }

    private func commit(_ choice: ModulaMascotKind) {
        HapticEngine.shared.play(.success)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
        if choice != kind {
            onSelect(choice)
            brain = MascotBrain()
            brain.react(.happy)
        } else {
            brain.hop()
        }
    }
}

/// Liquid Glass picker that springs out of the mascot: all six large, animated, with names and a line.
struct ModulaMascotPicker: View {
    let selected: ModulaMascotKind
    var hovered: ModulaMascotKind?
    var onFrames: ([ModulaMascotKind: CGRect]) -> Void
    var onSelect: (ModulaMascotKind) -> Void
    var onClose: () -> Void
    @State private var frames: [ModulaMascotKind: CGRect] = [:]
    @State private var brains: [ModulaMascotKind: MascotBrain] = Dictionary(uniqueKeysWithValues: ModulaMascotKind.allCases.map { ($0, MascotBrain()) })
    @State private var appeared = false

    private let columns = Array(repeating: GridItem(.fixed(96), spacing: 6), count: 3)

    var body: some View {
        let focus = hovered ?? selected
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.name).font(.headline)
                    Text(focus.personality).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.2), value: focus)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 6)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(ModulaMascotKind.allCases.enumerated()), id: \.element) { index, kind in
                    let isFocus = kind == hovered
                    let isSelected = kind == selected
                    Button { onSelect(kind) } label: {
                        VStack(spacing: 2) {
                            ModulaLiveMascot(kind: kind, size: 40, busy: false, brain: brains[kind] ?? MascotBrain(), showsShadow: true)
                                .frame(width: 70, height: 62)
                                .scaleEffect(isFocus ? 1.14 : 1)
                            Text(kind.name).font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected || isFocus ? .primary : .secondary)
                        }
                        .frame(width: 96, height: 88)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.primary.opacity(isFocus ? 0.10 : (isSelected ? 0.06 : 0)))
                        }
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                            }
                        }
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.03), value: appeared)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocus)
                    }
                    .buttonStyle(.plain)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        frames[kind] = frame
                        onFrames(frames)
                    }
                    .accessibilityLabel("\(kind.name). \(kind.personality)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(10)
        .frame(width: 3 * 96 + 2 * 6 + 20)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false)
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .onAppear { appeared = true }
        .onChange(of: hovered) { _, kind in if let kind { brains[kind]?.hop(burst: nil) } }
    }
}

// MARK: - Settings section

/// Live preview, mascot grid, and per-surface toggles (Settings → Chats → Composer).
struct ComposerMascotSettingsSection: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(ModulaMascotSettings.nodusKey) private var nodus = true
    @AppStorage(ModulaMascotSettings.commentsKey) private var comments = false
    @AppStorage(ModulaMascotSettings.otherKey) private var other = false
    @State private var previewText = ""
    @State private var previewBusy = false
    @State private var tileBrains: [ModulaMascotKind: MascotBrain] = Dictionary(uniqueKeysWithValues: ModulaMascotKind.allCases.map { ($0, MascotBrain()) })

    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        Section {
            previewCard
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text("Mascot")
        } footer: {
            Text("Tap it to hop, hold it to swap. Its eyes follow your touch and the tilt of your iPhone, it watches you type, cheers when you send, and glows while something is generating.")
        }
        Section("Choose") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ModulaMascotKind.allCases) { k in
                    tile(k)
                }
                offTile
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        }
        if kind != nil {
            Section("Show mascot on") {
                Toggle("Nodus", isOn: $nodus)
                Toggle("Comment inputs", isOn: $comments)
                Toggle("Other composers", isOn: $other)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind?.name ?? "Mascot off").font(.headline)
                Spacer()
                Button(previewBusy ? "Stop" : "Try thinking") {
                    withAnimation(.snappy) { previewBusy.toggle() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(kind == nil)
            }
            Text(kind?.personality ?? "Pick a mascot below to bring the composer to life.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Type to see it watch…", text: $previewText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                    .modulaComposerMascotPreview(kind: kind, busy: previewBusy, text: previewText) { kindRaw = $0.rawValue }
                Button {
                    previewText = ""
                } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send preview")
            }
            .padding(.top, 52)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [(kind?.palette.light ?? .gray).opacity(0.35), Color.primary.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .animation(.smooth, value: kindRaw)
    }

    private func tile(_ k: ModulaMascotKind) -> some View {
        let selected = kindRaw == k.rawValue
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { kindRaw = k.rawValue }
            tileBrains[k]?.react(.happy)
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 6) {
                ModulaLiveMascot(kind: k, size: 56, brain: tileBrains[k] ?? MascotBrain(), animated: selected)
                    .frame(height: 84)
                Text(k.name).font(.subheadline.weight(.semibold))
                Text(k.personality).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                    .frame(minHeight: 28, alignment: .top)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .scaleEffect(selected ? 1 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(k.name). \(k.personality)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var offTile: some View {
        let selected = kind == nil
        return Button {
            withAnimation(.snappy) { kindRaw = ModulaMascotSettings.off }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "eye.slash").font(.system(size: 30)).foregroundStyle(.secondary).frame(height: 84)
                Text("Off").font(.subheadline.weight(.semibold))
                Text("No mascot on any composer").font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: 28, alignment: .top)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mascot off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    /// Settings preview: always shows the chosen mascot regardless of per-surface toggles.
    @ViewBuilder
    func modulaComposerMascotPreview(kind: ModulaMascotKind?, busy: Bool, text: String, onSelect: @escaping (ModulaMascotKind) -> Void) -> some View {
        if let kind {
            overlay(alignment: .topTrailing) {
                ModulaComposerMascot(kind: kind, busy: busy, touch: nil, text: text, onSelect: onSelect)
                    .alignmentGuide(.top) { d in d[.bottom] - 8 - d.height * 0.16 }
                    .alignmentGuide(.trailing) { d in d[.trailing] - d.width * 0.18 + 10 }
            }
        } else {
            self
        }
    }
}
