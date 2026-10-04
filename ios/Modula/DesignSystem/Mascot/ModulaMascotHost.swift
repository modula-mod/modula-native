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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    @State private var motionOn = false
    @State private var frame: CGRect = .zero
    private let context = MascotContext.shared

    /// Whole view's size: figure canvas plus room for glow, bubbles and particles.
    static func container(_ s: CGFloat) -> CGSize { CGSize(width: s * 2.6, height: s * 2.4) }

    private var paused: Bool { !animated || reduceMotion || !visible || scenePhase != .active }

    var body: some View {
        let conditions = context.conditions(dark: colorScheme == .dark)
        let fps: Double = conditions.lowPower ? 30 : 60
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
                ModulaMascotFigure(kind: kind, pose: pose, size: size)
                if bubble && (pose.mood == .thinking || pose.mood == .typing) { thoughtBubble(now: now, typing: pose.mood == .typing) }
                if pose.mood == .sleepy && !reduceMotion { sleepZs(now: now) }
                if !reduceMotion && !brain.bursts.isEmpty { particles(now: now) }
            }
            .frame(width: c.width, height: c.height)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onAppear { visible = true; context.start(); brain.jiggle = kind == .tofu ? 0.05 : 0.025; syncMotion() }
        .onDisappear { visible = false; syncMotion() }
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
    func modulaComposerMascot(_ placement: ModulaMascotPlacement, busy: Bool = false, text: String = "", attachmentCount: Int = 0, trailingInset: CGFloat = 26) -> some View {
        modifier(ModulaComposerMascotModifier(placement: placement, busy: busy, text: text, attachmentCount: attachmentCount, trailingInset: trailingInset))
    }
}

struct ModulaComposerMascotModifier: ViewModifier {
    let placement: ModulaMascotPlacement
    var busy: Bool
    var text: String
    var attachmentCount: Int
    var trailingInset: CGFloat
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage private var shown: Bool
    @State private var touch: CGPoint?
    private let size: CGFloat = 48

    init(placement: ModulaMascotPlacement, busy: Bool, text: String, attachmentCount: Int, trailingInset: CGFloat) {
        self.placement = placement
        self.busy = busy
        self.text = text
        self.attachmentCount = attachmentCount
        self.trailingInset = trailingInset
        _shown = AppStorage(wrappedValue: ModulaMascotSettings.defaultShown(placement), ModulaMascotSettings.key(for: placement))
    }

    private var kind: ModulaMascotKind? {
        guard let k = ModulaMascotKind(rawValue: kindRaw) else { return nil }
        return MascotEntitlements.canUse(k) ? k : .pip
    }

    func body(content: Content) -> some View {
        if shown, let kind {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { touch = $0.location }
                        .onEnded { _ in touch = nil }
                )
                .overlayPreferenceValue(MascotPerchKey.self) { anchor in
                    GeometryReader { proxy in
                        let bar = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                        let x = bar.maxX - trailingInset - size * kind.bodySize.width / 2
                        // Feet sink ~6pt into the bar's top edge.
                        let y = bar.minY + 6 - kind.footFraction * size
                        ModulaComposerMascot(kind: kind, busy: busy, touch: touch, text: text, attachmentCount: attachmentCount, placement: placement, size: size) { kindRaw = $0.rawValue }
                            .position(x: x, y: y)
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
    var onSelect: (ModulaMascotKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var brain = MascotBrain()
    @State private var picking = false
    @State private var chatting = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var hovered: ModulaMascotKind?
    @State private var tileFrames: [ModulaMascotKind: CGRect] = [:]
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var lastTap: Date = .distantPast
    @State private var moved = false
    @State private var typingSettle: Task<Void, Never>?
    private let context = MascotContext.shared

    var body: some View {
        ModulaLiveMascot(kind: kind, size: size, busy: busy, touch: picking ? nil : touch, brain: brain)
            .id(kind)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity), removal: .scale(scale: 1.4).combined(with: .opacity)))
            .scaleEffect(picking ? 1.1 : 1, anchor: .bottom)
            .contentShape(Ellipse().scale(x: 0.42, y: 0.46))
            .gesture(pressGesture)
            .overlay(alignment: .bottomTrailing) {
                if picking {
                    ModulaMascotPicker(selected: kind, hovered: hovered, onFrames: { tileFrames = $0 }) { choice in
                        commit(choice)
                    } onClose: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { picking = false }
                    }
                    .alignmentGuide(.bottom) { d in d[.bottom] + size * 0.75 }
                    .alignmentGuide(.trailing) { d in d[.trailing] - size * 0.55 }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .popover(isPresented: $chatting, arrowEdge: .bottom) {
                MascotChatView(kind: kind, brain: brain)
                    .presentationCompactAdaptation(.popover)
            }
            .sheet(item: $premiumKind) { k in
                MascotPremiumSheet(kind: k)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: kind)
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: picking)
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
            .accessibilityLabel("\(kind.name), composer mascot")
            .accessibilityHint("Double-tap to chat. Hold to choose a different mascot.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { chatting = true }
            .accessibilityAction(named: "Choose mascot") { picking = true }
            .accessibilityIdentifier("composer.mascot")
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
    var onFrames: ([ModulaMascotKind: CGRect]) -> Void
    var onSelect: (ModulaMascotKind) -> Void
    var onClose: () -> Void
    @State private var frames: [ModulaMascotKind: CGRect] = [:]
    @State private var brains: [ModulaMascotKind: MascotBrain] = Dictionary(uniqueKeysWithValues: ModulaMascotKind.allCases.map { ($0, MascotBrain()) })
    @State private var appeared = false

    private let tile: CGFloat = 62
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(tile), spacing: 4), count: 5) }

