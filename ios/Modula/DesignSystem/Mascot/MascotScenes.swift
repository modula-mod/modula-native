import SwiftUI

// MARK: - Scene backgrounds (wardrobe "Scenes" slot)

/// Paints a wardrobe scene to fill its frame. Static by default (cheap in grids); `animated`
/// adds gentle twinkles/drift for the Studio preview card.
struct MascotSceneView: View {
    let item: MascotWardrobeItem?
    var dye: Color? = nil
    var animated = false

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                canvas(t: tl.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: Double) -> some View {
        let style = item?.style ?? "none"
        let tint = dye ?? item?.tint ?? .gray
        return Canvas { ctx, size in
            MascotScenePainter(ctx: ctx, size: size, t: t, tint: tint).paint(style)
        }
    }
}

struct MascotScenePainter {
    let ctx: GraphicsContext
    let size: CGSize
    let t: Double
    let tint: Color

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var full: Path { Path(CGRect(origin: .zero, size: size)) }

    func vgrad(_ colors: [Color]) { ctx.fill(full, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: h))) }

    func stars(_ n: Int, maxY: CGFloat, seed: Int = 7) {
        var rng = SeededRandom(seed: seed)
        for i in 0..<n {
            let x = rng.next() * w, y = rng.next() * maxY
            let tw = t > 0 ? 0.5 + 0.5 * sin(t * 2 + Double(i)) : 0.8
            let r = (0.6 + rng.next() * 1.2)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.4 + 0.6 * tw)))
        }
    }

    func hills(_ y: CGFloat, _ amp: CGFloat, _ color: Color, phase: CGFloat = 0) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: y))
        let n = 4
        for i in 0..<n {
            let x0 = CGFloat(i) * w / CGFloat(n), x1 = CGFloat(i + 1) * w / CGFloat(n)
            p.addQuadCurve(to: CGPoint(x: x1, y: y), control: CGPoint(x: (x0 + x1) / 2, y: y - amp * (i % 2 == 0 ? 1 : 0.4) + phase))
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [color, color.darker(0.18)]), startPoint: CGPoint(x: 0, y: y - amp), endPoint: CGPoint(x: 0, y: h)))
    }

    func cloud(_ c: CGPoint, _ r: CGFloat, _ color: Color = .white) {
        for (dx, dy, k) in [(-0.9, 0.2, 0.7), (0.0, 0.0, 1.0), (0.9, 0.25, 0.65)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - r * k, y: c.y + dy * r - r * k, width: r * k * 2, height: r * k * 2)), with: .color(color))
        }
    }

    func paint(_ style: String) {
        switch style {
        case "soft":
            ctx.fill(full, with: .linearGradient(Gradient(colors: [tint.lighter(0.55), tint.lighter(0.2)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.05, width: w * 0.8, height: h * 0.8)), with: .radialGradient(Gradient(colors: [.white.opacity(0.5), .clear]), center: CGPoint(x: w / 2, y: h * 0.4), startRadius: 0, endRadius: w * 0.45))
        case "meadow":
            vgrad([Color(red: 0.62, green: 0.84, blue: 1), Color(red: 0.86, green: 0.95, blue: 1)])
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.75, y: h * 0.08, width: h * 0.22, height: h * 0.22)), with: .color(Color(red: 1, green: 0.92, blue: 0.5)))
            cloud(CGPoint(x: w * 0.22 + CGFloat(t.truncatingRemainder(dividingBy: 60)) * 0.3, y: h * 0.2), h * 0.07)
            hills(h * 0.68, h * 0.12, Color(red: 0.55, green: 0.8, blue: 0.42))
            hills(h * 0.8, h * 0.08, tint)
            var rng = SeededRandom(seed: 3)
            for _ in 0..<14 {
                let x = rng.next() * w, y = h * 0.82 + rng.next() * h * 0.16
                let col: Color = [Color.white, Color.yellow, Color(red: 1, green: 0.6, blue: 0.75)][Int(rng.next() * 2.99)]
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(col))
            }
        case "night":
            vgrad([Color(red: 0.05, green: 0.06, blue: 0.2), tint, Color(red: 0.22, green: 0.2, blue: 0.45)])
            stars(40, maxY: h * 0.7)
            let m = CGRect(x: w * 0.72, y: h * 0.1, width: h * 0.22, height: h * 0.22)
            ctx.fill(Path(ellipseIn: m.insetBy(dx: -h * 0.08, dy: -h * 0.08)), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.25), .clear]), center: CGPoint(x: m.midX, y: m.midY), startRadius: 0, endRadius: h * 0.2))
            ctx.fill(Path(ellipseIn: m), with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
            ctx.fill(Path(ellipseIn: m.offsetBy(dx: m.width * 0.3, dy: -m.height * 0.1)), with: .color(Color(red: 0.12, green: 0.12, blue: 0.3)))
            hills(h * 0.85, h * 0.06, Color(red: 0.1, green: 0.12, blue: 0.25))
        case "sunset":
            vgrad([Color(red: 0.98, green: 0.45, blue: 0.45), tint, Color(red: 1, green: 0.82, blue: 0.5)])
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - h * 0.2, y: h * 0.48, width: h * 0.4, height: h * 0.4)), with: .color(Color(red: 1, green: 0.92, blue: 0.6)))
            ctx.fill(Path(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28)), with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.25, blue: 0.45), Color(red: 0.35, green: 0.15, blue: 0.35)]), startPoint: CGPoint(x: 0, y: h * 0.72), endPoint: CGPoint(x: 0, y: h)))
            for i in 0..<4 { ctx.fill(Path(CGRect(x: w * 0.3 + CGFloat(i) * 6, y: h * (0.76 + CGFloat(i) * 0.05), width: w * 0.4 - CGFloat(i) * 12, height: 2)), with: .color(Color(red: 1, green: 0.85, blue: 0.6).opacity(0.6))) }
        case "beach":
            vgrad([Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.85, green: 0.96, blue: 1)])
            cloud(CGPoint(x: w * 0.7, y: h * 0.18), h * 0.06)
            let waveY = h * 0.62 + CGFloat(t > 0 ? 3 * sin(t) : 0)
            ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.2)), with: .linearGradient(Gradient(colors: [tint, tint.darker(0.2)]), startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h * 0.75)))
            hills(waveY + h * 0.08, h * 0.03, Color(red: 0.98, green: 0.88, blue: 0.65))
            var foam = Path()
            foam.move(to: CGPoint(x: 0, y: waveY + h * 0.06))
            for i in 0..<8 { foam.addQuadCurve(to: CGPoint(x: CGFloat(i + 1) * w / 8, y: waveY + h * 0.06), control: CGPoint(x: (CGFloat(i) + 0.5) * w / 8, y: waveY + h * 0.03)) }
            ctx.stroke(foam, with: .color(.white.opacity(0.85)), lineWidth: 2)
        case "room":
            vgrad([tint.lighter(0.2), tint])
            ctx.fill(Path(CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.22)), with: .color(Color(red: 0.72, green: 0.52, blue: 0.36)))
            let win = CGRect(x: w * 0.62, y: h * 0.12, width: w * 0.26, height: h * 0.36)
            ctx.fill(Path(roundedRect: win, cornerRadius: 6), with: .linearGradient(Gradient(colors: [Color(red: 0.6, green: 0.85, blue: 1), Color(red: 0.9, green: 0.96, blue: 1)]), startPoint: CGPoint(x: 0, y: win.minY), endPoint: CGPoint(x: 0, y: win.maxY)))
            ctx.stroke(Path(roundedRect: win, cornerRadius: 6), with: .color(.white), lineWidth: 4)
            ctx.fill(Path(CGRect(x: win.midX - 1.5, y: win.minY, width: 3, height: win.height)), with: .color(.white))
            let pot = CGRect(x: w * 0.1, y: h * 0.66, width: w * 0.1, height: h * 0.13)
            for k in 0..<5 {
                let a = Double(k) * 0.5 - 1
                var leaf = Path()
                leaf.move(to: CGPoint(x: pot.midX, y: pot.minY))
                leaf.addQuadCurve(to: CGPoint(x: pot.midX + CGFloat(sin(a)) * w * 0.08, y: pot.minY - h * 0.2), control: CGPoint(x: pot.midX + CGFloat(sin(a)) * w * 0.1, y: pot.minY - h * 0.06))
                ctx.stroke(leaf, with: .color(Color(red: 0.3, green: 0.65, blue: 0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            ctx.fill(Path(roundedRect: pot, cornerRadius: 4), with: .color(Color(red: 0.85, green: 0.45, blue: 0.3)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.25, y: h * 0.84, width: w * 0.5, height: h * 0.1)), with: .color(Color(red: 0.95, green: 0.6, blue: 0.6).opacity(0.7)))
        case "space":
            vgrad([Color(red: 0.03, green: 0.02, blue: 0.1), tint, Color(red: 0.05, green: 0.03, blue: 0.15)])
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.2, y: h * 0.1, width: w * 0.8, height: h * 0.5)), with: .radialGradient(Gradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8).opacity(0.45), .clear]), center: CGPoint(x: w * 0.2, y: h * 0.35), startRadius: 0, endRadius: w * 0.4))
            stars(60, maxY: h)
            let pl = CGRect(x: w * 0.7, y: h * 0.12, width: h * 0.24, height: h * 0.24)
            ctx.fill(Path(ellipseIn: pl), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.75, blue: 0.4), Color(red: 0.85, green: 0.4, blue: 0.3)]), startPoint: CGPoint(x: pl.minX, y: pl.minY), endPoint: CGPoint(x: pl.maxX, y: pl.maxY)))
            ctx.stroke(Path(ellipseIn: pl.insetBy(dx: -pl.width * 0.35, dy: pl.height * 0.36)), with: .color(Color(red: 1, green: 0.9, blue: 0.7).opacity(0.8)), lineWidth: 2.5)
        case "sakura":
            vgrad([Color(red: 1, green: 0.93, blue: 0.95), tint])
            var branch = Path()
            branch.move(to: CGPoint(x: 0, y: h * 0.12)); branch.addQuadCurve(to: CGPoint(x: w * 0.45, y: h * 0.2), control: CGPoint(x: w * 0.2, y: h * 0.05))
            ctx.stroke(branch, with: .color(Color(red: 0.45, green: 0.3, blue: 0.28)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            var rng = SeededRandom(seed: 11)
            for i in 0..<16 {
                let fall = t > 0 ? CGFloat((t * 0.08 + Double(i) / 16).truncatingRemainder(dividingBy: 1)) : rng.next()
                let x = rng.next() * w + CGFloat(sin(Double(fall) * 6 + Double(i))) * 8
                let y = fall * h
                ctx.fill(MascotShapes.leaf(center: CGPoint(x: x, y: y), size: 7, angle: Double(i) + t), with: .color(Color(red: 1, green: 0.7, blue: 0.8)))
            }
            hills(h * 0.88, h * 0.03, Color(red: 0.98, green: 0.82, blue: 0.86))
        case "underwater":
            vgrad([tint.lighter(0.3), tint, tint.darker(0.35)])
            for k in 0..<4 {
                var ray = Path()
                let x = w * (0.15 + CGFloat(k) * 0.22)
                ray.move(to: CGPoint(x: x, y: 0)); ray.addLine(to: CGPoint(x: x + w * 0.08, y: 0)); ray.addLine(to: CGPoint(x: x + w * 0.2, y: h)); ray.addLine(to: CGPoint(x: x + w * 0.05, y: h)); ray.closeSubpath()
                ctx.fill(ray, with: .color(.white.opacity(0.07)))
            }
            for k in 0..<5 {
                var weed = Path()
                let x = w * (0.05 + CGFloat(k) * 0.22)
                weed.move(to: CGPoint(x: x, y: h))
                let sway = CGFloat(t > 0 ? 6 * sin(t * 1.2 + Double(k)) : 0)
                weed.addCurve(to: CGPoint(x: x + sway, y: h * 0.6), control1: CGPoint(x: x - 12, y: h * 0.85), control2: CGPoint(x: x + 12, y: h * 0.72))
                ctx.stroke(weed, with: .color(Color(red: 0.25, green: 0.65, blue: 0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            for k in 0..<8 {
                let ph = t > 0 ? CGFloat((t * 0.15 + Double(k) / 8).truncatingRemainder(dividingBy: 1)) : CGFloat(k) / 8
                let r: CGFloat = 2 + CGFloat(k % 3)
                ctx.stroke(Path(ellipseIn: CGRect(x: w * (0.1 + CGFloat(k) * 0.11), y: h * (1 - ph), width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        case "city":
            vgrad([Color(red: 0.2, green: 0.15, blue: 0.4), tint, Color(red: 0.95, green: 0.55, blue: 0.5)])
            var rng = SeededRandom(seed: 5)
            var x: CGFloat = 0
            while x < w {
                let bw = w * (0.08 + rng.next() * 0.08)
                let bh = h * (0.25 + rng.next() * 0.35)
                let r = CGRect(x: x, y: h - bh, width: bw, height: bh)
                ctx.fill(Path(r), with: .color(Color(red: 0.12, green: 0.1, blue: 0.25)))
                var wy = r.minY + 6
                while wy < h - 6 {
                    var wx = r.minX + 4
                    while wx < r.maxX - 4 {
                        if rng.next() > 0.45 { ctx.fill(Path(CGRect(x: wx, y: wy, width: 3, height: 4)), with: .color(Color(red: 1, green: 0.88, blue: 0.5).opacity(0.85))) }
                        wx += 7
                    }
                    wy += 9
                }
                x += bw + 2
            }
        case "candy":
            vgrad([tint.lighter(0.3), Color(red: 0.8, green: 0.9, blue: 1)])
            cloud(CGPoint(x: w * 0.25, y: h * 0.2), h * 0.07, Color(red: 1, green: 0.85, blue: 0.95))
            cloud(CGPoint(x: w * 0.78, y: h * 0.3), h * 0.06, Color(red: 0.88, green: 0.9, blue: 1))
            hills(h * 0.78, h * 0.08, Color(red: 0.98, green: 0.7, blue: 0.85))
            for (i, x) in ([0.12, 0.86] as [CGFloat]).enumerated() {
                ctx.fill(Path(CGRect(x: w * x - 2, y: h * 0.5, width: 4, height: h * 0.32)), with: .color(.white))
                let c = CGPoint(x: w * x, y: h * 0.48)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - h * 0.09, y: c.y - h * 0.09, width: h * 0.18, height: h * 0.18)), with: .color(i == 0 ? Color(red: 1, green: 0.45, blue: 0.6) : Color(red: 0.5, green: 0.75, blue: 1)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - h * 0.05, y: c.y - h * 0.05, width: h * 0.1, height: h * 0.1)), with: .color(.white), lineWidth: 2)
            }
        case "neon":
            vgrad([Color(red: 0.08, green: 0.02, blue: 0.18), Color(red: 0.3, green: 0.05, blue: 0.35)])
            let sun = CGRect(x: w / 2 - h * 0.22, y: h * 0.18, width: h * 0.44, height: h * 0.44)
            ctx.fill(Path(ellipseIn: sun), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), tint]), startPoint: CGPoint(x: 0, y: sun.minY), endPoint: CGPoint(x: 0, y: sun.maxY)))
            for k in 0..<4 { ctx.fill(Path(CGRect(x: sun.minX, y: sun.midY + CGFloat(k) * sun.height * 0.1, width: sun.width, height: 2 + CGFloat(k))), with: .color(Color(red: 0.2, green: 0.04, blue: 0.3))) }
            let horizon = h * 0.6
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .color(Color(red: 0.06, green: 0.02, blue: 0.14)))
            let scroll = t > 0 ? CGFloat((t * 0.4).truncatingRemainder(dividingBy: 1)) : 0
            for k in 0..<8 {
                let u = (CGFloat(k) + scroll) / 8
                let y = horizon + (h - horizon) * u * u
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 1.2)), with: .color(Color(red: 0.2, green: 0.9, blue: 1).opacity(0.8)))
            }
            for k in -6...6 {
                var l = Path(); l.move(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.03, y: horizon)); l.addLine(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.25, y: h))
                ctx.stroke(l, with: .color(Color(red: 0.2, green: 0.9, blue: 1).opacity(0.6)), lineWidth: 1)
            }
        default:
            break
        }
    }
}

/// Tiny deterministic RNG so scenes look the same every frame.
struct SeededRandom {
    private var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}
