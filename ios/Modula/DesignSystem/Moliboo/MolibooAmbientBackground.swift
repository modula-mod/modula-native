import SwiftUI

/// Moods for the shared moving background.
enum MolibooAmbience: String, CaseIterable, Identifiable, Sendable {
    case night, morning, afternoon, evening, dreamy
    var id: String { rawValue }

    /// Time-of-day mood (same bands as the Living World: 5–12 morning, 12–17 afternoon, 17–21 evening, else night).
    static func current(_ date: Date = Date(), calendar: Calendar = .current) -> MolibooAmbience {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
    }

    var sky: [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .night: return [c(0.03, 0.04, 0.14), c(0.09, 0.08, 0.27), c(0.22, 0.16, 0.40)]
        case .morning: return [c(0.99, 0.80, 0.78), c(0.99, 0.91, 0.82), c(0.86, 0.94, 0.99)]
        case .afternoon: return [c(0.42, 0.72, 0.98), c(0.70, 0.86, 0.99), c(0.92, 0.96, 0.99)]
        case .evening: return [c(0.28, 0.20, 0.48), c(0.92, 0.48, 0.45), c(1.00, 0.76, 0.48)]
        case .dreamy: return [c(0.62, 0.52, 0.95), c(0.90, 0.66, 0.92), c(0.99, 0.84, 0.90)]
        }
    }

    /// Current mood, with a Debug-only `-MOLAmbience <name>` launch override for screenshots and UI tests.
    static func resolved(_ date: Date = Date()) -> MolibooAmbience {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-MOLAmbience"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let a = MolibooAmbience(rawValue: ProcessInfo.processInfo.arguments[i + 1]) { return a }
        #endif
        return current(date)
    }

    /// Light or dark backdrop, so foreground text can adapt.
    var isDark: Bool { self == .night || self == .evening }
}

/// Reusable moving background (settings hub hero, Moliboo picker, Studio).
///
/// Cost model: one `Canvas` inside one `TimelineView` capped at `fps` (default 24). The timeline is paused when the
/// view is off-screen, the scene isn't active, or `animated` is false; under Reduce Motion it renders one still frame.
/// Particles are deterministic from their index (no per-frame allocation or state), so a paused frame costs nothing.
struct MolibooAmbientBackground: View {
    var ambience: MolibooAmbience
    var animated = true
    var fps: Double = 24
    /// Draw the sky gradient. Turn off to layer just the particles over other art.
    var showsSky = true
    var density: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false