    var body: some View {
        let focus = hovered ?? selected
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(focus.name).font(.headline)
                        if focus.isPremium { MascotPremiumBadge(locked: !MascotEntitlements.isPremium) }
                    }
                    Text(focus.personality).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .animation(.smooth(duration: 0.18), value: focus)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 6)
            .frame(height: 44, alignment: .top)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(ModulaMascotKind.allCases.enumerated()), id: \.element) { index, kind in
                    tileView(kind, index: index)
                }
            }
        }
        .padding(10)
        .frame(width: 5 * tile + 4 * 4 + 20)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false)
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        .onAppear { appeared = true }
        .onChange(of: hovered) { _, kind in if let kind { brains[kind]?.hop(burst: nil, height: 6) } }
    }

    private func tileView(_ kind: ModulaMascotKind, index: Int) -> some View {
        let isFocus = kind == hovered
        let isSelected = kind == selected
        return Button { onSelect(kind) } label: {
            VStack(spacing: 0) {
                ModulaLiveMascot(kind: kind, size: 30, brain: brains[kind] ?? MascotBrain(), showsShadow: true, bubble: false)
                    .frame(width: tile, height: 50)
                    .scaleEffect(isFocus ? 1.18 : 1)
                Text(kind.name).font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected || isFocus ? .primary : .secondary)
            }
            .frame(width: tile, height: 70)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(isFocus ? 0.10 : (isSelected ? 0.06 : 0)))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if kind.isPremium && !MascotEntitlements.isPremium {
                    Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15).background(Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)))
                        .offset(x: -3, y: 3)
                }
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.02), value: appeared)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocus)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            frames[kind] = frame
            onFrames(frames)
        }
        .accessibilityLabel("\(kind.name)\(kind.isPremium ? ", Premium" : ""). \(kind.personality)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                Text("\(kind.name) is a Premium mascot").font(.title3.weight(.bold))
                Text(kind.personality).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("All 15 mascots, with new friends over time", systemImage: "sparkles")
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
            Text("Mascot")
        } footer: {
            Text("Tap to hop, double-tap to chat, hold to swap. It watches you type, cheers when you send, glows while generating and picks up on your battery, the time of day and your connection.")
        }
        Section("Choose") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ModulaMascotKind.allCases) { k in tile(k) }
                offTile
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
        if kind != nil {
            Section("Show mascot on") {
                Toggle("Nodus", isOn: $nodus)
                Toggle("Comment inputs", isOn: $comments)
                Toggle("Other composers", isOn: $other)
            }
        }
        Section {
            Toggle("Mascot sounds", isOn: $sounds)
            #if DEBUG
            Toggle("Unlock Premium mascots (Debug)", isOn: $debugPremium)
            #endif
        } footer: {
            Text("Short, quiet sounds that follow your silent switch.")
        }
        .sheet(item: $premiumKind) { MascotPremiumSheet(kind: $0) }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(kind?.name ?? "Mascot off").font(.headline)
                if let kind, kind.isPremium { MascotPremiumBadge(locked: !MascotEntitlements.isPremium) }
                Spacer()
                Button(previewBusy ? "Stop" : "Try thinking") { withAnimation(.snappy) { previewBusy.toggle() } }
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
                Text("No mascot").font(.caption2).foregroundStyle(.secondary).frame(minHeight: 26, alignment: .top)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mascot off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
