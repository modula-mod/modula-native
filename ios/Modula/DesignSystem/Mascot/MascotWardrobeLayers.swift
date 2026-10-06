import SwiftUI
import UIKit

// MARK: - Layered wardrobe overlay

/// Which part of the figure stack a wardrobe pass paints:
/// `.back` behind the body (wings, capes, hoods, long hair, aura rings),
/// `.body` on the body but under the face (tops, outerwear, bottoms, shoes, neckwear),
/// `.front` over everything (hats, fringes, face props, held items, pets, aura particles).
enum MascotWearLayer: Sendable { case back, body, front }

struct MascotWardrobeOverlay: View {
    let outfit: MascotOutfit
    let rig: MascotRig
    var pose: MascotPose
    var size: CGFloat
    var layer: MascotWearLayer
    var animate: Bool = true

    var body: some View {
        let c = ModulaMascotFigure.canvas(size)
        let wear = MascotWearList(outfit.wearables(on: rig))
        let t = pose.t
        let amp = animate ? Double(pose.amp) : 0
        let mood = pose.mood
        let rig = rig
        let s = size
        let layer = layer
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, sz in
            MascotWearPainter(ctx: ctx, rig: rig, s: s, canvas: sz, t: t, amp: amp, mood: mood).paint(wear, layer: layer)
        }
        .frame(width: c.width, height: c.height)
        .allowsHitTesting(false)
    }
}

/// Resolved, drawable outfit: one entry per role, with seasonal items taking over the role they need.
struct MascotWearList: Sendable {
    enum Role: Sendable { case hat, hair, face, top, outer, bottom, shoes, neck, held, back, aura, pet }
    struct Entry: Sendable {
        let item: MascotWardrobeItem
        let color: Color
        let adapted: Bool
    }
    private(set) var byRole: [Role: Entry] = [:]

    init(_ list: [(item: MascotWardrobeItem, color: Color, fit: MascotFit)]) {
        var seasonal: (Role, Entry)?
        for w in list {
            let entry = Entry(item: w.item, color: w.color, adapted: w.fit != .fits)
            let role: Role
            switch w.item.slot {
            case .hat: role = .hat
            case .hair: role = .hair
            case .face: role = .face
            case .top: role = .top
            case .outerwear: role = .outer
            case .bottom: role = .bottom
            case .shoes: role = .shoes
            case .accessory: role = .neck
            case .held: role = .held
            case .back: role = .back
            case .aura: role = .aura
            case .pet: role = .pet
            case .background: continue
            case .seasonal:
                switch w.item.need {
                case .back: seasonal = (.back, entry)
                case .aura: seasonal = (.aura, entry)
                case .neck: seasonal = (.neck, entry)
                default: seasonal = (.hat, entry)
                }
                continue
            }
            byRole[role] = entry
        }
        if let seasonal { byRole[seasonal.0] = seasonal.1 }
    }

    subscript(_ role: Role) -> Entry? { byRole[role] }
    var isEmpty: Bool { byRole.isEmpty }
}

// MARK: - Swatch + colour helpers

extension Color {
    /// Cheap mix toward another colour (for wardrobe tint shading).
    func mix(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(amount)
        return Color(red: Double(ar + (br - ar) * t), green: Double(ag + (bg - ag) * t), blue: Double(ab + (bb - ab) * t), opacity: Double(aa + (ba - aa) * t))
    }
    func lighter(_ a: Double = 0.3) -> Color { mix(with: .white, by: a) }
    func darker(_ a: Double = 0.3) -> Color { mix(with: .black, by: a) }
}

/// Precomputed tones for one dye so a frame never recomputes them per stroke.
struct MascotSwatch: Sendable {
    let base: Color
    let light: Color
    let lighter: Color
    let dark: Color
    let deep: Color
    let ink: Color

    init(_ c: Color) {
        base = c
        light = c.lighter(0.28)
        lighter = c.lighter(0.55)
        dark = c.darker(0.22)
        deep = c.darker(0.42)
        ink = c.mix(with: Color(red: 0.12, green: 0.08, blue: 0.14), by: 0.68)
    }
}

// MARK: - Art kit

/// Drawing helpers working in any coordinate frame. `u` is the number of points per unit so
/// outlines and shading keep a constant on-screen weight however the frame is scaled.
struct MascotArt {
    var g: GraphicsContext
    let u: CGFloat
    let stroke: CGFloat

    var lw: CGFloat { stroke / u }

    /// Shaded, outlined, volumetric fill: gradient body, soft inner edge, gloss, outline.
    func solid(_ p: Path, _ w: MascotSwatch, gloss: Double = 0.45, outline: Bool = true, edge: Double = 1) {
        let r = p.boundingRect
        guard r.width > 0, r.height > 0 else { return }
        g.fill(p, with: .linearGradient(Gradient(colors: [w.light, w.base, w.dark]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        volume(p, w, edge: edge)
        if gloss > 0 { shine(p, opacity: gloss) }
        if outline { g.stroke(p, with: .color(w.ink), style: StrokeStyle(lineWidth: lw, lineJoin: .round)) }
    }

    /// Inner-edge occlusion for roundness, no blur needed.
    func volume(_ p: Path, _ w: MascotSwatch, edge: Double = 1) {
        let r = p.boundingRect
        var c = g
        c.clip(to: p)
        c.fill(p, with: .radialGradient(Gradient(colors: [.clear, .clear, w.deep.opacity(0.42 * edge)]), center: CGPoint(x: r.midX - r.width * 0.18, y: r.midY - r.height * 0.22), startRadius: 0, endRadius: max(r.width, r.height) * 0.78))
        c.stroke(p, with: .color(w.deep.opacity(0.16 * edge)), lineWidth: lw * 4.5)
        c.stroke(p, with: .color(w.deep.opacity(0.16 * edge)), lineWidth: lw * 2.2)
    }

    /// Soft specular highlight in the top-left of the shape.
    func shine(_ p: Path, opacity: Double = 0.45) {
        let r = p.boundingRect
        var c = g
        c.clip(to: p)
        let hi = CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.06, width: r.width * 0.42, height: r.height * 0.3)
        c.fill(Path(ellipseIn: hi), with: .linearGradient(Gradient(colors: [.white.opacity(opacity), .white.opacity(0)]), startPoint: CGPoint(x: hi.midX, y: hi.minY), endPoint: CGPoint(x: hi.midX, y: hi.maxY)))
    }

    /// Polished metal: banded gradient with bright specular streaks.
    func metal(_ p: Path, _ w: MascotSwatch, outline: Bool = true) {
        let r = p.boundingRect
        guard r.width > 0, r.height > 0 else { return }
        g.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: w.lighter, location: 0), .init(color: w.base, location: 0.28), .init(color: w.dark, location: 0.5),
            .init(color: w.light, location: 0.62), .init(color: w.lighter, location: 0.72), .init(color: w.dark, location: 1),
        ]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX * 0.4 + r.minX * 0.6, y: r.maxY)))
        var c = g
        c.clip(to: p)
        var streak = Path()
        streak.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY))
        streak.addLine(to: CGPoint(x: r.minX + r.width * 0.45, y: r.minY))
        c.stroke(streak, with: .color(.white.opacity(0.55)), lineWidth: max(r.width * 0.08, lw))
        if outline { g.stroke(p, with: .color(w.ink), style: StrokeStyle(lineWidth: lw, lineJoin: .round)) }
    }

    /// Faceted gem with a sparkle.
    func gem(_ center: CGPoint, _ radius: CGFloat, _ color: Color, sparkle: Double = 1) {
        let w = MascotSwatch(color)
        var p = Path()
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi - .pi / 2
            let pt = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        g.fill(p, with: .linearGradient(Gradient(colors: [w.lighter, w.base, w.deep]), startPoint: CGPoint(x: center.x - radius, y: center.y - radius), endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
        var facet = Path()
        facet.move(to: CGPoint(x: center.x, y: center.y - radius))
        facet.addLine(to: CGPoint(x: center.x - radius * 0.5, y: center.y))
        facet.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.2))
        facet.closeSubpath()
        g.fill(facet, with: .color(.white.opacity(0.55)))
        g.stroke(p, with: .color(w.ink), lineWidth: lw * 0.8)
        if sparkle > 0 { twinkle(CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.55), radius * 0.7 * sparkle) }
    }

    /// Four-point star glint.
    func twinkle(_ c: CGPoint, _ r: CGFloat, color: Color = .white) {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        g.fill(p, with: .color(color))
    }

    /// Dashed stitching along a path.
    func stitch(_ p: Path, _ w: MascotSwatch, opacity: Double = 0.7) {
        g.stroke(p, with: .color(w.lighter.opacity(opacity)), style: StrokeStyle(lineWidth: lw * 0.55, lineCap: .round, dash: [lw * 1.6, lw * 1.4]))
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat = 1) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lw * width, lineCap: .round))
    }

    func dot(_ c: CGPoint, _ r: CGFloat, _ color: Color, outline: Color? = nil) {
        let p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        g.fill(p, with: .color(color))
        if let outline { g.stroke(p, with: .color(outline), lineWidth: lw * 0.6) }
    }

    func button(_ c: CGPoint, _ r: CGFloat, _ w: MascotSwatch) {
        dot(c, r, w.light, outline: w.ink)
        dot(CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), r * 0.3, .white.opacity(0.7))
    }

    /// Fabric pattern clipped to the garment. `scale` is the motif size in this frame's units.
    func pattern(_ p: Path, _ kind: MascotPattern, _ w: MascotSwatch, scale: CGFloat) {
        guard kind != .plain else { return }
        let r = p.boundingRect.insetBy(dx: -scale, dy: -scale)
        var c = g
        c.clip(to: p)
        let k = scale
        switch kind {
        case .plain:
            break
        case .stripes:
            var y = r.minY
            var i = 0
            while y < r.maxY {
                if i % 2 == 0 { c.fill(Path(CGRect(x: r.minX, y: y, width: r.width, height: k * 0.5)), with: .color(w.lighter.opacity(0.85))) }
                y += k * 0.5; i += 1
            }
        case .dots:
            var row = 0
            var y = r.minY
            while y < r.maxY {
                var x = r.minX + (row % 2 == 0 ? 0 : k * 0.5)
                while x < r.maxX {
                    c.fill(Path(ellipseIn: CGRect(x: x - k * 0.14, y: y - k * 0.14, width: k * 0.28, height: k * 0.28)), with: .color(w.lighter.opacity(0.9)))
                    x += k
                }
                y += k * 0.6; row += 1
            }
        case .plaid:
            var x = r.minX
            while x < r.maxX {
                c.fill(Path(CGRect(x: x, y: r.minY, width: k * 0.28, height: r.height)), with: .color(w.deep.opacity(0.35)))
                c.fill(Path(CGRect(x: x + k * 0.5, y: r.minY, width: k * 0.06, height: r.height)), with: .color(w.lighter.opacity(0.6)))
                x += k
            }
            var y = r.minY
            while y < r.maxY {
                c.fill(Path(CGRect(x: r.minX, y: y, width: r.width, height: k * 0.28)), with: .color(w.deep.opacity(0.35)))
                c.fill(Path(CGRect(x: r.minX, y: y + k * 0.5, width: r.width, height: k * 0.06)), with: .color(w.lighter.opacity(0.6)))
                y += k
            }
        case .knit:
            var y = r.minY
            while y < r.maxY {
                var x = r.minX
                while x < r.maxX {
                    var v = Path()
                    v.move(to: CGPoint(x: x, y: y))
                    v.addLine(to: CGPoint(x: x + k * 0.2, y: y + k * 0.22))
                    v.addLine(to: CGPoint(x: x + k * 0.4, y: y))
                    c.stroke(v, with: .color(w.deep.opacity(0.35)), style: StrokeStyle(lineWidth: lw * 0.6, lineCap: .round, lineJoin: .round))
                    x += k * 0.4
                }
                y += k * 0.3
            }
        case .check:
            var y = r.minY
            var row = 0
            while y < r.maxY {
                var x = r.minX + (row % 2 == 0 ? 0 : k * 0.4)
                while x < r.maxX {
                    c.fill(Path(CGRect(x: x, y: y, width: k * 0.4, height: k * 0.4)), with: .color(w.deep.opacity(0.28)))
                    x += k * 0.8
                }
                y += k * 0.4; row += 1
            }
        case .stars, .hearts, .floral:
            var y = r.minY
            var row = 0
            while y < r.maxY {
                var x = r.minX + (row % 2 == 0 ? 0 : k * 0.55)
                while x < r.maxX {
                    let pt = CGPoint(x: x, y: y)
                    switch kind {
                    case .stars: MascotArt(g: c, u: u, stroke: stroke).twinkle(pt, k * 0.2, color: Color(red: 1, green: 0.92, blue: 0.55))
                    case .hearts: c.fill(MascotShapes.heart(center: pt, size: k * 0.3), with: .color(w.lighter.opacity(0.9)))
                    default: MascotArt(g: c, u: u, stroke: stroke).flower(pt, k * 0.22, petal: w.lighter, center: Color(red: 1, green: 0.85, blue: 0.3))
                    }
                    x += k * 1.1
                }
                y += k * 0.8; row += 1
            }
        case .zigzag:
            var y = r.minY
            while y < r.maxY {
                var z = Path()
                var x = r.minX
                z.move(to: CGPoint(x: x, y: y))
                var up = true
                while x < r.maxX { x += k * 0.25; z.addLine(to: CGPoint(x: x, y: y + (up ? -k * 0.14 : 0))); up.toggle() }
                c.stroke(z, with: .color(w.lighter.opacity(0.85)), lineWidth: lw * 0.9)
                y += k * 0.45
            }
        }
    }

    func flower(_ c: CGPoint, _ r: CGFloat, petal: Color, center: Color) {
        for i in 0..<5 {
            let a = Double(i) / 5 * 2 * .pi
            let pc = CGPoint(x: c.x + cos(a) * r * 0.62, y: c.y + sin(a) * r * 0.62)
            g.fill(Path(ellipseIn: CGRect(x: pc.x - r * 0.42, y: pc.y - r * 0.42, width: r * 0.84, height: r * 0.84)), with: .color(petal))
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.32, y: c.y - r * 0.32, width: r * 0.64, height: r * 0.64)), with: .color(center))
    }
}

