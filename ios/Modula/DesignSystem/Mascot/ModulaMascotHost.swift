import SwiftUI
import AVFoundation
import Network
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Context (battery, power, time, network, capture) — notification driven

@MainActor @Observable
final class MascotContext {
    static let shared = MascotContext()
    private(set) var batteryLow = false
    private(set) var charging = false
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var offline = false
    private(set) var captured = false
    private(set) var hour = Calendar.current.component(.hour, from: Date())
    /// Increments when a charger is plugged in.
    private(set) var chargeTick = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private let monitor = NWPathMonitor()

    func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        readBattery(initial: true)
        captured = UIScreen.main.isCaptured
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ block: @escaping @MainActor () -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { block() } })
        }
        observe(UIDevice.batteryLevelDidChangeNotification) { [weak self] in self?.readBattery(initial: false) }
        observe(UIDevice.batteryStateDidChangeNotification) { [weak self] in self?.readBattery(initial: false) }
        observe(.NSProcessInfoPowerStateDidChange) { [weak self] in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        observe(UIScreen.capturedDidChangeNotification) { [weak self] in self?.captured = UIScreen.main.isCaptured }
        observe(UIApplication.significantTimeChangeNotification) { [weak self] in self?.hour = Calendar.current.component(.hour, from: Date()) }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] in self?.hour = Calendar.current.component(.hour, from: Date()) }
        monitor.pathUpdateHandler = { [weak self] path in
            let bad = path.status != .satisfied || path.isConstrained
            Task { @MainActor in self?.offline = bad }
        }
        monitor.start(queue: .main)
    }

    private func readBattery(initial: Bool) {
        let device = UIDevice.current
        let level = device.batteryLevel
        let plugged = device.batteryState == .charging || device.batteryState == .full
        if !initial && plugged && !charging { chargeTick += 1 }
        charging = plugged
        batteryLow = level >= 0 && level < 0.2 && !plugged
    }

    func conditions(dark: Bool) -> MascotConditions {
        MascotConditions(
            tired: batteryLow,
            night: hour >= 23 || hour < 5,
            morning: hour >= 6 && hour < 10,
            lowPower: lowPower,
            offline: offline,
            shy: captured,
            dark: dark
        )
    }
}

// MARK: - Sounds (procedurally synthesised, ambient session)

@MainActor
final class MascotSound {
    static let shared = MascotSound()
    enum Cue: CaseIterable { case hop, pick, send, wake, tick, pop }

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var idleStop: Task<Void, Never>?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    var enabled: Bool { UserDefaults.standard.object(forKey: ModulaMascotSettings.soundsKey) as? Bool ?? true }

    func play(_ cue: Cue) {
        guard enabled else { return }
        let session = AVAudioSession.sharedInstance()
        // Respect the silent switch: only ever play in the ambient category, and never
        // hijack a session another feature (video, voice notes) has configured.
        if session.category == .soloAmbient { try? session.setCategory(.ambient, options: [.mixWithOthers]) }
        guard session.category == .ambient else { return }
        if engine == nil { setUp() }
        guard let engine, let player, let buffer = buffers[cue] else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
        idleStop?.cancel()
        idleStop = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.engine?.pause()
        }
    }

    private func setUp() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        self.engine = engine
        self.player = player
        buffers[.hop] = synth([Tone(from: 520, to: 880, dur: 0.09, gain: 0.32)])
        buffers[.pick] = synth([Tone(from: 784, to: 784, dur: 0.07, gain: 0.28), Tone(from: 1175, to: 1175, dur: 0.12, gain: 0.26)])
        buffers[.send] = synth([Tone(from: 440, to: 990, dur: 0.12, gain: 0.26, noise: 0.25), Tone(from: 1320, to: 1320, dur: 0.1, gain: 0.18)])
        buffers[.wake] = synth([Tone(from: 380, to: 300, dur: 0.08, gain: 0.25), Tone(from: 420, to: 700, dur: 0.14, gain: 0.25)])
        buffers[.tick] = synth([Tone(from: 1500, to: 1400, dur: 0.025, gain: 0.12)])
        buffers[.pop] = synth([Tone(from: 300, to: 1200, dur: 0.05, gain: 0.3)])
    }

    private struct Tone { var from: Double; var to: Double; var dur: Double; var gain: Double; var noise: Double = 0 }

    /// Soft sine chirps with a second harmonic, short attack and exponential decay.
    private func synth(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = tones.reduce(0) { $0 + $1.dur } + 0.03
        let frames = AVAudioFrameCount(total * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        var offset = 0
        var phase = 0.0
        var seed: UInt32 = 12345
        for tone in tones {
            let n = Int(tone.dur * rate)
            for i in 0..<n {
                let u = Double(i) / Double(n)
                let f = tone.from + (tone.to - tone.from) * u
                phase += 2 * .pi * f / rate
                let attack = min(1, Double(i) / (rate * 0.006))
                let env = attack * exp(-u * 4.2)
                seed = seed &* 1664525 &+ 1013904223
                let noise = (Double(seed) / Double(UInt32.max) * 2 - 1) * tone.noise
                let sample = (sin(phase) * 0.8 + sin(phase * 2) * 0.2 + noise) * env * tone.gain
                if offset + i < Int(frames) { data[offset + i] += Float(sample) }
            }
            offset += n
        }
        return buffer
    }
}

// MARK: - Live mascot (timeline-driven)

/// A living mascot: drives a `MascotBrain` from a TimelineView, paused when offscreen,
/// in the background, or under Reduce Motion. Generous canvas so nothing clips.
struct ModulaLiveMascot: View {
    let kind: ModulaMascotKind
    var size: CGFloat = 48
    var busy = false
    var touch: CGPoint? = nil
    var brain: MascotBrain
    var showsShadow = true
    var animated = true
    var bubble: Bool = true
    var outfit: MascotOutfit = .empty

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    @State private var motionOn = false
    @State private var frame: CGRect = .zero
    @State private var frozenFrame: CGRect?
    private let context = MascotContext.shared

    /// Whole view's size: figure canvas plus room for glow, bubbles and particles.
    static func container(_ s: CGFloat) -> CGSize { CGSize(width: s * 2.6, height: s * 2.4) }

    private var paused: Bool { !animated || reduceMotion || !visible || scenePhase != .active }

