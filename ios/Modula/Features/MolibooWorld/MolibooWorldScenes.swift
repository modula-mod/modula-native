import SwiftUI
import UIKit

/// MOL-03 "alive" pass: an illustrated cozy room behind the stage (arched window onto the time-of-day sky,
/// shelves with tiny figurines of the *registered* Moliboos, potted + hanging plants, warm lamp light, a mossy floor).
/// Static layers are plain shapes; everything that moves (plant sway, dust, petals / fireflies / sparkles) is drawn
/// by ONE Canvas inside a 20 fps TimelineView that is paused unless `animating` (foreground, not Low Power,
/// not Reduced Motion, stage awake) — so an idle room costs no frames.
struct MolibooRoomBackdrop: View {
    let period: MolibooTimeOfDay
    let scrollY: CGFloat
    let animating: Bool
    let figurines: [String]

    static let roomHeight: CGFloat = 470

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, top = geo.safeAreaInsets.top
            let lift = min(max(scrollY, -80), 600)
            ZStack(alignment: .top) {
                // The whole page is the scene: the shared ambient sky (stars / fireflies / petals) runs top to bottom,
                // the room sits over its upper part, and the lower part fades into sky + mist, never a flat fill.
                MolibooAmbientBackground(ambience: MolibooAmbience(rawValue: period.rawValue) ?? .night, animated: animating, fps: 12,
                                         density: 0.6, moon: UnitPoint(x: 0.9, y: 0.05), moonScale: 0)
                if period == .night {   // aurora / nebula band over the night sky (Metal, fps-capped, still frame under Reduce Motion)
                    Color.clear.frame(height: 520).molibooNebula(0.85, animated: animating).allowsHitTesting(false)
                } else if period == .morning || period == .afternoon {
                    Color.clear.frame(height: 480)
                        .molibooSunbeams(Color(red: 1.0, green: 0.96, blue: 0.80), intensity: 0.82, animated: animating)
                        .allowsHitTesting(false)
                }
                LinearGradient(colors: wall + [wall.last!.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: top + Self.roomHeight).offset(y: -lift * 0.7)
                // Far: window (slowest parallax).
                window(w: w).offset(y: top + 40 - lift * 0.35)
                // Warm lamp light pooling on the right.
                RadialGradient(colors: [lamp.opacity(period.isDark ? 0.55 : 0.30), .clear], center: .center, startRadius: 4, endRadius: 190)
                    .frame(width: 380, height: 380).offset(x: w * 0.42, y: top + 30 - lift * 0.45)
                // Mid: shelves with figurines.
                shelf(w: w).opacity(0.55).blur(radius: 1.2).offset(y: top + 112 - lift * 0.5)   // quieter: chrome no longer floats over clutter
                // Floor: mossy rug under the pedestal fading into the deep backdrop for the cards below.
                Ellipse().fill(RadialGradient(colors: [Color(red: 0.30, green: 0.45, blue: 0.26).opacity(0.75), .clear], center: .center, startRadius: 10, endRadius: w * 0.6))
                    .frame(width: w * 1.3, height: 160).offset(y: top + Self.roomHeight - 150 - lift * 0.7)
                LinearGradient(colors: [.clear, deep.opacity(0.55), deep.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 360).offset(y: top + Self.roomHeight - 90 - lift * 0.7)
                // Low mist banks drifting past as you scroll.
                ForEach(0..<3, id: \.self) { i in
                    Ellipse().fill(Color.white.opacity(period.isDark ? 0.07 : 0.16)).frame(width: w * 1.4, height: 120).blur(radius: 30)
                        .offset(x: CGFloat(i - 1) * w * 0.3, y: top + Self.roomHeight + CGFloat(i) * 260 - lift * (0.8 + Double(i) * 0.05))
                }
                // Near: plants + particles (the only animated layer).
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let sway = animating ? 1.0 : 0
                        MolibooRoomPainter.plants(in: &ctx, w: size.width, top: top - lift * 0.75, t: t, sway: sway)
                        MolibooParticles.draw(period: period, t: t, in: &ctx, size: size, scrollY: scrollY)
                        MolibooRoomPainter.dust(in: &ctx, size: size, top: top, t: t, warm: lamp)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: w, height: geo.size.height, alignment: .top)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .accessibilityIdentifier("world.backdrop.\(period.rawValue)")
    }

    // MARK: Palette

    private var wall: [Color] {
        switch period {
        case .morning: [Color(red: 0.98, green: 0.86, blue: 0.80), Color(red: 0.80, green: 0.80, blue: 0.92)]
        case .afternoon: [Color(red: 0.86, green: 0.90, blue: 0.97), Color(red: 0.62, green: 0.70, blue: 0.90)]
        case .evening: [Color(red: 0.90, green: 0.62, blue: 0.56), Color(red: 0.42, green: 0.36, blue: 0.62)]
        case .night: [Color(red: 0.16, green: 0.17, blue: 0.36), Color(red: 0.22, green: 0.22, blue: 0.46)]
        }
    }
    private var deep: Color {
        switch period {
        case .morning, .afternoon: Color(red: 0.30, green: 0.38, blue: 0.62)
        case .evening: Color(red: 0.24, green: 0.22, blue: 0.44)
        case .night: Color(red: 0.10, green: 0.11, blue: 0.26)
        }
    }
    private var lamp: Color { Color(red: 1.0, green: 0.80, blue: 0.50) }
    private let wood = Color(red: 0.55, green: 0.38, blue: 0.27)

    // MARK: Window

    private func window(w: CGFloat) -> some View {
        let ww = min(w * 0.66, 300), wh: CGFloat = 330
        return ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                LinearGradient(colors: period.sky, startPoint: .top, endPoint: .bottom)
                celestial.offset(x: ww * 0.30, y: 34)
                Hills(seed: 1, amplitude: 18).fill(period.ground.opacity(0.55)).frame(height: wh * 0.45).offset(y: wh * 0.55)
                Hills(seed: 3, amplitude: 22).fill(period.ground.opacity(0.9)).frame(height: wh * 0.4).offset(y: wh * 0.68)
                // Light rays during the day.
                if !period.isDark {
                    LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing).blendMode(.screen)
                }
            }
            .frame(width: ww, height: wh)
            .clipShape(ArchShape())
            ArchShape().stroke(wood.opacity(0.9), lineWidth: 9).frame(width: ww, height: wh)
            Rectangle().fill(wood.opacity(0.85)).frame(width: 6, height: wh - ww * 0.5).offset(y: ww * 0.5)
            Rectangle().fill(wood.opacity(0.85)).frame(width: ww, height: 6).offset(y: wh * 0.55)
            RoundedRectangle(cornerRadius: 4).fill(wood).frame(width: ww + 34, height: 12).offset(y: wh - 4)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
        }
        .frame(width: ww + 34, height: wh + 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var celestial: some View {
        switch period {
        case .night: Circle().fill(Color(white: 0.96)).frame(width: 34).shadow(color: .white.opacity(0.7), radius: 14)
        case .evening: Circle().fill(Color(red: 1, green: 0.72, blue: 0.45)).frame(width: 50).blur(radius: 1.5)
        default: Circle().fill(Color(red: 1, green: 0.96, blue: 0.78)).frame(width: 46).shadow(color: .yellow.opacity(0.5), radius: 20)
        }
    }

    // MARK: Shelves with figurines (registered characters only)

    private func shelf(w: CGFloat) -> some View {
        let right = Array(figurines.prefix(2)), left = Array(figurines.dropFirst(2).prefix(1))
        return ZStack(alignment: .topLeading) {
            shelfBoard(right, plant: true).frame(width: 128).offset(x: w - 128)
            shelfBoard(left, plant: false).frame(width: 84).offset(x: 0, y: 0)
        }
        .frame(width: w, alignment: .topLeading)
    }

    private func shelfBoard(_ ids: [String], plant: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    if let img = MolibooPortrait.image(for: id) {
                        Image(uiImage: img).resizable().scaledToFit().frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                    }
                }
                if plant {
                    ZStack(alignment: .bottom) {
                        Image(systemName: "leaf.fill").font(.system(size: 16)).foregroundStyle(Color(red: 0.36, green: 0.62, blue: 0.36))
                            .offset(x: -4, y: -12).rotationEffect(.degrees(-20))
                        Image(systemName: "leaf.fill").font(.system(size: 14)).foregroundStyle(Color(red: 0.42, green: 0.70, blue: 0.40))
                            .offset(x: 5, y: -14).rotationEffect(.degrees(25))
                        UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5).fill(Color(red: 0.86, green: 0.55, blue: 0.42))
                            .frame(width: 18, height: 14)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 2).fill(wood).frame(height: 7)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 3)
        }
    }
}

