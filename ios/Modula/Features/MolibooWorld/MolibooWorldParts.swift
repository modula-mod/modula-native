import SwiftUI
import UIKit

/// Layered illustrated environment: sky, far + near hills with subtle scroll parallax, a mossy pedestal glow,
/// and one cheap particle layer per period (petals / motes / fireflies / stars). Particles are a single Canvas
/// redrawn by a 20 fps TimelineView that is paused unless `animating` — static when idle, backgrounded,
/// Low Power or Reduced Motion.
struct MolibooWorldBackdrop: View {
    let period: MolibooTimeOfDay
    let scrollY: CGFloat
    let animating: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                LinearGradient(colors: period.sky, startPoint: .top, endPoint: .bottom)
                // Right of the character's head, below the header row: never behind the wordmark, ⋯ or the stats card.
                celestial.offset(x: w * 0.18, y: 122 - scrollY * 0.05)
                Hills(seed: 1, amplitude: 26).fill(period.ground.opacity(0.55))
                    .frame(height: h * 0.55).offset(y: h * 0.34 - scrollY * 0.12)
                Hills(seed: 2, amplitude: 34).fill(period.ground.opacity(0.85))
                    .frame(height: h * 0.55).offset(y: h * 0.42 - scrollY * 0.28)
                LinearGradient(colors: [.clear, Color.black.opacity(period.isDark ? 0.35 : 0.12)], startPoint: .center, endPoint: .bottom)
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { tl in
                    Canvas { ctx, size in
                        MolibooParticles.draw(period: period, t: tl.date.timeIntervalSinceReferenceDate, in: &ctx, size: size, scrollY: scrollY)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .accessibilityIdentifier("world.backdrop.\(period.rawValue)")
    }

    @ViewBuilder private var celestial: some View {
        switch period {
        case .night: Circle().fill(Color(white: 0.96)).frame(width: 36).shadow(color: .white.opacity(0.6), radius: 18)
        case .evening: Circle().fill(Color(red: 1, green: 0.72, blue: 0.45)).frame(width: 70).blur(radius: 2).opacity(0.9)
        default: Circle().fill(Color(red: 1, green: 0.95, blue: 0.75)).frame(width: 64).shadow(color: .yellow.opacity(0.5), radius: 24)
        }
    }
}

struct Hills: Shape {
    let seed: Double
    let amplitude: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: amplitude))
        let steps = 24
        for i in 0...steps {
            let x = r.width * CGFloat(i) / CGFloat(steps)
            let y = amplitude + sin(Double(i) * 0.55 + seed * 1.7) * amplitude * 0.8 + sin(Double(i) * 1.3 + seed) * amplitude * 0.25
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.closeSubpath()
        return p
    }
}

enum MolibooParticles {
    static let count = 22
    static func draw(period: MolibooTimeOfDay, t: Double, in ctx: inout GraphicsContext, size: CGSize, scrollY: CGFloat) {
        for i in 0..<count {
            let fi = Double(i)
            let rx = (fi * 0.618).truncatingRemainder(dividingBy: 1)
            let ry = (fi * 0.377 + 0.13).truncatingRemainder(dividingBy: 1)
            switch period {
            case .night:
                let x = rx * size.width, y = ry * size.height * 0.55 - scrollY * 0.05
                let tw = 0.45 + 0.55 * abs(sin(t * 0.8 + fi))
                let r = 1.0 + (fi.truncatingRemainder(dividingBy: 3)) * 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(tw)))
            case .evening:
                let x = rx * size.width + sin(t * 0.5 + fi) * 14
                let y = size.height * (0.35 + ry * 0.4) + cos(t * 0.4 + fi * 1.3) * 10 - scrollY * 0.2
                let a = 0.35 + 0.65 * max(0, sin(t * 1.2 + fi * 2))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)), with: .color(Color(red: 1, green: 0.92, blue: 0.5).opacity(a)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 12, height: 12)), with: .color(Color(red: 1, green: 0.9, blue: 0.4).opacity(a * 0.2)))
            case .morning:
                let fall = (t * 0.03 + ry).truncatingRemainder(dividingBy: 1)
                let x = rx * size.width + sin(t * 0.7 + fi) * 18
                let y = fall * size.height * 0.8 - scrollY * 0.15
                var c = ctx
                c.translateBy(x: x, y: y); c.rotate(by: .radians(t * 0.6 + fi))
                c.fill(Path(ellipseIn: CGRect(x: -4, y: -2, width: 8, height: 4)), with: .color(Color(red: 1, green: 0.75, blue: 0.82).opacity(0.85)))
            case .afternoon:
                let x = rx * size.width + sin(t * 0.3 + fi) * 10
                let y = size.height * ry * 0.7 + cos(t * 0.25 + fi) * 8 - scrollY * 0.1
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.45)))
            }
        }
    }
}