    var body: some View {
        let conditions = context.conditions(dark: colorScheme == .dark)
        let fps: Double = (conditions.lowPower || ModulaScrollActivity.shared.isScrolling) ? 20 : 60
        let c = Self.container(size)
        let foot = kind.footFraction * size
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: paused)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let pose = brain.pose(at: now, touchLook: touchLook, tilt: ModulaMascotMotion.shared.tilt, busy: busy, reduceMotion: reduceMotion || !animated, conditions: conditions)
            ZStack {
                ambientGlow(now: now, pose: pose)
                if showsShadow {
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(colorScheme == .dark ? 0.5 : 0.3), .clear], center: .center, startRadius: 0, endRadius: size * 0.45))
                        .frame(width: size * kind.bodySize.width * (1 - pose.hop / 40), height: size * 0.18)
                        .offset(y: foot)
                }
                ModulaMascotFigure(kind: kind, pose: pose, size: size, outfit: outfit)
                if bubble && (pose.mood == .thinking || pose.mood == .typing) { thoughtBubble(now: now, typing: pose.mood == .typing) }
                if pose.mood == .sleepy && !reduceMotion { sleepZs(now: now) }
                if !reduceMotion && !brain.bursts.isEmpty { particles(now: now) }
            }
            .frame(width: c.width, height: c.height)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if !ShellChromeFreeze.isSidebarDragging { frame = $0 } else { frozenFrame = $0 } }
        .onReceive(NotificationCenter.default.publisher(for: ShellChromeFreeze.didThaw)) { _ in
            if let frozenFrame { frame = frozenFrame }
            frozenFrame = nil
        }
        .onAppear { visible = true; context.start(); brain.jiggle = kind == .tofu ? 0.05 : 0.025; syncMotion() }
        .onDisappear { visible = false; syncMotion() }
        .onReceive(NotificationCenter.default.publisher(for: ModulaMascotEvent.notification)) { note in
            guard visible, animated, let raw = note.userInfo?["event"] as? String,
                  let event = ModulaMascotEvent(rawValue: raw) else { return }
            brain.handle(event)
        }
        .onChange(of: reduceMotion) { _, _ in syncMotion() }
        .onChange(of: animated) { _, _ in syncMotion() }
    }

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

    /// Soft per-mascot ambient glow; stronger with an orbiting light while busy.
    private func ambientGlow(now: Double, pose: MascotPose) -> some View {
        let pal = kind.palette
        let pulse = reduceMotion ? 0.8 : 0.65 + 0.35 * sin(now * 3.4)
        let strength: Double = busy ? pulse : (pose.conditions.dark ? 0.45 : 0.28)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [pal.accent.opacity(0.85), pal.mid.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: size * 0.9))
                .frame(width: size * 1.9, height: size * 1.9)
                .blur(radius: 10)
                .opacity(strength)
            if busy && !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    let a = now * 2.6 + Double(i) * .pi
                    Circle().fill(.white).frame(width: 4, height: 4).blur(radius: 0.8)
                        .shadow(color: pal.accent, radius: 3)
                        .offset(x: cos(a) * size * 0.66, y: sin(a) * size * 0.3 - size * 0.05)
                }
            }
        }
    }

    private func thoughtBubble(now: Double, typing: Bool) -> some View {
        let pal = kind.palette
        return ZStack(alignment: .bottomLeading) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(typing ? pal.dark : pal.outline.opacity(0.8))
                        .frame(width: 4.5, height: 4.5)
                        .offset(y: reduceMotion ? 0 : -2.5 * max(0, sin(now * (typing ? 8 : 6) - Double(i) * 0.9)))
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Capsule().fill(.white).shadow(color: .black.opacity(0.14), radius: 3, y: 1))
            .overlay(Capsule().stroke(pal.outline.opacity(0.2), lineWidth: 0.6))
            Circle().fill(.white).frame(width: 5, height: 5).shadow(color: .black.opacity(0.1), radius: 1)
                .offset(x: -4, y: 7)
        }
        .offset(x: size * 0.62, y: -size * 0.72)
    }

    private func sleepZs(now: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let u = (now * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 8 + CGFloat(u) * 6, weight: .heavy, design: .rounded))
                    .foregroundStyle(kind.palette.outline.opacity(0.85 * (1 - u)))
                    .offset(x: size * 0.48 + CGFloat(u) * 12 + CGFloat(sin(u * 6)) * 2, y: -size * 0.45 - CGFloat(u) * 22)
            }
        }
    }

    private func particles(now: Double) -> some View {
        let pal = kind.palette
        let bursts = brain.bursts
        let s = size
        return Canvas { ctx, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            for burst in bursts {
                let e = now - burst.start
                guard e >= 0 else { continue }
                let count: Int
                switch burst.style {
                case .hearts: count = 6
                case .confetti: count = 18
                case .aura, .outfit: count = 14
                case .tear: count = 1
                default: count = 9
                }
                for i in 0..<count {
                    let seed = burst.seed + Double(i) * 12.9898
                    let life = max(0, 1 - e / (burst.style == .confetti ? 1.5 : 1.1))
                    var pos: CGPoint
                    if burst.style == .tear {
                        pos = CGPoint(x: c.x - s * 0.3, y: c.y + s * 0.18 + CGFloat(e * e * 40))
                    } else {
                        let angle = (Double(i) / Double(count)) * 2 * .pi + sin(seed) * 0.5 - .pi / 2
                        let speed = (burst.style == .confetti ? 60 : 34) + 18 * abs(sin(seed * 1.7))
                        pos = CGPoint(x: c.x + CGFloat(cos(angle) * speed * e), y: c.y - s * 0.1 + CGFloat(sin(angle) * speed * e + 60 * e * e))
                    }
                    let r = CGFloat(burst.style == .pop ? 2.2 : 3.2) * CGFloat(0.6 + 0.4 * life)
                    let path: Path
                    let color: Color
                    switch burst.style {
                    case .hearts:
                        path = MascotParticle.heart(at: CGPoint(x: pos.x, y: pos.y - CGFloat(e * 22)), r: r * 1.25)
                        color = Color(red: 1, green: 0.38 + 0.1 * sin(seed), blue: 0.55)
                    case .sparkle:
                        path = MascotParticle.star(at: pos, r: r)
                        color = i % 2 == 0 ? pal.accent : .white
                    case .pop:
                        path = Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2))
                        color = i % 2 == 0 ? pal.light : pal.accent
                    case .confetti:
                        var rect = Path(roundedRect: CGRect(x: -2.5, y: -1.2, width: 5, height: 2.4), cornerRadius: 0.8)
                        rect = rect.applying(CGAffineTransform(rotationAngle: CGFloat(seed + e * 9)).concatenating(CGAffineTransform(translationX: pos.x, y: pos.y)))
                        path = rect
                        let palette: [Color] = [.pink, .yellow, .mint, .cyan, .orange, .purple]
                        color = palette[i % palette.count]
                    case .tear:
                        path = MascotDropShape().path(in: CGRect(x: pos.x - 2.5, y: pos.y - 4, width: 5, height: 7))
                        color = Color(red: 0.5, green: 0.75, blue: 1)
                    case .aura:
                        path = MascotParticle.star(at: pos, r: r * 1.4)
                        color = pal.accent.opacity(0.9)
                    case .outfit:
                        path = MascotParticle.star(at: pos, r: r * 1.1)
                        let palette: [Color] = [.pink, .mint, .yellow, .cyan, .orange]
                        color = palette[i % palette.count]
                    }
                    ctx.opacity = life
                    // Glow pass then crisp pass.
                    var glow = ctx
                    glow.addFilter(.blur(radius: 2.2))
                    glow.fill(path, with: .color(color.opacity(0.8)))
                    ctx.fill(path, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .frame(width: s * 3.2, height: s * 3.0)
    }
}

enum MascotParticle {
    static func star(at p: CGPoint, r: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let rr = i % 2 == 0 ? r * 1.7 : r * 0.5
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

// MARK: - Perch + composer host

/// The bar the mascot sits on. The first perch in the tree wins.
struct MascotPerchKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

extension View {
    /// Marks this view as the bar the composer mascot perches on.
    func modulaMascotPerch() -> some View { anchorPreference(key: MascotPerchKey.self, value: .bounds) { $0 } }

    /// Draws the mascot (if enabled for `placement`) above everything in this composer, perched on the
    /// `modulaMascotPerch()` bar (or this view's own bounds), `trailingInset` in from its right edge.
    func modulaComposerMascot(_ placement: ModulaMascotPlacement, busy: Bool = false, text: String = "", attachmentCount: Int = 0, trailingInset: CGFloat = 26, lift: CGFloat = 0, slotted: Bool = false, hidden: Bool = false) -> some View {
        modifier(ModulaComposerMascotModifier(placement: placement, busy: busy, text: text, attachmentCount: attachmentCount, trailingInset: trailingInset, slotted: slotted, hidden: hidden, lift: lift))
    }
}

struct ModulaComposerMascotModifier: ViewModifier {
    let placement: ModulaMascotPlacement
    var busy: Bool
    var text: String
    var attachmentCount: Int
    var trailingInset: CGFloat
    /// When true the mascot sits *inside* the `modulaMascotPerch()` slot (centred, scaled to fit)
    /// instead of standing on top of the bar, so it can never cover neighbouring controls.
    var slotted: Bool = false
    /// Fades the mascot out (keeping view identity, so the composer never loses focus).
    var hidden: Bool = false
    /// Extra rise above the perch (e.g. while a formatting bar fills the card's top edge).
    var lift: CGFloat = 0
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage private var shown: Bool
    @State private var touch: CGPoint?
    private let size: CGFloat = 48

    init(placement: ModulaMascotPlacement, busy: Bool, text: String, attachmentCount: Int, trailingInset: CGFloat, slotted: Bool = false, hidden: Bool = false, lift: CGFloat = 0) {
        self.lift = lift
        self.slotted = slotted
        self.hidden = hidden
        self.placement = placement
        self.busy = busy
        self.text = text
        self.attachmentCount = attachmentCount
        self.trailingInset = trailingInset
        _shown = AppStorage(wrappedValue: ModulaMascotSettings.defaultShown(placement), ModulaMascotSettings.key(for: placement))
    }

    private var kind: ModulaMascotKind? {
        if custom != nil { return .pip }   // behaviour proxy for custom mascots
        guard let k = ModulaMascotKind(rawValue: kindRaw) else { return nil }
        return MascotEntitlements.canUse(k) ? k : .pip
    }

    private var custom: CustomMascot? {
        guard kindRaw.hasPrefix("custom:") else { return nil }
        return CustomMascotStore.shared.mascot(id: kindRaw)
    }

    func body(content: Content) -> some View {
        if shown, let kind {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        // Coarse updates only: a re-render per pixel of finger travel was wasted work.
                        .onChanged { value in
                            if let t = touch, abs(t.x - value.location.x) + abs(t.y - value.location.y) < 12 { return }
                            touch = value.location
                        }
                        .onEnded { _ in touch = nil }
                )
                .overlayPreferenceValue(MascotPerchKey.self) { anchor in
                    GeometryReader { proxy in
                        let bar = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                        let s: CGFloat = slotted ? min(bar.height, bar.width) * 0.95 : size
                        let x = slotted ? bar.midX : bar.maxX - trailingInset - size * kind.bodySize.width / 2
                        // Slotted: feet rest on the slot floor. Perched: feet sink ~6pt into the bar's top edge.
                        let y = slotted ? bar.maxY - 2 - kind.footFraction * s : bar.minY + 6 - lift - kind.footFraction * size
                        ModulaComposerMascot(kind: kind, busy: busy, touch: touch, text: text, attachmentCount: attachmentCount, placement: placement, size: s, custom: custom) { kindRaw = $0.rawValue }
                            .position(x: x, y: y)
                            .opacity(hidden ? 0 : 1)
                            .allowsHitTesting(!hidden)
                            .accessibilityHidden(hidden)
                            .animation(.easeOut(duration: 0.18), value: hidden)
                    }
                }
                .zIndex(50)
        } else {
            content
        }
    }
}

/// Mascot + its gestures: tap to hop, double-tap to chat, hold to open the glass picker,
/// slide to preview, release to pick.
struct ModulaComposerMascot: View {
    let kind: ModulaMascotKind
    var busy: Bool
    var touch: CGPoint?
    var text: String = ""
    var attachmentCount: Int = 0
    var placement: ModulaMascotPlacement = .other
    var size: CGFloat = 48
    var custom: CustomMascot? = nil
    var onSelect: (ModulaMascotKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var brain = MascotBrain()
    @State private var picking = false
    @State private var chatting = false
    @State private var dressing = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var hovered: ModulaMascotKind?
    @State private var tileFrames: [ModulaMascotKind: CGRect] = [:]
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var lastTap: Date = .distantPast
    @State private var moved = false
    @State private var typingSettle: Task<Void, Never>?
    /// Global top of the mascot: the picker grows upward from here, so its grid is capped to the room above.
    @State private var mascotTop: CGFloat = 800
    private let context = MascotContext.shared
    private var wardrobe = MascotWardrobeStore.shared

    var body: some View {
        mascotChrome
            .task {
                MascotProgressStore.shared.touchDay()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-MOLPickerOpen") {
                    // Wait for the perch layout and any keyboard/scene settle (slower on device), then open; retry once.
                    for delay in [1200, 1500] {
                        try? await Task.sleep(for: .milliseconds(delay))
                        if !picking { withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { picking = true } }
                    }
                }
                #endif
            }
            .onChange(of: text) { old, new in textChanged(old: old, new: new) }
            .onChange(of: attachmentCount) { old, new in
                if new > old { brain.react(.surprised); MascotSound.shared.play(.pop); HapticEngine.shared.play(.lightImpact) }
            }
            .onChange(of: busy) { old, new in
                brain.poke()
                if new && !old { sent() }
            }
            .onChange(of: touch != nil) { _, touching in if touching { wake() } }
            .onChange(of: context.chargeTick) { _, _ in brain.react(.happy); brain.burst(.sparkle); MascotSound.shared.play(.wake) }
            .onChange(of: colorScheme) { _, _ in brain.react(.surprised) }
            .task(id: busy) {
                // Soft thinking tick while generating / sending.
                guard busy else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1100))
                    guard !Task.isCancelled else { break }
                    MascotSound.shared.play(.tick)
                }
            }
            .sensoryFeedback(.selection, trigger: hovered)
            .accessibilityElement()
            .accessibilityLabel("\(custom?.name ?? kind.name), composer Moliboo")
            .accessibilityHint("Double-tap to chat. Hold to choose or dress up the Moliboo.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { chatting = true }
            .accessibilityAction(named: "Choose Moliboo") { picking = true }
            .accessibilityIdentifier("composer.mascot")
    }

    private var mascotChrome: some View {
        Group {
            if let custom {
                CustomLiveMascot(mascot: custom, size: size, busy: busy, touch: picking ? nil : touch, brain: brain, outfit: wardrobe.outfit)
            } else if MolibooPortrait.usesPortrait(kind.rawValue) {
                MolibooPortraitCompanion(characterID: kind.rawValue, size: size, animated: !busy)   // MOL-03: lightweight 3D look
            } else {
                ModulaLiveMascot(kind: kind, size: size, busy: busy, touch: picking ? nil : touch, brain: brain, outfit: wardrobe.outfit)
            }
        }
            .id(custom?.id ?? kind.rawValue)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity), removal: .scale(scale: 1.4).combined(with: .opacity)))
            .scaleEffect(picking ? 1.1 : 1, anchor: .bottom)
            .contentShape(Ellipse().scale(x: 0.42, y: 0.46))
            .gesture(pressGesture)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { mascotTop = $0 }
            .overlay(alignment: .bottomTrailing) {
                if picking {
                    // Room above the mascot minus the status bar + navigation bar (~110pt) and the picker's lift.
                    ModulaMascotPicker(selected: kind, hovered: hovered, availableHeight: mascotTop + size * 0.25 - 110, onFrames: { tileFrames = $0 }) { choice in
                        commit(choice)
                    } onClose: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
                    } onDressUp: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
                        dressing = true
                    }
                    .alignmentGuide(.bottom) { d in d[.bottom] + size * 0.75 }
                    .alignmentGuide(.trailing) { d in d[.trailing] - size * 0.55 }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.08, anchor: .bottomTrailing).combined(with: .opacity).combined(with: .offset(x: 10, y: 18)), removal: .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity)))
                }
            }
            .popover(isPresented: $chatting, arrowEdge: .bottom) {
                MascotChatView(kind: kind, brain: brain)
                    .presentationCompactAdaptation(.popover)
            }
            .sheet(item: $premiumKind) { k in
                MascotPremiumSheet(kind: k)
            }
            .sheet(isPresented: $dressing) {
                MascotDressUpSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mascotOutfitDidChange)) { _ in
                brain.outfitChanged()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: kind)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72), value: picking)
    }

    private func wake() {
        if brain.poke() { MascotSound.shared.play(.wake); brain.react(.surprised) }
    }

    private func sent() {
        brain.react(.happy)
        MascotSound.shared.play(.send)
        HapticEngine.shared.play(.success)
        // Delight: first comment of the day gets confetti.
        if placement == .comments {
            let today = Date().formatted(.iso8601.year().month().day())
            if UserDefaults.standard.string(forKey: ModulaMascotSettings.celebrationKey) != today {
                UserDefaults.standard.set(today, forKey: ModulaMascotSettings.celebrationKey)
                brain.celebrate()
            }
        }
    }

    private func textChanged(old: String, new: String) {
        if new.count - old.count > 6 {
            brain.react(.surprised); MascotSound.shared.play(.pop); HapticEngine.shared.play(.lightImpact)
        } else if !old.isEmpty && new.isEmpty && !busy {
            sent()
        } else if !new.isEmpty {
            if brain.poke() { MascotSound.shared.play(.wake) }
            brain.keystroke()
            let line = new.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? new
            brain.caret = CGFloat(min(Double(line.count % 36) / 36, 1))
            if new.count > old.count, let last = new.last { emojiReaction(last) }
            typingSettle?.cancel()
            typingSettle = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                brain.react(.pleased)
            }
        }
    }

    /// Delight: reacts to a handful of emoji as you type them.
    private func emojiReaction(_ c: Character) {
        switch c {
        case "❤️", "😍", "🥰", "💖", "💕", "😘": brain.react(.happy)
        case "😂", "🤣", "😆", "😹": brain.react(.laughing)
        case "😢", "😭", "🥺", "💔": brain.react(.sad)
        case "🔥", "🎉", "✨", "🥳", "⭐️", "🌟": brain.hop(burst: .sparkle); brain.react(.pleased)
        case "😮", "😱", "🤯", "😲": brain.react(.surprised)
        default: break
        }
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
                        MascotSound.shared.play(.pop)
                        wake()
                        picking = true
                    }
                }
                if hypot(value.translation.width, value.translation.height) > 10, !picking { moved = true }
                if picking {
                    hovered = tileFrames.first(where: { $0.value.insetBy(dx: -3, dy: -3).contains(value.location) })?.key
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                defer { pressStart = nil; hovered = nil }
                if picking {
                    if let hovered { commit(hovered) }
                    return
                }
                guard !moved, let start = pressStart, Date().timeIntervalSince(start) < 0.32 else { return }
                if Date().timeIntervalSince(lastTap) < 0.3 {
                    lastTap = .distantPast
                    chatting = true
                    HapticEngine.shared.play(.contextOpen)
                } else {
                    lastTap = Date()
                    wake()
                    brain.hop(burst: reduceMotion ? nil : .sparkle)
                    MascotSound.shared.play(.hop)
                    HapticEngine.shared.play(.lightImpact)
                }
            }
    }

    private func commit(_ choice: ModulaMascotKind) {
        guard MascotEntitlements.canUse(choice) else {
            HapticEngine.shared.play(.warning)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
            premiumKind = choice
            return
        }
        HapticEngine.shared.play(.success)
        MascotSound.shared.play(.pick)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
        if choice != kind {
            onSelect(choice)
            brain = MascotBrain()
            brain.react(.happy)
            brain.burst(.sparkle)
        } else {
            brain.hop()
        }
    }
}