enum MascotShapes {
    static func heart(center c: CGPoint, size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + s * 0.42))
        p.addCurve(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.08), control1: CGPoint(x: c.x - s * 0.18, y: c.y + s * 0.28), control2: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.14))
        p.addArc(center: CGPoint(x: c.x - s * 0.25, y: c.y - s * 0.12), radius: s * 0.25, startAngle: .degrees(170), endAngle: .degrees(-10), clockwise: false)
        p.addArc(center: CGPoint(x: c.x + s * 0.25, y: c.y - s * 0.12), radius: s * 0.25, startAngle: .degrees(190), endAngle: .degrees(10), clockwise: false)
        p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.42), control1: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.14), control2: CGPoint(x: c.x + s * 0.18, y: c.y + s * 0.28))
        p.closeSubpath()
        return p
    }

    static func star(center c: CGPoint, outer: CGFloat, inner: CGFloat, points: Int = 5, rotation: Double = -.pi / 2) -> Path {
        var p = Path()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = rotation + Double(i) * .pi / Double(points)
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    static func note(center c: CGPoint, size s: CGFloat) -> Path {
        var p = Path(ellipseIn: CGRect(x: c.x - s * 0.32, y: c.y + s * 0.12, width: s * 0.36, height: s * 0.26))
        p.addRect(CGRect(x: c.x - s * 0.01, y: c.y - s * 0.42, width: s * 0.07, height: s * 0.68))
        var flag = Path()
        flag.move(to: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.42))
        flag.addQuadCurve(to: CGPoint(x: c.x + s * 0.32, y: c.y - s * 0.08), control: CGPoint(x: c.x + s * 0.36, y: c.y - s * 0.3))
        flag.addQuadCurve(to: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.22), control: CGPoint(x: c.x + s * 0.2, y: c.y - s * 0.2))
        p.addPath(flag)
        return p
    }

    static func bolt(center c: CGPoint, size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.5))
        p.addLine(to: CGPoint(x: c.x - s * 0.22, y: c.y + s * 0.06))
        p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.06))
        p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y + s * 0.5))
        p.addLine(to: CGPoint(x: c.x + s * 0.24, y: c.y - s * 0.1))
        p.addLine(to: CGPoint(x: c.x + s * 0.02, y: c.y - s * 0.1))
        p.closeSubpath()
        return p
    }

    static func leaf(center c: CGPoint, size s: CGFloat, angle: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -s * 0.5))
        p.addQuadCurve(to: CGPoint(x: 0, y: s * 0.5), control: CGPoint(x: s * 0.45, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.5), control: CGPoint(x: -s * 0.45, y: 0))
        return p.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }
}

// MARK: - Painter

/// Paints wardrobe items onto a figure canvas using the mascot's anatomy rig.
/// Coordinates: `P(x, y)` maps rig fractions (of `s`, from the canvas centre) to points.
struct MascotWearPainter {
    let ctx: GraphicsContext
    let rig: MascotRig
    let s: CGFloat
    let canvas: CGSize
    let t: Double
    let amp: Double
    let mood: MascotMood