/// The companion on its mossy pedestal. Uses the renderer's pre-rendered portrait (approved artwork: Pebble wears
/// the approved Signature Cap) with cheap SwiftUI transforms: breathing, irregular blink-squash, gaze tilt toward
/// the composer, tap bounce, thinking glow, sleepy dim + Zzz. Breathing runs only while `animating && stage.awake`.
struct MolibooStageCharacter: View {
    let characterID: String
    let emotion: MolibooEmotion
    let stage: MolibooStageState
    let animating: Bool
    let gaze: Double

    var body: some View {
        let live = animating && stage.awake
        ZStack {
            softContactShadow.offset(y: 96)
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !live)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let breath = live ? sin(t * 2 * .pi / emotion.breathPeriod) : 0
                let bob = live ? sin(t * 2 * .pi / (emotion.breathPeriod * 1.6)) * 4 : 0   // gentle idle float
                figure
                    .scaleEffect(x: 1 - breath * 0.012, y: 1 + breath * 0.022, anchor: .bottom)
                    .rotationEffect(.degrees(gaze * 6 + (emotion == .curious ? 4 : 0)), anchor: .bottom)
                    .offset(y: gaze * 6 - bob)
            }
            .keyframeAnimator(initialValue: 1.0, trigger: stage.blinkToken) { v, s in v.scaleEffect(x: 1, y: s, anchor: .bottom) } keyframes: { _ in
                CubicKeyframe(0.95, duration: 0.07); CubicKeyframe(1.0, duration: 0.09)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: stage.bounceToken) { v, y in v.offset(y: y) } keyframes: { _ in
                SpringKeyframe(-30, duration: 0.18, spring: .snappy); SpringKeyframe(0, duration: 0.45, spring: .bouncy)
            }
            // Squash before take-off, stretch in the air, squash on landing (cartoon squash-and-stretch).
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: stage.bounceToken) { v, k in
                v.scaleEffect(x: k.width, y: k.height, anchor: .bottom)
            } keyframes: { _ in
                CubicKeyframe(CGSize(width: 1.10, height: 0.86), duration: 0.08)
                CubicKeyframe(CGSize(width: 0.92, height: 1.10), duration: 0.14)
                CubicKeyframe(CGSize(width: 1.0, height: 1.0), duration: 0.16)
                CubicKeyframe(CGSize(width: 1.08, height: 0.92), duration: 0.08)
                SpringKeyframe(CGSize(width: 1, height: 1), duration: 0.3, spring: .bouncy)
            }
            .overlay { MolibooTapBurst(token: stage.bounceToken, live: live) }
            .opacity(emotion == .sleepy ? 0.88 : 1)
            .saturation(emotion == .tired ? 0.7 : 1)
            if emotion == .sleepy {
                Text("z z").font(.title2.weight(.heavy)).foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 3)
                    .offset(x: 84, y: -96)
            } else {
                speechBubble.offset(x: 92, y: -92)
            }
            // Emote pop: a little burst of hearts on happy/excited reactions.
            if emotion == .happy || emotion == .excited {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "heart.fill").font(.system(size: CGFloat(10 + i * 3))).foregroundStyle(.pink.opacity(0.9))
                        .offset(x: CGFloat(-70 + i * 18), y: CGFloat(-104 - i * 12))
                }
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(animating ? .spring(response: 0.4, dampingFraction: 0.6) : nil, value: emotion)
        .accessibilityIdentifier("world.stage.\(emotion.rawValue)")
    }

    /// Heart speech bubble beside the head; shows the current emotion's symbol when it isn't a happy one.
    private var speechBubble: some View {
        let happy = emotion == .happy || emotion == .excited || emotion == .calm
        return Image(systemName: happy ? "heart.fill" : emotion.symbol)
            .font(.title3).foregroundStyle(happy ? AnyShapeStyle(.pink) : AnyShapeStyle(.indigo))
            .frame(width: 42, height: 38)
            .background(.white.opacity(0.92), in: BubbleShape())
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .scaleEffect(emotion == .excited ? 1.15 : 1)
    }

    /// Soft contact shadow only — no moss rock / platform glow.
    private var softContactShadow: some View {
        Ellipse()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 120, height: 18)
            // No blur — soft alpha ellipse is enough and much cheaper while the hero TimelineView runs.
            .accessibilityHidden(true)
    }

    @ViewBuilder private var figure: some View {
        let live = animating && stage.awake
        if let img = MolibooPortrait.image(for: characterID) {
            Image(uiImage: img).resizable().interpolation(.high).antialiased(true).scaledToFit().frame(width: 230, height: 230)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        } else if let kind = ModulaMascotKind(rawValue: characterID) {
            ModulaMascotFigure(kind: kind, pose: .still(), size: 110, outfit: MolibooOutfit.equipped(for: kind))
        } else {
            Image(systemName: "pawprint.fill").font(.system(size: 80))
        }
    }
}