// MARK: - Picker

/// Liquid Glass picker that springs out of the mascot: all fifteen, animated, with names,
/// a personality line and Premium locks. Slide to preview, release to pick.
struct ModulaMascotPicker: View {
    let selected: ModulaMascotKind
    var hovered: ModulaMascotKind?
    /// Vertical room the whole picker may take (it springs upward from the mascot).
    var availableHeight: CGFloat = 640
    var onFrames: ([ModulaMascotKind: CGRect]) -> Void
    var onSelect: (ModulaMascotKind) -> Void
    var onClose: () -> Void
    var onDressUp: (() -> Void)? = nil
    @State private var frames: [ModulaMascotKind: CGRect] = [:]
    /// Family page shown in the grid (starts on the selected Moliboo's family). 115 Moliboos never fit one panel.
    @State private var family: MolibooFamily?
    /// Visible grid viewport (global): slide-to-pick only targets tiles you can actually see.
    @State private var gridViewport: CGRect = .zero
    @State private var brains: [ModulaMascotKind: MascotBrain] = Dictionary(uniqueKeysWithValues: ModulaMascotKind.allCases.map { ($0, MascotBrain()) })
    @State private var appeared = false
    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let ambience = MolibooAmbience.resolved()

    private let tile: CGFloat = 60
    private let gap: CGFloat = 5
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(tile), spacing: gap), count: 5) }
    private var ink: Color { ambience.isDark ? .white : .primary }
    private var families: [MolibooFamily] { MolibooFamily.allCases.filter { !$0.isDraft && !$0.kinds.isEmpty } }
    private var currentFamily: MolibooFamily { family ?? selected.family }
    private static let tileHeight: CGFloat = 66
    /// Hero, chips, Dress up, paddings and gaps around the grid.
    private var chromeHeight: CGFloat { 64 + 30 + (onDressUp != nil ? 38 + 8 : 0) + 8 * 2 + 20 }
    /// Grid height: the family's rows, capped at 3½ rows (and at the room above the mascot, never below 1½ rows).
    private var gridHeight: CGFloat {
        let rows = CGFloat((currentFamily.kinds.count + 4) / 5)
        let full = rows * Self.tileHeight + max(0, rows - 1) * gap
        let cap = 3.5 * Self.tileHeight + 3 * gap
        let room = max(1.5 * Self.tileHeight + gap, availableHeight - chromeHeight)
        return min(full, cap, room)
    }
    private var subInk: Color { ambience.isDark ? .white.opacity(0.75) : .secondary }

    var body: some View {
        let focus = hovered ?? selected
        VStack(alignment: .leading, spacing: 8) {
            hero(focus)
            familyChips
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: gap) {
                        ForEach(Array(currentFamily.kinds.enumerated()), id: \.element) { index, kind in
                            tileView(kind, index: index).id(kind)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: gridHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gridViewport = $0; publishFrames() }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                .onChange(of: currentFamily) { _, f in
                    frames = [:]
                    publishFrames()
                    if f == selected.family { proxy.scrollTo(selected, anchor: .center) }
                }
            }
            .accessibilityIdentifier("moliboo.picker.grid")
            if onDressUp != nil {
                Button { onDressUp?() } label: {
                    Label("Dress up", systemImage: "tshirt.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true, tint: focus.palette.dark, prominent: true, specular: true)
                .accessibilityLabel("Dress up Moliboo")
                .accessibilityIdentifier("moliboo.picker.dressup")
            }
        }
        .padding(10)
        .frame(width: 5 * tile + 4 * gap + 20)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false, specular: true)
        .background {
            MolibooAmbientBackground(ambience: ambience, animated: appeared, fps: 12, density: 0.45)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        // The picker sits on its own scene sky, so its glass and ink follow the scene, not the system appearance.
        .environment(\.colorScheme, ambience.isDark ? .dark : .light)
        .onAppear { appeared = true; if !reduceMotion { bob = true } }
        .onChange(of: hovered) { _, kind in if let kind { brains[kind]?.hop(burst: nil, height: 6) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moliboo.picker")
    }

    /// Only tiles of the shown family whose centre is inside the visible grid are slide-to-pick targets.
    private func publishFrames() {
        let shown = Set(currentFamily.kinds)
        onFrames(frames.filter { shown.contains($0.key) && gridViewport.contains(CGPoint(x: $0.value.midX, y: $0.value.midY)) })
    }

    /// Family chips in the Moliboos (rounded, heavy) face; the selected family takes its Moliboo's colour.
    private var familyChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(families) { f in
                        let on = f == currentFamily
                        let tint = (f == selected.family ? selected : (f.kinds.first ?? selected)).palette.dark
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { family = f }
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Text(f.label)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(on ? Color.white : ink.opacity(0.8))
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(Capsule().fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(ambience.isDark ? 0.16 : 0.07))))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(f)
                        .accessibilityLabel(f.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("moliboo.picker.family.\(f.rawValue)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 30)
            .onAppear { proxy.scrollTo(currentFamily, anchor: .center) }
        }
    }

    /// Hero preview of the focused character with a gentle idle bob (still under Reduce Motion).
    private func hero(_ focus: ModulaMascotKind) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(RadialGradient(colors: [focus.palette.light.opacity(0.95), focus.palette.mid.opacity(0.0)], center: .center, startRadius: 2, endRadius: 36))
                    .frame(width: 64, height: 64)
                // Idle bob as a repeating render-server animation: no per-frame body work.
                MolibooPickerArt(kind: focus, size: 58, brain: brains[focus] ?? MascotBrain())
                    .offset(y: bob ? -3 : 2)
                    .scaleEffect(x: bob ? 0.99 : 1.015, y: bob ? 1.015 : 0.99, anchor: .bottom)
                    .animation(reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: bob)
                    .id(focus)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(focus.name).font(.title3.weight(.bold)).foregroundStyle(ink)
                    if focus.isPremium { MascotPremiumBadge(locked: !MascotEntitlements.isPremium) }
                }
                Text(focus.personality).font(.caption).foregroundStyle(subInk).lineLimit(2)
            }
            .animation(.smooth(duration: 0.18), value: focus)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(ink)
                    .frame(width: 30, height: 30).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle(), specular: true)
            .accessibilityLabel("Close")
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 64)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.7), value: focus)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("moliboo.picker.hero")
    }

    private func tileView(_ kind: ModulaMascotKind, index: Int) -> some View {
        let isFocus = kind == hovered
        let isSelected = kind == selected
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { onSelect(kind) } label: {
            VStack(spacing: 1) {
                MolibooPickerArt(kind: kind, size: 42, brain: brains[kind] ?? MascotBrain(), animated: isFocus)
                    .frame(width: tile, height: 46)
                    .scaleEffect(isFocus ? 1.16 : 1)
                Text(kind.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.black.opacity(0.78)).lineLimit(1)
            }
            .frame(width: tile, height: 66)
            .background(shape.fill(LinearGradient(colors: [kind.palette.light, kind.palette.mid.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(isSelected ? Color.white : Color.white.opacity(0.5), lineWidth: isSelected ? 2 : 0.8))
            .shadow(color: isSelected ? kind.palette.accent.opacity(0.85) : .clear, radius: isSelected ? 8 : 0)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                } else if kind.isPremium && !MascotEntitlements.isPremium {
                    Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)))
                        .offset(x: -3, y: 3)
                }
            }
            .scaleEffect(appeared ? (isFocus ? 1.06 : 1) : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.015), value: appeared)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocus)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            frames[kind] = frame
            publishFrames()
        }
        .accessibilityLabel("\(kind.name)\(kind.isPremium ? ", Premium" : ""). \(kind.personality)")
        .accessibilityIdentifier("moliboo.picker.tile.\(kind.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Picker art: the approved portrait render when available (cheap static image), else the live 2D Moliboo.
struct MolibooPickerArt: View {
    let kind: ModulaMascotKind
    var size: CGFloat
    var brain: MascotBrain
    /// Live 2D art runs a 60 fps timeline plus CoreMotion tilt; only the focused tile/hero animates.
    var animated = true
    var body: some View {
        if MolibooPortrait.usesPortrait(kind.rawValue), let img = MolibooPortrait.image(for: kind.rawValue) {
            Image(uiImage: img).resizable().interpolation(.medium).scaledToFit().frame(width: size, height: size)
        } else {
            ModulaLiveMascot(kind: kind, size: size * 0.6, brain: brain, showsShadow: true, animated: animated, bubble: false)
        }
    }
}

struct MascotPremiumBadge: View {
    var locked = true
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: locked ? "lock.fill" : "crown.fill").font(.system(size: 8, weight: .bold))
            Text("Premium").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)))
        .accessibilityLabel(locked ? "Premium, locked" : "Premium")
    }
}