    var cx: CGFloat { canvas.width / 2 }
    var cy: CGFloat { canvas.height / 2 }
    var stroke: CGFloat { max(s * 0.022, 0.9) }

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * s, y: cy + y * s) }
    func L(_ v: CGFloat) -> CGFloat { v * s }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: cx + x * s, y: cy + y * s, width: w * s, height: h * s) }

    var art: MascotArt { MascotArt(g: ctx, u: 1, stroke: stroke) }

    /// Art kit in a local frame at `origin` (rig units) with `unit` rig-units per local unit.
    func local(_ origin: CGPoint, unit: CGFloat, rotate: Double = 0, flip: Bool = false, clipFace: Bool = true) -> MascotArt {
        var g = clipFace ? faceSafe() : ctx
        g.translateBy(x: cx + origin.x * s, y: cy + origin.y * s)
        if rotate != 0 { g.rotate(by: .radians(rotate)) }
        g.scaleBy(x: flip ? -unit * s : unit * s, y: unit * s)
        return MascotArt(g: g, u: unit * s, stroke: stroke)
    }

    // Anatomy paths

    var bodyPath: Path { rig.bodyPath(size: s, canvas: canvas) }

    func inflated(_ k: CGFloat) -> Path {
        let c = P(0, rig.bodyY)
        let tr = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k, y: k).translatedBy(x: -c.x, y: -c.y)
        return bodyPath.applying(tr)
    }

    /// Region below a scoop neckline that always stays clear of the eyes and mouth.
    func belowNeck(_ extra: CGFloat = 0, dip: CGFloat = 0.03) -> Path {
        let ny = rig.neckY + extra
        let side = max(ny - 0.1, rig.eyeBottom + 0.05)
        let half = rig.faceHalfWidth + 0.06
        var p = Path()
        p.move(to: P(-1.4, side))
        p.addLine(to: P(-half - 0.06, side))
        p.addQuadCurve(to: P(0, ny + dip), control: P(-half * 0.55, ny + dip))
        p.addQuadCurve(to: P(half + 0.06, side), control: P(half * 0.55, ny + dip))
        p.addLine(to: P(1.4, side))
        p.addLine(to: P(1.4, 1.4))
        p.addLine(to: P(-1.4, 1.4))
        p.closeSubpath()
        return p
    }

    func necklineCurve(_ extra: CGFloat = 0, dip: CGFloat = 0.03, widen: CGFloat = 0) -> Path {
        let ny = rig.neckY + extra
        let side = max(ny - 0.1, rig.eyeBottom + 0.05)
        let half = rig.faceHalfWidth + 0.06 + widen
        var p = Path()
        p.move(to: P(-half - 0.06, side))
        p.addQuadCurve(to: P(0, ny + dip), control: P(-half * 0.55, ny + dip))
        p.addQuadCurve(to: P(half + 0.06, side), control: P(half * 0.55, ny + dip))
        return p
    }

    func above(_ y: CGFloat) -> Path { Path(R(-1.4, -1.4, 2.8, 1.4 + y)) }
    func below(_ y: CGFloat) -> Path { Path(R(-1.4, y, 2.8, 2.8)) }
    func band(_ y0: CGFloat, _ y1: CGFloat) -> Path { Path(R(-1.4, y0, 2.8, y1 - y0)) }
    func columns(_ halfGap: CGFloat) -> Path {
        var p = Path(R(-1.4, -1.4, 1.4 - halfGap, 2.8))
        p.addRect(R(halfGap, -1.4, 1.4 - halfGap, 2.8))
        return p
    }

    /// Clip that removes the eyes + mouth area, so nothing but face props can ever cover them.
    func faceSafe() -> GraphicsContext {
        var g = ctx
        var p = Path(CGRect(origin: .zero, size: canvas).insetBy(dx: -canvas.width, dy: -canvas.height))
        let top = rig.eyeTop - 0.012
        let bottom = rig.faceBottom
        let w = rig.faceHalfWidth + 0.012
        p.addRoundedRect(in: R(-w, top, w * 2, bottom - top), cornerSize: CGSize(width: L(0.1), height: L(0.1)))
        g.clip(to: p, style: FillStyle(eoFill: true))
        return g
    }

    var waistY: CGFloat { min(rig.bodyBottom - 0.07, max(rig.hipY, rig.faceBottom + 0.05)) }
    var shoulderHalf: CGFloat { max(0.16, rig.chord(at: rig.neckY + 0.06) / 2) }
    var wave: Double { amp > 0 ? sin(t * 2.2) : 0 }
    var emoteLift: CGFloat {
        switch mood {
        case .wave, .celebrate, .excited: CGFloat(amp > 0 ? 0.08 + 0.05 * sin(t * 9) : 0.08)
        case .dance: CGFloat(amp > 0 ? 0.05 * sin(t * 6) : 0)
        default: 0
        }
    }

    // MARK: Dispatch

    func paint(_ wear: MascotWearList, layer: MascotWearLayer) {
        guard !wear.isEmpty else { return }
        switch layer {
        case .back:
            if let e = wear[.aura] { auraBack(e) }
            if let e = wear[.back] { back(e) }
            if let e = wear[.hair] { hairBack(e) }
            if let e = wear[.top], e.item.style == "hoodie", wear[.hat] == nil { hood(e) }
        case .body:
            if let e = wear[.bottom], !(wear[.top]?.item.style == "overalls") { bottom(e) }
            if let e = wear[.top] { top(e) }
            if let e = wear[.outer] { outer(e) }
            if let e = wear[.back] { backStraps(e) }
            if let e = wear[.neck] { neck(e) }
            if let e = wear[.shoes] { shoes(e) }
        case .front:
            if let e = wear[.hair] { hairFront(e) }
            if let e = wear[.face] { face(e) }
            if let e = wear[.hat] { hat(e, hasHair: wear[.hair] != nil) }
            if let e = wear[.held] { held(e) }
            if let e = wear[.pet] { pet(e) }
            if let e = wear[.aura] { auraFront(e) }
        }
    }

    // MARK: Tops

    /// Sleeve "arms": little rounded tubes at the body sides that read as clothing on any silhouette.
    func sleeves(_ w: MascotSwatch, length: CGFloat, width: CGFloat = 0.13, cuff: Color? = nil, pattern: MascotPattern = .plain) {
        let y0 = rig.neckY + 0.02
        let x = min(shoulderHalf, rig.bodyW / 2) - 0.02
        for side in [-1.0, 1.0] as [CGFloat] {
            let swing = CGFloat(side > 0 ? -emoteLift * 2.2 : 0)
            var g = faceSafe()
            g.translateBy(x: cx + side * x * s, y: cy + y0 * s)
            g.rotate(by: .radians(Double(side * (0.32 + swing)) + 0.03 * wave * Double(side)))
            let rect = CGRect(x: -width * s / 2, y: 0, width: width * s, height: length * s)
            let p = Path(roundedRect: rect, cornerRadius: width * s / 2)
            let a = MascotArt(g: g, u: 1, stroke: stroke)
            a.solid(p, w, gloss: 0.3)
            a.pattern(p, pattern, w, scale: L(0.09))
            if let cuff {
                let cp = Path(roundedRect: CGRect(x: rect.minX, y: rect.maxY - width * s * 0.42, width: rect.width, height: width * s * 0.42), cornerRadius: width * s * 0.2)
                a.solid(cp, MascotSwatch(cuff), gloss: 0.2)
            }
        }
    }

    func garment(hem: CGFloat, extra: CGFloat = 0, dip: CGFloat = 0.03, inflate: CGFloat = 1.035) -> Path {
        let p = inflated(inflate).meet(belowNeck(extra, dip: dip)).meet(above(hem))
        return p.isEmpty ? garmentPolygon(hem: hem, extra: extra, dip: dip, inflate: inflate) : p
    }

    /// Boolean-free torso outline (from the rig's chord profile), used if a path boolean fails.
    func garmentPolygon(hem: CGFloat, extra: CGFloat = 0, dip: CGFloat = 0.03, inflate: CGFloat = 1.035) -> Path {
        let ny = rig.neckY + extra
        let side = max(ny - 0.1, rig.eyeBottom + 0.05)
        let half = rig.faceHalfWidth + 0.12
        func hw(_ y: CGFloat) -> CGFloat { inflate * rig.chord(at: rig.bodyY + (y - rig.bodyY) / inflate) / 2 }
        let bottom = min(hem, rig.bodyY + (rig.bodyBottom - rig.bodyY) * inflate - 0.004)
        guard bottom > side + 0.02 else { return Path() }
        let n = 18
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let y = side + (bottom - side) * CGFloat(i) / CGFloat(n)
            let w = hw(y)
            left.append(P(-w, y)); right.append(P(w, y))
        }
        var p = Path()
        p.move(to: left[0])
        for i in 0...24 {
            let x = -half + 2 * half * CGFloat(i) / 24
            let k = max(0, 1 - (x / half) * (x / half))
            let y = side + (ny + dip - side) * k
            let lim = hw(y)
            p.addLine(to: P(min(max(x, -lim), lim), y))
        }
        p.addLine(to: right[0])
        for pt in right.dropFirst() { p.addLine(to: pt) }
        for pt in left.reversed().dropLast() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    func top(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let it = e.item
        let a = art
        let hipHem = min(rig.bodyBottom + 0.02, rig.hipY + 0.05)
        let fullHem = rig.bodyBottom + 0.03
        let g = faceSafe()
        let fa = MascotArt(g: g, u: 1, stroke: stroke)
        func base(_ p: Path, gloss: Double = 0.35) {
            fa.solid(p, w, gloss: gloss)
            fa.pattern(p, it.pattern, w, scale: L(0.11))
            fa.volume(p, w, edge: 0.6)
        }
        func collarTrim(_ color: Color, width: CGFloat = 0.035, dip: CGFloat = 0.03) {
            let c = necklineCurve(0.006, dip: dip)
            var g2 = g
            g2.clip(to: inflated(1.04))
            g2.stroke(c, with: .color(MascotSwatch(color).ink), style: StrokeStyle(lineWidth: L(width) + stroke, lineCap: .round))
            g2.stroke(c, with: .color(color), style: StrokeStyle(lineWidth: L(width), lineCap: .round))
        }
        func hemBand(_ y: CGFloat, _ color: Color, _ p: Path) {
            var g2 = g
            g2.clip(to: p)
            g2.fill(Path(R(-1.2, y - 0.045, 2.4, 0.06)), with: .color(color))
            var x: CGFloat = -0.6
            while x < 0.6 { MascotArt(g: g2, u: 1, stroke: stroke).line(P(x, y - 0.04), P(x, y + 0.01), MascotSwatch(color).dark, width: 0.5); x += 0.035 }
        }

        switch it.style {
        case "tee", "jersey":
            sleeves(w, length: 0.13, width: 0.15, pattern: it.pattern)
            let p = garment(hem: hipHem)
            base(p)
            collarTrim(w.dark)
            stitchLine(P(-0.6, hipHem - 0.035), P(0.6, hipHem - 0.035), clip: p, w)
            if it.style == "jersey" {
                let y = (rig.neckY + hipHem) / 2 + 0.02
                g.draw(Text("7").font(.system(size: L(0.16), weight: .black, design: .rounded)).foregroundStyle(w.lighter), at: P(0, y))
            }
        case "tank":
            let p = garment(hem: hipHem, dip: 0.06).meet(columns(0).meet(Path(R(-shoulderHalf * 0.82, -1, shoulderHalf * 1.64, 2.4))))
            base(p)
            collarTrim(w.lighter, width: 0.025, dip: 0.06)
        case "hoodie":
            sleeves(w, length: 0.22, cuff: w.dark)
            let p = garment(hem: fullHem)
            base(p)
            hemBand(fullHem - 0.01, w.dark, p)
            collarTrim(w.dark, width: 0.05)
            // Drawstrings + kangaroo pocket.
            for side in [-1.0, 1.0] as [CGFloat] {
                let x0 = side * 0.07
                let sway = CGFloat(0.01 * wave) * side
                fa.line(P(x0, rig.neckY + 0.05), P(x0 + sway, rig.neckY + 0.15), Color.white.opacity(0.95), width: 1.1)
                fa.dot(P(x0 + sway, rig.neckY + 0.16), L(0.012), w.lighter, outline: w.ink)
            }
            let py = max(rig.neckY + 0.12, fullHem - 0.17)
            let pw = min(0.4, rig.chord(at: py) * 0.6)
            var pocket = Path()
            pocket.move(to: P(-pw / 2, fullHem - 0.04))
            pocket.addLine(to: P(-pw / 2 + 0.05, py))
            pocket.addLine(to: P(pw / 2 - 0.05, py))
            pocket.addLine(to: P(pw / 2, fullHem - 0.04))
            pocket.closeSubpath()
            let pp = pocket.meet(p)
            fa.g.fill(pp, with: .color(w.dark.opacity(0.35)))
            fa.g.stroke(pp, with: .color(w.ink.opacity(0.8)), lineWidth: stroke * 0.8)
        case "sweater":
            sleeves(w, length: 0.2, cuff: w.dark, pattern: .knit)
            let p = garment(hem: fullHem)
            base(p)
            hemBand(fullHem - 0.01, w.dark, p)
            collarTrim(w.dark, width: 0.05)
            // Cable knit braids.
            for x in [-0.12, 0.12] as [CGFloat] {
                var cable = Path()
                var y = rig.neckY + 0.06
                cable.move(to: P(x, y))
                while y < fullHem - 0.05 {
                    cable.addQuadCurve(to: P(x, y + 0.05), control: P(x + 0.03, y + 0.025))
                    y += 0.05
                }
                var g2 = g; g2.clip(to: p)
                g2.stroke(cable, with: .color(w.deep.opacity(0.5)), lineWidth: stroke * 1.4)
                g2.stroke(cable, with: .color(w.lighter.opacity(0.6)), lineWidth: stroke * 0.5)
            }
        case "polo":
            sleeves(w, length: 0.12, width: 0.15, cuff: w.lighter)
            let p = garment(hem: hipHem)
            base(p)
            collar(w, style: .pointed)
            fa.line(P(0, rig.neckY + 0.04), P(0, rig.neckY + 0.14), w.dark, width: 0.9)
            fa.button(P(0, rig.neckY + 0.07), L(0.013), w)
            fa.button(P(0, rig.neckY + 0.12), L(0.013), w)
        case "overalls":
            let denim = w
            // Shirt underneath: plain white tee band.
            let shirt = garment(hem: hipHem)
            fa.solid(shirt, MascotSwatch(Color(red: 0.97, green: 0.96, blue: 0.94)), gloss: 0.2)
            collarTrim(Color(red: 0.9, green: 0.88, blue: 0.85), width: 0.025)
            let bibTop = rig.neckY + 0.06
            let bibHalf = min(0.18, rig.chord(at: bibTop + 0.05) * 0.3)
            var p = Path(roundedRect: R(-bibHalf, bibTop, bibHalf * 2, waistY - bibTop + 0.02), cornerRadius: L(0.03))
            p.addPath(below(waistY))
            let o = inflated(1.04).meet(p)
            fa.solid(o, denim, gloss: 0.25)
            fa.stitch(Path(roundedRect: R(-bibHalf + 0.02, bibTop + 0.02, bibHalf * 2 - 0.04, waistY - bibTop - 0.02), cornerRadius: L(0.02)), denim)
            stitchLine(P(0, waistY + 0.02), P(0, rig.bodyBottom), clip: o, denim)
            // Straps over the shoulders.
            for side in [-1.0, 1.0] as [CGFloat] {
                var strap = Path()
                strap.move(to: P(side * bibHalf * 0.8, bibTop + 0.02))
                strap.addQuadCurve(to: P(side * (shoulderHalf - 0.02), rig.neckY - 0.04), control: P(side * shoulderHalf * 0.8, bibTop))
                var g2 = g; g2.clip(to: inflated(1.04))
                g2.stroke(strap, with: .color(denim.ink), style: StrokeStyle(lineWidth: L(0.05) + stroke, lineCap: .round))
                g2.stroke(strap, with: .color(denim.base), style: StrokeStyle(lineWidth: L(0.05), lineCap: .round))
                MascotArt(g: g2, u: 1, stroke: stroke).gem(P(side * bibHalf * 0.75, bibTop + 0.035), L(0.022), Color(red: 1, green: 0.8, blue: 0.35), sparkle: 0.4)
            }
            let pk = Path(roundedRect: R(-bibHalf * 0.55, bibTop + 0.06, bibHalf * 1.1, 0.08), cornerRadius: L(0.015))
            fa.g.stroke(pk, with: .color(denim.ink.opacity(0.7)), lineWidth: stroke * 0.7)
        case "flannel":
            sleeves(w, length: 0.2, cuff: w.dark, pattern: .plaid)
            let p = garment(hem: hipHem + 0.02)
            base(p)
            collar(w, style: .pointed)
            placket(w, from: rig.neckY + 0.04, to: hipHem)
        case "turtleneck":
            sleeves(w, length: 0.21, cuff: w.dark)
            let p = garment(hem: fullHem, extra: -0.004, dip: 0.0)
            base(p)
            let c = necklineCurve(0.02, dip: 0.0)
            var g2 = g; g2.clip(to: inflated(1.05))
            g2.stroke(c, with: .color(w.ink), style: StrokeStyle(lineWidth: L(0.07) + stroke, lineCap: .round))
            g2.stroke(c, with: .linearGradient(Gradient(colors: [w.light, w.dark]), startPoint: P(0, rig.neckY - 0.02), endPoint: P(0, rig.neckY + 0.06)), style: StrokeStyle(lineWidth: L(0.07), lineCap: .round))
            var x: CGFloat = -0.4
            while x < 0.4 { fa.line(P(x, rig.neckY + 0.05), P(x, fullHem - 0.03), w.dark.opacity(0.35), width: 0.5); x += 0.05 }
        case "sailortop":
            let navy = MascotSwatch(it.dyes.count > 1 ? it.dyes[1] : Color(red: 0.2, green: 0.28, blue: 0.55))
            sleeves(w, length: 0.13, width: 0.15, cuff: navy.base)
            let p = garment(hem: hipHem, dip: 0.07)
            base(p)
            var col = Path()
            col.move(to: P(-shoulderHalf, rig.neckY - 0.02))
            col.addLine(to: P(0, rig.neckY + 0.14))
            col.addLine(to: P(shoulderHalf, rig.neckY - 0.02))
            col.addLine(to: P(shoulderHalf, rig.neckY + 0.06))
            col.addLine(to: P(0, rig.neckY + 0.2))
            col.addLine(to: P(-shoulderHalf, rig.neckY + 0.06))
            col.closeSubpath()
            let cp = col.meet(p)
            fa.solid(cp, navy, gloss: 0.2)
            fa.stitch(cp, navy, opacity: 0.9)
            let red = MascotSwatch(Color(red: 0.88, green: 0.2, blue: 0.24))
            var knot = Path()
            knot.move(to: P(-0.04, rig.neckY + 0.16))
            knot.addLine(to: P(0.04, rig.neckY + 0.16))
            knot.addLine(to: P(0.07, rig.neckY + 0.27))
            knot.addLine(to: P(0, rig.neckY + 0.22))
            knot.addLine(to: P(-0.07, rig.neckY + 0.27))
            knot.closeSubpath()
            fa.solid(knot.meet(inflated(1.06)), red, gloss: 0.3)
        case "islandshirt":
            sleeves(w, length: 0.13, width: 0.16, pattern: .floral)
            let p = garment(hem: hipHem + 0.02, dip: 0.08)
            base(p)
            collar(w, style: .open)
            placket(w, from: rig.neckY + 0.1, to: hipHem)
        case "tux":
            let jacket = MascotSwatch(Color(red: 0.1, green: 0.1, blue: 0.13))
            sleeves(jacket, length: 0.21, cuff: .white)
            let p = garment(hem: fullHem)
            fa.solid(p, jacket, gloss: 0.3)
            let shirt = p.meet(Path(R(-0.11, -1, 0.22, 3)))
            fa.solid(shirt, w, gloss: 0.2, outline: false)
            var x: CGFloat = -0.08
            while x <= 0.08 { fa.line(P(x, rig.neckY + 0.06), P(x, fullHem - 0.02), Color.black.opacity(0.12), width: 0.5); x += 0.04 }
            lapels(jacket, satin: true)
            bowTie(MascotSwatch(Color(red: 0.08, green: 0.08, blue: 0.1)), at: rig.neckY + 0.04, scale: 0.9)
            for y in [rig.neckY + 0.12, rig.neckY + 0.18] { fa.dot(P(0, y), L(0.011), .black) }
        case "robe":
            sleeves(w, length: 0.2, width: 0.17, cuff: w.dark, pattern: it.pattern)
            let p = garment(hem: fullHem + 0.02, dip: 0.08)
            base(p)
            var wrap = Path()
            wrap.move(to: P(-shoulderHalf * 0.7, rig.neckY))
            wrap.addQuadCurve(to: P(shoulderHalf * 0.9, waistY + 0.02), control: P(0.02, rig.neckY + 0.12))
            var g2 = g; g2.clip(to: p)
            g2.stroke(wrap, with: .color(w.ink), lineWidth: L(0.04) + stroke)
            g2.stroke(wrap, with: .color(w.lighter), lineWidth: L(0.04))
            let sash = Path(R(-0.6, waistY - 0.02, 1.2, 0.05)).meet(inflated(1.05))
            fa.solid(sash, MascotSwatch(w.base.mix(with: Color(red: 1, green: 0.8, blue: 0.3), by: 0.6)), gloss: 0.3)
            fa.dot(P(0.12, waistY + 0.005), L(0.03), w.dark, outline: w.ink)
        case "armor":
            let steel = w
            let gold = MascotSwatch(it.dyes.count > 1 ? it.dyes[1] : Color(red: 1, green: 0.8, blue: 0.35))
            sleeves(steel, length: 0.18, width: 0.15, cuff: gold.base)
            let p = garment(hem: fullHem)
            fa.metal(p, steel)
            var g2 = g; g2.clip(to: p)
            var y = rig.neckY + 0.08
            while y < fullHem {
                var plate = Path()
                plate.move(to: P(-0.6, y))
                plate.addQuadCurve(to: P(0.6, y), control: P(0, y + 0.04))
                g2.stroke(plate, with: .color(steel.ink.opacity(0.7)), lineWidth: stroke)
                g2.stroke(plate.offsetBy(dx: 0, dy: -stroke), with: .color(.white.opacity(0.5)), lineWidth: stroke * 0.6)
                y += 0.075
            }
            let gorget = necklineCurve(0.012, dip: 0.03)
            var g3 = g; g3.clip(to: inflated(1.05))
            g3.stroke(gorget, with: .color(gold.ink), lineWidth: L(0.04) + stroke)
            g3.stroke(gorget, with: .linearGradient(Gradient(colors: [gold.lighter, gold.base, gold.dark]), startPoint: P(-0.3, 0), endPoint: P(0.3, 0)), lineWidth: L(0.04))
            for x in [-0.2, 0.2] as [CGFloat] { fa.gem(P(x, rig.neckY + 0.1), L(0.016), gold.base, sparkle: 0.5) }
            MascotArt(g: g2, u: 1, stroke: stroke).gem(P(0, (rig.neckY + fullHem) / 2), L(0.04), Color(red: 0.9, green: 0.2, blue: 0.3))
        case "herosuit":
            sleeves(w, length: 0.2, cuff: w.dark)
            let p = garment(hem: fullHem)
            base(p, gloss: 0.5)
            let ey = (rig.neckY + waistY) / 2
            let shield = MascotShapes.star(center: P(0, ey), outer: L(0.075), inner: L(0.034))
            let disc = Path(ellipseIn: R(-0.1, ey - 0.085, 0.2, 0.17))
            fa.solid(disc, MascotSwatch(Color(red: 1, green: 0.85, blue: 0.3)), gloss: 0.5)
            fa.solid(shield, MascotSwatch(Color(red: 0.9, green: 0.2, blue: 0.25)), gloss: 0.4)
            let belt = Path(R(-0.7, waistY, 1.4, 0.045)).meet(inflated(1.05))
            fa.solid(belt, MascotSwatch(Color(red: 1, green: 0.8, blue: 0.3)), gloss: 0.5)
            fa.metal(Path(roundedRect: R(-0.04, waistY - 0.008, 0.08, 0.06), cornerRadius: L(0.01)), MascotSwatch(Color(red: 1, green: 0.85, blue: 0.4)))
        case "dresstop":
            let p = garment(hem: waistY + 0.02, dip: 0.06)
            base(p, gloss: 0.4)
            collarTrim(w.lighter, width: 0.02, dip: 0.06)
            skirt(e, w, flare: 1.18, pleats: false, ruffles: 1)
            let belt = Path(R(-0.7, waistY - 0.015, 1.4, 0.04)).meet(inflated(1.06))
            fa.solid(belt, MascotSwatch(w.dark), gloss: 0.5)
            for i in -2...2 { fa.gem(P(CGFloat(i) * 0.06, waistY + 0.005), L(0.012), Color(red: 1, green: 0.9, blue: 0.6), sparkle: i == 0 ? 0.6 : 0) }
        case "spacesuit":
            let accent = MascotSwatch(it.dyes.count > 1 ? it.dyes[1] : Color(red: 0.98, green: 0.6, blue: 0.25))
            sleeves(w, length: 0.21, width: 0.16, cuff: accent.base)
            let p = garment(hem: fullHem)
            base(p, gloss: 0.5)
            hemBand(fullHem - 0.01, accent.base, p)
            let collarRing = necklineCurve(0.01, dip: 0.03)
            var g2 = g; g2.clip(to: inflated(1.06))
            g2.stroke(collarRing, with: .color(w.ink), lineWidth: L(0.05) + stroke)
            g2.stroke(collarRing, with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.6)]), startPoint: P(0, rig.neckY - 0.03), endPoint: P(0, rig.neckY + 0.05)), lineWidth: L(0.05))
            let py = (rig.neckY + waistY) / 2
            let panel = Path(roundedRect: R(-0.11, py - 0.04, 0.22, 0.1), cornerRadius: L(0.02))
            fa.solid(panel, MascotSwatch(Color(white: 0.45)), gloss: 0.3)
            let lights: [Color] = [.red, .green, .yellow]
            for (i, c) in lights.enumerated() {
                let blink = amp > 0 ? (0.6 + 0.4 * sin(t * 4 + Double(i) * 2)) : 1
                fa.dot(P(-0.06 + CGFloat(i) * 0.06, py + 0.01), L(0.017), c.opacity(blink), outline: .black.opacity(0.4))
            }
            fa.dot(P(-0.2, rig.neckY + 0.09), L(0.03), accent.base, outline: accent.ink)
        default:
            let p = garment(hem: hipHem)
            base(p)
        }
    }

    func stitchLine(_ a: CGPoint, _ b: CGPoint, clip: Path, _ w: MascotSwatch) {
        var g = faceSafe()
        g.clip(to: clip)
        var p = Path(); p.move(to: a); p.addLine(to: b)
        MascotArt(g: g, u: 1, stroke: stroke).stitch(p, w)
    }

    enum CollarStyle { case pointed, open }

    func collar(_ w: MascotSwatch, style: CollarStyle) {
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        let ny = rig.neckY
        for side in [-1.0, 1.0] as [CGFloat] {
            var p = Path()
            p.move(to: P(side * 0.02, ny + 0.02))
            p.addLine(to: P(side * min(0.2, shoulderHalf * 0.7), ny - 0.025))
            p.addLine(to: P(side * (style == .open ? 0.16 : 0.12), ny + (style == .open ? 0.12 : 0.09)))
            p.closeSubpath()
            a.solid(p.meet(inflated(1.06)), MascotSwatch(w.light), gloss: 0.3)
        }
    }

    func placket(_ w: MascotSwatch, from y0: CGFloat, to y1: CGFloat) {
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        a.line(P(0, y0), P(0, y1), w.ink.opacity(0.6), width: 0.8)
        var y = y0 + 0.03
        while y < y1 - 0.02 { a.button(P(0.018, y), L(0.012), w); y += 0.055 }
    }

    func lapels(_ w: MascotSwatch, satin: Bool = false) {
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        let ny = rig.neckY
        for side in [-1.0, 1.0] as [CGFloat] {
            var p = Path()
            p.move(to: P(side * 0.1, ny + 0.01))
            p.addLine(to: P(side * min(0.24, shoulderHalf * 0.8), ny - 0.02))
            p.addLine(to: P(side * 0.2, ny + 0.06))
            p.addLine(to: P(side * 0.11, ny + 0.2))
            p.closeSubpath()
            let lp = p.meet(inflated(1.06))
            if satin { a.metal(lp, MascotSwatch(w.base.lighter(0.12))) } else { a.solid(lp, MascotSwatch(w.light), gloss: 0.25) }
        }
    }

    func bowTie(_ w: MascotSwatch, at y: CGFloat, scale k: CGFloat = 1) {
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        let flutter = CGFloat(amp > 0 ? 0.006 * sin(t * 5) : 0)
        for side in [-1.0, 1.0] as [CGFloat] {
            var p = Path()
            p.move(to: P(0, y))
            p.addQuadCurve(to: P(side * 0.1 * k, y - 0.045 * k - flutter), control: P(side * 0.05 * k, y - 0.05 * k))
            p.addQuadCurve(to: P(side * 0.1 * k, y + 0.045 * k + flutter), control: P(side * 0.13 * k, y))
            p.addQuadCurve(to: P(0, y), control: P(side * 0.05 * k, y + 0.05 * k))
            p.closeSubpath()
            a.solid(p, w, gloss: 0.4)
        }
        a.solid(Path(roundedRect: R(-0.022 * k, y - 0.028 * k, 0.044 * k, 0.056 * k), cornerRadius: L(0.012 * k)), MascotSwatch(w.dark), gloss: 0.3)
    }

    // MARK: Outerwear

    func outer(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let it = e.item
        let g = faceSafe()
        let fa = MascotArt(g: g, u: 1, stroke: stroke)
        let fullHem = rig.bodyBottom + 0.035
        let longHem = rig.bodyBottom + 0.09
        func panels(gap: CGFloat, hem: CGFloat, inflate: CGFloat = 1.06) -> Path {
            let core = inflated(inflate).meet(belowNeck(-0.006, dip: 0.04)).meet(columns(gap))
            guard hem > rig.bodyBottom + 0.04 else { return core.meet(above(hem)) }
            // Long coats continue past the body as a straight skirt.
            let skirtTop = max(waistY, rig.bodyBottom - 0.16)
            let ext = Path(roundedRect: R(-rig.bodyW * 0.46, skirtTop, rig.bodyW * 0.92, hem - skirtTop), cornerRadius: L(0.05)).meet(columns(gap))
            return core.join(ext)
        }
        switch it.style {
        case "cardigan":
            sleeves(w, length: 0.22, width: 0.15, cuff: w.dark, pattern: .knit)
            let p = panels(gap: 0.06, hem: fullHem)
            fa.solid(p, w, gloss: 0.3); fa.pattern(p, .knit, w, scale: L(0.1))
            for side in [-1.0, 1.0] as [CGFloat] {
                var y = rig.neckY + 0.07
                while y < fullHem - 0.04 { fa.button(P(side * 0.075, y), L(0.014), MascotSwatch(Color(red: 0.6, green: 0.42, blue: 0.26))); y += 0.07 }
            }
        case "vest", "puffer":
            if it.style == "puffer" { sleeves(w, length: 0.22, width: 0.18, cuff: w.dark) }
            let p = panels(gap: 0, hem: fullHem, inflate: 1.08)
            fa.solid(p, w, gloss: 0.55)
            var g2 = g; g2.clip(to: p)
            var y = rig.neckY + 0.08
            while y < fullHem {
                var q = Path()
                q.move(to: P(-0.7, y)); q.addQuadCurve(to: P(0.7, y), control: P(0, y + 0.035))
                g2.stroke(q, with: .color(w.deep.opacity(0.55)), lineWidth: stroke * 1.2)
                g2.stroke(q.offsetBy(dx: 0, dy: -L(0.012)), with: .color(w.lighter.opacity(0.5)), lineWidth: stroke * 0.8)
                y += 0.07
            }
            fa.line(P(0, rig.neckY + 0.03), P(0, fullHem), w.ink, width: 1.2)
            fa.metal(Path(roundedRect: R(-0.014, rig.neckY + 0.04, 0.028, 0.05), cornerRadius: L(0.008)), MascotSwatch(Color(white: 0.8)))
        case "raincoat":
            sleeves(w, length: 0.22, width: 0.17, cuff: w.dark)
            let p = panels(gap: 0, hem: longHem)
            fa.solid(p, w, gloss: 0.75)
            for i in 0..<3 {
                let y = rig.neckY + 0.07 + CGFloat(i) * 0.07
                fa.solid(Path(roundedRect: R(-0.03, y, 0.06, 0.022), cornerRadius: L(0.011)), MascotSwatch(Color(white: 0.95)), gloss: 0.3)
            }
            collar(w, style: .pointed)
        case "denim":
            sleeves(w, length: 0.22, width: 0.16, cuff: w.dark)
            let p = panels(gap: 0.07, hem: fullHem)
            fa.solid(p, w, gloss: 0.3)
            fa.stitch(p, MascotSwatch(Color(red: 0.95, green: 0.75, blue: 0.4)), opacity: 0.9)
            for side in [-1.0, 1.0] as [CGFloat] {
                let flap = Path(roundedRect: R(side > 0 ? 0.1 : -0.22, rig.neckY + 0.08, 0.12, 0.05), cornerRadius: L(0.01)).meet(p)
                fa.solid(flap, MascotSwatch(w.dark), gloss: 0.2)
                fa.button(P(side * 0.16, rig.neckY + 0.11), L(0.01), MascotSwatch(Color(red: 0.85, green: 0.65, blue: 0.3)))
            }
            collar(w, style: .pointed)
        case "blazer", "trench", "labcoat":
            let hem = it.style == "blazer" ? fullHem : longHem
            sleeves(w, length: 0.22, width: 0.16, cuff: it.style == "labcoat" ? nil : w.dark)
            let p = panels(gap: it.style == "trench" ? 0.02 : 0.08, hem: hem)
            fa.solid(p, w, gloss: 0.35)
            lapels(w)
            if it.style == "blazer" {
                var sq = Path()
                sq.move(to: P(-0.22, rig.neckY + 0.12)); sq.addLine(to: P(-0.18, rig.neckY + 0.08)); sq.addLine(to: P(-0.14, rig.neckY + 0.12)); sq.closeSubpath()
                fa.solid(sq, MascotSwatch(.white), gloss: 0.2)
                fa.button(P(0.085, waistY - 0.02), L(0.014), MascotSwatch(w.dark))
            } else if it.style == "trench" {
                for side in [-1.0, 1.0] as [CGFloat] {
                    for i in 0..<2 { fa.button(P(side * 0.07, rig.neckY + 0.12 + CGFloat(i) * 0.08), L(0.013), MascotSwatch(w.dark)) }
                }
                let belt = Path(R(-0.8, waistY - 0.01, 1.6, 0.045)).meet(inflated(1.08))
                fa.solid(belt, MascotSwatch(w.dark), gloss: 0.3)
                fa.metal(Path(roundedRect: R(-0.035, waistY - 0.015, 0.07, 0.055), cornerRadius: L(0.008)), MascotSwatch(Color(red: 0.9, green: 0.8, blue: 0.5)))
            } else {
                let pocket = Path(roundedRect: R(-0.23, rig.neckY + 0.1, 0.1, 0.07), cornerRadius: L(0.01))
                fa.g.stroke(pocket, with: .color(w.ink.opacity(0.6)), lineWidth: stroke * 0.8)
                fa.line(P(-0.2, rig.neckY + 0.06), P(-0.2, rig.neckY + 0.12), Color(red: 0.2, green: 0.4, blue: 0.9), width: 1.6)
            }
        case "leather":
            sleeves(w, length: 0.22, width: 0.16, cuff: w.dark)
            let p = panels(gap: 0.03, hem: fullHem)
            fa.solid(p, w, gloss: 0.8)
            lapels(w, satin: false)
            var zip = Path()
            zip.move(to: P(0.12, rig.neckY + 0.04)); zip.addLine(to: P(0.04, fullHem - 0.02))
            fa.g.stroke(zip, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: stroke * 1.2, dash: [stroke, stroke * 0.6]))
            for side in [-1.0, 1.0] as [CGFloat] { fa.dot(P(side * 0.22, rig.neckY + 0.02), L(0.012), Color(white: 0.85), outline: .black) }
        case "varsity":
            sleeves(MascotSwatch(Color(white: 0.96)), length: 0.22, width: 0.16, cuff: w.dark)
            let p = panels(gap: 0.05, hem: fullHem)
            fa.solid(p, w, gloss: 0.35)
            var g2 = g; g2.clip(to: p)
            g2.fill(Path(R(-1, fullHem - 0.05, 2, 0.05)), with: .color(Color(white: 0.96)))
            g.draw(Text("M").font(.system(size: L(0.13), weight: .black, design: .serif)).foregroundStyle(Color(white: 0.97)), at: P(-0.17, rig.neckY + 0.12))
            for side in [-1.0, 1.0] as [CGFloat] {
                var y = rig.neckY + 0.07
                while y < fullHem - 0.06 { fa.button(P(side * 0.065, y), L(0.012), MascotSwatch(Color(white: 0.95))); y += 0.06 }
            }
        case "royalrobe":
            sleeves(w, length: 0.22, width: 0.18, cuff: .white)
            let p = panels(gap: 0.06, hem: longHem, inflate: 1.08)
            fa.solid(p, w, gloss: 0.4)
            ermine(along: p, width: 0.05)
            fa.gem(P(0, rig.neckY + 0.05), L(0.03), Color(red: 1, green: 0.8, blue: 0.3))
        case "tabard":
            let p = inflated(1.07).meet(belowNeck(-0.004, dip: 0.04)).meet(Path(R(-0.2, -1, 0.4, 3))).meet(above(longHem))
                .join(Path(roundedRect: R(-0.2, rig.bodyBottom - 0.1, 0.4, longHem - rig.bodyBottom + 0.1), cornerRadius: L(0.02)))
            fa.solid(p, w, gloss: 0.3)
            fa.stitch(p, MascotSwatch(Color(red: 1, green: 0.85, blue: 0.4)), opacity: 1)
            let cy0 = (rig.neckY + waistY) / 2
            let cross = Path(R(-0.018, cy0 - 0.07, 0.036, 0.14)).join(Path(R(-0.06, cy0 - 0.03, 0.12, 0.036)))
            fa.solid(cross, MascotSwatch(Color(red: 1, green: 0.85, blue: 0.35)), gloss: 0.6)
            let belt = Path(R(-0.8, waistY + 0.02, 1.6, 0.04)).meet(inflated(1.08))
            fa.solid(belt, MascotSwatch(Color(red: 0.4, green: 0.26, blue: 0.16)), gloss: 0.2)
        default:
            let p = panels(gap: 0.06, hem: fullHem)
            fa.solid(p, w)
        }
    }

    func ermine(along p: Path, width: CGFloat) {
        var g = faceSafe()
        g.clip(to: p)
        let fur = MascotSwatch(Color(white: 0.98))
        g.stroke(p, with: .color(fur.base), lineWidth: L(width) * 2)
        let r = p.boundingRect
        var y = r.minY
        var row = 0
        while y < r.maxY {
            var x = r.minX + (row % 2 == 0 ? 0 : L(0.04))
            while x < r.maxX {
                g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: L(0.012), height: L(0.024))), with: .color(.black.opacity(0.75)))
                x += L(0.08)
            }
            y += L(0.06); row += 1
        }
        g.stroke(p, with: .color(fur.ink.opacity(0.4)), lineWidth: stroke)
    }

    // MARK: Bottoms

    func skirt(_ e: MascotWearList.Entry, _ w: MascotSwatch, flare: CGFloat, pleats: Bool, ruffles: Int, top: CGFloat? = nil) {
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        let y0 = top ?? waistY
        let hem = rig.bodyBottom + 0.07 + (rig.floats ? 0.02 : 0)
        let topHalf = max(0.18, rig.chord(at: y0) / 2 + 0.02)
        let hemHalf = max(topHalf + 0.06, rig.bodyW / 2 * flare)
        let sw = CGFloat(amp > 0 ? 0.015 * sin(t * 3) : 0)
        var p = Path()
        p.move(to: P(-topHalf, y0))
        p.addLine(to: P(topHalf, y0))
        p.addQuadCurve(to: P(hemHalf + sw, hem), control: P(topHalf + (hemHalf - topHalf) * 0.3, (y0 + hem) / 2))
        let n = 6
        for i in 0..<n {
            let x0 = hemHalf - CGFloat(i) * hemHalf * 2 / CGFloat(n)
            let x1 = x0 - hemHalf * 2 / CGFloat(n)
            p.addQuadCurve(to: P(x1 + sw, hem), control: P((x0 + x1) / 2 + sw, hem + (ruffles > 0 ? 0.035 : 0.012)))
        }
        p.addQuadCurve(to: P(-topHalf, y0), control: P(-topHalf - (hemHalf - topHalf) * 0.3, (y0 + hem) / 2))
        p.closeSubpath()
        a.solid(p, w, gloss: 0.35)
        a.pattern(p, e.item.pattern, w, scale: L(0.1))
        if pleats {
            for i in 1..<n {
                let fx = -1 + 2 * CGFloat(i) / CGFloat(n)
                a.line(P(fx * topHalf * 0.9, y0 + 0.02), P(fx * hemHalf * 0.95 + sw, hem - 0.01), w.deep.opacity(0.5), width: 0.7)
            }
        }
        if ruffles > 1 {
            var r = Path()
            r.move(to: P(-hemHalf, hem - 0.03))
            for i in 0..<(n * 2) {
                let x0 = -hemHalf + CGFloat(i) * hemHalf / CGFloat(n)
                r.addQuadCurve(to: P(x0 + hemHalf / CGFloat(n), hem - 0.03), control: P(x0 + hemHalf / CGFloat(n) / 2, hem - 0.005))
            }
            a.g.stroke(r, with: .color(w.lighter.opacity(0.9)), lineWidth: stroke * 1.2)
        }
        let band = Path(roundedRect: R(-topHalf, y0 - 0.012, topHalf * 2, 0.035), cornerRadius: L(0.012))
        a.solid(band, MascotSwatch(w.dark), gloss: 0.3)
    }

    func bottom(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let style = e.item.style
        // Mascots without legs wear any bottom as a frilly skirt.
        if !rig.hasLegs && ["shorts", "jeans", "cargo"].contains(style) {
            skirt(e, w, flare: 1.12, pleats: false, ruffles: 2)
            return
        }
        let a = MascotArt(g: faceSafe(), u: 1, stroke: stroke)
        switch style {
        case "skirt": skirt(e, w, flare: 1.14, pleats: false, ruffles: 0)
        case "pleated": skirt(e, w, flare: 1.12, pleats: true, ruffles: 0)
        case "tutu", "sparkleskirt", "petalskirt":
            for layer in 0..<3 {
                let c = MascotSwatch(w.base.lighter(Double(layer) * 0.12))
                var g2 = a.g
                g2.opacity = style == "tutu" ? 0.78 : 1
                let la = MascotArt(g: g2, u: 1, stroke: stroke)
                let y0 = waistY + CGFloat(layer) * 0.015
                let hem = rig.bodyBottom + 0.02 + CGFloat(2 - layer) * 0.025
                let half = rig.bodyW / 2 * (1.08 + CGFloat(2 - layer) * 0.06)
                var p = Path()
                p.move(to: P(-half * 0.8, y0))
                p.addLine(to: P(half * 0.8, y0))
                p.addLine(to: P(half, hem - 0.03))
                let n = 9
                for i in 0..<n {
                    let x0 = half - CGFloat(i) * half * 2 / CGFloat(n)
                    let x1 = x0 - half * 2 / CGFloat(n)
                    if style == "petalskirt" {
                        p.addQuadCurve(to: P(x1, hem - 0.03), control: P((x0 + x1) / 2, hem + 0.05))
                    } else {
                        p.addQuadCurve(to: P(x1, hem - 0.03), control: P((x0 + x1) / 2, hem + 0.03))
                    }
                }
                p.closeSubpath()
                if style == "sparkleskirt" { la.metal(p, c, outline: layer == 2) } else { la.solid(p, c, gloss: 0.3, outline: layer == 2) }
            }
            if style == "sparkleskirt" && amp > 0 {
                for i in 0..<4 {
                    let ph = t * 2 + Double(i) * 1.7
                    if sin(ph) > 0.6 { a.twinkle(P(CGFloat(i) * 0.14 - 0.2, rig.bodyBottom - 0.02 + CGFloat(i % 2) * 0.04), L(0.025)) }
                }
            }
            a.solid(Path(roundedRect: R(-rig.bodyW * 0.38, waistY - 0.012, rig.bodyW * 0.76, 0.03), cornerRadius: L(0.012)), MascotSwatch(w.dark), gloss: 0.3)
        default:
            // Shorts / jeans / cargo on legged mascots.
            let body = inflated(1.04).meet(below(waistY))
            let legLen: CGFloat = style == "jeans" ? 0.1 : 0.05
            var legs = Path()
            for side in [-1.0, 1.0] as [CGFloat] {
                legs.addRoundedRect(in: R(side * 0.17 - 0.11, rig.bodyBottom - 0.08, 0.22, 0.08 + legLen), cornerSize: CGSize(width: L(0.05), height: L(0.05)))
            }
            let p = body.join(legs)
            a.solid(p, w, gloss: 0.3)
            a.pattern(p, e.item.pattern, w, scale: L(0.1))
            a.line(P(0, waistY + 0.03), P(0, rig.bodyBottom + 0.01), w.ink.opacity(0.7), width: 0.8)
            let bandP = Path(R(-1, waistY - 0.005, 2, 0.04)).meet(inflated(1.05))
            a.solid(bandP, MascotSwatch(w.dark), gloss: 0.2)
            for x in [-0.16, 0.0, 0.16] as [CGFloat] { a.line(P(x, waistY - 0.005), P(x, waistY + 0.035), w.ink.opacity(0.7), width: 0.7) }
            if style == "jeans" || style == "cargo" { a.stitch(p, MascotSwatch(Color(red: 0.95, green: 0.75, blue: 0.4)), opacity: 0.9) }
            if style == "cargo" {
                for side in [-1.0, 1.0] as [CGFloat] {
                    let pk = Path(roundedRect: R(side * 0.24 - 0.05, rig.bodyBottom - 0.1, 0.1, 0.08), cornerRadius: L(0.012)).meet(p)
                    a.solid(pk, MascotSwatch(w.dark), gloss: 0.15)
                }
            }
            for side in [-1.0, 1.0] as [CGFloat] {
                let cuffY = rig.bodyBottom + legLen - 0.03
                a.solid(Path(roundedRect: R(side * 0.17 - 0.11, cuffY, 0.22, 0.03), cornerRadius: L(0.012)), MascotSwatch(w.dark), gloss: 0.2)
            }
        }
    }

    // MARK: Shoes

    func shoes(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let style = e.item.style
        let y = rig.footY - 0.02
        let spread = max(0.15, min(0.24, rig.bodyW * 0.22))
        let tap = CGFloat(mood == .dance && amp > 0 ? 0.03 * max(0, sin(t * 12)) : 0)
        for side in [-1.0, 1.0] as [CGFloat] {
            let lift = side > 0 ? tap : 0
            let a = local(CGPoint(x: side * spread, y: y - lift), unit: 0.25, flip: side < 0, clipFace: false)
            // Local frame: shoe spans x -0.5…0.6, sole at y 0.22, toe to the outside.
            var shoe = Path()
            shoe.move(to: CGPoint(x: -0.45, y: 0.22))
            shoe.addLine(to: CGPoint(x: -0.45, y: -0.12))
            shoe.addQuadCurve(to: CGPoint(x: 0.05, y: -0.22), control: CGPoint(x: -0.3, y: -0.3))
            shoe.addQuadCurve(to: CGPoint(x: 0.6, y: 0.08), control: CGPoint(x: 0.55, y: -0.18))
            shoe.addQuadCurve(to: CGPoint(x: 0.5, y: 0.22), control: CGPoint(x: 0.65, y: 0.22))
            shoe.closeSubpath()
            let sole = Path(roundedRect: CGRect(x: -0.5, y: 0.14, width: 1.15, height: 0.14), cornerRadius: 0.07)
            switch style {
            case "sneakers", "lightup":
                a.solid(shoe, w, gloss: 0.5)
                a.solid(sole, MascotSwatch(style == "lightup" ? Color(hue: (t * 0.3).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1) : .white), gloss: 0.3)
                for i in 0..<3 { a.line(CGPoint(x: -0.15 + CGFloat(i) * 0.12, y: -0.17), CGPoint(x: -0.05 + CGFloat(i) * 0.12, y: -0.05), .white, width: 1) }
                a.dot(CGPoint(x: 0.3, y: 0.02), 0.06, w.lighter)
            case "rainboots", "boots":
                var boot = shoe
                boot.addRoundedRect(in: CGRect(x: -0.45, y: -0.5, width: 0.55, height: 0.5), cornerSize: CGSize(width: 0.08, height: 0.08))
                a.solid(boot, w, gloss: style == "rainboots" ? 0.8 : 0.3)
                a.solid(sole, MascotSwatch(style == "boots" ? Color(white: 0.2) : w.dark), gloss: 0.2)
                if style == "boots" { for i in 0..<3 { a.line(CGPoint(x: -0.3, y: -0.38 + CGFloat(i) * 0.12), CGPoint(x: -0.02, y: -0.32 + CGFloat(i) * 0.12), Color(red: 0.85, green: 0.2, blue: 0.2), width: 1) } }
            case "slippers":
                let fluffy = Path(ellipseIn: CGRect(x: -0.5, y: -0.25, width: 1.1, height: 0.5))
                a.solid(fluffy, w, gloss: 0.4)
                for ex in [-0.05, 0.18] as [CGFloat] {
                    let ear = Path(ellipseIn: CGRect(x: ex, y: -0.6, width: 0.14, height: 0.42))
                    a.solid(ear, w, gloss: 0.3)
                    a.g.fill(Path(ellipseIn: CGRect(x: ex + 0.035, y: -0.52, width: 0.07, height: 0.28)), with: .color(Color(red: 1, green: 0.7, blue: 0.78)))
                }
                a.dot(CGPoint(x: 0.42, y: -0.02), 0.04, .black)
            case "rollers":
                a.solid(shoe, w, gloss: 0.5)
                a.solid(Path(roundedRect: CGRect(x: -0.5, y: 0.15, width: 1.12, height: 0.1), cornerRadius: 0.04), MascotSwatch(Color(white: 0.85)))
                let spin = amp > 0 ? t * 6 : 0
                for (i, wx) in ([-0.3, 0.4] as [CGFloat]).enumerated() {
                    a.dot(CGPoint(x: wx, y: 0.34), 0.11, Color(hue: Double(i) * 0.3 + 0.55, saturation: 0.8, brightness: 1), outline: .black.opacity(0.6))
                    a.line(CGPoint(x: wx + cos(spin) * 0.08, y: 0.34 + sin(spin) * 0.08), CGPoint(x: wx - cos(spin) * 0.08, y: 0.34 - sin(spin) * 0.08), .white, width: 0.8)
                }
            case "rocketboots":
                a.metal(shoe, w)
                a.solid(sole, MascotSwatch(Color(red: 0.95, green: 0.35, blue: 0.35)), gloss: 0.3)
                let flick = amp > 0 ? 0.12 * sin(t * 30) : 0
                var flame = Path()
                flame.move(to: CGPoint(x: -0.25, y: 0.28))
                flame.addQuadCurve(to: CGPoint(x: 0, y: 0.75 + flick), control: CGPoint(x: -0.25, y: 0.55))
                flame.addQuadCurve(to: CGPoint(x: 0.25, y: 0.28), control: CGPoint(x: 0.25, y: 0.55))
                a.g.fill(flame, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.45, blue: 0.1), .clear]), startPoint: CGPoint(x: 0, y: 0.28), endPoint: CGPoint(x: 0, y: 0.8)))
            case "crystal":
                var g2 = a.g
                g2.opacity = 0.85
                MascotArt(g: g2, u: a.u, stroke: stroke).solid(shoe, w, gloss: 0.9)
                a.solid(sole, MascotSwatch(w.lighter), gloss: 0.5)
                a.twinkle(CGPoint(x: 0.2, y: -0.12), 0.12)
            default:
                a.solid(shoe, w)
            }
        }
    }

    // MARK: Neckwear

    func neck(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let g = faceSafe()
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        let ny = rig.neckY + 0.02
        let chestY = min(rig.neckY + 0.14, (rig.neckY + rig.bodyBottom) / 2)
        let chestX = -min(0.2, rig.chord(at: chestY) * 0.28)
        switch e.item.style {
        case "scarf", "winterscarf":
            let c = necklineCurve(0.015, dip: 0.035, widen: 0.02)
            var g2 = g; g2.clip(to: inflated(1.12))
            g2.stroke(c, with: .color(w.ink), style: StrokeStyle(lineWidth: L(0.075) + stroke * 2, lineCap: .round))
            g2.stroke(c, with: .linearGradient(Gradient(colors: [w.light, w.base, w.dark]), startPoint: P(0, rig.neckY - 0.03), endPoint: P(0, rig.neckY + 0.08)), style: StrokeStyle(lineWidth: L(0.075), lineCap: .round))
            var stripes = g2
            stripes.clip(to: c.strokedPath(StrokeStyle(lineWidth: L(0.075), lineCap: .round)))
            var x: CGFloat = -0.5
            while x < 0.5 { stripes.fill(Path(R(x, -1, 0.03, 2)), with: .color(w.lighter.opacity(0.7))); x += 0.09 }
            // Hanging tail that flutters.
            let flutter = CGFloat(amp > 0 ? 0.02 * sin(t * 4) : 0)
            var tail = Path()
            tail.move(to: P(0.1, ny + 0.02))
            tail.addLine(to: P(0.19, ny + 0.02))
            tail.addQuadCurve(to: P(0.22 + flutter, ny + 0.2), control: P(0.22, ny + 0.1))
            tail.addLine(to: P(0.13 + flutter, ny + 0.2))
            tail.addQuadCurve(to: P(0.1, ny + 0.02), control: P(0.12, ny + 0.1))
            a.solid(tail, w, gloss: 0.3)
            a.pattern(tail, .stripes, w, scale: L(0.08))
            for i in 0..<4 { a.line(P(0.135 + CGFloat(i) * 0.025 + flutter, ny + 0.2), P(0.135 + CGFloat(i) * 0.025 + flutter, ny + 0.235), w.dark, width: 1) }
        case "bowtie":
            bowTie(w, at: ny + 0.015)
        case "pendant", "amulet":
            var chain = Path()
            chain.move(to: P(-0.17, ny - 0.03))
            chain.addQuadCurve(to: P(0.17, ny - 0.03), control: P(0, ny + 0.14))
            a.g.stroke(chain, with: .color(MascotSwatch(Color(red: 1, green: 0.82, blue: 0.4)).dark), lineWidth: stroke * 0.9)
            let swing = CGFloat(amp > 0 ? 0.01 * sin(t * 2.5) : 0)
            if e.item.style == "amulet" {
                a.metal(Path(ellipseIn: R(-0.055 + swing, ny + 0.03, 0.11, 0.11)), MascotSwatch(Color(red: 1, green: 0.8, blue: 0.35)))
                a.gem(P(swing, ny + 0.085), L(0.035), e.color)
            } else {
                a.gem(P(swing, ny + 0.07), L(0.03), e.color)
            }
        case "pearls":
            for i in 0..<9 {
                let u = CGFloat(i) / 8
                let x = -0.18 + u * 0.36
                let y = ny - 0.03 + 4 * 0.06 * u * (1 - u)
                let pw = MascotSwatch(e.color)
                a.dot(P(x, y), L(0.021), pw.base, outline: pw.ink.opacity(0.6))
                a.dot(P(x - 0.006, y - 0.006), L(0.007), .white.opacity(0.9))
            }
        case "starpin", "heartpin", "firstpin":
            let c = P(chestX, chestY)
            if e.item.style == "starpin" {
                a.solid(MascotShapes.star(center: c, outer: L(0.055), inner: L(0.025)), w, gloss: 0.6)
            } else if e.item.style == "heartpin" {
                a.solid(MascotShapes.heart(center: c, size: L(0.1)), w, gloss: 0.6)
            } else {
                a.solid(Path(ellipseIn: R(chestX - 0.055, chestY - 0.055, 0.11, 0.11)), w, gloss: 0.5)
                a.g.draw(Text("1").font(.system(size: L(0.07), weight: .black, design: .rounded)).foregroundStyle(.white), at: c)
                a.twinkle(CGPoint(x: c.x + L(0.04), y: c.y - L(0.04)), L(0.02))
            }
        case "bellcollar":
            let c = necklineCurve(0.01, dip: 0.03)
            var g2 = g; g2.clip(to: inflated(1.06))
            g2.stroke(c, with: .color(w.ink), lineWidth: L(0.035) + stroke)
            g2.stroke(c, with: .color(w.base), lineWidth: L(0.035))
            let ring = amp > 0 ? 0.25 * sin(t * 6) : 0
            var bg = g
            bg.translateBy(x: cx, y: cy + (rig.neckY + 0.045) * s)
            bg.rotate(by: .radians(ring))
            let bell = Path(ellipseIn: CGRect(x: -L(0.035), y: 0, width: L(0.07), height: L(0.07)))
            MascotArt(g: bg, u: 1, stroke: stroke).metal(bell, MascotSwatch(Color(red: 1, green: 0.82, blue: 0.35)))
            bg.fill(Path(CGRect(x: -L(0.004), y: L(0.04), width: L(0.008), height: L(0.025))), with: .color(.black.opacity(0.6)))
        case "daisychain":
            for i in 0..<7 {
                let u = CGFloat(i) / 6
                let x = -0.2 + u * 0.4
                let y = ny - 0.03 + 4 * 0.055 * u * (1 - u)
                a.flower(P(x, y), L(0.028), petal: .white, center: Color(red: 1, green: 0.82, blue: 0.3))
            }
        case "satchel":
            var strap = Path()
            strap.move(to: P(-shoulderHalf + 0.02, rig.neckY - 0.02))
            strap.addLine(to: P(shoulderHalf * 0.75, waistY + 0.02))
            var g2 = g; g2.clip(to: inflated(1.06))
            g2.stroke(strap, with: .color(w.ink), lineWidth: L(0.04) + stroke)
            g2.stroke(strap, with: .color(w.dark), lineWidth: L(0.04))
            let bag = Path(roundedRect: R(shoulderHalf * 0.75 - 0.05, waistY - 0.01, 0.17, 0.13), cornerRadius: L(0.03))
            a.solid(bag, w, gloss: 0.35)
            let flap = Path(roundedRect: R(shoulderHalf * 0.75 - 0.05, waistY - 0.01, 0.17, 0.06), cornerRadius: L(0.03))
            a.solid(flap, MascotSwatch(w.dark), gloss: 0.2)
            a.metal(Path(roundedRect: R(shoulderHalf * 0.75 + 0.02, waistY + 0.03, 0.03, 0.03), cornerRadius: L(0.005)), MascotSwatch(Color(red: 1, green: 0.8, blue: 0.35)))
        case "necktie":
            var knot = Path()
            knot.move(to: P(-0.03, ny)); knot.addLine(to: P(0.03, ny)); knot.addLine(to: P(0.02, ny + 0.04)); knot.addLine(to: P(-0.02, ny + 0.04)); knot.closeSubpath()
            let len = max(0.12, min(0.24, waistY - ny))
            var blade = Path()
            blade.move(to: P(-0.02, ny + 0.035)); blade.addLine(to: P(0.02, ny + 0.035)); blade.addLine(to: P(0.045, ny + len)); blade.addLine(to: P(0, ny + len + 0.035)); blade.addLine(to: P(-0.045, ny + len)); blade.closeSubpath()
            a.solid(blade, w, gloss: 0.4)
            a.pattern(blade, e.item.pattern, w, scale: L(0.06))
            a.solid(knot, MascotSwatch(w.dark), gloss: 0.3)
        case "medal", "goldchain":
            if e.item.style == "medal" {
                for side in [-1.0, 1.0] as [CGFloat] {
                    var rib = Path()
                    rib.move(to: P(side * 0.12, ny - 0.04)); rib.addLine(to: P(side * 0.16, ny - 0.02)); rib.addLine(to: P(side * 0.02, ny + 0.1)); rib.addLine(to: P(side * -0.01, ny + 0.08)); rib.closeSubpath()
                    a.solid(rib, MascotSwatch(side < 0 ? Color(red: 0.2, green: 0.4, blue: 0.9) : Color(red: 0.9, green: 0.2, blue: 0.25)), gloss: 0.2)
                }
                let disc = Path(ellipseIn: R(-0.05, ny + 0.07, 0.1, 0.1))
                a.metal(disc, w)
                a.solid(MascotShapes.star(center: P(0, ny + 0.12), outer: L(0.03), inner: L(0.013)), MascotSwatch(w.dark), gloss: 0.2, outline: false)
            } else {
                for i in 0..<8 {
                    let u = CGFloat(i) / 7
                    let x = -0.19 + u * 0.38
                    let y = ny - 0.03 + 4 * 0.07 * u * (1 - u)
                    let link = Path(ellipseIn: R(x - 0.026, y - 0.016, 0.052, 0.032))
                    a.g.stroke(link, with: .color(w.ink), lineWidth: L(0.014) + stroke * 0.6)
                    a.g.stroke(link, with: .linearGradient(Gradient(colors: [w.lighter, w.base, w.dark]), startPoint: P(x, y - 0.02), endPoint: P(x, y + 0.02)), lineWidth: L(0.014))
                }
                a.metal(Path(roundedRect: R(-0.035, ny + 0.06, 0.07, 0.07), cornerRadius: L(0.012)), w)
            }
        default:
            bowTie(w, at: ny + 0.015)
        }
    }

    /// Straps or clasps for back items, drawn on the body so the item reads as worn.
    func backStraps(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let g = faceSafe()
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        switch e.item.style {
        case "backpack", "jetpack":
            guard rig.canWearNeck else { return }
            for side in [-1.0, 1.0] as [CGFloat] {
                var strap = Path()
                strap.move(to: P(side * (shoulderHalf - 0.03), rig.neckY - 0.03))
                strap.addQuadCurve(to: P(side * (shoulderHalf - 0.01), waistY + 0.02), control: P(side * (shoulderHalf - 0.08), (rig.neckY + waistY) / 2))
                var g2 = g; g2.clip(to: inflated(1.05))
                let col = e.item.style == "jetpack" ? MascotSwatch(Color(white: 0.3)) : MascotSwatch(w.dark)
                g2.stroke(strap, with: .color(col.ink), lineWidth: L(0.04) + stroke)
                g2.stroke(strap, with: .color(col.base), lineWidth: L(0.04))
            }
        case "herocape", "streakcape", "royalcape", "wizardcape", "spookycape":
            let clasp = e.item.style == "royalcape" ? Color(red: 1, green: 0.8, blue: 0.3) : (e.item.style == "streakcape" ? Color(red: 1, green: 0.85, blue: 0.3) : w.lighter)
            let half = min(rig.faceHalfWidth + 0.06, shoulderHalf)
            for side in [-1.0, 1.0] as [CGFloat] {
                a.metal(Path(ellipseIn: R(side * half - 0.03, rig.neckY - 0.03, 0.06, 0.06)), MascotSwatch(clasp))
            }
            if e.item.style == "royalcape" {
                ermine(along: inflated(1.06).meet(belowNeck(0, dip: 0.03)).meet(above(rig.neckY + 0.07)), width: 0.04)
            }
            if e.item.style == "spookycape" {
                // Tall collar points beside (never over) the face.
                for side in [-1.0, 1.0] as [CGFloat] {
                    var col = Path()
                    let x0 = side * (rig.faceHalfWidth + 0.05)
                    col.move(to: P(x0, rig.neckY))
                    col.addLine(to: P(x0 + side * 0.14, rig.eyeY - 0.02))
                    col.addLine(to: P(x0 + side * 0.18, rig.neckY + 0.04))
                    col.closeSubpath()
                    a.solid(col, MascotSwatch(Color(red: 0.6, green: 0.12, blue: 0.2)), gloss: 0.3)
                }
            }
        default:
            break
        }
    }
}