// MARK: - Care UI (shared by Home and the Care sheet)

/// One need as a small glass ring: icon in the middle, label and a state word underneath.
struct MolibooNeedRing: View {
    let label: String
    let value: Double
    let symbol: String
    let tint: Color
    var body: some View {
        let v = min(1, max(0, value / 100))
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle().trim(from: 0, to: v)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)
            VStack(spacing: 1) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                Text(Self.word(v)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Int(value)) percent, \(Self.word(v))")
    }
    static func word(_ v: Double) -> String { v >= 0.8 ? "Great" : v >= 0.6 ? "Good" : v >= 0.4 ? "Okay" : "Low" }
}

/// Mood · Energy · Clean · Full rings, the bond level badge with XP progress, and the daily streak / check-in.
struct MolibooStatusPanel: View {
    let state: MolibooCareState
    let life: MolibooLifeState
    let checkIn: () -> Void
    var body: some View {
        let now = Date()
        let streak = life.currentStreak(at: now)
        let done = life.checkedIn(on: now)
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                MolibooNeedRing(label: "Mood", value: state.mood, symbol: "heart.fill", tint: .pink)
                MolibooNeedRing(label: "Energy", value: state.energy, symbol: "bolt.fill", tint: Color(red: 0.95, green: 0.70, blue: 0.10))
                MolibooNeedRing(label: "Clean", value: state.cleanliness, symbol: "drop.fill", tint: Color(red: 0.24, green: 0.62, blue: 0.90))
                MolibooNeedRing(label: "Full", value: 100 - state.hunger, symbol: "fork.knife", tint: Color(red: 0.95, green: 0.55, blue: 0.30))
            }
            HStack(spacing: 12) {
                Text("Lv \(state.bondLevel)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Bond").font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(state.xpToNextLevel) XP to Lv \(state.bondLevel + 1)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.orange.gradient).frame(width: max(6, g.size.width * state.bondProgress))
                        }
                    }
                    .frame(height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bond level \(state.bondLevel), \(state.xpToNextLevel) XP to the next level")
            HStack(spacing: 10) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? .orange : .secondary)
                Text(streak > 0 ? "\(streak)-day streak" : "Start a streak").font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: checkIn) {
                    Text(done ? "Checked in" : "Check in").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 32)
                        .modulaGlass(in: Capsule(), interactive: !done, tint: done ? nil : Color.orange.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(done)
                .accessibilityIdentifier("care.checkin")
                .accessibilityHint(done ? "Already checked in today" : "Daily check-in, adds bond")
            }
        }
        .padding(16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .accessibilityIdentifier("care.status")
    }
}