// MARK: - Premium sheet (placeholder upgrade)

struct MascotPremiumSheet: View {
    let kind: ModulaMascotKind
    @Environment(\.dismiss) private var dismiss
    @State private var brain = MascotBrain()
    @State private var tapped = false

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 8)
            ModulaLiveMascot(kind: kind, size: 84, brain: brain)
                .frame(height: 170)
                .onAppear { brain.react(.happy) }
                .onTapGesture { brain.hop(); MascotSound.shared.play(.hop) }
            VStack(spacing: 6) {
                MascotPremiumBadge(locked: true)
                Text("\(kind.name) is a Premium Moliboo").font(.title3.weight(.bold))
                Text(kind.personality).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("All 15 Moliboos, with new friends over time", systemImage: "sparkles")
                Label("Exclusive reactions and seasonal looks", systemImage: "wand.and.stars")
                Label("Supports the people building Modula", systemImage: "heart")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.05)))
            Button {
                tapped = true
                HapticEngine.shared.play(.selection)
            } label: {
                Text(tapped ? "Premium is coming soon" : "Upgrade to Premium")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .animation(.snappy, value: tapped)
            Button("Not now") { dismiss() }.font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Chat with the mascot

struct MascotChatMessage: Identifiable, Equatable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

enum MascotVoice {
    /// Reply in the mascot's voice. Uses the on-device Apple model when available; otherwise a small
    /// local personality responder (`onDevice == false`).
    static func reply(kind: ModulaMascotKind, to prompt: String, history: [MascotChatMessage]) async -> (text: String, onDevice: Bool) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let instructions = """
            You are \(kind.name), a tiny mascot who lives on the Modula app's message composer. Personality: \(kind.personality). \
            Reply in one or two short, warm, playful sentences (under 30 words), in character, sometimes ending with "\(kind.tic)". \
            Never claim to take actions in the app.
            """
            let context = history.suffix(6).map { ($0.fromUser ? "User: " : "\(kind.name): ") + $0.text }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: instructions)
            if let response = try? await session.respond(to: context.isEmpty ? prompt : context + "\nUser: " + prompt) {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return (text, true) }
            }
        }
        #endif
        try? await Task.sleep(for: .milliseconds(650))
        return (canned(kind: kind, prompt: prompt), false)
    }

    static func canned(kind: ModulaMascotKind, prompt: String) -> String {
        let p = prompt.lowercased()
        let line: String
        if p.contains("joke") {
            line = ["Why did the comment cross the thread? To get to the other side of the argument.", "I tried to write a joke about drafts, but I keep editing it.", "What do you call a sleepy keyboard? A snooze bar."].randomElement()!
        } else if p.contains("cheer") || p.contains("sad") || p.contains("tired") {
            line = ["You're doing better than you think. One sentence at a time.", "Deep breath. You've got this, and I've got your back.", "Tiny steps still count as steps!"].randomElement()!
        } else if p.contains("write") || p.contains("help") || p.contains("idea") {
            line = ["Start with what you'd say out loud, then trim it by a third.", "Lead with the point, then add one example.", "Try asking a question at the end; people love answering."].randomElement()!
        } else if p.contains("who") || p.contains("name") {
            line = "I'm \(kind.name)! \(kind.personality)."
        } else if p.contains("hi") || p.contains("hello") || p.contains("hey") {
            line = ["Hi hi! I was just watching you type.", "Hello! Nice to see you.", "Hey! Ready when you are."].randomElement()!
        } else {
            line = ["Ooh, tell me more.", "I like the way you think.", "Hmm, that's a good one to ponder.", "I'm all ears. Well, mostly."].randomElement()!
        }
        return "\(line) \(kind.tic)"
    }
}