/// Arched window: rectangle with a semicircular top.
struct ArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

enum MolibooRoomPainter {
    /// Potted monstera bottom-left, a fern bottom-right and a hanging vine top-right. `sway` 0 = perfectly still.
    static func plants(in ctx: inout GraphicsContext, w: CGFloat, top: CGFloat, t: Double, sway: Double) {
        let dark = Color(red: 0.20, green: 0.45, blue: 0.28), mid = Color(red: 0.30, green: 0.58, blue: 0.34), light = Color(red: 0.45, green: 0.72, blue: 0.42)
        _ = dark   // (left potted plant removed: its leaves poked out of the left edge)
        // Bottom-right fern.
        let base2 = CGPoint(x: w - 30, y: top + 430)
        let angles2: [Double] = [-170, -150, -130, -110, -160, -125]
        for (i, a) in angles2.enumerated() {
            let s = sin(t * 0.8 + Double(i)) * 3.5 * sway
            leaf(&ctx, at: base2, angle: a + s, length: 52 + CGFloat(i % 2) * 12, width: 14, color: [mid, dark, light][i % 3])
        }
        pot(&ctx, at: base2, width: 34)
        // Hanging vine from the top-right corner.
        let swing = sin(t * 0.6) * 6 * sway
        for i in 0..<9 {
            let f = CGFloat(i) / 8
            let p = CGPoint(x: w - 18 - f * 22 + CGFloat(swing) * f, y: top + 10 + f * 150)
            leaf(&ctx, at: p, angle: (i % 2 == 0 ? 30 : 150) + swing * 0.5, length: 18, width: 10, color: i % 2 == 0 ? mid : light)
        }
    }