/// A large glass action tile: icon, title, effect line, or the cooldown while it recharges.
struct MolibooActionTile: View {
    let action: MolibooCareAction
    let remaining: TimeInterval
    let asleep: Bool
    let perform: () -> Void
    var body: some View {
        let cooling = remaining > 0
        let title = action == .nap && asleep ? "Wake" : action.title
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: action == .nap && asleep ? "sun.max.fill" : action.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(action.tint.gradient))
                    .opacity(cooling ? 0.45 : 1)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Group {
                    if cooling {
                        Label(MolibooCareStore.short(remaining), systemImage: "hourglass")
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else if action.effectIcons.isEmpty || (action == .nap && asleep) {
                        Text(action == .nap && asleep ? "Wake up" : "Studio")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        // Tiny stat chips instead of cramped "Full · +Energy" text.
                        HStack(spacing: 6) {
                            ForEach(action.effectIcons, id: \.symbol) { e in
                                HStack(spacing: 1) {
                                    Image(systemName: e.symbol).font(.system(size: 10, weight: .bold))
                                    Image(systemName: e.up ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .heavy))
                                }
                                .foregroundStyle(e.up ? action.tint : Color.secondary)
                            }
                        }
                    }
                }
                .lineLimit(1).frame(height: 14)
            }
            .frame(maxWidth: .infinity).frame(height: 116)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(cooling ? "Ready in \(MolibooCareStore.short(remaining))" : action.effect)
        .accessibilityIdentifier("care.action.\(action.rawValue)")
    }
}

/// The action grid. Re-renders once a second only while something is cooling down.
struct MolibooActionGrid: View {
    let life: MolibooLifeState
    let asleep: Bool
    var columns = 3
    let perform: (MolibooCareAction) -> Void
    var body: some View {
        let cooling = MolibooCareAction.allCases.contains { life.remaining($0, at: Date()) > 0 }
        TimelineView(.periodic(from: .now, by: cooling ? 1 : 3600)) { ctx in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(MolibooCareAction.allCases) { a in
                    MolibooActionTile(action: a, remaining: life.remaining(a, at: ctx.date), asleep: asleep) { perform(a) }
                }
            }
        }
    }
}

/// Recent moments: the last few things you did together.
struct MolibooMomentsList: View {
    let moments: [MolibooMoment]
    var limit = 4
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if moments.isEmpty {
                Text("Your moments together will show up here.").font(.footnote).foregroundStyle(.secondary).padding(16)
            }
            ForEach(Array(moments.prefix(limit).enumerated()), id: \.element.id) { i, m in
                if i > 0 { Divider().padding(.leading, 52) }
                HStack(spacing: 12) {
                    Image(systemName: m.symbol).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.primary.opacity(0.06)))
                    Text(m.text).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(m.date, style: .relative).font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityIdentifier("care.moments")
    }
}

/// Care sheet: the same status, actions and moments as Home (one source of truth: `MolibooCareStore`),
/// with the pet small in the header. Uses the system Liquid Glass sheet background.
struct MolibooCareSheet: View {
    let characterID: String
    let name: String
    let care: MolibooCareStore
    let perform: (MolibooCareAction) -> Void

    var body: some View {
        let s = care.state(for: characterID)
        let life = care.life(for: characterID)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        if let img = MolibooPortrait.image(for: characterID) {
                            Image(uiImage: img).resizable().interpolation(.high).scaledToFit().frame(width: 72, height: 72)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.title2.weight(.bold))
                            Label(s.emotion.label, systemImage: s.emotion.symbol)
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                .accessibilityIdentifier("care.feeling")
                        }
                        Spacer()
                    }
                    MolibooStatusPanel(state: s, life: life) { _ = care.checkIn(characterID, name: name) }
                    Text("Activities").font(.headline)
                    MolibooActionGrid(life: life, asleep: s.asleep, columns: 3, perform: perform)
                    Text("Recent moments").font(.headline)
                    MolibooMomentsList(moments: life.moments, limit: 6)
                }
                .padding(20)
            }
            .navigationTitle("Care").navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Stickers: the companion's live figure in every expression (MolibooStickers.swift). Tapping copies a PNG sticker.