/// Small Liquid Glass pop-up chat anchored to the mascot. Swipe down or tap outside to close.
struct MascotChatView: View {
    let kind: ModulaMascotKind
    let brain: MascotBrain
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [MascotChatMessage] = []
    @State private var draft = ""
    @State private var replying = false
    @State private var onDevice: Bool?
    @State private var faceBrain = MascotBrain()
    @FocusState private var focused: Bool
    @State private var dragY: CGFloat = 0

    private let prompts = ["Say hi", "Tell me a joke", "Cheer me up", "Help me write"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ModulaLiveMascot(kind: kind, size: 26, busy: replying, brain: faceBrain, showsShadow: false, bubble: false)
                    .frame(width: 44, height: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.name).font(.subheadline.weight(.semibold))
                    Text(onDevice == false ? "Offline replies" : (onDevice == true ? "On-device" : kind.personality))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if messages.isEmpty {
                            bubble(MascotChatMessage(fromUser: false, text: "Hi! I'm \(kind.name). What's up? \(kind.tic)"))
                        }
                        ForEach(messages) { bubble($0).id($0.id) }
                        if replying { typingBubble.id("typing") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .onChange(of: messages) { _, m in withAnimation { proxy.scrollTo(m.last?.id, anchor: .bottom) } }
            }
            ModulaGlassGroup(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(prompts, id: \.self) { p in
                        Button(p) { send(p) }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), interactive: true)
                            .disabled(replying)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("Say something to \(kind.name)…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, 12).frame(height: 38)
                    .modulaGlass(in: Capsule(), interactive: false, specular: true)
                ModulaGlassSendButton(ready: !draft.trimmingCharacters(in: .whitespaces).isEmpty && !replying, busy: replying, size: 38, tint: .accentColor) { send(draft) }
            }
            }
        }
        .padding(14)
        .frame(width: 300)
        .offset(y: max(dragY, 0))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height > 60 { dismiss() } else { withAnimation(.spring) { dragY = 0 } }
                }
        )
        .onAppear { faceBrain.react(.happy) }
    }

    private func bubble(_ m: MascotChatMessage) -> some View {
        Text(m.text)
            .font(.subheadline)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(m.fromUser ? Color.accentColor.opacity(0.85) : kind.palette.mid.opacity(0.35)))
            .foregroundStyle(m.fromUser ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
            .transition(.scale(scale: 0.8, anchor: m.fromUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
    }

    private var typingBubble: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { t in
            let now = t.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                        .offset(y: -3 * max(0, sin(now * 7 - Double(i) * 0.9)))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(kind.palette.mid.opacity(0.3)))
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !replying else { return }
        draft = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { messages.append(MascotChatMessage(fromUser: true, text: trimmed)) }
        replying = true
        brain.keystroke()
        Task {
            let result = await MascotVoice.reply(kind: kind, to: trimmed, history: messages)
            onDevice = result.onDevice
            replying = false
            let speakFor = min(Double(result.text.count) * 0.045, 3.2)
            brain.speakingUntil = MascotBrain.now + speakFor
            faceBrain.speakingUntil = MascotBrain.now + speakFor
            MascotSound.shared.play(.pop)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { messages.append(MascotChatMessage(fromUser: false, text: result.text)) }
        }
    }
}

