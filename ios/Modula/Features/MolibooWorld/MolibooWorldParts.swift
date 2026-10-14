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
                celestial.offset(x: w * 0.28, y: 70 - scrollY * 0.05)
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
        case .night: Circle().fill(Color(white: 0.96)).frame(width: 46).shadow(color: .white.opacity(0.6), radius: 18)
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
            Ellipse().fill(Color(red: 0.36, green: 0.55, blue: 0.30).gradient)
                .frame(width: 170, height: 46).offset(y: 92)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            if emotion == .thinking {
                Circle().fill(RadialGradient(colors: [.cyan.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: 120))
                    .frame(width: 240, height: 240)
                    .phaseAnimator([0.7, 1.0], trigger: live) { v, p in v.opacity(live ? p : 0.85) }
                    .accessibilityIdentifier("world.stage.glow")
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let breath = live ? sin(t * 2 * .pi / emotion.breathPeriod) : 0
                figure
                    .scaleEffect(x: 1 - breath * 0.012, y: 1 + breath * 0.022, anchor: .bottom)
                    .rotationEffect(.degrees(gaze * 6 + (emotion == .curious ? 4 : 0)), anchor: .bottom)
                    .offset(y: gaze * 6)
            }
            .keyframeAnimator(initialValue: 1.0, trigger: stage.blinkToken) { v, s in v.scaleEffect(x: 1, y: s, anchor: .bottom) } keyframes: { _ in
                CubicKeyframe(0.95, duration: 0.07); CubicKeyframe(1.0, duration: 0.09)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: stage.bounceToken) { v, y in v.offset(y: y) } keyframes: { _ in
                SpringKeyframe(-26, duration: 0.18, spring: .snappy); SpringKeyframe(0, duration: 0.4, spring: .bouncy)
            }
            .opacity(emotion == .sleepy ? 0.85 : 1)
            .saturation(emotion == .tired ? 0.7 : 1)
            if emotion == .sleepy {
                Text("z z").font(.title3.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                    .offset(x: 70, y: -80)
            }
            if emotion == .happy || emotion == .excited {
                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.title3)
                    .padding(6).background(.white.opacity(0.85), in: Circle())
                    .offset(x: 78, y: -78)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: emotion)
        .accessibilityIdentifier("world.stage.\(emotion.rawValue)")
    }

    @ViewBuilder private var figure: some View {
        if let img = MolibooPortrait.image(for: characterID) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 200, height: 200)
        } else if let kind = ModulaMascotKind(rawValue: characterID) {
            ModulaMascotFigure(kind: kind, pose: .still(), size: 110, outfit: MascotWardrobeStore.shared.outfit)
        } else {
            Image(systemName: "pawprint.fill").font(.system(size: 80))
        }
    }
}

/// Care sheet: stats with bars and the four activities (same actions as the home cards).
struct MolibooCareSheet: View {
    let characterID: String
    let name: String
    let care: MolibooCareStore
    let perform: (MolibooActivity) -> Void

    var body: some View {
        let s = care.state(for: characterID)
        NavigationStack {
            List {
                Section("How \(name) is doing") {
                    bar("Mood", s.mood, .pink, id: "mood")
                    bar("Energy", s.energy, .yellow, id: "energy")
                    bar("Clean", s.cleanliness, .cyan, id: "clean")
                    bar("Full", 100 - s.hunger, .orange, id: "full")
                    LabeledContent("Bond", value: "Level \(s.bondLevel) · \(Int(s.bondXP)) XP")
                    LabeledContent("Feeling", value: s.emotion.label).accessibilityIdentifier("care.feeling")
                }
                Section("Activities") {
                    ForEach(MolibooActivity.allCases) { a in
                        Button { perform(a) } label: {
                            Label { VStack(alignment: .leading) { Text(a == .sleep && s.asleep ? "Wake up" : a.title); Text(a.subtitle).font(.caption).foregroundStyle(.secondary) } }
                                icon: { Image(systemName: a.symbol).foregroundStyle(a.tint) }
                        }
                        .accessibilityIdentifier("care.activity.\(a.rawValue)")
                    }
                }
            }
            .navigationTitle("Care").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bar(_ label: String, _ v: Double, _ tint: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text("\(Int(v))%").monospacedDigit().foregroundStyle(.secondary) }
            ProgressView(value: v, total: 100).tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("care.bar.\(id)")
    }
}

/// Stickers: the companion's portrait in each mood. Tapping copies a real PNG sticker to the clipboard.
struct MolibooStickerSheet: View {
    let characterID: String
    let name: String
    let notify: (String) -> Void
    private let moods: [MolibooEmotion] = [.happy, .excited, .curious, .calm, .sleepy, .sad]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(moods, id: \.self) { m in
                        Button { copy(m) } label: { sticker(m).frame(width: 96, height: 96) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(name) \(m.label) sticker")
                            .accessibilityIdentifier("stickers.\(m.rawValue)")
                    }
                }
                .padding()
                Text("Tap a sticker to copy it, then paste it in any chat.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("\(name) stickers").navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private func sticker(_ m: MolibooEmotion) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = MolibooPortrait.image(for: characterID) { Image(uiImage: img).resizable().scaledToFit() }
            else { Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(20) }
            Image(systemName: m.symbol).font(.headline).foregroundStyle(.white)
                .padding(6).background(Color.pink.gradient, in: Circle())
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