struct MolibooStickerSheet: View {
    let characterID: String
    let name: String
    let notify: (String) -> Void
    private let moods: [MolibooEmotion] = [.happy, .excited, .curious, .calm, .sleepy, .sad]
    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: characterID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let kind {
                        Text("\(MolibooStickerExpression.all.count) stickers · tap to copy, then paste in any chat.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                            ForEach(MolibooStickerExpression.all) { e in
                                Button {
                                    let ok = MolibooStickerExpression.copy(kind: kind, e)
                                    HapticEngine.shared.play(ok ? .success : .failure)
                                    notify(ok ? "\(e.label) sticker copied" : "Couldn't make that sticker")
                                } label: {
                                    MolibooStickerArt(kind: kind, expression: e, size: 100)
                                        .padding(4)
                                        .background(kind.palette.mid.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(MolibooSpringPressStyle())
                                .accessibilityLabel("\(name) \(e.label) sticker")
                                .accessibilityIdentifier("stickers.\(e.id)")
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(moods, id: \.self) { m in
                                Button { copy(m) } label: { sticker(m).frame(width: 96, height: 96) }
                                    .buttonStyle(MolibooSpringPressStyle())
                                    .accessibilityLabel("\(name) \(m.label) sticker")
                                    .accessibilityIdentifier("stickers.\(m.rawValue)")
                            }
                        }
                        Text("Tap a sticker to copy it, then paste it in any chat.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("\(name) stickers").navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private func sticker(_ m: MolibooEmotion) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = MolibooPortrait.image(for: characterID) { Image(uiImage: img).resizable().scaledToFit() }
            else { Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(20) }
            Image(systemName: m.symbol).font(.headline).foregroundStyle(Color(uiColor: .systemBackground))
                .padding(6).background(Color.primary, in: Circle())
        }
    }

    @MainActor private func copy(_ m: MolibooEmotion) {
        let r = ImageRenderer(content: sticker(m).frame(width: 256, height: 256))
        r.scale = 2
        if let img = r.uiImage {
            UIPasteboard.general.image = img
            notify("\(m.label) sticker copied")
        } else {
            notify("Couldn't make that sticker")
        }
    }
}

/// Rounded speech bubble with a small tail at the bottom-left.
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 6), cornerRadius: min(r.width, r.height) * 0.42)
        p.move(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY - 8))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - 8))
        p.closeSubpath()
        return p
    }
}

