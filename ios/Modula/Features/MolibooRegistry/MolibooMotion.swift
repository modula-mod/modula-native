import SwiftUI

// MARK: - MOL-03C shared 2D animation runtime
//
// One engine for every Moliboo. Family motion profiles (registry `motionProfiles`) configure the shared primitives;
// per-character reactions (registry `reactions`) pick a mood + primitive + burst. Evaluation is a pure function of
// (profile, time, reaction, seed), so tests are deterministic and nothing accumulates between frames. Only composited
// transforms are produced (offset / rotation / scale / opacity / glow) — no frame-by-frame full-canvas animation.

struct MolibooMotionFrame: Equatable, Sendable {
    var offset: CGSize = .zero          // fractions of figure size
    var rotation: Double = 0            // degrees
    var scale: CGFloat = 1
    var squash: CGFloat = 1             // >1 wider/shorter, <1 taller/narrower
    var opacity: Double = 1
    var glow: Double = 0                // 0…1
    var blink: CGFloat = 0              // 0 open … 1 closed
    var layerOffset: [String: CGFloat] = [:]
    var mood: MascotMood = .idle
    var burst: String?

    static let rest = MolibooMotionFrame()
}

/// A reaction in flight. Starting a new one replaces (interrupts) the current one.
struct MolibooReactionPlayback: Equatable, Sendable {
    var name: String
    var reaction: MolibooRegistryReaction
    var start: Double
    var progress: (Double) -> Double { { t in max(0, min(1, (t - start) / max(0.05, Double(reaction.durationMs) / 1000))) } }
    func isFinished(at t: Double) -> Bool { t - start >= Double(reaction.durationMs) / 1000 }
    static func == (a: Self, b: Self) -> Bool { a.name == b.name && a.start == b.start }
}

enum MolibooMotionEngine {
    /// Evaluates the idle profile plus an optional reaction at time `t` (seconds). `seed` de-phases characters.
    static func frame(profile: MolibooMotionProfile, t: Double, seed: Double = 0, reaction: MolibooReactionPlayback? = nil, reduceMotion: Bool) -> MolibooMotionFrame {
        var f = MolibooMotionFrame()
        let steps = reduceMotion ? profile.reducedMotion.idle : profile.idle
        let tt = t * profile.tempo + seed
        for s in steps where s.period > 0 {
            let w = sin(2 * .pi * tt / s.period)
            apply(s.primitive, axis: s.axis, layer: s.layer, value: s.amplitude * w, positive: s.amplitude * (w * 0.5 + 0.5), into: &f, reduceMotion: reduceMotion)
        }
        if (!reduceMotion || profile.reducedMotion.allowBlink) {
            // Deterministic blink every ~3.7 s (de-phased by seed), 140 ms long.
            let phase = (t + seed * 1.7).truncatingRemainder(dividingBy: 3.7)
            if phase < 0.14 { f.blink = CGFloat(sin(.pi * phase / 0.14)) }
        }
        if let r = reaction, !r.isFinished(at: t) {
            let p = r.progress(t)
            let env = sin(.pi * p)                     // ease in/out, returns to rest at the end
            f.mood = MolibooReactionMoods.mood(named: r.reaction.mood) ?? .happy
            f.burst = p < 0.25 ? r.reaction.burst : nil
            if !reduceMotion {
                apply(r.reaction.primitive, axis: "y", layer: "signature", value: 0.08 * env, positive: env, into: &f, reduceMotion: false)
            } else {
                f.glow = max(f.glow, 0.4 * env)        // Reduce Motion: a soft glow instead of movement
            }
        }
        return f
    }

    private static func apply(_ p: MolibooAnimationPrimitive, axis: String?, layer: String?, value v: Double, positive: Double, into f: inout MolibooMotionFrame, reduceMotion: Bool) {
        switch p {
        case .translate:
            if reduceMotion { return }
            if axis == "x" { f.offset.width += v } else { f.offset.height -= abs(v) }
        case .rotate: if !reduceMotion { f.rotation += v }
        case .scale: if !reduceMotion { f.scale *= 1 + v }
        case .squashStretch: if !reduceMotion { f.squash *= 1 + v }
        case .opacity: f.opacity = max(0.6, min(1, f.opacity - abs(v)))
        case .blink: f.blink = max(f.blink, CGFloat(max(0, v) > 0.98 ? 1 : 0))
        case .layerOffset: if !reduceMotion { f.layerOffset[layer ?? "parts", default: 0] += v }
        case .glowIntensity: f.glow = max(0, min(1, f.glow + positive))
        case .particleBurst: f.burst = f.burst ?? "sparkle"
        case .accessoryFollow: if !reduceMotion { f.offset.height -= abs(v) * 0.5 }   // the cap rides the same transform
        case .expressionTransition: break
        }
    }
}