// MARK: - Settings section

/// Live preview, mascot grid, sounds and per-surface toggles (Settings → Chats → Composer).
struct ComposerMascotSettingsSection: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(ModulaMascotSettings.nodusKey) private var nodus = true
    @AppStorage(ModulaMascotSettings.commentsKey) private var comments = false
    @AppStorage(ModulaMascotSettings.otherKey) private var other = false
    @AppStorage(ModulaMascotSettings.homeCompanionKey) private var homeCompanion = true
    @AppStorage(ModulaMascotSettings.soundsKey) private var sounds = true
    @AppStorage(ModulaMascotSettings.debugPremiumKey) private var debugPremium = false
    @State private var previewText = ""
    @State private var previewBusy = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var tileBrains: [ModulaMascotKind: MascotBrain] = Dictionary(uniqueKeysWithValues: ModulaMascotKind.allCases.map { ($0, MascotBrain()) })

    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Section {
            previewCard
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text("Moliboo")
        } footer: {
            Text("Tap to hop, double-tap to chat, hold to swap. It watches you type, cheers when you send, glows while generating and picks up on your battery, the time of day and your connection.")
        }
        Section("Choose") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ModulaMascotKind.roster) { k in tile(k) }
                offTile
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
        if kind != nil {
            Section("Show Moliboo on") {
                Toggle("Nodus", isOn: $nodus)
                Toggle("Comment inputs", isOn: $comments)
                Toggle("Other composers", isOn: $other)
                Toggle("Home companion", isOn: $homeCompanion)
                    .accessibilityHint("Your Moliboo walks along the bottom of Home, peeks over posts and naps when idle.")
            }
        }
        Section {
            NavigationLink {
                MolibooStudioEntry(tab: .wardrobe)
            } label: {
                Label("Moliboo Studio", systemImage: "tshirt.fill")
            }
            NavigationLink {
                MolibooStudioEntry(tab: .assistant)
            } label: {
                Label("Assistant & keywords", systemImage: "bubble.left.and.text.bubble.right")
            }
        } footer: {
            Text("Dress up, create custom Moliboos, and set keyword draft-replies for comments on your posts.")
        }
        MascotProfileSettingsSection()
        Section {
            Toggle("Moliboo sounds", isOn: $sounds)
            #if DEBUG
            Toggle("Unlock Premium Moliboos (Debug)", isOn: $debugPremium)
            #endif
        } footer: {
            Text("Short, quiet sounds that follow your silent switch.")
        }
        .sheet(item: $premiumKind) { MascotPremiumSheet(kind: $0) }
        .onAppear {
            MascotProgressStore.shared.touchDay()
            _ = MascotWardrobeStore.shared.applyOutfitOfTheDayIfNeeded()
            _ = MascotWardrobeStore.shared.applyBirthdayOutfitIfNeeded(birthday: MascotAssistantStore.shared.context.birthday)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(kind?.name ?? "Moliboo off").font(.headline)
                if let kind, kind.isPremium { MascotPremiumBadge(locked: !MascotEntitlements.isPremium) }
                Spacer()
                Button(previewBusy ? "Stop" : "Try thinking") { withAnimation(.snappy) { previewBusy.toggle() } }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(kind == nil)
            }
            Text(kind?.personality ?? "Pick a Moliboo below to bring the composer to life.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Chat with your Moliboo…", text: $previewText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
                    .modulaMascotPerch()
                ModulaGlassSendButton(title: "Send preview", ready: !previewText.isEmpty) { previewText = "" }
            }
            .padding(.top, 62)
            .overlayPreferenceValue(MascotPerchKey.self) { anchor in
                GeometryReader { proxy in
                    if let kind, let anchor {
                        let bar = proxy[anchor]
                        ModulaComposerMascot(kind: kind, busy: previewBusy, touch: nil, text: previewText, size: 48) { kindRaw = $0.rawValue }
                            .position(x: bar.maxX - 26 - 24 * kind.bodySize.width, y: bar.minY + 6 - kind.footFraction * 48)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [(kind?.palette.light ?? .gray).opacity(0.4), Color.primary.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .animation(.smooth, value: kindRaw)
    }

    private func tile(_ k: ModulaMascotKind) -> some View {
        let selected = kindRaw == k.rawValue
        let locked = !MascotEntitlements.canUse(k)
        return Button {
            tileBrains[k]?.react(.happy)
            if locked {
                premiumKind = k
                HapticEngine.shared.play(.warning)
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { kindRaw = k.rawValue }
            MascotSound.shared.play(.pick)
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 4) {
                ModulaLiveMascot(kind: k, size: 40, brain: tileBrains[k] ?? MascotBrain(), animated: selected, bubble: false)
                    .frame(height: 66)
                Text(k.name).font(.subheadline.weight(.semibold))
                Text(k.personality).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                    .frame(minHeight: 26, alignment: .top)
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if k.isPremium {
                    Image(systemName: locked ? "lock.fill" : "crown.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)))
                        .padding(6)
                }
            }
            .scaleEffect(selected ? 1 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(k.name)\(k.isPremium ? ", Premium" : ""). \(k.personality)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var offTile: some View {
        let selected = kind == nil
        return Button {
            withAnimation(.snappy) { kindRaw = ModulaMascotSettings.off }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "eye.slash").font(.system(size: 26)).foregroundStyle(.secondary).frame(height: 66)
                Text("Off").font(.subheadline.weight(.semibold))
                Text("No Moliboo").font(.caption2).foregroundStyle(.secondary).frame(minHeight: 26, alignment: .top)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Moliboo off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Home companion

/// The user's mascot as a Home companion: strolls along the bottom edge, peeks up over the
/// feed, naps when nothing is happening and can be dragged anywhere (drop it near the bottom
/// to send it walking again). Off switch: Settings → Chats → Composer → "Home companion".
struct HomeMascotCompanion: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(ModulaMascotSettings.homeCompanionKey) private var enabled = true
    /// Parked position as fractions of the Home area; negative = walking the bottom edge.
    @AppStorage("home.companion.parkX") private var parkX = -1.0
    @AppStorage("home.companion.parkY") private var parkY = -1.0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var brain = MascotBrain()
    @State private var x: CGFloat = 0.84
    @State private var facesLeft = false
    @State private var lift: CGFloat = 0
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var napping = false
    private var wardrobe = MascotWardrobeStore.shared
    private let size: CGFloat = 28

    /// Last time the user did something on Home (scroll, tap, reaction).
    @MainActor static var lastActivity = Date()
    @MainActor static func noteActivity() { lastActivity = Date() }

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        let selection = MascotSelection.resolve(raw: kindRaw)
        if enabled, selection != .off {
            GeometryReader { geo in
                let box = CGSize(width: size * 2.6, height: size * 2.4)
                let parked = parkX >= 0 && parkY >= 0
                let base: CGPoint = parked
                    ? CGPoint(x: min(max(parkX * geo.size.width, box.width / 2), geo.size.width - box.width / 2),
                              y: min(max(parkY * geo.size.height, box.height / 2), geo.size.height - box.height / 2))
                    : CGPoint(x: min(max(x * geo.size.width, box.width / 2), geo.size.width - box.width / 2),
                              y: geo.size.height - box.height / 2 + 6 - lift)
                Group {
                    if MolibooPortrait.usesPortrait(kindRaw) {
                        MolibooPortraitCompanion(characterID: kindRaw, size: size, animated: !napping)   // MOL-03: lightweight 3D look
                    } else {
                        MascotDressedLive(selection: selection, size: size, brain: brain, showsShadow: true, outfit: wardrobe.outfit)
                    }
                }
                    .scaleEffect(x: facesLeft ? -1 : 1, y: 1)
                    .frame(width: box.width, height: box.height)
                    .scaleEffect(dragging ? 1.14 : 1)
                    .contentShape(Circle().inset(by: size * 0.3))
                    .position(x: base.x + drag.width, y: base.y + drag.height)
                    .onTapGesture {
                        Self.noteActivity()
                        wake()
                        brain.hop(burst: .sparkle)
                        MascotSound.shared.play(.hop)
                        HapticEngine.shared.play(.lightImpact)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .local)
                            .onChanged { value in
                                if !dragging {
                                    dragging = true
                                    brain.react(.surprised)
                                    HapticEngine.shared.play(.dragThreshold)
                                }
                                drag = value.translation
                            }
                            .onEnded { value in
                                let end = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                                var t = Transaction(); t.disablesAnimations = true
                                withTransaction(t) {
                                    drag = .zero
                                    if end.y > geo.size.height - box.height * 1.1 {
                                        // Dropped on the bottom edge: back to strolling from here.
                                        parkX = -1; parkY = -1
                                        x = max(0, min(1, end.x / max(geo.size.width, 1)))
                                    } else {
                                        parkX = Double(max(0, min(1, end.x / max(geo.size.width, 1))))
                                        parkY = Double(max(0, min(1, end.y / max(geo.size.height, 1))))
                                    }
                                }
                                withAnimation(.spring(duration: 0.35, bounce: 0.4)) { dragging = false }
                                brain.hop(burst: .pop, height: 8)
                                HapticEngine.shared.play(.drop)
                                Self.noteActivity()
                            }
                    )
                    .contextMenu {
                        if parked {
                            Button("Walk along the bottom", systemImage: "figure.walk") {
                                parkX = -1; parkY = -1
                                brain.hop(burst: .sparkle)
                            }
                        }
                        Button("Hide Home companion", systemImage: "eye.slash") {
                            withAnimation(.smooth) { enabled = false }
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Moliboo companion")
                    .accessibilityValue(napping ? "Napping" : "Awake")
                    .accessibilityHint("Double-tap to make it hop. Drag to move it.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Hide Home companion") { enabled = false }
            }
            .transition(.opacity)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await live()
            }
            .onReceive(NotificationCenter.default.publisher(for: ModulaMascotEvent.notification)) { _ in
                Self.noteActivity()
                wake()
            }
        }
    }

    private func wake() {
        guard napping else { return }
        napping = false
        brain.react(.wave)
    }

    /// Ambient behaviour loop: stroll, peek or look around; after ~40s of no activity it
    /// stops and the brain drifts off to sleep by itself (the brain naps after ~28s idle).
    private func live() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 5.5...10)))
            guard !Task.isCancelled else { return }
            if Date().timeIntervalSince(Self.lastActivity) > 40 {
                napping = true
                continue
            }
            if napping { wake() }
            guard !dragging, !calm, parkX < 0 else { continue }
            let roll = Double.random(in: 0...1)
            if roll < 0.55 {
                await walk()
            } else if roll < 0.85 {
                await peek()
            } else {
                brain.react(.curious)
            }
        }
    }

    private func walk() async {
        let target = CGFloat.random(in: 0.08...0.92)
        let distance = abs(target - x)
        guard distance > 0.1 else { return }
        facesLeft = target < x
        let duration = Double(distance) * 6.5
        withAnimation(.linear(duration: duration)) { x = target }
        var walked = 0.0
        while walked < duration, !Task.isCancelled, !dragging {
            brain.hop(burst: nil, height: 3)
            try? await Task.sleep(for: .milliseconds(300))
            walked += 0.3
        }
    }

    private func peek() async {
        withAnimation(.spring(duration: 0.55, bounce: 0.35)) { lift = 44 }
        brain.react(.curious)
        try? await Task.sleep(for: .seconds(1.8))
        if Bool.random() { brain.wave() }
        try? await Task.sleep(for: .seconds(0.8))
        withAnimation(.smooth(duration: 0.5)) { lift = 0 }
    }
}

// MARK: - Celebration moments

/// Milestones worth a moment of delight. Each is shown once per account and remembered on-device.
enum ModulaMilestone: Hashable, Sendable {
    case firstPost
    case firstStory
    case followers(Int)
    case streak(Int)

    static let followerSteps = [10, 100, 1000]
    static let streakSteps = [3, 7, 30]

    var id: String {
        switch self {
        case .firstPost: "first-post"
        case .firstStory: "first-story"
        case .followers(let n): "followers-\(n)"
        case .streak(let n): "streak-\(n)"
        }
    }

    var title: String {
        switch self {
        case .firstPost: "Your first post is live!"
        case .firstStory: "First story, shared!"
        case .followers(let n): "\(n.formatted()) followers"
        case .streak(let n): "\(n)-day streak"
        }
    }

    var subtitle: String {
        switch self {
        case .firstPost: "Welcome to the conversation. Your Moliboo is thrilled."
        case .firstStory: "It disappears in 24 hours — but this moment won’t."
        case .followers(let n): n >= 1000 ? "A whole community. Thank you for building here." : "People want to see what you make next."
        case .streak(let n): "You’ve opened Modula \(n) days in a row."
        }
    }

    var symbol: String {
        switch self {
        case .firstPost: "sparkles"
        case .firstStory: "circle.dashed.inset.filled"
        case .followers: "person.3.fill"
        case .streak: "flame.fill"
        }
    }
}

@MainActor @Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()
    private(set) var current: ModulaMilestone?
    @ObservationIgnored private var queue: [ModulaMilestone] = []
    @ObservationIgnored var accountKey = "anon"

    private var seenKey: String { "celebrations.seen.v1.\(accountKey)" }
    private var baselineKey: String { "celebrations.baseline.v1.\(accountKey)" }

    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }

    func hasSeen(_ milestone: ModulaMilestone) -> Bool { seen.contains(milestone.id) }

    /// Shows the milestone once (queued if another is on screen).
    func reach(_ milestone: ModulaMilestone) {
        guard !hasSeen(milestone) else { return }
        seen.insert(milestone.id)
        if current == nil {
            current = milestone
        } else {
            queue.append(milestone)
        }
    }

    func dismiss() {
        current = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.current = next
        }
    }

    /// First sighting of the account's numbers: milestones already passed are recorded
    /// silently, so long-time users aren't congratulated for old news.
    func baselineIfNeeded(followers: Int, posts: Int) {
        guard !UserDefaults.standard.bool(forKey: baselineKey) else { return }
        UserDefaults.standard.set(true, forKey: baselineKey)
        var marked = seen
        for step in ModulaMilestone.followerSteps where followers >= step {
            marked.insert(ModulaMilestone.followers(step).id)
        }
        if posts > 0 { marked.insert(ModulaMilestone.firstPost.id) }
        seen = marked
    }

    func followersChanged(from old: Int?, to new: Int) {
        guard let old, new > old else { return }
        for step in ModulaMilestone.followerSteps where old < step && new >= step {
            reach(.followers(step))
        }
    }

    func streakChanged(_ streak: Int) {
        if ModulaMilestone.streakSteps.contains(streak) { reach(.streak(streak)) }
    }
}

