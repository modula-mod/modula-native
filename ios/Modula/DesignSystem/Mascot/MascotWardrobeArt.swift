import SwiftUI

// MARK: - Head, face, hands, back, aura and pet art

extension MascotWearPainter {
    // MARK: Hats (local frame: brim spans x −0.5…0.5 at y 0, up is −y, 1 unit = hat width)

    func hat(_ e: MascotWearList.Entry, hasHair: Bool) {
        let w = MascotSwatch(e.color)
        let it = e.item
        let brimY = rig.headTop + rig.hatSink - (hasHair ? 0.035 : 0)
        let W = rig.hatWidth
        let wobble = amp > 0 ? 0.035 * sin(t * 1.3) : 0
        if it.style == "headphones" { headphones(w); return }
        var tilt = wobble
        switch it.style {
        case "beret": tilt += -0.2
        case "party", "santa": tilt += 0.14
        case "fedora", "cowboy": tilt += -0.06
        default: break
        }
        let a = local(CGPoint(x: 0, y: brimY), unit: W, rotate: tilt)
        let gold = MascotSwatch(Color(red: 1, green: 0.8, blue: 0.32))
        func dome(_ h: CGFloat = 0.55, _ half: CGFloat = 0.48) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: -half, y: 0.02))
            p.addCurve(to: CGPoint(x: 0, y: -h), control1: CGPoint(x: -half, y: -h * 0.7), control2: CGPoint(x: -half * 0.55, y: -h))
            p.addCurve(to: CGPoint(x: half, y: 0.02), control1: CGPoint(x: half * 0.55, y: -h), control2: CGPoint(x: half, y: -h * 0.7))
            p.closeSubpath()
            return p
        }
        func band(_ y: CGFloat, _ h: CGFloat, _ half: CGFloat = 0.52) -> Path {
            Path(roundedRect: CGRect(x: -half, y: y, width: half * 2, height: h), cornerRadius: h * 0.45)
        }
        func ribs(_ p: Path, _ c: Color) {
            var g = a.g; g.clip(to: p)
            var x: CGFloat = -0.5
            while x < 0.55 { MascotArt(g: g, u: a.u, stroke: stroke).line(CGPoint(x: x, y: -1), CGPoint(x: x, y: 1), c, width: 0.6); x += 0.06 }
        }
        func pom(_ c: CGPoint, _ r: CGFloat, _ col: MascotSwatch) {
            for i in 0..<8 {
                let ang = Double(i) / 8 * 2 * .pi
                a.dot(CGPoint(x: c.x + cos(ang) * r * 0.6, y: c.y + sin(ang) * r * 0.6), r * 0.5, col.dark)
            }
            a.solid(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), col, gloss: 0.5)
        }
        switch it.style {
        case "beanie", "pombeanie", "catbeanie", "froghat":
            if it.style == "catbeanie" {
                for side in [-1.0, 1.0] as [CGFloat] {
                    var ear = Path()
                    ear.move(to: CGPoint(x: side * 0.18, y: -0.4)); ear.addLine(to: CGPoint(x: side * 0.4, y: -0.72)); ear.addLine(to: CGPoint(x: side * 0.46, y: -0.25)); ear.closeSubpath()
                    a.solid(ear, w, gloss: 0.3)
                    var inner = Path()
                    inner.move(to: CGPoint(x: side * 0.25, y: -0.42)); inner.addLine(to: CGPoint(x: side * 0.39, y: -0.62)); inner.addLine(to: CGPoint(x: side * 0.42, y: -0.36)); inner.closeSubpath()
                    a.g.fill(inner, with: .color(Color(red: 1, green: 0.72, blue: 0.8)))
                }
            }
            let d = dome(0.58)
            a.solid(d, w, gloss: 0.4)
            a.pattern(d, it.pattern, w, scale: 0.16)
            let b = band(-0.14, 0.18)
            a.solid(b, MascotSwatch(w.dark), gloss: 0.25)
            ribs(b, w.deep.opacity(0.55))
            if it.style == "pombeanie" { pom(CGPoint(x: 0, y: -0.62), 0.13, MascotSwatch(w.lighter)) }
            if it.style == "froghat" {
                for side in [-1.0, 1.0] as [CGFloat] {
                    let c = CGPoint(x: side * 0.2, y: -0.55)
                    a.solid(Path(ellipseIn: CGRect(x: c.x - 0.13, y: c.y - 0.13, width: 0.26, height: 0.26)), w, gloss: 0.3)
                    a.dot(c, 0.09, .white, outline: w.ink)
                    a.dot(CGPoint(x: c.x + 0.015, y: c.y + 0.01), 0.05, .black)
                }
            }
        case "cap", "backcap", "propeller":
            if it.style == "backcap" {
                let bill = Path(ellipseIn: CGRect(x: -0.32, y: -0.6, width: 0.64, height: 0.2))
                a.solid(bill, MascotSwatch(w.dark), gloss: 0.2)
            }
            let d = dome(0.48, 0.47)
            if it.style == "propeller" {
                let cols: [Color] = [.red, .yellow, .green, .blue]
                for i in 0..<4 {
                    var g = a.g; g.clip(to: d)
                    g.fill(Path(CGRect(x: -0.5 + CGFloat(i) * 0.25, y: -0.6, width: 0.25, height: 0.7)), with: .color(cols[i]))
                }
                a.volume(d, w); a.shine(d)
                a.g.stroke(d, with: .color(w.ink), lineWidth: a.lw)
            } else {
                a.solid(d, w, gloss: 0.4)
            }
            var g = a.g; g.clip(to: d)
            for x in [-0.18, 0.18] as [CGFloat] {
                var seam = Path(); seam.move(to: CGPoint(x: 0, y: -0.48)); seam.addQuadCurve(to: CGPoint(x: x * 1.8, y: 0), control: CGPoint(x: x * 1.3, y: -0.35))
                g.stroke(seam, with: .color(w.deep.opacity(0.5)), lineWidth: a.lw * 0.7)
            }
            a.dot(CGPoint(x: 0, y: -0.49), 0.045, w.dark, outline: w.ink)
            if it.style == "cap" {
                var bill = Path()
                bill.move(to: CGPoint(x: -0.4, y: -0.02))
                bill.addQuadCurve(to: CGPoint(x: 0.62, y: -0.02), control: CGPoint(x: 0.1, y: -0.12))
                bill.addQuadCurve(to: CGPoint(x: -0.4, y: -0.02), control: CGPoint(x: 0.15, y: 0.1))
                a.solid(bill, MascotSwatch(w.dark), gloss: 0.3)
                a.solid(Path(ellipseIn: CGRect(x: -0.1, y: -0.32, width: 0.18, height: 0.18)), MascotSwatch(.white), gloss: 0.2)
            } else if it.style == "backcap" {
                a.g.fill(Path(roundedRect: CGRect(x: -0.12, y: -0.18, width: 0.24, height: 0.12), cornerRadius: 0.06), with: .color(w.deep))
            } else {
                a.line(CGPoint(x: 0, y: -0.5), CGPoint(x: 0, y: -0.66), Color(white: 0.4), width: 1.2)
                let spin = amp > 0 ? cos(t * 14) : 1
                for side in [-1.0, 1.0] as [CGFloat] {
                    let blade = Path(ellipseIn: CGRect(x: side > 0 ? 0 : -0.36 * abs(spin), y: -0.72, width: 0.36 * abs(spin), height: 0.1))
                    a.solid(blade, MascotSwatch(side > 0 ? .red : .blue), gloss: 0.3)
                }
                a.dot(CGPoint(x: 0, y: -0.67), 0.04, .yellow, outline: .black.opacity(0.5))
            }
        case "bucket", "sunhat":
            let wide: CGFloat = it.style == "sunhat" ? 0.78 : 0.62
            let brim = Path(ellipseIn: CGRect(x: -wide, y: -0.13, width: wide * 2, height: 0.24))
            a.solid(brim, MascotSwatch(w.dark), gloss: 0.25)
            var crown = Path()
            crown.move(to: CGPoint(x: -0.4, y: -0.04))
            crown.addLine(to: CGPoint(x: -0.32, y: -0.44))
            crown.addQuadCurve(to: CGPoint(x: 0.32, y: -0.44), control: CGPoint(x: 0, y: -0.52))
            crown.addLine(to: CGPoint(x: 0.4, y: -0.04))
            crown.closeSubpath()
            a.solid(crown, w, gloss: 0.35)
            a.pattern(crown, it.style == "sunhat" ? .check : it.pattern, w, scale: 0.14)
            if it.style == "sunhat" {
                a.pattern(brim, .check, w, scale: 0.12)
                let rib = MascotSwatch(Color(red: 0.95, green: 0.45, blue: 0.55))
                a.solid(Path(CGRect(x: -0.39, y: -0.16, width: 0.78, height: 0.1)), rib, gloss: 0.3)
                a.solid(Path(ellipseIn: CGRect(x: 0.26, y: -0.2, width: 0.16, height: 0.16)), rib, gloss: 0.3)
            } else {
                a.stitch(Path(ellipseIn: CGRect(x: -wide + 0.06, y: -0.1, width: (wide - 0.06) * 2, height: 0.18)), w)
            }
        case "beret":
            let p = Path(ellipseIn: CGRect(x: -0.56, y: -0.44, width: 1.1, height: 0.42))
            a.solid(p, w, gloss: 0.4)
            a.solid(band(-0.08, 0.1, 0.42), MascotSwatch(w.dark), gloss: 0.2)
            a.line(CGPoint(x: -0.02, y: -0.44), CGPoint(x: 0.04, y: -0.56), w.ink, width: 2)
        case "flowerclip":
            let c = CGPoint(x: 0.32, y: -0.08)
            a.solid(MascotShapes.leaf(center: CGPoint(x: c.x - 0.14, y: c.y + 0.06), size: 0.2, angle: -1.0), MascotSwatch(Color(red: 0.35, green: 0.7, blue: 0.35)), gloss: 0.2)
            for i in 0..<5 {
                let ang = Double(i) / 5 * 2 * .pi + (amp > 0 ? 0.1 * sin(t) : 0)
                let pc = CGPoint(x: c.x + cos(ang) * 0.1, y: c.y + sin(ang) * 0.1)
                a.solid(Path(ellipseIn: CGRect(x: pc.x - 0.08, y: pc.y - 0.08, width: 0.16, height: 0.16)), w, gloss: 0.4)
            }
            a.solid(Path(ellipseIn: CGRect(x: c.x - 0.055, y: c.y - 0.055, width: 0.11, height: 0.11)), MascotSwatch(Color(red: 1, green: 0.85, blue: 0.3)), gloss: 0.5)
        case "bigbow":
            let c = CGPoint(x: 0.22, y: -0.16)
            let flutter = amp > 0 ? 0.03 * sin(t * 3) : 0
            for side in [-1.0, 1.0] as [CGFloat] {
                var loop = Path()
                loop.move(to: c)
                loop.addCurve(to: c, control1: CGPoint(x: c.x + side * 0.3, y: c.y - 0.28 - flutter), control2: CGPoint(x: c.x + side * 0.34, y: c.y + 0.2))
                a.solid(loop, w, gloss: 0.5)
                a.pattern(loop, it.pattern, w, scale: 0.12)
                var tail = Path()
                tail.move(to: c); tail.addLine(to: CGPoint(x: c.x + side * 0.12, y: c.y + 0.26 + flutter)); tail.addLine(to: CGPoint(x: c.x + side * 0.04, y: c.y + 0.22)); tail.closeSubpath()
                a.solid(tail, MascotSwatch(w.dark), gloss: 0.2)
            }
            a.solid(Path(ellipseIn: CGRect(x: c.x - 0.06, y: c.y - 0.07, width: 0.12, height: 0.14)), MascotSwatch(w.dark), gloss: 0.4)
        case "bandana":
            var b = Path()
            b.move(to: CGPoint(x: -0.52, y: 0.0))
            b.addQuadCurve(to: CGPoint(x: 0.52, y: 0.0), control: CGPoint(x: 0, y: 0.06))
            b.addLine(to: CGPoint(x: 0.5, y: -0.2))
            b.addQuadCurve(to: CGPoint(x: -0.5, y: -0.2), control: CGPoint(x: 0, y: -0.15))
            b.closeSubpath()
            a.solid(b, w, gloss: 0.35)
            a.pattern(b, it.pattern, w, scale: 0.12)
            let fl = amp > 0 ? 0.05 * sin(t * 4) : 0
            for (i, ang) in ([0.3, -0.25] as [Double]).enumerated() {
                var tail = Path()
                tail.move(to: CGPoint(x: 0.5, y: -0.1))
                tail.addLine(to: CGPoint(x: 0.5 + 0.28 * cos(ang + fl), y: -0.1 + 0.28 * sin(ang + fl) + CGFloat(i) * 0.04))
                tail.addLine(to: CGPoint(x: 0.5 + 0.22 * cos(ang + fl + 0.3), y: -0.1 + 0.22 * sin(ang + fl + 0.3)))
                tail.closeSubpath()
                a.solid(tail, w, gloss: 0.2)
            }
            a.solid(Path(ellipseIn: CGRect(x: 0.44, y: -0.16, width: 0.12, height: 0.12)), MascotSwatch(w.dark), gloss: 0.3)
        case "chef":
            let b = Path(roundedRect: CGRect(x: -0.36, y: -0.4, width: 0.72, height: 0.42), cornerRadius: 0.05)
            for (x, y, r) in [(-0.26, -0.62, 0.22), (0.26, -0.62, 0.22), (0.0, -0.74, 0.26)] as [(CGFloat, CGFloat, CGFloat)] {
                a.solid(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), w, gloss: 0.5)
            }
            a.solid(b, w, gloss: 0.3)
            ribs(b, Color.black.opacity(0.08))
        case "party":
            var cone = Path()
            cone.move(to: CGPoint(x: -0.3, y: 0)); cone.addLine(to: CGPoint(x: 0, y: -1.0)); cone.addLine(to: CGPoint(x: 0.3, y: 0)); cone.closeSubpath()
            a.solid(cone, w, gloss: 0.4)
            a.pattern(cone, .dots, w, scale: 0.16)
            var g = a.g; g.clip(to: cone)
            for y in [-0.25, -0.55] as [CGFloat] { g.fill(Path(CGRect(x: -0.5, y: y, width: 1, height: 0.07)), with: .color(Color(red: 1, green: 0.85, blue: 0.3))) }
            pom(CGPoint(x: 0, y: -1.0), 0.09, MascotSwatch(Color(red: 1, green: 0.9, blue: 0.4)))
        case "halo":
            let bob = amp > 0 ? 0.04 * sin(t * 2) : 0
            let ring = Path(ellipseIn: CGRect(x: -0.4, y: -0.42 + bob, width: 0.8, height: 0.2))
            a.g.stroke(ring, with: .color(e.color.opacity(0.35)), lineWidth: 0.16)
            a.g.stroke(ring, with: .color(w.ink.opacity(0.4)), lineWidth: 0.09)
            a.g.stroke(ring, with: .linearGradient(Gradient(colors: [w.lighter, w.base, w.light]), startPoint: CGPoint(x: -0.4, y: 0), endPoint: CGPoint(x: 0.4, y: 0)), lineWidth: 0.07)
            a.twinkle(CGPoint(x: 0.3, y: -0.4 + bob), 0.07)
        case "bdaycrown", "crown", "tiara":
            let pts = it.style == "tiara" ? 3 : 5
            let h: CGFloat = it.style == "tiara" ? 0.3 : 0.48
            if it.style == "crown" {
                a.solid(dome(0.4, 0.4), MascotSwatch(Color(red: 0.75, green: 0.12, blue: 0.2)), gloss: 0.4)
            }
            var p = Path()
            let half: CGFloat = it.style == "tiara" ? 0.36 : 0.44
            p.move(to: CGPoint(x: -half, y: 0.02))
            for i in 0...(pts * 2) {
                let x = -half + CGFloat(i) * half * 2 / CGFloat(pts * 2)
                let peak = i % 2 == 1
                let centre = it.style == "tiara" && i == pts
                p.addLine(to: CGPoint(x: x, y: peak || centre ? -h * (centre ? 1.25 : 1) : -h * 0.45))
            }
            p.addLine(to: CGPoint(x: half, y: 0.02))
            p.closeSubpath()
            if it.style == "bdaycrown" {
                a.solid(p, w, gloss: 0.4)
                a.pattern(p, .dots, w, scale: 0.14)
                for i in [1, 5, 9] {
                    let x = -half + CGFloat(i) * half * 2 / 10
                    a.solid(Path(roundedRect: CGRect(x: x - 0.025, y: -h - 0.2, width: 0.05, height: 0.2), cornerRadius: 0.02), MascotSwatch(Color(red: 0.5, green: 0.75, blue: 1)), gloss: 0.3)
                    let fl = amp > 0 ? 0.02 * sin(t * 18 + Double(i)) : 0
                    var flame = Path()
                    flame.move(to: CGPoint(x: x, y: -h - 0.32 - fl))
                    flame.addQuadCurve(to: CGPoint(x: x, y: -h - 0.2), control: CGPoint(x: x + 0.07, y: -h - 0.22))
                    flame.addQuadCurve(to: CGPoint(x: x, y: -h - 0.32 - fl), control: CGPoint(x: x - 0.07, y: -h - 0.22))
                    a.g.fill(flame, with: .linearGradient(Gradient(colors: [.yellow, .orange]), startPoint: CGPoint(x: x, y: -h - 0.32), endPoint: CGPoint(x: x, y: -h - 0.2)))
                }
            } else {
                a.metal(p, w)
                let gems: [Color] = [Color(red: 0.9, green: 0.15, blue: 0.3), Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.2, green: 0.8, blue: 0.4)]
                a.gem(CGPoint(x: 0, y: -h * 0.3), it.style == "tiara" ? 0.07 : 0.06, gems[1])
                if it.style == "crown" {
                    a.gem(CGPoint(x: -0.24, y: -h * 0.25), 0.045, gems[0], sparkle: 0)
                    a.gem(CGPoint(x: 0.24, y: -h * 0.25), 0.045, gems[2], sparkle: 0)
                    for i in stride(from: 1, through: pts * 2, by: 2) {
                        let x = -half + CGFloat(i) * half * 2 / CGFloat(pts * 2)
                        a.dot(CGPoint(x: x, y: -h - 0.03), 0.04, w.lighter, outline: w.ink)
                    }
                } else {
                    a.gem(CGPoint(x: -0.2, y: -h * 0.35), 0.04, gems[0], sparkle: 0)
                    a.gem(CGPoint(x: 0.2, y: -h * 0.35), 0.04, gems[0], sparkle: 0)
                }
                if amp > 0, sin(t * 2.3) > 0.7 { a.twinkle(CGPoint(x: 0.25, y: -h), 0.08) }
            }
        case "tophat":
            a.solid(Path(ellipseIn: CGRect(x: -0.62, y: -0.1, width: 1.24, height: 0.18)), MascotSwatch(w.dark), gloss: 0.3)
            let cyl = Path(roundedRect: CGRect(x: -0.36, y: -0.98, width: 0.72, height: 0.94), cornerRadius: 0.05)
            a.solid(cyl, w, gloss: 0.55)
            a.solid(Path(CGRect(x: -0.36, y: -0.3, width: 0.72, height: 0.13)), MascotSwatch(Color(red: 0.75, green: 0.15, blue: 0.22)), gloss: 0.3)
            a.solid(Path(ellipseIn: CGRect(x: -0.36, y: -1.04, width: 0.72, height: 0.12)), MascotSwatch(w.light), gloss: 0.2)
        case "cowboy", "fedora":
            let wide: CGFloat = it.style == "cowboy" ? 0.75 : 0.6
            var brim = Path()
            brim.move(to: CGPoint(x: -wide, y: it.style == "cowboy" ? -0.22 : -0.06))
            brim.addQuadCurve(to: CGPoint(x: wide, y: it.style == "cowboy" ? -0.22 : -0.06), control: CGPoint(x: 0, y: 0.2))
            brim.addQuadCurve(to: CGPoint(x: -wide, y: it.style == "cowboy" ? -0.22 : -0.06), control: CGPoint(x: 0, y: 0.02))
            a.solid(brim, MascotSwatch(w.dark), gloss: 0.3)
            var crown = Path()
            crown.move(to: CGPoint(x: -0.36, y: -0.05))
            crown.addLine(to: CGPoint(x: -0.32, y: -0.62))
            crown.addQuadCurve(to: CGPoint(x: 0, y: -0.56), control: CGPoint(x: -0.15, y: -0.72))
            crown.addQuadCurve(to: CGPoint(x: 0.32, y: -0.62), control: CGPoint(x: 0.15, y: -0.72))
            crown.addLine(to: CGPoint(x: 0.36, y: -0.05))
            crown.closeSubpath()
            a.solid(crown, w, gloss: 0.35)
            a.line(CGPoint(x: 0, y: -0.56), CGPoint(x: 0, y: -0.35), w.deep.opacity(0.6), width: 1)
            a.solid(Path(CGRect(x: -0.355, y: -0.2, width: 0.71, height: 0.11)), MascotSwatch(it.style == "cowboy" ? Color(red: 0.35, green: 0.22, blue: 0.14) : Color(white: 0.12)), gloss: 0.2)
            if it.style == "cowboy" { a.metal(Path(roundedRect: CGRect(x: -0.06, y: -0.21, width: 0.12, height: 0.13), cornerRadius: 0.02), MascotSwatch(Color(white: 0.85))) }
            else { a.solid(MascotShapes.leaf(center: CGPoint(x: 0.24, y: -0.2), size: 0.22, angle: 1.2), MascotSwatch(Color(red: 0.9, green: 0.4, blue: 0.3)), gloss: 0.2) }
        case "tricorn":
            var p = Path()
            p.move(to: CGPoint(x: -0.66, y: -0.08))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.62), control: CGPoint(x: -0.4, y: -0.6))
            p.addQuadCurve(to: CGPoint(x: 0.66, y: -0.08), control: CGPoint(x: 0.4, y: -0.6))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0.06), control: CGPoint(x: 0.3, y: 0.08))
            p.addQuadCurve(to: CGPoint(x: -0.66, y: -0.08), control: CGPoint(x: -0.3, y: 0.08))
            a.solid(p, w, gloss: 0.35)
            var g = a.g; g.clip(to: p)
            g.stroke(p, with: .color(gold.base), lineWidth: 0.08)
            a.g.stroke(p, with: .color(w.ink), lineWidth: a.lw)
            a.gem(CGPoint(x: 0, y: -0.3), 0.07, Color(red: 0.9, green: 0.2, blue: 0.3))
        case "wizard", "witch":
            if it.style == "witch" { a.solid(Path(ellipseIn: CGRect(x: -0.7, y: -0.12, width: 1.4, height: 0.22)), MascotSwatch(w.dark), gloss: 0.2) }
            else { a.solid(Path(ellipseIn: CGRect(x: -0.58, y: -0.1, width: 1.16, height: 0.18)), MascotSwatch(w.dark), gloss: 0.2) }
            let droop = amp > 0 ? 0.04 * sin(t * 1.5) : 0
            var cone = Path()
            cone.move(to: CGPoint(x: -0.42, y: -0.02))
            cone.addQuadCurve(to: CGPoint(x: 0.42 + droop, y: -1.15), control: CGPoint(x: -0.1, y: -0.9))
            cone.addQuadCurve(to: CGPoint(x: 0.42, y: -0.02), control: CGPoint(x: 0.12, y: -0.6))
            cone.closeSubpath()
            a.solid(cone, w, gloss: 0.4)
            a.pattern(cone, it.style == "wizard" ? .stars : .plain, w, scale: 0.2)
            let bandY: CGFloat = -0.2
            var g = a.g; g.clip(to: cone)
            g.fill(Path(CGRect(x: -0.6, y: bandY, width: 1.2, height: 0.12)), with: .color(it.style == "witch" ? Color(red: 0.55, green: 0.3, blue: 0.75) : gold.base))
            if it.style == "witch" { a.metal(Path(roundedRect: CGRect(x: -0.07, y: bandY - 0.01, width: 0.14, height: 0.14), cornerRadius: 0.02), gold) }
        case "laurel", "clover":
            for side in [-1.0, 1.0] as [CGFloat] {
                for i in 0..<6 {
                    let u = CGFloat(i) / 5
                    let ang = Double(side) * (0.3 + Double(u) * 1.1)
                    let x = side * (0.12 + 0.36 * sin(Double(u) * .pi / 2))
                    let y = -0.06 - 0.12 * cos(Double(u) * .pi / 2)
                    if it.style == "clover" {
                        for k in 0..<3 {
                            let a2 = Double(k) * 2.1 + ang
                            a.g.fill(MascotShapes.heart(center: CGPoint(x: x + cos(a2) * 0.05, y: y + sin(a2) * 0.05), size: 0.09), with: .color(w.base))
                        }
                    } else {
                        a.solid(MascotShapes.leaf(center: CGPoint(x: x, y: y), size: 0.18, angle: ang), w, gloss: 0.3)
                    }
                }
            }
            if it.style == "laurel" { a.gem(CGPoint(x: 0, y: -0.06), 0.05, Color(red: 1, green: 0.8, blue: 0.3)) }
        case "horns", "antlers":
            for side in [-1.0, 1.0] as [CGFloat] {
                var horn = Path()
                horn.move(to: CGPoint(x: side * 0.2, y: 0))
                horn.addQuadCurve(to: CGPoint(x: side * 0.42, y: -0.55), control: CGPoint(x: side * 0.15, y: -0.4))
                horn.addQuadCurve(to: CGPoint(x: side * 0.36, y: 0), control: CGPoint(x: side * 0.4, y: -0.25))
                horn.closeSubpath()
                if it.style == "antlers" {
                    a.g.stroke(horn, with: .color(w.ink), style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
                    var br = Path()
                    br.move(to: CGPoint(x: side * 0.3, y: -0.3)); br.addLine(to: CGPoint(x: side * 0.5, y: -0.42))
                    br.move(to: CGPoint(x: side * 0.36, y: -0.45)); br.addLine(to: CGPoint(x: side * 0.28, y: -0.64))
                    a.g.stroke(br, with: .color(w.ink), style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
                    a.g.stroke(br, with: .color(w.base), style: StrokeStyle(lineWidth: 0.07, lineCap: .round))
                }
                a.solid(horn, w, gloss: 0.4)
                var g = a.g; g.clip(to: horn)
                for k in 1..<4 { g.stroke(Path(ellipseIn: CGRect(x: side * 0.3 - 0.15, y: -CGFloat(k) * 0.13 - 0.02, width: 0.3, height: 0.08)), with: .color(w.deep.opacity(0.35)), lineWidth: a.lw * 0.7) }
            }
            if it.style == "antlers" {
                a.solid(band(-0.06, 0.08, 0.46), MascotSwatch(Color(red: 0.85, green: 0.2, blue: 0.25)), gloss: 0.3)
                a.metal(Path(ellipseIn: CGRect(x: -0.07, y: -0.08, width: 0.14, height: 0.14)), gold)
            }
        case "unicorn":
            var horn = Path()
            horn.move(to: CGPoint(x: -0.12, y: 0)); horn.addLine(to: CGPoint(x: 0.02, y: -0.85)); horn.addLine(to: CGPoint(x: 0.12, y: 0)); horn.closeSubpath()
            a.g.fill(horn, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.95), Color(red: 0.85, green: 0.9, blue: 1), Color(red: 1, green: 0.95, blue: 0.8)]), startPoint: CGPoint(x: -0.12, y: 0), endPoint: CGPoint(x: 0.12, y: -0.8)))
            var g = a.g; g.clip(to: horn)
            for k in 0..<5 {
                var sp = Path(); sp.move(to: CGPoint(x: -0.2, y: -CGFloat(k) * 0.17)); sp.addLine(to: CGPoint(x: 0.2, y: -CGFloat(k) * 0.17 - 0.1))
                g.stroke(sp, with: .color(.white.opacity(0.8)), lineWidth: a.lw * 1.2)
                g.stroke(sp.offsetBy(dx: 0, dy: 0.03), with: .color(w.deep.opacity(0.3)), lineWidth: a.lw * 0.8)
            }
            a.g.stroke(horn, with: .color(w.ink), style: StrokeStyle(lineWidth: a.lw, lineJoin: .round))
            if amp > 0 { a.twinkle(CGPoint(x: 0.12 + 0.05 * sin(t * 2), y: -0.8), 0.08 * (0.6 + 0.4 * abs(sin(t * 3)))) }
        case "mushroom":
            var cap = Path()
            cap.move(to: CGPoint(x: -0.64, y: -0.02))
            cap.addCurve(to: CGPoint(x: 0.64, y: -0.02), control1: CGPoint(x: -0.6, y: -0.78), control2: CGPoint(x: 0.6, y: -0.78))
            cap.addQuadCurve(to: CGPoint(x: -0.64, y: -0.02), control: CGPoint(x: 0, y: 0.1))
            a.solid(cap, w, gloss: 0.5)
            var g = a.g; g.clip(to: cap)
            for (x, y, r) in [(-0.3, -0.3, 0.1), (0.1, -0.45, 0.12), (0.38, -0.2, 0.08), (-0.05, -0.15, 0.07)] as [(CGFloat, CGFloat, CGFloat)] {
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 1.8)), with: .color(.white.opacity(0.95)))
            }
        case "gradcap":
            a.solid(dome(0.3, 0.38), w, gloss: 0.3)
            var board = Path()
            board.move(to: CGPoint(x: -0.62, y: -0.36)); board.addLine(to: CGPoint(x: 0, y: -0.52)); board.addLine(to: CGPoint(x: 0.62, y: -0.36)); board.addLine(to: CGPoint(x: 0, y: -0.22)); board.closeSubpath()
            a.solid(board, w, gloss: 0.4)
            let swing = amp > 0 ? 0.05 * sin(t * 2.4) : 0
            a.line(CGPoint(x: 0, y: -0.37), CGPoint(x: 0.42, y: -0.32), gold.base, width: 1.2)
            a.line(CGPoint(x: 0.42, y: -0.32), CGPoint(x: 0.44 + swing, y: -0.05), gold.base, width: 1.4)
            a.solid(Path(roundedRect: CGRect(x: 0.4 + swing, y: -0.08, width: 0.08, height: 0.12), cornerRadius: 0.02), gold, gloss: 0.3)
            a.dot(CGPoint(x: 0, y: -0.37), 0.035, gold.base, outline: gold.ink)
        case "sailor":
            let cyl = Path(roundedRect: CGRect(x: -0.4, y: -0.32, width: 0.8, height: 0.34), cornerRadius: 0.06)
            a.solid(Path(ellipseIn: CGRect(x: -0.48, y: -0.46, width: 0.96, height: 0.24)), w, gloss: 0.4)
            a.solid(cyl, w, gloss: 0.3)
            a.solid(Path(CGRect(x: -0.4, y: -0.12, width: 0.8, height: 0.12)), MascotSwatch(Color(red: 0.18, green: 0.25, blue: 0.5)), gloss: 0.2)
        case "pumpkin":
            let d = dome(0.55, 0.5)
            a.solid(d, w, gloss: 0.35)
            var g = a.g; g.clip(to: d)
            for x in [-0.3, -0.1, 0.1, 0.3] as [CGFloat] {
                var rib = Path(); rib.move(to: CGPoint(x: x * 0.4, y: -0.55)); rib.addQuadCurve(to: CGPoint(x: x * 1.2, y: 0.02), control: CGPoint(x: x * 1.4, y: -0.3))
                g.stroke(rib, with: .color(w.deep.opacity(0.45)), lineWidth: a.lw * 1.4)
            }
            a.solid(Path(roundedRect: CGRect(x: -0.05, y: -0.72, width: 0.1, height: 0.2), cornerRadius: 0.03), MascotSwatch(Color(red: 0.35, green: 0.55, blue: 0.25)), gloss: 0.2)
            a.solid(MascotShapes.leaf(center: CGPoint(x: 0.14, y: -0.62), size: 0.2, angle: 1.1), MascotSwatch(Color(red: 0.35, green: 0.7, blue: 0.3)), gloss: 0.2)
        case "santa":
            let flop = amp > 0 ? 0.04 * sin(t * 2) : 0
            var cone = Path()
            cone.move(to: CGPoint(x: -0.46, y: -0.05))
            cone.addQuadCurve(to: CGPoint(x: 0.55 + flop, y: -0.55), control: CGPoint(x: -0.1, y: -1.0))
            cone.addQuadCurve(to: CGPoint(x: 0.46, y: -0.05), control: CGPoint(x: 0.35, y: -0.5))
            cone.closeSubpath()
            a.solid(cone, w, gloss: 0.4)
            let fur = MascotSwatch(Color(white: 0.98))
            a.solid(band(-0.16, 0.2), fur, gloss: 0.3)
            pom(CGPoint(x: 0.56 + flop, y: -0.55), 0.12, fur)
        case "bunnyears":
            a.solid(band(-0.08, 0.08, 0.46), MascotSwatch(Color(red: 0.98, green: 0.6, blue: 0.75)), gloss: 0.3)
            for side in [-1.0, 1.0] as [CGFloat] {
                let flop = side > 0 ? 0.5 + (amp > 0 ? 0.1 * sin(t * 2) : 0) : 0.1
                var g = a.g
                g.translateBy(x: side * 0.2, y: -0.05)
                g.rotate(by: .radians(Double(side) * flop))
                let ear = Path(ellipseIn: CGRect(x: -0.1, y: -0.72, width: 0.2, height: 0.72))
                let ea = MascotArt(g: g, u: a.u, stroke: stroke)
                ea.solid(ear, w, gloss: 0.3)
                g.fill(Path(ellipseIn: CGRect(x: -0.05, y: -0.62, width: 0.1, height: 0.5)), with: .color(Color(red: 1, green: 0.72, blue: 0.8)))
            }
        default:
            a.solid(dome(), w)
        }
    }

    func headphones(_ w: MascotSwatch) {
        let g = faceSafe()
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        let y = rig.eyeY + 0.02
        let half = max(rig.faceHalfWidth + 0.06, rig.chord(at: y) / 2 + 0.01)
        var arc = Path()
        arc.move(to: P(-half + 0.02, y - 0.04))
        arc.addCurve(to: P(half - 0.02, y - 0.04), control1: P(-half, rig.bodyTop - 0.2), control2: P(half, rig.bodyTop - 0.2))
        g.stroke(arc, with: .color(w.ink), style: StrokeStyle(lineWidth: L(0.05) + stroke, lineCap: .round))
        g.stroke(arc, with: .linearGradient(Gradient(colors: [w.light, w.dark]), startPoint: P(0, rig.bodyTop - 0.2), endPoint: P(0, y)), style: StrokeStyle(lineWidth: L(0.05), lineCap: .round))
        for side in [-1.0, 1.0] as [CGFloat] {
            let cup = Path(roundedRect: R(side * half - 0.07, y - 0.11, 0.14, 0.22), cornerRadius: L(0.06))
            a.solid(cup, w, gloss: 0.5)
            a.solid(Path(roundedRect: R(side * half - 0.04, y - 0.07, 0.08, 0.14), cornerRadius: L(0.04)), MascotSwatch(w.lighter), gloss: 0.3)
        }
    }

    // MARK: Hair

    var fringeY: CGFloat { min(rig.eyeTop - 0.03, rig.bodyTop + max(0.13, rig.foreheadRoom * 0.6)) }

    func fringeRegion(bumps: Int, depth: CGFloat, slant: CGFloat = 0) -> Path {
        let y = fringeY
        let hw = rig.bodyW / 2 + 0.1
        var p = Path()
        p.move(to: P(-1.4, -1.4))
        p.addLine(to: P(1.4, -1.4))
        p.addLine(to: P(1.4, y - depth))
        p.addLine(to: P(hw, y - depth - slant))
        for i in 0..<bumps {
            let x0 = hw - CGFloat(i) * hw * 2 / CGFloat(bumps)
            let x1 = x0 - hw * 2 / CGFloat(bumps)
            let s0 = slant * (x0 / hw), s1 = slant * (x1 / hw)
            p.addQuadCurve(to: P(x1, y - depth - s1), control: P((x0 + x1) / 2, y + depth * 0.4 - (s0 + s1) / 2))
        }
        p.addLine(to: P(-1.4, y - depth))
        p.closeSubpath()
        return p
    }

    func sideLocks(to y1: CGFloat, wavy: Bool = false) -> Path {
        let x0 = rig.faceHalfWidth + 0.03
        var p = Path(R(x0, fringeY - 0.1, 0.8, y1 - fringeY + 0.1))
        p.addRect(R(-x0 - 0.8, fringeY - 0.1, 0.8, y1 - fringeY + 0.1))
        return inflated(1.07).meet(p)
    }

    func hairShine(_ cap: Path, _ w: MascotSwatch) {
        var g = ctx; g.clip(to: cap)
        var arc = Path()
        let y = rig.bodyTop + (fringeY - rig.bodyTop) * 0.4
        arc.move(to: P(-rig.bodyW * 0.3, y + 0.03))
        arc.addQuadCurve(to: P(rig.bodyW * 0.15, y - 0.01), control: P(-rig.bodyW * 0.05, y - 0.04))
        g.stroke(arc, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: L(0.03), lineCap: .round))
    }

    func strands(_ cap: Path, _ w: MascotSwatch) {
        var g = ctx; g.clip(to: cap)
        for i in -3...3 {
            var s = Path()
            let x = CGFloat(i) * rig.bodyW * 0.11
            s.move(to: P(x * 0.3, rig.bodyTop - 0.02))
            s.addQuadCurve(to: P(x, fringeY + 0.02), control: P(x * 0.9, rig.bodyTop + 0.06))
            g.stroke(s, with: .color(w.deep.opacity(0.35)), lineWidth: stroke * 0.7)
        }
    }

    func hairBack(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let a = art
        let sw = CGFloat(amp > 0 ? 0.03 * sin(t * 2.2) : 0)
        switch e.item.style {
        case "waves":
            var p = Path()
            let top = rig.bodyTop + 0.05
            p.move(to: P(-rig.bodyW / 2 - 0.02, top))
            p.addQuadCurve(to: P(rig.bodyW / 2 + 0.02, top), control: P(0, rig.bodyTop - 0.2))
            p.addCurve(to: P(rig.bodyW / 2 + 0.06 + sw, rig.bodyBottom - 0.02), control1: P(rig.bodyW / 2 + 0.16, rig.bodyY), control2: P(rig.bodyW / 2 - 0.02, rig.bodyY + 0.2))
            p.addLine(to: P(-rig.bodyW / 2 - 0.06 + sw, rig.bodyBottom - 0.02))
            p.addCurve(to: P(-rig.bodyW / 2 - 0.02, top), control1: P(-rig.bodyW / 2 + 0.02, rig.bodyY + 0.2), control2: P(-rig.bodyW / 2 - 0.16, rig.bodyY))
            a.solid(p, MascotSwatch(w.dark), gloss: 0.2)
        case "ponytail":
            var p = Path()
            let root = P(rig.bodyW * 0.32, rig.bodyTop + 0.08)
            p.move(to: root)
            p.addCurve(to: P(rig.bodyW / 2 + 0.2 + sw, rig.bodyY + 0.2), control1: P(rig.bodyW / 2 + 0.25, rig.bodyTop), control2: P(rig.bodyW / 2 + 0.3, rig.bodyY))
            p.addCurve(to: P(rig.bodyW * 0.3, rig.bodyTop + 0.2), control1: P(rig.bodyW / 2 + 0.1, rig.bodyY), control2: P(rig.bodyW / 2, rig.bodyTop + 0.2))
            p.closeSubpath()
            a.solid(p, w, gloss: 0.3)
        case "pigtails":
            for side in [-1.0, 1.0] as [CGFloat] {
                let root = CGPoint(x: side * (rig.bodyW / 2 - 0.06), y: rig.bodyTop + 0.12)
                let swing = sw * side
                var p = Path()
                p.move(to: P(root.x, root.y - 0.05))
                p.addCurve(to: P(root.x + side * 0.12 + swing, root.y + 0.36), control1: P(root.x + side * 0.22, root.y - 0.02), control2: P(root.x + side * 0.2, root.y + 0.2))
                p.addCurve(to: P(root.x, root.y + 0.06), control1: P(root.x + side * 0.02, root.y + 0.25), control2: P(root.x - side * 0.02, root.y + 0.12))
                p.closeSubpath()
                a.solid(p, w, gloss: 0.3)
                a.dot(P(root.x + side * 0.03, root.y), L(0.035), Color(red: 1, green: 0.45, blue: 0.6), outline: .black.opacity(0.4))
            }
        case "afro":
            let c = CGPoint(x: 0, y: rig.bodyTop + 0.1)
            let r = rig.bodyW * 0.58
            for i in 0..<12 {
                let ang = Double(i) / 12 * 2 * .pi
                let pc = P(c.x + cos(ang) * r * 0.8, c.y + sin(ang) * r * 0.55 - 0.04)
                a.solid(Path(ellipseIn: CGRect(x: pc.x - L(0.13), y: pc.y - L(0.13), width: L(0.26), height: L(0.26))), w, gloss: 0.15, edge: 0.6)
            }
        default:
            break
        }
    }

    func hairFront(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let g = faceSafe()
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        let style = e.item.style
        var cap: Path
        switch style {
        case "spiky": cap = inflated(1.05).meet(fringeRegion(bumps: 7, depth: 0.04))
        case "swoop": cap = inflated(1.05).meet(fringeRegion(bumps: 3, depth: 0.03, slant: 0.06))
        case "curlybob", "afro": cap = inflated(1.06).meet(fringeRegion(bumps: 8, depth: 0.03))
        case "mohawk": cap = Path()
        default: cap = inflated(1.05).meet(fringeRegion(bumps: 5, depth: 0.025))
        }
        if ["bob", "curlybob", "waves", "braid"].contains(style) {
            cap = cap.join(sideLocks(to: style == "waves" ? rig.bodyBottom - 0.06 : rig.mouthY + 0.04))
        }
        if !cap.isEmpty {
            a.solid(cap, w, gloss: 0.15)
            strands(cap, w)
            hairShine(cap, w)
        }
        switch style {
        case "spiky":
            for i in 0..<5 {
                let x = CGFloat(i - 2) * rig.bodyW * 0.15
                var sp = Path()
                let base = rig.bodyTop + 0.05 + abs(x) * 0.3
                sp.move(to: P(x - 0.09, base))
                sp.addLine(to: P(x * 1.25, base - 0.2 + abs(x) * 0.2))
                sp.addLine(to: P(x + 0.09, base))
                sp.closeSubpath()
                a.solid(sp, w, gloss: 0.3)
            }
        case "topbun", "twinbuns":
            let spots: [CGFloat] = style == "topbun" ? [0] : [-rig.bodyW * 0.28, rig.bodyW * 0.28]
            for x in spots {
                let c = P(x, rig.bodyTop - (style == "topbun" ? 0.06 : 0.02))
                let r = L(style == "topbun" ? 0.13 : 0.1)
                a.solid(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), w, gloss: 0.4)
                var g2 = g; g2.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)))
                g2.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.5, width: r * 1.1, height: r)), with: .color(w.deep.opacity(0.4)), lineWidth: stroke * 0.7)
                a.solid(Path(roundedRect: CGRect(x: c.x - r * 0.7, y: c.y + r * 0.7, width: r * 1.4, height: r * 0.35), cornerRadius: r * 0.15), MascotSwatch(Color(red: 1, green: 0.45, blue: 0.6)), gloss: 0.3)
            }
        case "swoop":
            var curl = Path()
            curl.move(to: P(-rig.bodyW * 0.4, rig.bodyTop + 0.06))
            curl.addCurve(to: P(rig.bodyW * 0.3, rig.bodyTop - 0.02), control1: P(-rig.bodyW * 0.2, rig.bodyTop - 0.2), control2: P(rig.bodyW * 0.1, rig.bodyTop - 0.18))
            curl.addQuadCurve(to: P(-rig.bodyW * 0.4, rig.bodyTop + 0.06), control: P(0, rig.bodyTop - 0.02))
            a.solid(curl, w, gloss: 0.4)
        case "mohawk":
            for i in 0..<5 {
                let u = CGFloat(i) / 4
                let y = rig.bodyTop + 0.02 + abs(u - 0.5) * 0.08
                let x = (u - 0.5) * rig.bodyW * 0.32
                var sp = Path()
                sp.move(to: P(x - 0.05, y + 0.04))
                sp.addLine(to: P(x + 0.04, y - 0.2))
                sp.addLine(to: P(x + 0.06, y + 0.04))
                sp.closeSubpath()
                a.solid(sp, w, gloss: 0.3)
            }
        case "braid":
            let x = rig.faceHalfWidth + 0.08
            var y = fringeY
            var i = 0
            while y < rig.hipY {
                let r = L(0.045)
                let c = P(x + (i % 2 == 0 ? -0.015 : 0.015), y)
                a.solid(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 1.2, width: r * 2, height: r * 2.4)), w, gloss: 0.3)
                y += 0.06; i += 1
            }
            a.dot(P(x, y), L(0.03), Color(red: 1, green: 0.45, blue: 0.6), outline: .black.opacity(0.4))
        case "curlybob":
            for i in 0..<6 {
                let x = CGFloat(i) / 5 * rig.bodyW * 0.8 - rig.bodyW * 0.4
                a.solid(Path(ellipseIn: R(x - 0.06, rig.bodyTop - 0.04 + abs(x) * 0.1, 0.12, 0.12)), w, gloss: 0.25)
            }
        default:
            break
        }
    }

    func hood(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let p = inflated(1.14).meet(above(rig.neckY + 0.03))
        art.solid(p, MascotSwatch(w.dark), gloss: 0.2)
        var g = ctx; g.clip(to: p)
        g.stroke(inflated(1.06), with: .color(w.deep.opacity(0.6)), lineWidth: L(0.03))
    }

    // MARK: Face props (exempt from the face clip: they frame the eyes and stay see-through)

    func face(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let a = art
        let r = rig.eyeSize * 0.62 + 0.03
        let ey = rig.eyeY
        let ex = rig.eyeSpread
        let templeX = max(ex + r + 0.03, rig.chord(at: ey) / 2 - 0.01)
        let cheekY = min(rig.eyeY + rig.eyeSize * 0.85, rig.mouthY)
        let cheekX = ex + 0.08
        func lens(_ x: CGFloat) -> Path { Path(ellipseIn: R(x - r, ey - r, r * 2, r * 2)) }
        func frames(_ lenses: [Path], tint: Color?, tintOpacity: Double, frame: MascotSwatch, width: CGFloat = 0.02) {
            for l in lenses {
                if let tint {
                    a.g.fill(l, with: .linearGradient(Gradient(colors: [tint.opacity(tintOpacity + 0.12), tint.opacity(tintOpacity - 0.08)]), startPoint: CGPoint(x: l.boundingRect.midX, y: l.boundingRect.minY), endPoint: CGPoint(x: l.boundingRect.midX, y: l.boundingRect.maxY)))
                } else {
                    a.g.fill(l, with: .color(.white.opacity(0.1)))
                }
                var g = a.g; g.clip(to: l)
                var glare = Path(); glare.move(to: CGPoint(x: l.boundingRect.minX + l.boundingRect.width * 0.25, y: l.boundingRect.maxY - l.boundingRect.height * 0.3)); glare.addLine(to: CGPoint(x: l.boundingRect.minX + l.boundingRect.width * 0.55, y: l.boundingRect.minY + l.boundingRect.height * 0.15))
                g.stroke(glare, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: L(0.018), lineCap: .round))
                a.g.stroke(l, with: .color(frame.ink), lineWidth: L(width) + stroke * 0.8)
                a.g.stroke(l, with: .color(frame.base), lineWidth: L(width))
            }
            var bridge = Path()
            bridge.move(to: P(-ex + r * 0.85, ey - r * 0.3))
            bridge.addQuadCurve(to: P(ex - r * 0.85, ey - r * 0.3), control: P(0, ey - r * 0.75))
            a.g.stroke(bridge, with: .color(frame.base), style: StrokeStyle(lineWidth: L(width), lineCap: .round))
            for side in [-1.0, 1.0] as [CGFloat] { a.line(P(side * (ex + r * 0.95), ey - r * 0.25), P(side * templeX, ey - r * 0.4), frame.base, width: 1.1) }
        }
        switch e.item.style {
        case "roundglasses": frames([lens(-ex), lens(ex)], tint: nil, tintOpacity: 0, frame: w)
        case "squareglasses", "tapedglasses":
            let sq = [-ex, ex].map { Path(roundedRect: R($0 - r, ey - r * 0.85, r * 2, r * 1.7), cornerRadius: L(0.04)) }
            frames(sq, tint: nil, tintOpacity: 0, frame: w, width: 0.028)
            if e.item.style == "tapedglasses" {
                a.solid(Path(roundedRect: R(-0.035, ey - r * 0.6, 0.07, 0.06), cornerRadius: L(0.01)), MascotSwatch(Color(white: 0.97)), gloss: 0.1)
            }
        case "heartshades":
            frames([-ex, ex].map { MascotShapes.heart(center: P($0, ey - 0.01), size: L(r * 2.3)) }, tint: e.color, tintOpacity: 0.42, frame: MascotSwatch(e.color.darker(0.2)))
        case "starshades":
            frames([-ex, ex].map { MascotShapes.star(center: P($0, ey), outer: L(r * 1.25), inner: L(r * 0.75)) }, tint: e.color, tintOpacity: 0.42, frame: MascotSwatch(e.color.darker(0.2)))
        case "aviators":
            let drops = [-ex, ex].map { x -> Path in
                var p = Path()
                p.move(to: P(x - r, ey - r * 0.7))
                p.addLine(to: P(x + r, ey - r * 0.7))
                p.addQuadCurve(to: P(x, ey + r * 1.05), control: P(x + r * 1.1, ey + r * 0.8))
                p.addQuadCurve(to: P(x - r, ey - r * 0.7), control: P(x - r * 1.1, ey + r * 0.8))
                return p
            }
            frames(drops, tint: Color(red: 0.25, green: 0.2, blue: 0.3), tintOpacity: 0.4, frame: w, width: 0.015)
            a.line(P(-ex + r * 0.8, ey - r * 0.68), P(ex - r * 0.8, ey - r * 0.68), w.base, width: 1)
        case "monocle":
            let l = lens(ex)
            a.g.fill(l, with: .color(.white.opacity(0.12)))
            a.g.stroke(l, with: .color(w.ink), lineWidth: L(0.024) + stroke * 0.8)
            a.g.stroke(l, with: .linearGradient(Gradient(colors: [w.lighter, w.base, w.dark]), startPoint: P(ex - r, ey - r), endPoint: P(ex + r, ey + r)), lineWidth: L(0.024))
            var chain = Path()
            chain.move(to: P(ex + r * 0.7, ey + r * 0.7))
            chain.addQuadCurve(to: P(templeX, rig.mouthY + 0.1), control: P(ex + r, rig.mouthY + 0.14))
            a.g.stroke(chain, with: .color(w.base), style: StrokeStyle(lineWidth: stroke * 0.8, dash: [stroke, stroke * 0.5]))
        case "masquerade":
            var mask = Path()
            let mw = templeX + 0.02
            mask.move(to: P(-mw, ey - r * 0.3))
            mask.addQuadCurve(to: P(0, ey - r * 0.9), control: P(-mw * 0.5, ey - r * 1.8))
            mask.addQuadCurve(to: P(mw, ey - r * 0.3), control: P(mw * 0.5, ey - r * 1.8))
            mask.addQuadCurve(to: P(0, ey + r * 0.6), control: P(mw * 0.6, ey + r * 1.6))
            mask.addQuadCurve(to: P(-mw, ey - r * 0.3), control: P(-mw * 0.6, ey + r * 1.6))
            mask.addPath(lens(-ex).applying(.identity))
            mask.addPath(lens(ex))
            var g = a.g
            g.clip(to: mask, style: FillStyle(eoFill: true))
            let mr = mask.boundingRect
            g.fill(Path(mr), with: .linearGradient(Gradient(colors: [w.light, w.base, w.dark]), startPoint: CGPoint(x: mr.minX, y: mr.minY), endPoint: CGPoint(x: mr.maxX, y: mr.maxY)))
            for i in 0..<10 {
                let ang = Double(i) / 10 * 2 * .pi
                g.fill(Path(ellipseIn: CGRect(x: mr.midX + cos(ang) * mr.width * 0.4 - L(0.008), y: mr.midY + sin(ang) * mr.height * 0.35 - L(0.008), width: L(0.016), height: L(0.016))), with: .color(.white.opacity(0.8)))
            }
            a.g.stroke(mask, with: .color(w.ink), style: StrokeStyle(lineWidth: stroke))
            var feather = Path()
            feather.move(to: P(mw - 0.02, ey - r * 0.4))
            feather.addQuadCurve(to: P(mw + 0.18, ey - r * 2.6), control: P(mw + 0.2, ey - r))
            feather.addQuadCurve(to: P(mw - 0.02, ey - r * 0.4), control: P(mw + 0.02, ey - r * 1.8))
            a.solid(feather, MascotSwatch(Color(red: 0.95, green: 0.5, blue: 0.75)), gloss: 0.3)
        case "visor":
            let band = Path(roundedRect: R(-templeX - 0.02, ey - r * 0.95, (templeX + 0.02) * 2, r * 1.9), cornerRadius: L(r * 0.9))
            a.g.fill(band, with: .linearGradient(Gradient(colors: [e.color.opacity(0.42), e.color.opacity(0.18)]), startPoint: P(0, ey - r), endPoint: P(0, ey + r)))
            var g = a.g; g.clip(to: band)
            let scan = amp > 0 ? CGFloat((t * 0.8).truncatingRemainder(dividingBy: 1)) : 0.3
            g.fill(Path(R(-templeX - 0.1 + scan * (templeX * 2 + 0.2), ey - r, 0.05, r * 2)), with: .color(.white.opacity(0.45)))
            a.g.stroke(band, with: .color(w.ink), lineWidth: stroke)
        case "glasses3d":
            let sq = [-ex, ex].map { Path(roundedRect: R($0 - r, ey - r * 0.8, r * 2, r * 1.6), cornerRadius: L(0.02)) }
            a.g.fill(sq[0], with: .color(Color.red.opacity(0.38)))
            a.g.fill(sq[1], with: .color(Color.cyan.opacity(0.38)))
            frames(sq, tint: nil, tintOpacity: 0, frame: MascotSwatch(.white), width: 0.03)
        case "blush":
            for side in [-1.0, 1.0] as [CGFloat] {
                let c = P(side * cheekX, cheekY)
                a.g.fill(Path(ellipseIn: CGRect(x: c.x - L(0.08), y: c.y - L(0.045), width: L(0.16), height: L(0.09))), with: .radialGradient(Gradient(colors: [e.color.opacity(0.75), e.color.opacity(0)]), center: c, startRadius: 0, endRadius: L(0.08)))
            }
        case "freckles":
            for side in [-1.0, 1.0] as [CGFloat] {
                for (dx, dy) in [(-0.03, 0.0), (0.0, 0.02), (0.03, -0.005), (0.015, -0.025)] as [(CGFloat, CGFloat)] {
                    a.dot(P(side * cheekX + dx, cheekY + dy), L(0.009), e.color.opacity(0.85))
                }
            }
        case "bandaid":
            var g = a.g
            let c = P(ex + 0.1, rig.eyeTop - 0.035)
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(0.5))
            let ba = MascotArt(g: g, u: 1, stroke: stroke)
            ba.solid(Path(roundedRect: CGRect(x: -L(0.08), y: -L(0.025), width: L(0.16), height: L(0.05)), cornerRadius: L(0.025)), w, gloss: 0.3)
            g.fill(Path(roundedRect: CGRect(x: -L(0.025), y: -L(0.02), width: L(0.05), height: L(0.04)), cornerRadius: L(0.008)), with: .color(w.dark))
        case "whiskers":
            for side in [-1.0, 1.0] as [CGFloat] {
                for k in -1...1 {
                    a.line(P(side * 0.16, rig.mouthY - 0.02 + CGFloat(k) * 0.025), P(side * min(0.36, templeX + 0.04), rig.mouthY - 0.04 + CGFloat(k) * 0.04), e.color.opacity(0.85), width: 0.8)
                }
            }
        case "starpaint", "heartpaint":
            let c = P(cheekX + 0.01, cheekY)
            if e.item.style == "starpaint" { a.solid(MascotShapes.star(center: c, outer: L(0.045), inner: L(0.02)), w, gloss: 0.5, outline: false) }
            else { a.solid(MascotShapes.heart(center: c, size: L(0.08)), w, gloss: 0.5, outline: false) }
        case "glitter":
            for side in [-1.0, 1.0] as [CGFloat] {
                for k in 0..<3 {
                    let ph = amp > 0 ? abs(sin(t * 3 + Double(k) * 2 + Double(side))) : 0.8
                    a.twinkle(P(side * (cheekX - 0.02 + CGFloat(k) * 0.025), cheekY - 0.02 + CGFloat(k % 2) * 0.03), L(0.018) * ph, color: e.color)
                }
            }
        case "teargem":
            a.gem(P(-ex, rig.eyeBottom + 0.04), L(0.025), e.color)
        default:
            break
        }
    }

    // MARK: Held items (local frame at the hand; 1 unit = 0.4 s; up is −y)

    func held(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let lift = emoteLift
        let hand = CGPoint(x: rig.hand.x, y: rig.hand.y - lift)
        let bob = amp > 0 ? 0.04 * sin(t * 1.8) : 0
        let a = local(hand, unit: 0.4, rotate: bob)
        let gold = MascotSwatch(Color(red: 1, green: 0.8, blue: 0.32))
        switch e.item.style {
        case "balloon":
            var string = Path()
            string.move(to: CGPoint(x: 0, y: 0))
            string.addCurve(to: CGPoint(x: 0.3, y: -1.45), control1: CGPoint(x: 0.2, y: -0.5), control2: CGPoint(x: 0.05, y: -1.0))
            a.g.stroke(string, with: .color(Color(white: 0.45)), lineWidth: a.lw * 0.7)
            let sway = amp > 0 ? 0.06 * sin(t * 1.3) : 0
            let b = Path(ellipseIn: CGRect(x: 0.02 + sway, y: -2.15, width: 0.56, height: 0.68))
            a.solid(b, w, gloss: 0.7)
            var knot = Path(); knot.move(to: CGPoint(x: 0.3 + sway, y: -1.48)); knot.addLine(to: CGPoint(x: 0.25 + sway, y: -1.4)); knot.addLine(to: CGPoint(x: 0.35 + sway, y: -1.4)); knot.closeSubpath()
            a.g.fill(knot, with: .color(w.dark))
        case "lollipop":
            a.solid(Path(roundedRect: CGRect(x: -0.03, y: -0.9, width: 0.06, height: 0.95), cornerRadius: 0.03), MascotSwatch(.white), gloss: 0.2)
            let disc = Path(ellipseIn: CGRect(x: -0.3, y: -1.4, width: 0.6, height: 0.6))
            a.solid(disc, w, gloss: 0.6)
            var sp = Path()
            for k in 0..<60 {
                let ang = Double(k) * 0.32
                let rr = 0.27 * Double(k) / 60
                let pt = CGPoint(x: cos(ang) * rr, y: -1.1 + sin(ang) * rr)
                if k == 0 { sp.move(to: pt) } else { sp.addLine(to: pt) }
            }
            a.g.stroke(sp, with: .color(.white.opacity(0.85)), lineWidth: 0.04)
        case "bouquet":
            for (i, off) in ([-0.18, 0.0, 0.18] as [CGFloat]).enumerated() {
                a.line(CGPoint(x: 0, y: 0), CGPoint(x: off, y: -0.7), Color(red: 0.3, green: 0.6, blue: 0.3), width: 1.2)
                let col = i == 1 ? w.base : w.base.mix(with: [Color.pink, Color.yellow][i / 2], by: 0.5)
                a.flower(CGPoint(x: off, y: -0.78 - (i == 1 ? 0.1 : 0)), 0.16, petal: col, center: Color(red: 1, green: 0.85, blue: 0.3))
            }
            var wrap = Path()
            wrap.move(to: CGPoint(x: -0.25, y: -0.5)); wrap.addLine(to: CGPoint(x: 0.25, y: -0.5)); wrap.addLine(to: CGPoint(x: 0.06, y: 0.12)); wrap.addLine(to: CGPoint(x: -0.06, y: 0.12)); wrap.closeSubpath()
            a.solid(wrap, MascotSwatch(Color(red: 0.95, green: 0.9, blue: 0.8)), gloss: 0.2)
        case "icecream":
            var cone = Path()
            cone.move(to: CGPoint(x: -0.2, y: -0.55)); cone.addLine(to: CGPoint(x: 0.2, y: -0.55)); cone.addLine(to: CGPoint(x: 0, y: 0.1)); cone.closeSubpath()
            a.solid(cone, MascotSwatch(Color(red: 0.9, green: 0.68, blue: 0.4)), gloss: 0.2)
            a.pattern(cone, .check, MascotSwatch(Color(red: 0.9, green: 0.68, blue: 0.4)), scale: 0.14)
            a.solid(Path(ellipseIn: CGRect(x: -0.24, y: -0.82, width: 0.48, height: 0.4)), MascotSwatch(Color(red: 0.98, green: 0.94, blue: 0.82)), gloss: 0.4)
            a.solid(Path(ellipseIn: CGRect(x: -0.22, y: -1.12, width: 0.44, height: 0.4)), w, gloss: 0.5)
            a.dot(CGPoint(x: 0.02, y: -1.15), 0.05, .red, outline: .black.opacity(0.3))
        case "book":
            let b = Path(roundedRect: CGRect(x: -0.3, y: -0.75, width: 0.5, height: 0.68), cornerRadius: 0.04)
            a.solid(b, w, gloss: 0.3)
            a.g.fill(Path(CGRect(x: 0.17, y: -0.72, width: 0.05, height: 0.62)), with: .color(.white.opacity(0.9)))
            a.solid(MascotShapes.star(center: CGPoint(x: -0.05, y: -0.42), outer: 0.1, inner: 0.045), gold, gloss: 0.4)
        case "coffee", "boba":
            let cup = Path { p in
                p.move(to: CGPoint(x: -0.2, y: -0.7)); p.addLine(to: CGPoint(x: 0.2, y: -0.7)); p.addLine(to: CGPoint(x: 0.15, y: 0.05)); p.addLine(to: CGPoint(x: -0.15, y: 0.05)); p.closeSubpath()
            }
            if e.item.style == "coffee" {
                a.solid(cup, w, gloss: 0.3)
                a.solid(Path(CGRect(x: -0.19, y: -0.45, width: 0.37, height: 0.2)), MascotSwatch(Color(red: 0.7, green: 0.5, blue: 0.3)), gloss: 0.1)
                a.solid(Path(roundedRect: CGRect(x: -0.23, y: -0.8, width: 0.46, height: 0.12), cornerRadius: 0.04), MascotSwatch(Color(white: 0.95)), gloss: 0.3)
                if amp > 0 {
                    for k in 0..<2 {
                        let ph = (t * 0.6 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                        var steam = Path()
                        steam.move(to: CGPoint(x: -0.06 + CGFloat(k) * 0.12, y: -0.85))
                        steam.addCurve(to: CGPoint(x: -0.06 + CGFloat(k) * 0.12, y: -1.2), control1: CGPoint(x: 0.06, y: -0.95), control2: CGPoint(x: -0.15, y: -1.1))
                        a.g.stroke(steam, with: .color(.white.opacity(0.7 * (1 - ph))), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))
                    }
                }
            } else {
                var g = a.g; g.opacity = 0.9
                MascotArt(g: g, u: a.u, stroke: stroke).solid(cup, w, gloss: 0.6)
                for k in 0..<6 { a.dot(CGPoint(x: -0.1 + CGFloat(k % 3) * 0.1, y: -0.08 - CGFloat(k / 3) * 0.08), 0.04, Color(red: 0.2, green: 0.12, blue: 0.1)) }
                a.solid(Path(ellipseIn: CGRect(x: -0.22, y: -0.85, width: 0.44, height: 0.24)), MascotSwatch(.white.opacity(0.9)), gloss: 0.5)
                a.solid(Path(roundedRect: CGRect(x: 0.0, y: -1.2, width: 0.06, height: 0.5), cornerRadius: 0.03), MascotSwatch(Color(red: 1, green: 0.5, blue: 0.6)), gloss: 0.3)
            }
        case "wand":
            a.solid(Path(roundedRect: CGRect(x: -0.03, y: -0.9, width: 0.06, height: 0.95), cornerRadius: 0.03), MascotSwatch(Color(white: 0.2)), gloss: 0.3)
            a.solid(MascotShapes.star(center: CGPoint(x: 0, y: -1.05), outer: 0.24, inner: 0.11), w, gloss: 0.7)
            if amp > 0 {
                for k in 0..<3 {
                    let ph = (t * 0.9 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    a.twinkle(CGPoint(x: 0.15 + ph * 0.4, y: -1.0 + ph * 0.3 - CGFloat(k) * 0.1), 0.08 * (1 - ph), color: w.lighter)
                }
            }
        case "umbrella":
            a.line(CGPoint(x: 0, y: 0.05), CGPoint(x: -0.3, y: -1.5), Color(white: 0.3), width: 1.4)
            var canopy = Path()
            canopy.move(to: CGPoint(x: -1.15, y: -1.25))
            canopy.addQuadCurve(to: CGPoint(x: 0.55, y: -1.25), control: CGPoint(x: -0.3, y: -2.3))
            for k in 0..<4 {
                let x0 = 0.55 - CGFloat(k) * 0.425
                canopy.addQuadCurve(to: CGPoint(x: x0 - 0.425, y: -1.25), control: CGPoint(x: x0 - 0.21, y: -1.12))
            }
            canopy.closeSubpath()
            a.solid(canopy, w, gloss: 0.5)
            a.pattern(canopy, e.item.pattern, w, scale: 0.3)
            var hook = Path(); hook.move(to: CGPoint(x: 0, y: 0.05)); hook.addQuadCurve(to: CGPoint(x: 0.12, y: 0.1), control: CGPoint(x: 0.06, y: 0.2))
            a.g.stroke(hook, with: .color(Color(white: 0.3)), lineWidth: a.lw * 1.4)
        case "sword":
            var blade = Path()
            blade.move(to: CGPoint(x: -0.06, y: -0.2)); blade.addLine(to: CGPoint(x: -0.06, y: -1.4)); blade.addLine(to: CGPoint(x: 0, y: -1.55)); blade.addLine(to: CGPoint(x: 0.06, y: -1.4)); blade.addLine(to: CGPoint(x: 0.06, y: -0.2)); blade.closeSubpath()
            a.metal(blade, w)
            a.metal(Path(roundedRect: CGRect(x: -0.24, y: -0.24, width: 0.48, height: 0.08), cornerRadius: 0.04), gold)
            a.solid(Path(roundedRect: CGRect(x: -0.04, y: -0.16, width: 0.08, height: 0.22), cornerRadius: 0.02), MascotSwatch(Color(red: 0.45, green: 0.28, blue: 0.16)), gloss: 0.2)
            a.gem(CGPoint(x: 0, y: -0.2), 0.05, Color(red: 0.9, green: 0.2, blue: 0.3), sparkle: 0.5)
            if amp > 0, sin(t * 1.7) > 0.8 { a.twinkle(CGPoint(x: 0.03, y: -1.2), 0.1) }
        case "lantern":
            a.line(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.15), Color(white: 0.3), width: 1)
            let glow = amp > 0 ? 0.7 + 0.3 * sin(t * 7) : 0.9
            a.g.fill(Path(ellipseIn: CGRect(x: -0.55, y: -0.05, width: 1.1, height: 1.1)), with: .radialGradient(Gradient(colors: [e.color.opacity(0.45 * glow), .clear]), center: CGPoint(x: 0, y: 0.5), startRadius: 0, endRadius: 0.55))
            let body = Path(roundedRect: CGRect(x: -0.2, y: 0.2, width: 0.4, height: 0.55), cornerRadius: 0.12)
            a.g.fill(body, with: .radialGradient(Gradient(colors: [Color.white, e.color, e.color.darker(0.2)]), center: CGPoint(x: 0, y: 0.48), startRadius: 0, endRadius: 0.3))
            a.g.stroke(body, with: .color(Color(white: 0.25)), lineWidth: a.lw)
            for x in [-0.07, 0.07] as [CGFloat] { a.line(CGPoint(x: x, y: 0.22), CGPoint(x: x, y: 0.73), Color(white: 0.25), width: 0.6) }
            a.solid(Path(roundedRect: CGRect(x: -0.16, y: 0.13, width: 0.32, height: 0.09), cornerRadius: 0.03), MascotSwatch(Color(white: 0.3)), gloss: 0.3)
        case "paintbrush":
            a.solid(Path(roundedRect: CGRect(x: -0.04, y: -0.7, width: 0.08, height: 0.8), cornerRadius: 0.04), MascotSwatch(Color(red: 0.75, green: 0.5, blue: 0.3)), gloss: 0.3)
            a.metal(Path(CGRect(x: -0.06, y: -0.85, width: 0.12, height: 0.16)), MascotSwatch(Color(white: 0.8)))
            var tip = Path()
            tip.move(to: CGPoint(x: -0.07, y: -0.85)); tip.addQuadCurve(to: CGPoint(x: 0.02, y: -1.15), control: CGPoint(x: -0.08, y: -1.05)); tip.addQuadCurve(to: CGPoint(x: 0.07, y: -0.85), control: CGPoint(x: 0.08, y: -1.0)); tip.closeSubpath()
            a.solid(tip, w, gloss: 0.5)
            let drip = amp > 0 ? CGFloat((t * 0.5).truncatingRemainder(dividingBy: 1)) : 0
            if drip > 0.3 { a.dot(CGPoint(x: 0.03, y: -1.15 + drip * 0.4), 0.03, w.base) }
        case "sparkler":
            a.line(CGPoint(x: 0, y: 0.05), CGPoint(x: 0, y: -0.9), Color(white: 0.5), width: 1)
            let n = 10
            for k in 0..<n {
                let ang = Double(k) / Double(n) * 2 * .pi + (amp > 0 ? t * 3 : 0)
                let len = 0.18 + (amp > 0 ? 0.08 * abs(sin(t * 20 + Double(k))) : 0.05)
                a.line(CGPoint(x: 0, y: -0.95), CGPoint(x: cos(ang) * len, y: -0.95 + sin(ang) * len), Color(red: 1, green: 0.9, blue: 0.5), width: 0.8)
            }
            a.g.fill(Path(ellipseIn: CGRect(x: -0.1, y: -1.05, width: 0.2, height: 0.2)), with: .radialGradient(Gradient(colors: [.white, Color.yellow.opacity(0)]), center: CGPoint(x: 0, y: -0.95), startRadius: 0, endRadius: 0.12))
        case "trophy":
            var cup = Path()
            cup.move(to: CGPoint(x: -0.3, y: -0.95)); cup.addLine(to: CGPoint(x: 0.3, y: -0.95))
            cup.addQuadCurve(to: CGPoint(x: 0.05, y: -0.45), control: CGPoint(x: 0.3, y: -0.5))
            cup.addLine(to: CGPoint(x: -0.05, y: -0.45))
            cup.addQuadCurve(to: CGPoint(x: -0.3, y: -0.95), control: CGPoint(x: -0.3, y: -0.5))
            for side in [-1.0, 1.0] as [CGFloat] {
                a.g.stroke(Path(ellipseIn: CGRect(x: side > 0 ? 0.22 : -0.42, y: -0.9, width: 0.2, height: 0.24)), with: .color(w.dark), lineWidth: 0.05)
            }
            a.metal(cup, w)
            a.metal(Path(CGRect(x: -0.05, y: -0.46, width: 0.1, height: 0.25)), w)
            a.solid(Path(roundedRect: CGRect(x: -0.2, y: -0.22, width: 0.4, height: 0.2), cornerRadius: 0.03), MascotSwatch(Color(red: 0.35, green: 0.22, blue: 0.14)), gloss: 0.3)
            a.solid(MascotShapes.star(center: CGPoint(x: 0, y: -0.75), outer: 0.1, inner: 0.045), MascotSwatch(.white), gloss: 0.3, outline: false)
        default:
            break
        }
        // Paw nub gripping the item.
        let paw = MascotSwatch(rig.bodyTint)
        MascotArt(g: faceSafe(), u: 1, stroke: stroke).solid(Path(ellipseIn: R(hand.x - 0.055, hand.y - 0.045, 0.11, 0.09)), paw, gloss: 0.4)
    }

    // MARK: Back items

    func back(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let style = e.item.style
        let flap = amp > 0 ? sin(t * (style == "fairy" ? 9 : 4)) : 0
        let a = art
        switch style {
        case "butterfly", "fairy", "angel", "batwings", "dragonwings", "valwings":
            for side in [-1.0, 1.0] as [CGFloat] {
                let root = CGPoint(x: side * rig.bodyW * 0.22, y: rig.backAnchorY - 0.04)
                let la = local(root, unit: 0.5, rotate: Double(side) * (-0.12 * flap), flip: side < 0, clipFace: false)
                wing(style, la, w)
            }
        case "herocape", "streakcape", "royalcape", "wizardcape", "spookycape":
            let flutter = CGFloat(amp > 0 ? 0.03 * sin(t * 3) : 0)
            let topY = rig.neckY - 0.04
            let topHalf = min(shoulderHalf * 0.95, rig.bodyW * 0.42)
            let hem = (rig.floats ? rig.bodyBottom + 0.06 : rig.footY + 0.03)
            let hemHalf = rig.bodyW / 2 + 0.16
            var p = Path()
            p.move(to: P(-topHalf, topY))
            p.addLine(to: P(topHalf, topY))
            p.addQuadCurve(to: P(hemHalf + flutter, hem), control: P(hemHalf + 0.06, (topY + hem) / 2))
            let n = style == "spookycape" ? 6 : 4
            for i in 0..<n {
                let x0 = hemHalf - CGFloat(i) * hemHalf * 2 / CGFloat(n)
                let x1 = x0 - hemHalf * 2 / CGFloat(n)
                let wv = CGFloat(amp > 0 ? 0.02 * sin(t * 4 + Double(i)) : 0)
                if style == "spookycape" {
                    p.addLine(to: P((x0 + x1) / 2 + flutter, hem - 0.07))
                    p.addLine(to: P(x1 + flutter, hem + wv))
                } else if style == "streakcape" {
                    p.addQuadCurve(to: P(x1 + flutter, hem + wv), control: P((x0 + x1) / 2 + flutter, hem + 0.08))
                } else {
                    p.addQuadCurve(to: P(x1 + flutter, hem + wv), control: P((x0 + x1) / 2 + flutter, hem + 0.035))
                }
            }
            p.addQuadCurve(to: P(-topHalf, topY), control: P(-hemHalf - 0.06, (topY + hem) / 2))
            p.closeSubpath()
            if style == "streakcape" {
                let r = p.boundingRect
                a.g.fill(p, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.35, blue: 0.15), Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.88, blue: 0.35)]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                a.volume(p, w); a.shine(p, opacity: 0.3)
                a.g.stroke(p, with: .color(w.ink), lineWidth: stroke)
            } else {
                let lining = style == "spookycape" ? MascotSwatch(Color(red: 0.6, green: 0.1, blue: 0.18)) : MascotSwatch(w.dark)
                a.solid(p, lining, gloss: 0.25)
                var g = ctx; g.clip(to: p)
                g.stroke(p, with: .color(w.base), lineWidth: L(0.06))
                a.pattern(p, e.item.pattern, w, scale: L(0.12))
                if style == "royalcape" { ermine(along: p.meet(below(hem - 0.06)), width: 0.05) }
            }
        case "backpack":
            let pack = Path(roundedRect: R(-rig.bodyW / 2 - 0.08, rig.neckY - 0.06, rig.bodyW + 0.16, waistY - rig.neckY + 0.14), cornerRadius: L(0.08))
            a.solid(pack, w, gloss: 0.3)
            a.stitch(pack.applying(CGAffineTransform(translationX: 0, y: 0)), w)
            var handle = Path()
            handle.move(to: P(-0.08, rig.neckY - 0.05))
            handle.addQuadCurve(to: P(0.08, rig.neckY - 0.05), control: P(0, rig.neckY - 0.14))
            ctx.stroke(handle, with: .color(w.dark), lineWidth: L(0.03))
            for side in [-1.0, 1.0] as [CGFloat] {
                a.solid(Path(roundedRect: R(side * (rig.bodyW / 2 + 0.04) - 0.05, waistY - 0.06, 0.1, 0.12), cornerRadius: L(0.03)), MascotSwatch(w.dark), gloss: 0.2)
            }
        case "jetpack":
            for side in [-1.0, 1.0] as [CGFloat] {
                let x = side * (rig.bodyW / 2 + 0.02)
                let tank = Path(roundedRect: R(x - 0.075, rig.neckY - 0.1, 0.15, waistY - rig.neckY + 0.1), cornerRadius: L(0.07))
                a.metal(tank, w)
                var cone = Path()
                cone.move(to: P(x - 0.075, rig.neckY - 0.06)); cone.addQuadCurve(to: P(x + 0.075, rig.neckY - 0.06), control: P(x, rig.neckY - 0.22)); cone.closeSubpath()
                a.solid(cone, MascotSwatch(e.item.dyes.count > 1 ? e.item.dyes[1] : .red), gloss: 0.4)
                let fl = amp > 0 ? 0.04 * sin(t * 30 + Double(side)) : 0
                var flame = Path()
                flame.move(to: P(x - 0.05, waistY + 0.01))
                flame.addQuadCurve(to: P(x, waistY + 0.2 + fl), control: P(x - 0.06, waistY + 0.12))
                flame.addQuadCurve(to: P(x + 0.05, waistY + 0.01), control: P(x + 0.06, waistY + 0.12))
                ctx.fill(flame, with: .linearGradient(Gradient(colors: [.white, .yellow, .orange, .clear]), startPoint: P(x, waistY), endPoint: P(x, waistY + 0.22)))
            }
        case "shell":
            let sh = inflated(1.2).applying(CGAffineTransform(translationX: 0, y: -L(0.04)))
            a.solid(sh, w, gloss: 0.4)
            var g = ctx; g.clip(to: sh)
            let r = sh.boundingRect
            var y = r.minY
            var row = 0
            while y < r.maxY {
                var x = r.minX + (row % 2 == 0 ? 0 : L(0.09))
                while x < r.maxX {
                    g.stroke(MascotShapes.star(center: CGPoint(x: x, y: y), outer: L(0.08), inner: L(0.07), points: 6, rotation: 0), with: .color(w.deep.opacity(0.5)), lineWidth: stroke)
                    x += L(0.18)
                }
                y += L(0.14); row += 1
            }
        default:
            break
        }
    }

    /// Wing drawn in a local frame extending to +x (outward) and up; 1 unit = 0.5 s.
    func wing(_ style: String, _ a: MascotArt, _ w: MascotSwatch) {
        switch style {
        case "butterfly":
            let upper = Path(ellipseIn: CGRect(x: 0.05, y: -0.95, width: 0.85, height: 0.8)).applying(.identity)
            let lower = Path(ellipseIn: CGRect(x: 0.05, y: -0.25, width: 0.6, height: 0.55))
            a.solid(lower, MascotSwatch(w.dark), gloss: 0.3)
            a.solid(upper, w, gloss: 0.5)
            a.dot(CGPoint(x: 0.55, y: -0.6), 0.12, w.lighter, outline: w.ink)
            a.dot(CGPoint(x: 0.4, y: 0.02), 0.08, w.lighter, outline: w.ink)
            for k in 0..<3 { a.line(CGPoint(x: 0.05, y: -0.2), CGPoint(x: 0.35 + CGFloat(k) * 0.2, y: -0.9 + CGFloat(k) * 0.15), w.ink.opacity(0.4), width: 0.6) }
        case "fairy":
            var g = a.g; g.opacity = 0.72
            let fa = MascotArt(g: g, u: a.u, stroke: stroke)
            let up = Path(ellipseIn: CGRect(x: 0.0, y: -1.1, width: 0.5, height: 1.0)).applying(CGAffineTransform(rotationAngle: 0.5))
            let lo = Path(ellipseIn: CGRect(x: 0.05, y: -0.3, width: 0.4, height: 0.6)).applying(CGAffineTransform(rotationAngle: 0.2))
            for p in [lo, up] {
                fa.g.fill(p, with: .linearGradient(Gradient(colors: [w.lighter, Color(red: 0.85, green: 0.75, blue: 1), Color(red: 0.75, green: 1, blue: 0.9)]), startPoint: CGPoint(x: p.boundingRect.minX, y: p.boundingRect.minY), endPoint: CGPoint(x: p.boundingRect.maxX, y: p.boundingRect.maxY)))
                fa.shine(p, opacity: 0.6)
                fa.g.stroke(p, with: .color(w.ink.opacity(0.6)), lineWidth: a.lw * 0.8)
            }
        case "angel", "valwings":
            if style == "valwings" {
                let h = MascotShapes.heart(center: CGPoint(x: 0.45, y: -0.4), size: 0.85).applying(.identity)
                a.solid(h, w, gloss: 0.6)
                a.solid(MascotShapes.heart(center: CGPoint(x: 0.45, y: -0.38), size: 0.45), MascotSwatch(w.lighter), gloss: 0.3, outline: false)
                return
            }
            for row in 0..<3 {
                for k in 0..<(5 - row) {
                    let x = 0.1 + CGFloat(k) * 0.17 + CGFloat(row) * 0.05
                    let y = -0.75 + CGFloat(row) * 0.28 + CGFloat(k) * 0.06
                    let fe = Path(ellipseIn: CGRect(x: x, y: y, width: 0.22, height: 0.5)).applying(CGAffineTransform(translationX: -x - 0.11, y: -y).concatenating(CGAffineTransform(rotationAngle: -0.4)).concatenating(CGAffineTransform(translationX: x + 0.11, y: y)))
                    a.solid(fe, MascotSwatch(w.base.darker(Double(row) * 0.06)), gloss: 0.4)
                }
            }
        case "batwings", "dragonwings":
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -0.2))
            p.addLine(to: CGPoint(x: 0.35, y: -0.85))
            p.addLine(to: CGPoint(x: 0.95, y: -0.6))
            p.addQuadCurve(to: CGPoint(x: 0.75, y: -0.2), control: CGPoint(x: 0.75, y: -0.45))
            p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.0), control: CGPoint(x: 0.55, y: -0.2))
            p.addQuadCurve(to: CGPoint(x: 0.2, y: 0.12), control: CGPoint(x: 0.3, y: -0.05))
            p.closeSubpath()
            a.solid(p, w, gloss: 0.35)
            for end in [CGPoint(x: 0.95, y: -0.6), CGPoint(x: 0.75, y: -0.2), CGPoint(x: 0.5, y: 0.0)] {
                a.line(CGPoint(x: 0.35, y: -0.85), end, w.deep, width: style == "dragonwings" ? 1.4 : 0.9)
            }
            if style == "dragonwings" { a.dot(CGPoint(x: 0.35, y: -0.87), 0.04, w.lighter, outline: w.ink) }
        default:
            break
        }
    }

    // MARK: Auras

    func orbitPoint(_ i: Int, _ n: Int, speed: Double) -> (CGPoint, Bool) {
        let ang = (amp > 0 ? t * speed : 0.4) + Double(i) / Double(n) * 2 * .pi
        let rx = rig.bodyW / 2 + 0.2, ry = rig.bodyH / 2 + 0.1
        let pt = CGPoint(x: cos(ang) * rx, y: rig.bodyY - 0.05 + sin(ang) * ry * 0.55)
        return (pt, sin(ang) > 0)
    }

    func risePoint(_ i: Int, _ n: Int, speed: Double) -> (CGPoint, Double) {
        let ph = ((amp > 0 ? t * speed : 0) + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
        let side: CGFloat = i % 2 == 0 ? -1 : 1
        let x = side * (rig.bodyW / 2 + 0.1 + 0.06 * CGFloat(sin(ph * 6 + Double(i))))
        let y = rig.bodyBottom - CGFloat(ph) * (rig.bodyH + 0.35)
        return (CGPoint(x: x, y: y), sin(ph * .pi))
    }

    func auraBack(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        switch e.item.style {
        case "rainbow":
            let cols: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
            for (i, c) in cols.enumerated() {
                let r = rig.bodyW * 0.78 - CGFloat(i) * 0.045
                var arc = Path()
                arc.addArc(center: P(0, rig.bodyY + 0.05), radius: L(r), startAngle: .degrees(190), endAngle: .degrees(-10), clockwise: false)
                ctx.stroke(arc, with: .color(c.opacity(0.75)), style: StrokeStyle(lineWidth: L(0.045), lineCap: .round))
            }
            for side in [-1.0, 1.0] as [CGFloat] {
                for k in 0..<3 {
                    let c = P(side * (rig.bodyW * 0.72 + CGFloat(k) * 0.05), rig.bodyY + 0.08 + CGFloat(k % 2) * 0.03)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - L(0.06), y: c.y - L(0.05), width: L(0.12), height: L(0.1))), with: .color(.white))
                }
            }
        case "galaxy":
            let c = P(0, rig.bodyY)
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(-0.3))
            let disc = Path(ellipseIn: CGRect(x: -L(0.8), y: -L(0.32), width: L(1.6), height: L(0.64)))
            g.fill(disc, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.8), w.base.opacity(0.7), (e.item.dyes.count > 1 ? e.item.dyes[1] : .pink).opacity(0.4), .clear]), center: .zero, startRadius: 0, endRadius: L(0.8)))
            for k in 0..<14 {
                let ang = Double(k) * 0.9 + (amp > 0 ? t * 0.5 : 0)
                let rr = L(0.25 + 0.04 * CGFloat(k))
                g.fill(Path(ellipseIn: CGRect(x: cos(ang) * rr - 1, y: sin(ang) * rr * 0.4 - 1, width: 2, height: 2)), with: .color(.white))
            }
        case "flamering", "lightning":
            if e.item.style == "flamering" {
                ring(w, front: false)
            } else if amp > 0 {
                for side in [-1.0, 1.0] as [CGFloat] where sin(t * 7 + Double(side) * 2) > 0.3 {
                    let b = MascotShapes.bolt(center: P(side * (rig.bodyW / 2 + 0.18), rig.bodyY - 0.15), size: L(0.32))
                    ctx.fill(b, with: .color(w.base))
                    ctx.stroke(b, with: .color(w.ink), lineWidth: stroke)
                }
            }
        default:
            orbiting(e, front: false)
        }
    }

    func ring(_ w: MascotSwatch, front: Bool) {
        let c = P(0, rig.bodyY + rig.bodyH * 0.3)
        let rx = L(rig.bodyW / 2 + 0.16), ry = L(0.12)
        var arc = Path()
        arc.addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
        var g = ctx
        g.clip(to: Path(CGRect(x: c.x - rx * 1.5, y: front ? c.y : c.y - ry * 4, width: rx * 3, height: ry * 4)))
        g.stroke(arc, with: .color(w.base.opacity(0.85)), lineWidth: L(0.03))
        for k in 0..<12 {
            let ang = Double(k) / 12 * 2 * .pi + (amp > 0 ? t * 1.2 : 0)
            let isFront = sin(ang) > 0
            guard isFront == front else { continue }
            let p = CGPoint(x: c.x + cos(ang) * rx, y: c.y + sin(ang) * ry)
            let h = L(0.12) * (amp > 0 ? 0.7 + 0.3 * abs(sin(t * 8 + Double(k))) : 1)
            var f = Path()
            f.move(to: CGPoint(x: p.x - L(0.035), y: p.y))
            f.addQuadCurve(to: CGPoint(x: p.x, y: p.y - h), control: CGPoint(x: p.x - L(0.04), y: p.y - h * 0.6))
            f.addQuadCurve(to: CGPoint(x: p.x + L(0.035), y: p.y), control: CGPoint(x: p.x + L(0.04), y: p.y - h * 0.6))
            ctx.fill(f, with: .linearGradient(Gradient(colors: [.yellow, w.base, w.base.opacity(0)]), startPoint: p, endPoint: CGPoint(x: p.x, y: p.y - h)))
        }
    }

    func auraFront(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        switch e.item.style {
        case "flamering": ring(w, front: true)
        case "raincloud":
            let g = faceSafe()
            let a = MascotArt(g: g, u: 1, stroke: stroke)
            let cyc = rig.headTop - 0.32
            let bob = CGFloat(amp > 0 ? 0.02 * sin(t * 1.5) : 0)
            for (x, y, r) in [(-0.12, 0.02, 0.1), (0.0, -0.03, 0.13), (0.13, 0.02, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
                a.solid(Path(ellipseIn: R(x - r, cyc + y - r + bob, r * 2, r * 2)), w, gloss: 0.3, outline: false)
            }
            for k in 0..<5 {
                let ph = CGFloat(((amp > 0 ? t * 1.4 : 0) + Double(k) * 0.37).truncatingRemainder(dividingBy: 1))
                let x = -0.15 + CGFloat(k) * 0.075
                let y = cyc + 0.1 + ph * 0.25
                a.line(P(x, y), P(x - 0.01, y + 0.04), Color(red: 0.5, green: 0.7, blue: 1).opacity(Double(1 - ph)), width: 1.1)
            }
        case "flamering_none":
            break
        case "rainbow", "galaxy", "lightning":
            break
        case "fireworks":
            let g = faceSafe()
            for k in 0..<3 {
                let ph = ((amp > 0 ? t * 0.5 : 0.5) + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let c = P(CGFloat(k - 1) * 0.42, rig.headTop - 0.22 - CGFloat(k % 2) * 0.12)
                let col: Color = [Color(red: 1, green: 0.75, blue: 0.25), Color(red: 0.4, green: 0.7, blue: 1), Color(red: 1, green: 0.45, blue: 0.7)][k]
                for r in 0..<10 {
                    let ang = Double(r) / 10 * 2 * .pi
                    let d = L(0.04 + 0.14 * CGFloat(ph))
                    var ray = Path()
                    ray.move(to: CGPoint(x: c.x + cos(ang) * d * 0.6, y: c.y + sin(ang) * d * 0.6))
                    ray.addLine(to: CGPoint(x: c.x + cos(ang) * d, y: c.y + sin(ang) * d))
                    g.stroke(ray, with: .color(col.opacity(1 - ph)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
            }
        default:
            orbiting(e, front: true)
        }
    }

    /// Particle auras: orbiting or rising motifs, split front/back around the body.
    func orbiting(_ e: MascotWearList.Entry, front: Bool) {
        let w = MascotSwatch(e.color)
        let g = faceSafe()
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        let style = e.item.style
        let rising = ["hearts", "bubbles", "zzz", "notes", "heartburst"].contains(style)
        let falling = ["snow", "leaves", "petals"].contains(style)
        let n = style == "heartburst" ? 8 : 6
        for i in 0..<n {
            var pt: CGPoint
            var alpha = 1.0
            if rising {
                guard front else { return }
                let r = risePoint(i, n, speed: 0.35)
                pt = r.0; alpha = r.1
            } else if falling {
                guard front else { return }
                let r = risePoint(i, n, speed: 0.25)
                pt = CGPoint(x: r.0.x, y: rig.bodyTop + rig.bodyBottom - r.0.y - 0.2); alpha = r.1
            } else {
                let o = orbitPoint(i, n, speed: 1.1)
                guard o.1 == front else { continue }
                pt = o.0
            }
            let c = P(pt.x, pt.y)
            var g2 = g; g2.opacity = alpha
            let pa = MascotArt(g: g2, u: 1, stroke: stroke)
            let k = L(0.07)
            switch style {
            case "sparkles": pa.twinkle(c, k * (amp > 0 ? 0.7 + 0.3 * abs(sin(t * 4 + Double(i))) : 1), color: e.color)
            case "hearts", "heartburst": pa.solid(MascotShapes.heart(center: c, size: k * 1.4), w, gloss: 0.5, outline: false)
            case "notes": pa.g.fill(MascotShapes.note(center: c, size: k * 1.5), with: .color(e.color))
            case "bubbles":
                pa.g.fill(Path(ellipseIn: CGRect(x: c.x - k * 0.7, y: c.y - k * 0.7, width: k * 1.4, height: k * 1.4)), with: .color(e.color.opacity(0.25)))
                pa.g.stroke(Path(ellipseIn: CGRect(x: c.x - k * 0.7, y: c.y - k * 0.7, width: k * 1.4, height: k * 1.4)), with: .color(.white.opacity(0.9)), lineWidth: stroke * 0.7)
                pa.dot(CGPoint(x: c.x - k * 0.3, y: c.y - k * 0.3), k * 0.15, .white)
            case "zzz": pa.g.draw(Text("z").font(.system(size: k * 1.6, weight: .heavy, design: .rounded)).foregroundStyle(e.color), at: c)
            case "petals": pa.g.fill(MascotShapes.leaf(center: c, size: k * 1.2, angle: Double(i) + t), with: .color(e.color))
            case "leaves": pa.solid(MascotShapes.leaf(center: c, size: k * 1.5, angle: Double(i) * 1.3 + t), MascotSwatch(i % 2 == 0 ? e.color : Color(red: 0.85, green: 0.3, blue: 0.2)), gloss: 0.2, outline: false)
            case "snow": pa.dot(c, k * 0.35, .white, outline: Color(red: 0.7, green: 0.8, blue: 0.95))
            case "candyaura":
                pa.solid(Path(ellipseIn: CGRect(x: c.x - k * 0.5, y: c.y - k * 0.4, width: k, height: k * 0.8)), MascotSwatch(i % 2 == 0 ? e.color : Color(red: 0.6, green: 0.3, blue: 0.8)), gloss: 0.5)
            default: pa.twinkle(c, k, color: e.color)
            }
        }
        _ = a
    }

    // MARK: Pets (local frame on the ground to the mascot's left; 1 unit = 0.3 s; faces +x)

    func pet(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let style = e.item.style
        let flying = ["bee", "ghostie", "dragonling"].contains(style)
        let hop = CGFloat(amp > 0 ? abs(sin(t * (flying ? 1.6 : 3.2))) * (flying ? 0.05 : 0.03) : 0)
        let ground = rig.floats ? rig.bodyY + 0.3 : rig.footY
        let x = -(rig.bodyW / 2 + 0.24)
        let y = flying ? rig.bodyTop + 0.1 - hop : ground - hop
        let a = local(CGPoint(x: x, y: y), unit: 0.3)
        let ink = MascotSwatch(Color(red: 0.15, green: 0.1, blue: 0.15))
        func eyes(_ c: CGPoint, _ r: CGFloat = 0.06) {
            let blink = amp > 0 && sin(t * 0.7 + 1) > 0.97
            if blink { a.line(CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x + r, y: c.y), ink.base, width: 1.2) }
            else { a.dot(c, r, ink.base); a.dot(CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), r * 0.35, .white) }
        }
        // Soft contact shadow.
        if !flying { a.g.fill(Path(ellipseIn: CGRect(x: -0.4, y: 0.0 + hop / 0.3, width: 0.8, height: 0.14)), with: .color(.black.opacity(0.18))) }
        switch style {
        case "chick":
            let b = Path(ellipseIn: CGRect(x: -0.35, y: -0.7, width: 0.7, height: 0.7))
            a.solid(b, w, gloss: 0.5)
            var beak = Path(); beak.move(to: CGPoint(x: 0.3, y: -0.42)); beak.addLine(to: CGPoint(x: 0.46, y: -0.36)); beak.addLine(to: CGPoint(x: 0.3, y: -0.3)); beak.closeSubpath()
            a.solid(beak, MascotSwatch(Color(red: 1, green: 0.55, blue: 0.2)), gloss: 0.2)
            eyes(CGPoint(x: 0.15, y: -0.45))
            a.solid(Path(ellipseIn: CGRect(x: -0.2, y: -0.35, width: 0.3, height: 0.18)), MascotSwatch(w.dark), gloss: 0.2)
            a.line(CGPoint(x: 0, y: -0.7), CGPoint(x: 0.05, y: -0.82), w.dark, width: 1.2)
        case "snail":
            var slug = Path(); slug.move(to: CGPoint(x: -0.45, y: 0)); slug.addLine(to: CGPoint(x: 0.4, y: 0)); slug.addQuadCurve(to: CGPoint(x: 0.3, y: -0.3), control: CGPoint(x: 0.5, y: -0.25)); slug.addLine(to: CGPoint(x: -0.3, y: -0.12)); slug.closeSubpath()
            a.solid(slug, MascotSwatch(Color(red: 0.85, green: 0.8, blue: 0.65)), gloss: 0.4)
            let shell = Path(ellipseIn: CGRect(x: -0.4, y: -0.62, width: 0.55, height: 0.55))
            a.solid(shell, w, gloss: 0.5)
            var sp = Path()
            for k in 0..<40 { let ang = Double(k) * 0.35; let rr = 0.22 * Double(k) / 40; let pt = CGPoint(x: -0.125 + cos(ang) * rr, y: -0.345 + sin(ang) * rr); if k == 0 { sp.move(to: pt) } else { sp.addLine(to: pt) } }
            a.g.stroke(sp, with: .color(w.deep), lineWidth: a.lw)
            for dx in [0.28, 0.38] as [CGFloat] { a.line(CGPoint(x: dx, y: -0.25), CGPoint(x: dx + 0.04, y: -0.48), Color(red: 0.7, green: 0.65, blue: 0.5), width: 1); a.dot(CGPoint(x: dx + 0.04, y: -0.5), 0.035, ink.base) }
        case "kitty", "puppy", "bunnypet":
            let b = Path(ellipseIn: CGRect(x: -0.35, y: -0.45, width: 0.62, height: 0.45))
            let tailWag = amp > 0 ? 0.25 * sin(t * (style == "puppy" ? 9 : 3)) : 0
            var tail = Path(); tail.move(to: CGPoint(x: -0.3, y: -0.25)); tail.addQuadCurve(to: CGPoint(x: -0.5 + tailWag * 0.3, y: -0.6), control: CGPoint(x: -0.55, y: -0.3))
            if style != "bunnypet" { a.g.stroke(tail, with: .color(w.ink), style: StrokeStyle(lineWidth: 0.12, lineCap: .round)); a.g.stroke(tail, with: .color(w.base), style: StrokeStyle(lineWidth: 0.08, lineCap: .round)) }
            else { a.dot(CGPoint(x: -0.35, y: -0.25), 0.09, .white, outline: w.ink) }
            a.solid(b, w, gloss: 0.4)
            let head = Path(ellipseIn: CGRect(x: 0.02, y: -0.78, width: 0.46, height: 0.42))
            switch style {
            case "kitty":
                for ex in [0.08, 0.32] as [CGFloat] {
                    var ear = Path(); ear.move(to: CGPoint(x: ex, y: -0.66)); ear.addLine(to: CGPoint(x: ex + 0.04, y: -0.9)); ear.addLine(to: CGPoint(x: ex + 0.14, y: -0.7)); ear.closeSubpath()
                    a.solid(ear, w, gloss: 0.2)
                }
            case "puppy":
                for ex in [0.0, 0.38] as [CGFloat] { a.solid(Path(ellipseIn: CGRect(x: ex, y: -0.74, width: 0.12, height: 0.3)), MascotSwatch(w.dark), gloss: 0.2) }
            default:
                for ex in [0.12, 0.28] as [CGFloat] {
                    a.solid(Path(ellipseIn: CGRect(x: ex, y: -1.18, width: 0.12, height: 0.46)), w, gloss: 0.3)
                    a.g.fill(Path(ellipseIn: CGRect(x: ex + 0.03, y: -1.1, width: 0.06, height: 0.3)), with: .color(Color(red: 1, green: 0.72, blue: 0.8)))
                }
            }
            a.solid(head, w, gloss: 0.45)
            eyes(CGPoint(x: 0.18, y: -0.6), 0.045)
            eyes(CGPoint(x: 0.35, y: -0.6), 0.045)
            a.dot(CGPoint(x: 0.27, y: -0.52), 0.03, Color(red: 0.95, green: 0.5, blue: 0.6))
        case "bee":
            let wf = amp > 0 ? abs(sin(t * 40)) : 0.8
            for wx in [-0.12, 0.05] as [CGFloat] {
                var g = a.g; g.opacity = 0.7
                g.fill(Path(ellipseIn: CGRect(x: wx, y: -0.55 - 0.15 * wf, width: 0.2, height: 0.3 * wf + 0.05)), with: .color(.white))
            }
            let b = Path(ellipseIn: CGRect(x: -0.3, y: -0.4, width: 0.6, height: 0.4))
            a.solid(b, w, gloss: 0.5)
            var g = a.g; g.clip(to: b)
            for sx in [-0.12, 0.06] as [CGFloat] { g.fill(Path(CGRect(x: sx, y: -0.5, width: 0.08, height: 0.6)), with: .color(ink.base)) }
            eyes(CGPoint(x: 0.18, y: -0.24), 0.045)
        case "ghostie":
            var g = a.g; g.opacity = 0.9
            let ga = MascotArt(g: g, u: a.u, stroke: stroke)
            var p = Path()
            p.move(to: CGPoint(x: -0.3, y: 0))
            p.addLine(to: CGPoint(x: -0.3, y: -0.4))
            p.addArc(center: CGPoint(x: 0, y: -0.4), radius: 0.3, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: 0.3, y: 0))
            let wv = amp > 0 ? 0.03 * sin(t * 5) : 0
            for k in 0..<3 { let x0 = 0.3 - CGFloat(k) * 0.2; p.addQuadCurve(to: CGPoint(x: x0 - 0.2, y: 0), control: CGPoint(x: x0 - 0.1, y: (k % 2 == 0 ? -0.08 : 0.06) + wv)) }
            p.closeSubpath()
            ga.solid(p, w, gloss: 0.6)
            eyes(CGPoint(x: -0.05, y: -0.42), 0.05); eyes(CGPoint(x: 0.12, y: -0.42), 0.05)
            a.dot(CGPoint(x: 0.04, y: -0.3), 0.04, ink.base)
        case "slime":
            let sq = amp > 0 ? 0.06 * sin(t * 4) : 0
            var p = Path()
            p.move(to: CGPoint(x: -0.38 - sq, y: 0))
            p.addCurve(to: CGPoint(x: 0.38 + sq, y: 0), control1: CGPoint(x: -0.4, y: -0.7 + sq * 2), control2: CGPoint(x: 0.4, y: -0.7 + sq * 2))
            p.closeSubpath()
            var g = a.g; g.opacity = 0.92
            MascotArt(g: g, u: a.u, stroke: stroke).solid(p, w, gloss: 0.8)
            eyes(CGPoint(x: 0.0, y: -0.25), 0.05); eyes(CGPoint(x: 0.18, y: -0.25), 0.05)
        case "fishbowl":
            let bowl = Path(ellipseIn: CGRect(x: -0.4, y: -0.8, width: 0.8, height: 0.8))
            a.g.fill(bowl.meet(Path(CGRect(x: -0.5, y: -0.55, width: 1, height: 0.6))), with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.55)))
            let sw = amp > 0 ? 0.12 * sin(t * 1.2) : 0
            let fish = Path(ellipseIn: CGRect(x: -0.12 + sw, y: -0.38, width: 0.24, height: 0.14))
            a.solid(fish, w, gloss: 0.5)
            var tail = Path(); tail.move(to: CGPoint(x: -0.12 + sw, y: -0.31)); tail.addLine(to: CGPoint(x: -0.22 + sw, y: -0.38)); tail.addLine(to: CGPoint(x: -0.22 + sw, y: -0.24)); tail.closeSubpath()
            a.solid(tail, w, gloss: 0.2)
            a.dot(CGPoint(x: 0.06 + sw, y: -0.33), 0.02, ink.base)
            a.g.stroke(bowl, with: .color(.white.opacity(0.9)), lineWidth: a.lw * 1.2)
            a.shine(bowl, opacity: 0.6)
        case "dragonling":
            let flap = amp > 0 ? sin(t * 8) : 0
            for side in [-1.0, 1.0] as [CGFloat] {
                var g = a.g
                g.translateBy(x: 0, y: -0.35)
                g.rotate(by: .radians(Double(side) * (0.6 + 0.4 * flap)))
                var wing = Path(); wing.move(to: .zero); wing.addLine(to: CGPoint(x: 0, y: -0.4)); wing.addQuadCurve(to: CGPoint(x: side * 0.3, y: -0.1), control: CGPoint(x: side * 0.25, y: -0.35)); wing.closeSubpath()
                MascotArt(g: g, u: a.u, stroke: stroke).solid(wing, MascotSwatch(w.dark), gloss: 0.2)
            }
            let b = Path(ellipseIn: CGRect(x: -0.28, y: -0.5, width: 0.5, height: 0.42))
            a.solid(b, w, gloss: 0.5)
            let head = Path(ellipseIn: CGRect(x: 0.08, y: -0.75, width: 0.36, height: 0.32))
            a.solid(head, w, gloss: 0.5)
            for hx in [0.14, 0.3] as [CGFloat] { var horn = Path(); horn.move(to: CGPoint(x: hx, y: -0.72)); horn.addLine(to: CGPoint(x: hx + 0.02, y: -0.86)); horn.addLine(to: CGPoint(x: hx + 0.07, y: -0.72)); horn.closeSubpath(); a.solid(horn, MascotSwatch(Color(red: 1, green: 0.9, blue: 0.7)), gloss: 0.2) }
            eyes(CGPoint(x: 0.3, y: -0.6), 0.045)
            if amp > 0, sin(t * 0.8) > 0.9 {
                var puff = Path(); puff.addEllipse(in: CGRect(x: 0.44, y: -0.62, width: 0.14, height: 0.1))
                a.g.fill(puff, with: .color(Color.orange.opacity(0.8)))
            }
        default:
            break
        }
    }
}