    static func dust(in ctx: inout GraphicsContext, size: CGSize, top: CGFloat, t: Double, warm: Color) {
        for i in 0..<14 {
            let fi = Double(i)
            let rx = (fi * 0.731).truncatingRemainder(dividingBy: 1), ry = (fi * 0.457 + 0.21).truncatingRemainder(dividingBy: 1)
            let x = rx * size.width + sin(t * 0.21 + fi) * 16
            let y = top + ry * 420 + cos(t * 0.17 + fi * 1.7) * 12
            let a = 0.15 + 0.35 * abs(sin(t * 0.5 + fi))
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.4, height: 2.4)), with: .color(warm.opacity(a)))
        }
    }

    private static func leaf(_ ctx: inout GraphicsContext, at p: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: Color) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .degrees(angle))
        var path = Path()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -width))
        path.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: width * 0.6))
        c.fill(path, with: .color(color))
        var vein = Path(); vein.move(to: .zero); vein.addLine(to: CGPoint(x: length * 0.85, y: -width * 0.12))
        c.stroke(vein, with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    private static func pot(_ ctx: inout GraphicsContext, at p: CGPoint, width: CGFloat) {
        let r = CGRect(x: p.x - width / 2, y: p.y - 4, width: width, height: width * 0.8)
        ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(Color(red: 0.84, green: 0.52, blue: 0.40)))
        ctx.fill(Path(roundedRect: CGRect(x: r.minX - 3, y: r.minY - 2, width: width + 6, height: 8), cornerRadius: 3), with: .color(Color(red: 0.74, green: 0.44, blue: 0.34)))
    }
}