/// Registry mood names → the shared `MascotMood` vocabulary.
enum MolibooReactionMoods {
    static let all: [String: MascotMood] = [
        "idle": .idle, "typing": .typing, "happy": .happy, "pleased": .pleased, "surprised": .surprised, "sleepy": .sleepy,
        "thinking": .thinking, "dizzy": .dizzy, "sad": .sad, "laughing": .laughing, "speaking": .speaking, "wave": .wave,
        "dance": .dance, "celebrate": .celebrate, "shy": .shy, "excited": .excited, "curious": .curious, "sit": .sit,
    ]
    static func mood(named n: String) -> MascotMood? { all[n] }
}

// MARK: - Active renderer budget (only one expensive preview at a time)

@MainActor
@Observable
final class MolibooActiveRendererBudget {
    static let shared = MolibooActiveRendererBudget()
    static let limit = 1
    private(set) var active: [UUID] = []
    private(set) var peak = 0

    /// Returns true if this renderer may animate. Newest wins; older ones fall back to a still pose.
    func claim(_ id: UUID) -> Bool {
        active.removeAll { $0 == id }
        active.append(id)
        if active.count > Self.limit { active.removeFirst(active.count - Self.limit) }
        peak = max(peak, active.count)
        return true
    }
    func release(_ id: UUID) { active.removeAll { $0 == id } }
    func isActive(_ id: UUID) -> Bool { active.contains(id) }
}

// MARK: - Animated figure (the one active preview)

/// The registry-driven animated Moliboo. Pauses when off screen or backgrounded, honours Reduce Motion, and maps
/// tap / double tap / long press / horizontal drag to the character's registry reactions. Gestures use
/// `simultaneousGesture` with a horizontal threshold so system scrolling and navigation keep working.
struct MolibooAnimatedFigure: View {
    let kind: ModulaMascotKind
    var size: CGFloat = 140
    var outfit: MascotOutfit = .empty
    var greetOnAppear = true
    var onReaction: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var id = UUID()
    @State private var visible = false
    @State private var playback: MolibooReactionPlayback?
    @State private var budget = MolibooActiveRendererBudget.shared

    private var entry: MolibooRegistryCharacter? { kind.registryEntry }
    private var profile: MolibooMotionProfile? { entry.flatMap { MolibooRegistryStore.bundled?.motionProfiles[$0.motionProfile] } }
    private var animating: Bool { visible && scenePhase == .active && budget.isActive(id) && profile != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let f = profile.map { MolibooMotionEngine.frame(profile: $0, t: t, seed: Double(kind.number) * 0.37, reaction: playback, reduceMotion: reduceMotion) } ?? .rest
            ModulaMascotFigure(kind: kind, pose: MascotPose(t: animating ? t : 0, blink: f.blink, mood: f.mood, amp: animating && !reduceMotion ? 1 : 0), size: size, outfit: outfit)
                .scaleEffect(x: f.scale * f.squash, y: f.scale / max(0.5, f.squash), anchor: .bottom)
                .rotationEffect(.degrees(f.rotation), anchor: .bottom)
                .offset(x: f.offset.width * size, y: f.offset.height * size)
                .opacity(f.opacity)
                .shadow(color: kind.palette.accent.opacity(0.55 * f.glow), radius: size * 0.12 * f.glow)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { react("doubleTap") }
        .onTapGesture { react("tap") }
        .onLongPressGesture(minimumDuration: 0.45) { react("longPress") }
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
            if abs(v.translation.width) > abs(v.translation.height) * 2 { react("horizontalDrag") }
        })
        .onAppear {
            visible = true
            _ = budget.claim(id)
            if greetOnAppear { react("greeting") }
        }
        .onDisappear { visible = false; budget.release(id); playback = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active, visible { react("foreground") } }
        .onChange(of: outfit) { _, _ in react("equip") }
        .accessibilityElement()
        .accessibilityLabel("\(kind.name), Moliboo \(kind.catalogueNumber)")
        .accessibilityHint(entry?.signature?.line ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Signature move") { react("signature") }
        .accessibilityIdentifier("moliboo.animated.\(kind.rawValue)")
    }

    private func react(_ name: String) {
        guard let r = entry?.reactions[name] else { return }
        playback = MolibooReactionPlayback(name: name, reaction: r, start: Date.timeIntervalSinceReferenceDate)
        onReaction?(name)
    }
}