/// Reaction particles: a ring of sparkles that bursts out of the character on each tap (no-op when not live).
struct MolibooTapBurst: View {
    let token: Int
    let live: Bool
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Image(systemName: i % 2 == 0 ? "sparkle" : "heart.fill")
                    .font(.system(size: i % 2 == 0 ? 14 : 10, weight: .bold))
                    .foregroundStyle(i % 2 == 0 ? Color.yellow : Color.pink)
                    .keyframeAnimator(initialValue: 0.0, trigger: token) { v, p in
                        let a = Double(i) / 8 * 2 * .pi
                        return v.offset(x: cos(a) * 110 * p, y: sin(a) * 90 * p - 30)
                            .opacity(live && p > 0.01 && p < 0.99 ? 1 - p * 0.8 : 0)
                            .scaleEffect(0.6 + p * 0.6)
                    } keyframes: { _ in
                        CubicKeyframe(0.0, duration: 0.01); CubicKeyframe(1.0, duration: 0.6)
                    }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Family naming & picker chrome

extension MolibooFamily {
    /// Consistent family title ("The Originals", "The Angels", "The Underground", …) derived from the case, so
    /// families added later (e.g. Legends) are named the same way without another switch.
    var displayTitle: String { "The " + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Family title in the Moliboos display style. No Moliboos font ships (the wordmark is vector artwork), so this
/// mirrors `MoliboosWordmark`'s treatment: a heavy rounded face, accent fill and a soft top highlight in light
/// mode, pastel-bright in dark. Used only for family titles; app fonts are unchanged elsewhere.
struct MolibooFamilyTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let label = Text(text).font(.system(.title2, design: .rounded, weight: .black)).lineLimit(1).minimumScaleFactor(0.8)
        label
            .foregroundStyle(scheme == .dark ? AnyShapeStyle(Color(red: 1.0, green: 0.72, blue: 0.80)) : AnyShapeStyle(.tint))
            .overlay {
                if !reduceTransparency && scheme != .dark {
                    LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center)
                        .mask(label)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(.isHeader)
    }
}

/// Progressive top blur for the pinned Moliboo header: a real material blur whose strength fades out below the
/// header (masked gradient), plus a light background wash so text under the wordmark never reads through.
/// Extends into the status bar and a little below the header so content fades rather than cutting off.
/// Reduce Transparency: an opaque background fade instead of blur.
struct MolibooProgressiveHeaderBlur: View {
    /// `.top` for the pinned header, `.bottom` for the sticky composer (gradients flip).
    var edge: VerticalEdge = .top
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency {
                Rectangle().fill(Color(uiColor: .systemBackground))
                    .mask(fade([(0, 1), (0.7, 1), (1, 0)]))
            } else {
                Rectangle().fill(.regularMaterial)
                    .mask(fade([(0, 1), (0.55, 1), (0.8, 0.55), (1, 0)]))
                Rectangle().fill(.ultraThinMaterial)
                    .mask(fade([(0, 1), (0.75, 1), (1, 0)]))
                Rectangle().fill(Color(uiColor: .systemBackground).opacity(scheme == .dark ? 0.72 : 0.66))
                    .mask(fade([(0, 1), (0.5, 0.9), (0.85, 0.25), (1, 0)]))
            }
        }
        .padding(edge == .top ? .bottom : .top, -36)
        .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func fade(_ stops: [(CGFloat, Double)]) -> LinearGradient {
        LinearGradient(stops: stops.map { .init(color: .black.opacity($0.1), location: $0.0) },
                       startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
    }
}

// MARK: - Daily goals + week strip

/// Today's care goals as a progress ring with four chips, plus the last seven check-in days.
struct MolibooGoalsCard: View {
    let life: MolibooLifeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let now = Date()
        let goals = life.goals(on: now)
        let done = goals.filter(\.done).count
        let week = life.week(ending: now)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(done) / CGFloat(max(goals.count, 1)))
                        .stroke(Color.green.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(done)/\(goals.count)").font(.caption.weight(.bold)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(done == goals.count ? "All care goals done!" : "Today's care goals").font(.subheadline.weight(.semibold))
                    Text(done == goals.count ? "Come back tomorrow for new ones." : "Feed, play, bath and cuddle once today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(goals) { g in
                    Label(g.action.title, systemImage: g.done ? "checkmark.circle.fill" : g.action.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(g.done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Capsule().fill(Color.primary.opacity(g.done ? 0.04 : 0.06)))
                        .accessibilityLabel("\(g.action.title), \(g.done ? "done" : "not done yet")")
                }
            }
            HStack(spacing: 0) {
                ForEach(week) { d in
                    VStack(spacing: 4) {
                        Text(d.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: d.checked ? "flame.fill" : "circle")
                            .font(.system(size: d.checked ? 15 : 9, weight: .semibold))
                            .foregroundStyle(d.checked ? Color.orange : Color.secondary.opacity(0.5))
                            .frame(height: 18)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.date.formatted(.dateTime.weekday(.wide))), \(d.checked ? "checked in" : "no check-in")")
                }
            }
        }
        .padding(16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: done)
        .accessibilityIdentifier("care.goals")
    }
}

// MARK: - Feelings