    private var running: Bool { animated && onScreen && scenePhase == .active && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / max(fps, 1), paused: !running)) { ctx in
            let t = running ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000) : 12.5
            Canvas(rendersAsynchronously: true) { g, size in
                if showsSky {
                    g.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .linearGradient(Gradient(colors: ambience.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                MolibooAmbientPainter(size: size, t: t, density: density).draw(ambience, in: &g)
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("moliboo.ambient.\(ambience.rawValue)")
    }
}

/// Pure drawing; `t` is seconds. Deterministic pseudo-random per particle index.
struct MolibooAmbientPainter {
    let size: CGSize
    let t: Double
    var density: Double = 1

    private func rnd(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
    private func count(_ n: Int) -> Int { max(1, Int(Double(n) * density)) }
    private var w: Double { size.width }
    private var h: Double { size.height }

    func draw(_ a: MolibooAmbience, in g: inout GraphicsContext) {
        switch a {
        case .night:
            glow(&g, at: CGPoint(x: w * 0.78, y: h * 0.16), radius: min(w, h) * 0.30, color: Color(red: 0.85, green: 0.88, blue: 1), alpha: 0.35)
            moon(&g)
            stars(&g)
            shootingStar(&g)
            fireflies(&g, color: Color(red: 0.85, green: 1, blue: 0.55), n: 10, band: 0.55...0.95)
        case .morning:
            rays(&g, origin: CGPoint(x: w * 0.12, y: -h * 0.05), color: Color(red: 1, green: 0.95, blue: 0.75))
            petals(&g)
        case .afternoon:
            glow(&g, at: CGPoint(x: w * 0.8, y: h * 0.12), radius: min(w, h) * 0.35, color: Color(red: 1, green: 0.97, blue: 0.8), alpha: 0.6)
            clouds(&g)
            pollen(&g)
        case .evening:
            glow(&g, at: CGPoint(x: w * 0.5, y: h * 0.92), radius: max(w, h) * 0.55, color: Color(red: 1, green: 0.62, blue: 0.3), alpha: 0.55)
            fireflies(&g, color: Color(red: 1, green: 0.86, blue: 0.45), n: 14, band: 0.35...0.95)
        case .dreamy:
            bokeh(&g)
            sparkles(&g)
        }
    }

    private func glow(_ g: inout GraphicsContext, at p: CGPoint, radius: Double, color: Color, alpha: Double) {
        g.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
               with: .radialGradient(Gradient(colors: [color.opacity(alpha), .clear]), center: p, startRadius: 0, endRadius: radius))
    }

    private func moon(_ g: inout GraphicsContext) {
        let r = min(w, h) * 0.07, p = CGPoint(x: w * 0.78, y: h * 0.16)
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.98, green: 0.97, blue: 0.9)))
        g.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.35, y: p.y - r * 0.5, width: r * 0.4, height: r * 0.4)), with: .color(Color(red: 0.88, green: 0.87, blue: 0.82).opacity(0.7)))
    }

    /// Three depth layers: far (small, slow twinkle, slow drift), mid, near (bigger, brighter).
    private func stars(_ g: inout GraphicsContext) {
        for layer in 0..<3 {
            let n = count([46, 24, 10][layer])
            let size = [1.0, 1.6, 2.4][layer]
            let drift = [0.6, 1.2, 2.2][layer]
            for i in 0..<n {
                let k = i + layer * 1000
                let x = (rnd(k, 1) * w + t * drift).truncatingRemainder(dividingBy: w)
                let y = rnd(k, 2) * h * 0.85
                let tw = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (0.8 + rnd(k, 3) * 2.2) + rnd(k, 4) * 6.28))
                let s = size * (0.8 + rnd(k, 5) * 0.5)
                g.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(.white.opacity(tw * [0.55, 0.75, 0.95][layer])))
                if layer == 2 && tw > 0.85 {
                    var cross = Path()
                    cross.move(to: CGPoint(x: x - s * 2, y: y)); cross.addLine(to: CGPoint(x: x + s * 2, y: y))
                    cross.move(to: CGPoint(x: x, y: y - s * 2)); cross.addLine(to: CGPoint(x: x, y: y + s * 2))
                    g.stroke(cross, with: .color(.white.opacity(0.5)), lineWidth: 0.6)
                }
            }
        }
    }

    /// One shooting star every ~7 s, visible ~0.9 s.
    private func shootingStar(_ g: inout GraphicsContext) {
        let period = 7.0
        let cycle = Int(t / period)
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase < 0.9 else { return }
        let p = phase / 0.9
        let sx = w * (0.15 + rnd(cycle, 7) * 0.6), sy = h * (0.05 + rnd(cycle, 8) * 0.25)
        let len = w * 0.35
        let head = CGPoint(x: sx + len * p, y: sy + len * 0.45 * p)
        let tail = CGPoint(x: head.x - len * 0.35, y: head.y - len * 0.35 * 0.45)
        var path = Path(); path.move(to: tail); path.addLine(to: head)
        g.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * (1 - p))]), startPoint: tail, endPoint: head), lineWidth: 1.6)
    }

    private func fireflies(_ g: inout GraphicsContext, color: Color, n: Int, band: ClosedRange<Double>) {
        for i in 0..<count(n) {
            let x = rnd(i, 11) * w + sin(t * (0.3 + rnd(i, 12) * 0.4) + Double(i)) * 24
            let y = h * (band.lowerBound + rnd(i, 13) * (band.upperBound - band.lowerBound)) + cos(t * (0.25 + rnd(i, 14) * 0.3) + Double(i)) * 16
            let pulse = 0.25 + 0.75 * max(0, sin(t * (0.9 + rnd(i, 15)) + rnd(i, 16) * 6.28))
            glow(&g, at: CGPoint(x: x, y: y), radius: 9, color: color, alpha: 0.5 * pulse)
            g.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(color.opacity(0.4 + 0.6 * pulse)))
        }
    }

    private func rays(_ g: inout GraphicsContext, origin: CGPoint, color: Color) {
        for i in 0..<5 {
            let a = 0.35 + Double(i) * 0.16 + sin(t * 0.15 + Double(i)) * 0.03
            let len = max(w, h) * 1.3, spread = 0.035
            var p = Path()
            p.move(to: origin)
            p.addLine(to: CGPoint(x: origin.x + cos(a - spread) * len, y: origin.y + sin(a - spread) * len))
            p.addLine(to: CGPoint(x: origin.x + cos(a + spread) * len, y: origin.y + sin(a + spread) * len))
            p.closeSubpath()
            let alpha = 0.10 + 0.06 * sin(t * 0.5 + Double(i) * 1.7)
            g.fill(p, with: .linearGradient(Gradient(colors: [color.opacity(alpha), .clear]), startPoint: origin,
                                            endPoint: CGPoint(x: origin.x + cos(a) * len, y: origin.y + sin(a) * len)))
        }
    }

    private func petals(_ g: inout GraphicsContext) {
        for i in 0..<count(16) {
            let speed = 14 + rnd(i, 21) * 18
            let y = (rnd(i, 22) * h + t * speed).truncatingRemainder(dividingBy: h + 20) - 10
            let x = rnd(i, 23) * w + sin(t * 0.8 + Double(i)) * 18
            var c = g
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(t * (0.6 + rnd(i, 24)) + Double(i)))
            c.fill(Path(ellipseIn: CGRect(x: -4, y: -2.2, width: 8, height: 4.4)),
                   with: .color((i % 3 == 0 ? Color.white : Color(red: 1, green: 0.66, blue: 0.78)).opacity(0.8)))
        }
    }

    private func clouds(_ g: inout GraphicsContext) {
        for i in 0..<4 {
            let cw = w * (0.30 + rnd(i, 31) * 0.2), ch = cw * 0.28
            let x = (rnd(i, 32) * (w + cw) + t * (4 + Double(i) * 2)).truncatingRemainder(dividingBy: w + cw) - cw
            let y = h * (0.08 + rnd(i, 33) * 0.3)
            var c = g
            c.addFilter(.blur(radius: 6))
            for j in 0..<3 {
                let bx = x + Double(j) * cw * 0.3, by = y - (j == 1 ? ch * 0.35 : 0)
                c.fill(Path(ellipseIn: CGRect(x: bx, y: by, width: cw * 0.5, height: ch)), with: .color(.white.opacity(0.75)))
            }
        }
    }

    private func pollen(_ g: inout GraphicsContext) {
        for i in 0..<count(22) {
            let x = (rnd(i, 41) * w + t * (3 + rnd(i, 42) * 6)).truncatingRemainder(dividingBy: w)
            let y = h * (0.3 + rnd(i, 43) * 0.7) + sin(t * (0.4 + rnd(i, 44)) + Double(i)) * 10
            let s = 1.5 + rnd(i, 45) * 2
            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(red: 1, green: 0.95, blue: 0.6).opacity(0.7)))
        }
    }

    private func bokeh(_ g: inout GraphicsContext) {
        let palette = [Color.white, Color(red: 1, green: 0.8, blue: 0.95), Color(red: 0.8, green: 0.85, blue: 1), Color(red: 1, green: 0.9, blue: 0.7)]
        for i in 0..<count(12) {
            let r = 16 + rnd(i, 51) * 34
            let x = rnd(i, 52) * w + sin(t * 0.12 + Double(i)) * 20
            let y = rnd(i, 53) * h + cos(t * 0.1 + Double(i) * 1.3) * 16
            let a = 0.10 + 0.10 * (0.5 + 0.5 * sin(t * 0.4 + Double(i)))
            glow(&g, at: CGPoint(x: x, y: y), radius: r, color: palette[i % palette.count], alpha: a * 2)
        }
    }

    private func sparkles(_ g: inout GraphicsContext) {
        for i in 0..<count(14) {
            let x = rnd(i, 61) * w, y = rnd(i, 62) * h
            let p = max(0, sin(t * (0.7 + rnd(i, 63)) + rnd(i, 64) * 6.28))
            guard p > 0.2 else { continue }
            let s = 3 + 5 * p
            var star = Path()
            star.move(to: CGPoint(x: x, y: y - s)); star.addQuadCurve(to: CGPoint(x: x + s, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y + s), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x - s, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y - s), control: CGPoint(x: x, y: y))
            g.fill(star, with: .color(.white.opacity(0.85 * p)))
        }
    }
}