/// Mount once at the root. Confetti + a dancing mascot + a glass card; tap or wait to dismiss.
struct CelebrationHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var center: CelebrationCenter { CelebrationCenter.shared }

    private func syncBaseline() {
        center.accountKey = app.auth.account?.accountId ?? "anon"
        guard let profile = app.profile.ownProfile else { return }
        center.baselineIfNeeded(followers: profile.followerCount, posts: profile.postCount)
    }

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        ZStack {
            if let milestone = center.current {
                CelebrationMoment(milestone: milestone, calm: calm) { center.dismiss() }
                    .id(milestone.id)
                    .transition(calm ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.72), value: center.current)
        .onAppear { syncBaseline() }
        .onChange(of: app.auth.account?.accountId) { _, _ in syncBaseline() }
        .onChange(of: app.profile.ownProfile?.id) { _, _ in syncBaseline() }
        .onChange(of: app.profile.ownProfile?.followerCount) { old, new in
            guard let new else { return }
            syncBaseline()
            center.followersChanged(from: old, to: new)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, app.auth.isSignedIn else { return }
            MascotProgressStore.shared.touchDay()
            center.streakChanged(MascotProgressStore.shared.streak)
        }
    }
}

private struct CelebrationMoment: View {
    let milestone: ModulaMilestone
    var calm: Bool
    var onDismiss: () -> Void
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(AppEnvironment.self) private var app
    @State private var brain = MascotBrain()
    private var wardrobe = MascotWardrobeStore.shared