struct MolibooFeelingRow: View {
    let select: (MolibooFeeling) -> Void
    @State private var picked: MolibooFeeling?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MolibooCareStore.feelingsKey) private var feelingsRaw = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row
            week
        }
    }

    /// Your last seven days of feelings as a little emoji strip (empty days show a dot).
    @ViewBuilder private var week: some View {
        let map = MolibooFeeling.parse(feelingsRaw)
        if !map.isEmpty {
            let now = Date()
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let day = Calendar.current.date(byAdding: .day, value: i - 6, to: now) ?? now
                    let f = map[MolibooFeeling.dayKey(day)]
                    VStack(spacing: 3) {
                        Text(f?.emoji ?? "·").font(.system(size: f == nil ? 16 : 20)).foregroundStyle(.secondary)
                            .frame(height: 24)
                            .transition(.scale.combined(with: .opacity))
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(f?.label ?? "no entry")")
                }
            }
            .padding(.vertical, 8)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: feelingsRaw)
            .accessibilityIdentifier("care.feelings.week")
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(MolibooFeeling.allCases) { f in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55)) { picked = f }
                    select(f)
                } label: {
                    VStack(spacing: 4) {
                        Text(f.emoji).font(.system(size: 28)).scaleEffect(picked == f ? 1.18 : 1)
                        Text(f.label).font(.caption2.weight(.semibold)).foregroundStyle(picked == f ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("I feel \(f.label.lowercased())")
                .accessibilityAddTraits(picked == f ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("care.feelings")
    }
}

// MARK: - Mini-games (2D)

enum MolibooMiniGame: String, Identifiable, CaseIterable {
    case treats, match
    var id: String { rawValue }
    var title: String { self == .treats ? "Treat Catch" : "Memory Match" }
    var subtitle: String { self == .treats ? "Tap treats before they land" : "Find the six pairs" }
    var symbol: String { self == .treats ? "carrot.fill" : "square.grid.3x3.fill" }
    var tint: Color { self == .treats ? Color(red: 0.96, green: 0.58, blue: 0.42) : Color(red: 0.45, green: 0.45, blue: 0.85) }
    var bestKey: String { "moliboo.game.best.\(rawValue)" }
}

struct MolibooGamesRow: View {
    let open: (MolibooMiniGame) -> Void
    var body: some View {
        HStack(spacing: 12) {
            ForEach(MolibooMiniGame.allCases) { g in
                Button { open(g) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: g.symbol).font(.headline).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Circle().fill(g.tint.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(g.subtitle).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12).frame(maxWidth: .infinity, minHeight: 72)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.96))
                .accessibilityIdentifier("care.game.\(g.rawValue)")
            }
        }
    }
}

/// Shared chrome: title, live score, result card with best score and a black/white Done button.
private struct MolibooGameChrome<Content: View>: View {
    let game: MolibooMiniGame
    let status: String
    let finished: Bool
    let resultLine: String
    let finish: () -> Void
    let restart: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(game.title).font(.title3.weight(.bold))
                Spacer()
                Text(status).font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            }
            ZStack {
                content.opacity(finished ? 0.25 : 1).allowsHitTesting(!finished)
                if finished {
                    VStack(spacing: 12) {
                        Text(resultLine).font(.headline).multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button("Play again", action: restart)
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(height: 44)
                                .modulaGlass(in: Capsule(), interactive: true)
                            Button { finish(); dismiss() } label: {
                                Text("Done").font(.subheadline.weight(.semibold)).foregroundStyle(Color(uiColor: .systemBackground))
                                    .padding(.horizontal, 22).frame(height: 44).background(Capsule().fill(Color.primary))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: finished)
    }
}

private struct FallingTreat: Identifiable {
    let id = UUID()
    let x: CGFloat
    let born: Date
    let duration: Double
    let symbol: String
}

/// Tap falling treats for 20 seconds. Under Reduce Motion treats pop in place and fade instead of falling.
struct MolibooTreatCatchGame: View {
    let finish: (Int) -> Void
    @AppStorage(MolibooMiniGame.treats.bestKey) private var best = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var treats: [FallingTreat] = []
    @State private var score = 0
    @State private var started = Date()
    @State private var running = true
    @State private var round = 0
    private static let length: Double = 20
    private static let symbols = ["carrot.fill", "birthday.cake.fill", "leaf.fill", "star.fill", "heart.fill"]

    var body: some View {
        MolibooGameChrome(game: .treats, status: "\(score) caught", finished: !running,
                          resultLine: score > 0 && score >= best ? "New best! \(score) treats" : "\(score) treats · best \(best)",
                          finish: { finish(score) }, restart: restart) {
            GeometryReader { g in
                TimelineView(.animation(paused: !running)) { ctx in
                    let left = max(0, Self.length - ctx.date.timeIntervalSince(started))
                    ZStack(alignment: .topLeading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.primary).frame(width: g.size.width * left / Self.length, height: 4)
                            }
                        ForEach(treats) { t in
                            let p: Double = min(1, ctx.date.timeIntervalSince(t.born) / t.duration)
                            let y: CGFloat = reduceMotion ? restingY(t, height: g.size.height) : 30 + CGFloat(p) * (g.size.height - 30)
                            Button { catchTreat(t) } label: {
                                Image(systemName: t.symbol).font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.42).gradient)
                                    .frame(width: 56, height: 56).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(reduceMotion ? 1 - p : 1)
                            .position(x: t.x * (g.size.width - 56) + 28, y: y)
                            .accessibilityLabel("Treat")
                        }
                    }
                }
            }
            .clipped()
        }
        .task(id: round) { await spawnLoop() }
        .sensoryFeedback(.impact(weight: .light), trigger: score)
    }

    /// Reduce Motion: a fixed spot derived from the treat's x, so it pops in place.
    private func restingY(_ t: FallingTreat, height: CGFloat) -> CGFloat {
        let band = (t.x * 7).truncatingRemainder(dividingBy: 1)
        return 50 + band * max(0, height - 100)
    }

    private func catchTreat(_ t: FallingTreat) {
        guard running, let i = treats.firstIndex(where: { $0.id == t.id }) else { return }
        treats.remove(at: i)
        withAnimation(.snappy) { score += 1 }
    }

    private func spawnLoop() async {
        while running && !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= Self.length {
                running = false; treats.removeAll()
                if score > best { best = score }
                return
            }
            let now = Date()
            treats.removeAll { now.timeIntervalSince($0.born) > $0.duration }
            // Gets a little faster as the round goes on.
            let duration = max(1.4, 2.8 - elapsed * 0.06) * (reduceMotion ? 0.8 : 1)
            treats.append(FallingTreat(x: .random(in: 0...1), born: now, duration: duration, symbol: Self.symbols.randomElement() ?? "star.fill"))
            try? await Task.sleep(for: .milliseconds(Int(max(380, 700 - elapsed * 15))))
        }
    }

    private func restart() {
        treats = []; score = 0; started = Date(); running = true; round += 1
    }
}