/// Illustrated scene for each activity card, composed from the character's real portrait + SwiftUI shapes
/// (Sleep on a cloud, Play in a meadow, Clean in a bubble bath, Feed with a cookie).
struct MolibooActivityScene: View {
    let activity: MolibooActivity
    let characterID: String

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            props
            portrait
        }
        .clipped()
    }

    private var portrait: some View {
        Group {
            if let img = MolibooPortrait.thumb(for: characterID, dressed: true) ?? MolibooPortrait.image(for: characterID) {
                Image(uiImage: img).resizable().scaledToFit().frame(width: 92, height: 92)
                    .rotationEffect(.degrees(activity == .sleep ? -8 : 0))
                    .opacity(activity == .sleep ? 0.92 : 1)
            }
        }
        .offset(y: activity == .clean ? -26 : (activity == .sleep ? -30 : -14))
    }

    @ViewBuilder private var background: some View {
        switch activity {
        case .sleep: LinearGradient(colors: [Color(red: 0.24, green: 0.24, blue: 0.52), Color(red: 0.52, green: 0.46, blue: 0.80)], startPoint: .top, endPoint: .bottom)
        case .play: LinearGradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.98), Color(red: 0.86, green: 0.95, blue: 0.86)], startPoint: .top, endPoint: .bottom)
        case .clean: LinearGradient(colors: [Color(red: 0.62, green: 0.88, blue: 0.96), Color(red: 0.86, green: 0.96, blue: 1.0)], startPoint: .top, endPoint: .bottom)
        case .feed: LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.70), Color(red: 1.0, green: 0.92, blue: 0.84)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private var props: some View {
        switch activity {
        case .sleep:
            ZStack {
                Image(systemName: "moon.fill").foregroundStyle(.yellow).font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "sparkle").font(.system(size: CGFloat(6 + i % 3 * 2))).foregroundStyle(.white.opacity(0.8))
                        .position(x: CGFloat(40 + i * 19), y: CGFloat(16 + (i * 13) % 34))
                }
                cloud.frame(height: 54).offset(y: 50).frame(maxHeight: .infinity, alignment: .bottom)
                Text("z z").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.85)).offset(x: 34, y: -18)
            }
        case .play:
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color(red: 0.44, green: 0.72, blue: 0.38)).frame(height: 70).offset(y: 30).scaleEffect(x: 1.6)
                ForEach(0..<6, id: \.self) { i in
                    Circle().fill([Color.pink, .yellow, .white][i % 3]).frame(width: 6, height: 6)
                        .offset(x: CGFloat(-56 + i * 22), y: CGFloat(-10 - (i % 2) * 8))
                }
                Image(systemName: "butterfly.fill").foregroundStyle(.orange).font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
            }
        case .clean:
            ZStack(alignment: .bottom) {
                Capsule().fill(.white).frame(height: 52).offset(y: 18).padding(.horizontal, -6)
                ForEach(0..<9, id: \.self) { i in
                    Circle().fill(.white.opacity(0.85)).overlay(Circle().stroke(.cyan.opacity(0.3), lineWidth: 1))
                        .frame(width: CGFloat(12 + i % 3 * 8)).offset(x: CGFloat(-60 + i * 15), y: CGFloat(-24 - (i * 7) % 26))
                }
                Image(systemName: "bubbles.and.sparkles.fill").foregroundStyle(.cyan).font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
            }
        case .feed:
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color(red: 0.95, green: 0.72, blue: 0.56)).frame(height: 36).offset(y: 14).scaleEffect(x: 1.4)
                cookie.frame(width: 34, height: 34).offset(x: 38, y: -20)
                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.footnote)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
            }
        }
    }

    private var cloud: some View {
        ZStack {
            Capsule().fill(.white).frame(width: 140, height: 40).offset(y: 10)
            Circle().fill(.white).frame(width: 52).offset(x: -30, y: -4)
            Circle().fill(.white).frame(width: 64).offset(x: 14, y: -10)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
    }

    private var cookie: some View {
        ZStack {
            Circle().fill(Color(red: 0.80, green: 0.56, blue: 0.32))
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(Color(red: 0.36, green: 0.22, blue: 0.14)).frame(width: 5)
                    .offset(x: CGFloat([-7, 6, 0, -4, 8][i]), y: CGFloat([-6, -4, 2, 8, 6][i]))
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
    }
}

/// Spring press feedback for cards (disabled under Reduced Motion).
struct MolibooSpringPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    /// Soft feathered edges for character art and illustrations (radial fade instead of a hard cut-off).
    func molibooSoftEdges(_ strength: CGFloat = 0.18) -> some View {
        mask(RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - strength), .init(color: .clear, location: 1)],
                            center: .center, startRadius: 0, endRadius: 60).scaleEffect(1.25))
    }
}