    init(milestone: ModulaMilestone, calm: Bool, onDismiss: @escaping () -> Void) {
        self.milestone = milestone
        self.calm = calm
        self.onDismiss = onDismiss
    }

    var body: some View {
        let accent = app.appearance.liveAccent
        let selection = MascotSelection.resolve(raw: kindRaw)
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            if !calm {
                ConfettiBurst(colors: [accent, .pink, .yellow, .mint, .orange, .purple])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 14) {
                if selection != .off {
                    MascotDressedLive(selection: selection, size: 56, brain: brain, outfit: wardrobe.outfit)
                        .frame(height: 120)
                } else {
                    Image(systemName: milestone.symbol)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(accent.gradient)
                        .symbolEffect(.bounce, options: .repeat(2))
                        .frame(height: 90)
                }
                Text(milestone.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(milestone.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onDismiss) {
                    Text("Yay!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(accent.gradient))
                        .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.3))
                }
                .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .selection))
                .accessibilityIdentifier("celebration.dismiss")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: false, specular: true)
            .shadow(color: accent.opacity(0.35), radius: 30, y: 12)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("\(milestone.title). \(milestone.subtitle)")
        .accessibilityAction(.escape, onDismiss)
        .task {
            HapticEngine.shared.play(.success)
            if !calm {
                brain.celebrate()
                MascotSound.shared.play(.pop)
                try? await Task.sleep(for: .seconds(1.4))
                brain.dance()
                brain.hop(burst: .confetti, height: 14)
            }
            try? await Task.sleep(for: .seconds(4.2))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}

/// One-shot confetti burst from the top centre; stops drawing after ~3s.
struct ConfettiBurst: View {
    var colors: [Color]
    @State private var start = Date()
    private let count = 90
    private let lifetime = 3.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: Date().timeIntervalSince(start) > lifetime)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < lifetime else { return }
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let angle = -Double.pi / 2 + sin(seed) * 1.15
                    let speed = 380 + 260 * abs(sin(seed * 1.7))
                    let x = size.width / 2 + CGFloat(cos(angle) * speed * t) + CGFloat(sin(t * 3 + seed) * 18)
                    let y = size.height * 0.28 + CGFloat(sin(angle) * speed * t + 520 * t * t)
                    let life = max(0, 1 - t / lifetime)
                    var piece = Path(roundedRect: CGRect(x: -4, y: -2, width: 8, height: 4), cornerRadius: 1)
                    piece = piece.applying(CGAffineTransform(rotationAngle: CGFloat(seed + t * 8)).concatenating(CGAffineTransform(translationX: x, y: y)))
                    context.opacity = life
                    context.fill(piece, with: .color(colors[i % max(colors.count, 1)]))
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}