/// Six pairs on a 4×3 grid; cards flip with a flat horizontal squash (2D, no perspective).
struct MolibooMemoryGame: View {
    let finish: (Int) -> Void
    @AppStorage(MolibooMiniGame.match.bestKey) private var bestMoves = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cards: [String] = Self.deal()
    @State private var faceUp: Set<Int> = []
    @State private var matched: Set<Int> = []
    @State private var moves = 0
    @State private var busy = false
    private static let symbols = ["carrot.fill", "heart.fill", "star.fill", "moon.fill", "leaf.fill", "music.note"]
    private static func deal() -> [String] { (symbols + symbols).shuffled() }
    private var done: Bool { matched.count == cards.count }
    /// Score for the care reward: 10 for a perfect 6-move game, minus one per extra move (min 1).
    private var score: Int { max(1, 10 - max(0, moves - 6)) }

    var body: some View {
        MolibooGameChrome(game: .match, status: "\(moves) moves", finished: done,
                          resultLine: bestMoves == moves ? "New best! \(moves) moves" : "\(moves) moves · best \(bestMoves)",
                          finish: { finish(score) }, restart: restart) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(cards.indices, id: \.self) { i in
                    let up = faceUp.contains(i) || matched.contains(i)
                    Button { flip(i) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(up ? AnyShapeStyle(Color.primary.opacity(0.06)) : AnyShapeStyle(Color(red: 0.45, green: 0.45, blue: 0.85).gradient))
                            Image(systemName: up ? cards[i] : "questionmark")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(up ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.white.opacity(0.85)))
                        }
                        .aspectRatio(0.8, contentMode: .fit)
                        .scaleEffect(x: up ? 1 : 0.98, y: 1)
                        .opacity(matched.contains(i) ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(up || busy)
                    .accessibilityLabel(up ? cards[i].replacingOccurrences(of: ".fill", with: "") : "Hidden card \(i + 1)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: faceUp)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: matched)
        }
        .sensoryFeedback(.success, trigger: matched.count) { old, new in new > old }
    }

    private func flip(_ i: Int) {
        guard !busy, !faceUp.contains(i), !matched.contains(i) else { return }
        faceUp.insert(i)
        guard faceUp.count == 2 else { return }
        moves += 1
        let pair = Array(faceUp)
        if cards[pair[0]] == cards[pair[1]] {
            matched.formUnion(pair); faceUp.removeAll()
            if done, bestMoves == 0 || moves < bestMoves { bestMoves = moves }
        } else {
            busy = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(750))
                faceUp.removeAll(); busy = false
            }
        }
    }

    private func restart() {
        cards = Self.deal(); faceUp = []; matched = []; moves = 0; busy = false
    }
}