// MARK: - Robust path booleans

extension Path {
    /// Curves → short line segments. Boolean ops on line-only paths behave the same on every iOS
    /// runtime (curve-vs-curve booleans can come back empty, and CoreGraphics returns the whole
    /// argument when the receiver is empty, which painted giant rectangles).
    func mascotFlattened(segments: Int = 14) -> Path {
        var out = Path()
        var cur = CGPoint.zero
        var start = CGPoint.zero
        forEach { el in
            switch el {
            case .move(let p):
                out.move(to: p); cur = p; start = p
            case .line(let p):
                out.addLine(to: p); cur = p
            case .quadCurve(let p, let c):
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    out.addLine(to: CGPoint(x: u * u * cur.x + 2 * u * t * c.x + t * t * p.x,
                                            y: u * u * cur.y + 2 * u * t * c.y + t * t * p.y))
                }
                cur = p
            case .curve(let p, let c1, let c2):
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    let k0 = u * u * u, k1 = 3 * u * u * t, k2 = 3 * u * t * t, k3 = t * t * t
                    out.addLine(to: CGPoint(x: k0 * cur.x + k1 * c1.x + k2 * c2.x + k3 * p.x,
                                            y: k0 * cur.y + k1 * c1.y + k2 * c2.y + k3 * p.y))
                }
                cur = p
            case .closeSubpath:
                out.closeSubpath(); cur = start
            }
        }
        return out
    }

    /// Safe intersection: empty in → empty out, and never larger than either input.
    func meet(_ other: Path) -> Path {
        if isEmpty || other.isEmpty { return Path() }
        let a = boundingRect, b = other.boundingRect
        guard a.intersects(b) else { return Path() }
        let r = mascotFlattened().intersection(other.mascotFlattened())
        guard !r.isEmpty, a.intersection(b).insetBy(dx: -1, dy: -1).contains(r.boundingRect) else { return Path() }
        return r
    }

    /// Safe union.
    func join(_ other: Path) -> Path {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return mascotFlattened().union(other.mascotFlattened())
    }
}
