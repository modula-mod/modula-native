import SwiftUI

// MARK: - Full-body costume painting
//
// Drawn in the existing back / body / front wardrobe passes and fitted to the glossy
// round body through the shared garment paths. Every stroke stays inside the figure
// canvas (2.0s × 1.9s) so nothing is clipped or cut off.

extension MascotWearPainter {
    func costumeBack(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        switch e.item.style {
        case "starbolt":
            cape(w, length: 0.62, flare: 0.22, wave: true)
        case "hexweave":
            cape(MascotSwatch(e.color.darker(0.25)), length: 0.42, flare: 0.12, wave: false)
        case "nightveil":
            cape(w, length: 0.68, flare: 0.20, wave: true)
            hoodBack(w)
        case "solarranger":
            jetpack(w)
        case "pebbleknight":
            cape(MascotSwatch(e.item.dye(1)), length: 0.50, flare: 0.14, wave: false)
        case "glimmermage":
            cape(w, length: 0.70, flare: 0.24, wave: true)
        case "tidecaptain":
            cape(MascotSwatch(e.item.dye(1)), length: 0.56, flare: 0.16, wave: true)
        case "shadowstep":
            scarfTails(w)
        case "moonwalker", "voltframe", "auroradiver":
            packBox(w, accent: MascotSwatch(e.item.dye(1)))
        case "sproutsaur":
            dinoTail(w, spots: MascotSwatch(e.item.dye(2)))
        case "cottonhop":
            pomTail(w)
        case "crownlight":
            cape(w, length: 0.66, flare: 0.22, wave: true)
            ermineTrim(w)
        case "cluecoat":
            trenchTails(w)
        case "harvestpilot":
            shortCape(w)
        case "candymage":
            cape(w, length: 0.64, flare: 0.20, wave: true)
        case "meadowbard":
            shortCape(MascotSwatch(e.item.dye(1)))
        default:
            break
        }
    }

    func costumeBody(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let accent = MascotSwatch(e.item.dye(1))
        let trim = MascotSwatch(e.item.dye(min(2, max(0, e.item.dyes.count - 1))))
        switch e.item.style {
        case "starbolt":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.26)
            chestEmblem(starBoltEmblem(trim.base), color: trim)
            chestEmblem(MascotShapes.bolt(center: .zero, size: L(0.05)), color: accent)
            belt(accent, buckle: trim)
            boots(accent, height: 0.10)
        case "hexweave":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.28)
            hexLattice(w, on: garment(hem: rig.bodyBottom - 0.01, inflate: 1.04))
            belt(accent)
            boots(accent, height: 0.09)
        case "nightveil":
            suit(w, hem: rig.bodyBottom - 0.005, sleeves: 0.24)
            belt(accent, buckle: trim)
            boots(w, height: 0.11)
        case "solarranger":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.22, cuff: accent.base)
            chestEmblem(rangerBurst(trim.base), color: trim)
            belt(accent)
            boots(accent, height: 0.10)
        case "pebbleknight":
            suit(w, hem: rig.bodyBottom - 0.005, sleeves: 0.20)
            chestEmblem(shieldEmblem(accent.base), color: accent)
            belt(accent, buckle: accent)
            boots(MascotSwatch(w.dark), height: 0.11)
        case "glimmermage":
            robe(w, stars: true, hem: rig.bodyBottom + 0.01)
            sash(accent)
        case "tidecaptain":
            suit(w, hem: rig.hipY + 0.06, sleeves: 0.26, cuff: Color.white)
            sash(accent)
            boots(MascotSwatch(w.deep), height: 0.10)
        case "shadowstep":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.26)
            sash(accent)
            wraps(accent)
            boots(w, height: 0.08)
        case "moonwalker":
            suit(w, hem: rig.bodyBottom - 0.005, sleeves: 0.20, cuff: accent.base)
            chestBox(accent, light: trim)
            boots(w, height: 0.12, bulky: true)
        case "sproutsaur":
            onesie(w, belly: Color.white.opacity(0.92), spots: trim)
            boots(w, height: 0.08)
        case "cottonhop":
            onesie(w, belly: Color.white.opacity(0.95), spots: nil)
            boots(w, height: 0.07)
        case "whisk":
            suit(MascotSwatch(Color.white), hem: rig.hipY + 0.08, sleeves: 0.22, cuff: w.base)
            apron(Color.white, straps: accent)
            kerchief(accent)
        case "emberbrigade":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.24, cuff: accent.base)
            suspenders(accent)
            belt(accent, buckle: trim)
            boots(accent, height: 0.11)
        case "crownlight":
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.24, cuff: trim.base)
            sash(accent)
            boots(accent, height: 0.09)
        case "cluecoat":
            trench(w)
            belt(accent)
            boots(MascotSwatch(w.deep), height: 0.09)
        case "voltframe":
            suit(w, hem: rig.bodyBottom - 0.005, sleeves: 0.18, cuff: accent.base)
            panelLines(accent)
            chestLight(accent)
            boots(w, height: 0.10, bulky: true)
        case "auroradiver":
            suit(w, hem: rig.bodyBottom - 0.005, sleeves: 0.20, cuff: accent.base)
            chestBox(accent, light: trim)
            boots(w, height: 0.12, bulky: true)
        case "harvestpilot":
            jacket(w, collar: accent)
            belt(accent)
            boots(MascotSwatch(w.deep), height: 0.09)
        case "candymage":
            robe(w, stars: false, hem: rig.bodyBottom + 0.01, stripes: true)
            sash(accent)
        case "meadowbard":
            tunic(w, hem: rig.hipY + 0.10)
            sash(accent)
            boots(accent, height: 0.08)
        default:
            suit(w, hem: rig.bodyBottom - 0.01, sleeves: 0.22)
        }
    }

    func costumeFront(_ e: MascotWearList.Entry) {
        let w = MascotSwatch(e.color)
        let accent = MascotSwatch(e.item.dye(1))
        let trim = MascotSwatch(e.item.dye(min(2, max(0, e.item.dyes.count - 1))))
        switch e.item.style {
        case "starbolt":
            shortMask(accent, eyeCut: true)
        case "hexweave":
            hexMask(w, eyeCut: true)
        case "nightveil":
            hoodFront(w)
            shortMask(accent, eyeCut: true)
        case "solarranger":
            visorHelm(w, visor: accent, crest: trim)
        case "pebbleknight":
            knightHelm(w, plume: accent)
        case "glimmermage":
            pointyHat(w, brim: accent.base, star: trim)
        case "tidecaptain":
            tricorn(w, accent: accent)
        case "shadowstep":
            ninjaHood(w, eyeBand: accent)
        case "moonwalker":
            bubbleHelm(w, visor: accent)
        case "sproutsaur":
            dinoHood(w, spots: trim)
        case "cottonhop":
            bunnyHood(w, inner: Color(red: 1, green: 0.72, blue: 0.80))
        case "whisk":
            toque(Color.white)
        case "emberbrigade":
            fireHelm(w, badge: trim)
        case "crownlight":
            tinyCrown(accent)
        case "cluecoat":
            brimHat(w)
            glass(at: P(rig.hand.x * 0.92, rig.hand.y), color: accent)
        case "voltframe":
            robotHelm(w, visor: accent, antenna: trim)
        case "auroradiver":
            bubbleHelm(w, visor: accent)
        case "harvestpilot":
            aviatorCap(w, goggles: accent)
        case "candymage":
            pointyHat(w, brim: Color.white, star: trim)
        case "meadowbard":
            softCap(w)
            lute(at: P(-rig.hand.x * 0.9, rig.hand.y + 0.02), color: accent, face: trim)
        default:
            break
        }
    }

    // MARK: Shared costume pieces (all coordinates in rig units, kept inside the canvas)

    private var canvasSafeX: CGFloat { 0.92 }
    private var canvasSafeYTop: CGFloat { -0.88 }
    private var canvasSafeYBot: CGFloat { 0.88 }

    func suit(_ w: MascotSwatch, hem: CGFloat, sleeves sleeveLength: CGFloat, cuff: Color? = nil) {
        let p = garment(hem: min(hem, canvasSafeYBot), extra: 0, dip: 0.03, inflate: 1.04)
        guard !p.isEmpty else { return }
        art.solid(p, w, gloss: 0.38)
        sleeves(w, length: sleeveLength, width: 0.13, cuff: cuff)
    }

    func onesie(_ w: MascotSwatch, belly: Color, spots: MascotSwatch?) {
        let p = garment(hem: min(rig.bodyBottom - 0.005, canvasSafeYBot), extra: -0.01, dip: 0.02, inflate: 1.05)
        art.solid(p, w, gloss: 0.32)
        sleeves(w, length: 0.22, width: 0.14, cuff: w.light)
        let bellyPath = inflated(0.72).meet(belowNeck(0.04, dip: 0.04)).meet(above(rig.hipY + 0.04))
        if !bellyPath.isEmpty {
            art.solid(bellyPath, MascotSwatch(belly), gloss: 0.2, edge: 0.6)
        }
        if let spots {
            for pt in [P(-0.10, rig.bodyY + 0.02), P(0.12, rig.bodyY + 0.08), P(-0.04, rig.hipY)] {
                art.dot(pt, L(0.035), spots.base)
            }
        }
    }

    func robe(_ w: MascotSwatch, stars: Bool, hem: CGFloat, stripes: Bool = false) {
        let p = garment(hem: min(hem, canvasSafeYBot), extra: 0.01, dip: 0.05, inflate: 1.08)
        art.solid(p, w, gloss: 0.28)
        sleeves(w, length: 0.30, width: 0.15, cuff: w.lighter)
        if stars {
            art.pattern(p, .stars, w, scale: L(0.10))
        }
        if stripes {
            art.pattern(p, .stripes, w, scale: L(0.11))
        }
    }

    func tunic(_ w: MascotSwatch, hem: CGFloat) {
        let p = garment(hem: min(hem, canvasSafeYBot), extra: 0, dip: 0.03, inflate: 1.04)
        art.solid(p, w, gloss: 0.3)
        sleeves(w, length: 0.20, width: 0.13)
    }

    func jacket(_ w: MascotSwatch, collar: MascotSwatch) {
        let p = garment(hem: rig.hipY + 0.08, extra: 0, dip: 0.02, inflate: 1.07)
        art.solid(p, w, gloss: 0.3)
        sleeves(w, length: 0.24, width: 0.14, cuff: w.dark)
        collarTrim(collar)
    }

    func trench(_ w: MascotSwatch) {
        let p = garment(hem: min(rig.bodyBottom + 0.01, canvasSafeYBot), extra: 0.01, dip: 0.02, inflate: 1.08)
        art.solid(p, w, gloss: 0.26)
        sleeves(w, length: 0.26, width: 0.14, cuff: w.dark)
        lapels(w)
        collarTrim(w)
    }

    func collarTrim(_ w: MascotSwatch) {
        let p = necklineCurve(0, dip: 0.02, widen: 0.01)
        art.solid(p, w, gloss: 0.2, edge: 0.7)
    }

    func belt(_ w: MascotSwatch, buckle: MascotSwatch? = nil) {
        let y = rig.hipY - 0.02
        let half = min(rig.chord(at: y) / 2 * 1.02, canvasSafeX)
        var p = Path()
        p.addPath(Path(roundedRect: CGRect(x: P(-half, y).x, y: P(0, y).y, width: L(half * 2), height: L(0.045)), cornerRadius: L(0.012)))
        art.solid(p, w, gloss: 0.2)
        if let buckle {
            art.button(P(0, y + 0.022), L(0.028), buckle)
        }
    }

    func sash(_ w: MascotSwatch) {
        let y0 = rig.neckY + 0.06
        let y1 = min(rig.bodyBottom - 0.04, canvasSafeYBot)
        var p = Path()
        p.move(to: P(-0.04, y0))
        p.addLine(to: P(0.10, y0 + 0.02))
        p.addLine(to: P(0.18, y1))
        p.addLine(to: P(0.08, y1))
        p.closeSubpath()
        art.solid(p.meet(inflated(1.02)), w, gloss: 0.2)
    }

    func apron(_ color: Color, straps: MascotSwatch) {
        let p = inflated(0.82).meet(belowNeck(0.05, dip: 0.02)).meet(above(min(rig.bodyBottom - 0.02, canvasSafeYBot)))
        art.solid(p, MascotSwatch(color), gloss: 0.18)
        art.line(P(-0.10, rig.neckY + 0.01), P(-0.08, rig.bodyY), straps.base, width: L(0.018))
        art.line(P(0.10, rig.neckY + 0.01), P(0.08, rig.bodyY), straps.base, width: L(0.018))
    }

    func kerchief(_ w: MascotSwatch) {
        var p = Path()
        let y = rig.neckY + 0.01
        p.move(to: P(-0.12, y))
        p.addQuadCurve(to: P(0.12, y), control: P(0, y + 0.04))
        p.addLine(to: P(0.14, y + 0.03))
        p.addQuadCurve(to: P(-0.14, y + 0.03), control: P(0, y + 0.07))
        p.closeSubpath()
        art.solid(p, w, gloss: 0.25)
    }

    func suspenders(_ w: MascotSwatch) {
        art.line(P(-0.11, rig.neckY + 0.02), P(-0.08, rig.hipY), w.base, width: L(0.022))
        art.line(P(0.11, rig.neckY + 0.02), P(0.08, rig.hipY), w.base, width: L(0.022))
    }

    func wraps(_ w: MascotSwatch) {
        let y = rig.hipY + 0.02
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.16, y, 0.32, 0.04), cornerRadius: L(0.01)))
        art.solid(p, w, gloss: 0.15)
    }

    func boots(_ w: MascotSwatch, height: CGFloat, bulky: Bool = false) {
        guard rig.hasFeet else { return }
        let y = min(rig.footY - height * 0.2, canvasSafeYBot - height)
        let spread = min(rig.bodyW * 0.28, 0.22)
        let bw: CGFloat = bulky ? 0.13 : 0.10
        for side in [-1.0, 1.0] as [CGFloat] {
            let rect = R(side * spread - bw / 2, y, bw, min(height, canvasSafeYBot - y))
            art.solid(Path(roundedRect: rect, cornerRadius: L(0.03)), w, gloss: 0.22)
        }
    }

    func chestBox(_ w: MascotSwatch, light: MascotSwatch) {
        let r = R(-0.10, rig.bodyY - 0.02, 0.20, 0.16)
        art.solid(Path(roundedRect: r, cornerRadius: L(0.025)), w, gloss: 0.18)
        art.gem(P(0, rig.bodyY + 0.05), L(0.028), light.base)
    }

    func chestLight(_ w: MascotSwatch) {
        art.gem(P(0, rig.bodyY + 0.02), L(0.04), w.base, sparkle: 0.8)
    }

    func panelLines(_ w: MascotSwatch) {
        let clip = garment(hem: rig.bodyBottom - 0.01, inflate: 1.03)
        art.line(P(-0.14, rig.bodyY), P(0.14, rig.bodyY), w.dark.opacity(0.55), width: L(0.012))
        art.line(P(0, rig.neckY + 0.04), P(0, rig.hipY), w.dark.opacity(0.45), width: L(0.010))
        _ = clip
    }

    func chestEmblem(_ path: Path, color: MascotSwatch) {
        var g = ctx
        g.translateBy(x: P(0, rig.bodyY + 0.02).x, y: P(0, rig.bodyY + 0.02).y)
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        a.solid(path, color, gloss: 0.45)
    }

    func starBoltEmblem(_ color: Color) -> Path {
        _ = color
        return MascotShapes.star(center: .zero, outer: L(0.07), inner: L(0.03), points: 5)
    }

    func rangerBurst(_ color: Color) -> Path {
        _ = color
        return MascotShapes.star(center: .zero, outer: L(0.065), inner: L(0.028), points: 8)
    }

    func shieldEmblem(_ color: Color) -> Path {
        _ = color
        var p = Path()
        let s = L(0.055)
        p.move(to: CGPoint(x: 0, y: -s))
        p.addLine(to: CGPoint(x: s * 0.7, y: -s * 0.4))
        p.addLine(to: CGPoint(x: s * 0.6, y: s * 0.3))
        p.addQuadCurve(to: CGPoint(x: -s * 0.6, y: s * 0.3), control: CGPoint(x: 0, y: s * 0.9))
        p.addLine(to: CGPoint(x: -s * 0.7, y: -s * 0.4))
        p.closeSubpath()
        return p
    }

    func hexLattice(_ w: MascotSwatch, on clip: Path) {
        var g = ctx
        g.clip(to: clip)
        let a = MascotArt(g: g, u: 1, stroke: stroke)
        let step = L(0.07)
        var y = P(0, rig.neckY).y
        let maxY = P(0, rig.bodyBottom - 0.02).y
        var row = 0
        while y < maxY {
            var x = P(-0.22, 0).x + (row % 2 == 0 ? 0 : step * 0.5)
            let maxX = P(0.22, 0).x
            while x < maxX {
                a.line(CGPoint(x: x, y: y), CGPoint(x: x + step * 0.5, y: y + step * 0.35), w.light.opacity(0.55), width: 0.7)
                x += step
            }
            y += step * 0.62
            row += 1
        }
    }

    func cape(_ w: MascotSwatch, length: CGFloat, flare: CGFloat, wave: Bool) {
        let top = rig.neckY - 0.01
        let bot = min(top + length, canvasSafeYBot)
        let sway = wave ? CGFloat(self.wave) * 0.03 : 0
        let half = min(rig.bodyW / 2 + flare, canvasSafeX - 0.02)
        var p = Path()
        p.move(to: P(-0.10, top))
        p.addQuadCurve(to: P(-half + sway, bot), control: P(-half * 0.7, (top + bot) / 2))
        p.addQuadCurve(to: P(half + sway, bot), control: P(sway, bot + 0.04))
        p.addQuadCurve(to: P(0.10, top), control: P(half * 0.7, (top + bot) / 2))
        p.closeSubpath()
        art.solid(p, w, gloss: 0.22)
    }

    func shortCape(_ w: MascotSwatch) {
        cape(w, length: 0.36, flare: 0.12, wave: false)
    }

    func ermineTrim(_ w: MascotSwatch) {
        let y = rig.neckY
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.16, y - 0.02, 0.32, 0.05), cornerRadius: L(0.02)))
        art.solid(p, MascotSwatch(Color.white), gloss: 0.15)
        for x in [-0.10, 0.0, 0.10] as [CGFloat] {
            art.dot(P(x, y + 0.005), L(0.012), w.deep)
        }
    }

    func hoodBack(_ w: MascotSwatch) {
        let top = max(rig.headTop - 0.10, canvasSafeYTop)
        var p = Path()
        p.addEllipse(in: R(-0.28, top, 0.56, 0.36))
        art.solid(p, w, gloss: 0.2)
    }

    func hoodFront(_ w: MascotSwatch) {
        let top = max(rig.headTop - 0.08, canvasSafeYTop)
        var shell = Path()
        shell.addEllipse(in: R(-0.26, top, 0.52, 0.32))
        var hole = Path()
        hole.addEllipse(in: R(-0.16, rig.eyeY - 0.10, 0.32, 0.22))
        // Subtract the face opening so bead eyes stay visible; never punch through the canvas.
        art.solid(shell.subtracting(hole), w, gloss: 0.22)
    }

    func scarfTails(_ w: MascotSwatch) {
        var p = Path()
        p.move(to: P(-0.16, rig.neckY))
        p.addLine(to: P(-0.22, min(rig.bodyY + 0.28, canvasSafeYBot)))
        p.addLine(to: P(-0.12, rig.bodyY + 0.24))
        p.closeSubpath()
        var q = Path()
        q.move(to: P(0.16, rig.neckY))
        q.addLine(to: P(0.24, min(rig.bodyY + 0.30, canvasSafeYBot)))
        q.addLine(to: P(0.10, rig.bodyY + 0.22))
        q.closeSubpath()
        art.solid(p, w, gloss: 0.2)
        art.solid(q, w, gloss: 0.2)
    }

    func trenchTails(_ w: MascotSwatch) {
        shortCape(w)
    }

    func dinoTail(_ w: MascotSwatch, spots: MascotSwatch) {
        var p = Path()
        let root = P(0.16, rig.hipY)
        let tip = P(min(0.42, canvasSafeX - 0.04), min(rig.bodyBottom + 0.02, canvasSafeYBot))
        p.move(to: CGPoint(x: root.x, y: root.y - L(0.05)))
        p.addQuadCurve(to: tip, control: P(0.34, rig.hipY + 0.04))
        p.addQuadCurve(to: CGPoint(x: root.x, y: root.y + L(0.05)), control: P(0.30, rig.hipY + 0.10))
        p.closeSubpath()
        art.solid(p, w, gloss: 0.25)
        art.dot(P(0.28, rig.hipY + 0.04), L(0.022), spots.base)
    }

    func pomTail(_ w: MascotSwatch) {
        art.dot(P(min(0.28, canvasSafeX - 0.08), rig.hipY + 0.02), L(0.06), Color.white, outline: w.ink)
    }

    func jetpack(_ w: MascotSwatch) {
        let x = min(0.22, canvasSafeX - 0.10)
        for side in [-1.0, 1.0] as [CGFloat] {
            let r = CGRect(x: P(side * x, rig.bodyY - 0.06).x - L(0.05), y: P(0, rig.bodyY - 0.06).y, width: L(0.10), height: L(0.20))
            art.solid(Path(roundedRect: r, cornerRadius: L(0.03)), w, gloss: 0.2)
            art.dot(P(side * x, rig.bodyY + 0.16), L(0.03), Color.orange)
        }
    }

    func packBox(_ w: MascotSwatch, accent: MascotSwatch) {
        let r = R(-0.10, rig.bodyY - 0.08, 0.20, 0.18)
        art.solid(Path(roundedRect: r, cornerRadius: L(0.03)), w, gloss: 0.18)
        art.solid(Path(roundedRect: R(-0.07, rig.bodyY - 0.04, 0.14, 0.08), cornerRadius: L(0.015)), accent, gloss: 0.15)
    }

    func shortMask(_ w: MascotSwatch, eyeCut: Bool) {
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.16, rig.eyeY - 0.07, 0.32, 0.12), cornerRadius: L(0.04)))
        if eyeCut {
            var holes = Path()
            holes.addEllipse(in: CGRect(x: P(-rig.eyeSpread, rig.eyeY).x - L(0.038), y: P(0, rig.eyeY).y - L(0.028), width: L(0.076), height: L(0.056)))
            holes.addEllipse(in: CGRect(x: P(rig.eyeSpread, rig.eyeY).x - L(0.038), y: P(0, rig.eyeY).y - L(0.028), width: L(0.076), height: L(0.056)))
            p = p.subtracting(holes)
        }
        art.solid(p, w, gloss: 0.2)
    }

    func hexMask(_ w: MascotSwatch, eyeCut: Bool) {
        shortMask(w, eyeCut: eyeCut)
    }

    func visorHelm(_ w: MascotSwatch, visor: MascotSwatch, crest: MascotSwatch) {
        let top = max(rig.headTop - 0.10, canvasSafeYTop)
        var p = Path()
        p.addEllipse(in: R(-0.26, top, 0.52, 0.36))
        art.solid(p, w, gloss: 0.28)
        var v = Path()
        v.addPath(Path(roundedRect: R(-0.18, rig.eyeY - 0.10, 0.36, 0.055), cornerRadius: L(0.02)))
        art.solid(v, visor, gloss: 0.5, edge: 0.6)
        var c = Path()
        c.addPath(Path(roundedRect: R(-0.02, top - 0.02, 0.04, 0.10), cornerRadius: L(0.015)))
        art.solid(c, crest, gloss: 0.3)
    }

    func knightHelm(_ w: MascotSwatch, plume: MascotSwatch) {
        let top = max(rig.headTop - 0.08, canvasSafeYTop)
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.22, top, 0.44, 0.30), cornerRadius: L(0.10)))
        art.solid(p, w, gloss: 0.3)
        art.line(P(-0.10, rig.eyeY), P(0.10, rig.eyeY), w.deep, width: L(0.016))
        var plumePath = Path()
        plumePath.move(to: P(0, top))
        plumePath.addQuadCurve(to: P(0.02, top - 0.14), control: P(0.10, top - 0.08))
        plumePath.addQuadCurve(to: P(0, top + 0.01), control: P(-0.04, top - 0.06))
        plumePath.closeSubpath()
        if top - 0.14 > canvasSafeYTop {
            art.solid(plumePath, plume, gloss: 0.25)
        }
    }

    func pointyHat(_ w: MascotSwatch, brim: Color, star: MascotSwatch) {
        let brimY = rig.headTop + 0.02
        let tipY = max(rig.headTop - 0.28, canvasSafeYTop + 0.02)
        var cone = Path()
        cone.move(to: P(-0.20, brimY))
        cone.addLine(to: P(0, tipY))
        cone.addLine(to: P(0.20, brimY))
        cone.closeSubpath()
        art.solid(cone, w, gloss: 0.28)
        var b = Path()
        b.addEllipse(in: R(-0.24, brimY - 0.025, 0.48, 0.06))
        art.solid(b, MascotSwatch(brim), gloss: 0.2)
        art.gem(P(0, tipY + 0.04), L(0.022), star.base)
    }

    func tricorn(_ w: MascotSwatch, accent: MascotSwatch) {
        let y = rig.headTop + 0.01
        var p = Path()
        p.move(to: P(-0.28, y + 0.04))
        p.addQuadCurve(to: P(0, y - 0.08), control: P(-0.18, y - 0.10))
        p.addQuadCurve(to: P(0.28, y + 0.04), control: P(0.18, y - 0.10))
        p.addQuadCurve(to: P(-0.28, y + 0.04), control: P(0, y + 0.08))
        p.closeSubpath()
        art.solid(p, w, gloss: 0.22)
        art.dot(P(0, y - 0.02), L(0.02), accent.base)
    }

    func ninjaHood(_ w: MascotSwatch, eyeBand: MascotSwatch) {
        hoodFront(w)
        var band = Path()
        band.addPath(Path(roundedRect: R(-0.18, rig.eyeY - 0.05, 0.36, 0.08), cornerRadius: L(0.02)))
        art.solid(band, eyeBand, gloss: 0.15)
        shortMask(eyeBand, eyeCut: true)
    }

    func bubbleHelm(_ w: MascotSwatch, visor: MascotSwatch) {
        let top = max(rig.headTop - 0.16, canvasSafeYTop)
        let rect = R(-0.30, top, 0.60, 0.50)
        let outer = Path(ellipseIn: rect)
        let inner = Path(ellipseIn: rect.insetBy(dx: L(0.045), dy: L(0.045)))
        // Rim only — the dome stays clear so bead eyes show through.
        art.solid(outer.subtracting(inner), w, gloss: 0.2, outline: true, edge: 1.2)
        let shine = Path(ellipseIn: R(-0.16, top + 0.05, 0.14, 0.08))
        art.solid(shine, MascotSwatch(Color.white.opacity(0.28)), gloss: 0, outline: false)
        _ = visor
    }

    func dinoHood(_ w: MascotSwatch, spots: MascotSwatch) {
        hoodFront(w)
        let top = max(rig.headTop - 0.10, canvasSafeYTop)
        for i in 0..<3 {
            let x = CGFloat(i - 1) * 0.08
            var spike = Path()
            spike.move(to: P(x - 0.04, top + 0.06))
            spike.addLine(to: P(x, top - 0.08))
            spike.addLine(to: P(x + 0.04, top + 0.06))
            spike.closeSubpath()
            if top - 0.08 > canvasSafeYTop { art.solid(spike, w, gloss: 0.25) }
        }
        art.dot(P(-0.10, rig.headTop + 0.04), L(0.02), spots.base)
        art.dot(P(0.10, rig.headTop + 0.05), L(0.018), spots.base)
    }

    func bunnyHood(_ w: MascotSwatch, inner: Color) {
        hoodFront(w)
        let top = max(rig.headTop - 0.04, canvasSafeYTop + 0.22)
        for side in [-1.0, 1.0] as [CGFloat] {
            let ear = Path(roundedRect: R(side * 0.12 - 0.05, top - 0.26, 0.10, 0.28), cornerRadius: L(0.05))
            if top - 0.26 > canvasSafeYTop {
                art.solid(ear, w, gloss: 0.22)
                art.solid(Path(roundedRect: R(side * 0.12 - 0.03, top - 0.22, 0.06, 0.20), cornerRadius: L(0.03)), MascotSwatch(inner), gloss: 0.1, edge: 0.4)
            }
        }
    }

    func toque(_ color: Color) {
        let w = MascotSwatch(color)
        let y = rig.headTop
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.16, y - 0.22, 0.32, 0.24), cornerRadius: L(0.06)))
        art.solid(p, w, gloss: 0.2)
        var band = Path()
        band.addPath(Path(roundedRect: R(-0.18, y - 0.02, 0.36, 0.06), cornerRadius: L(0.02)))
        art.solid(band, w, gloss: 0.15)
        art.line(P(-0.12, y - 0.18), P(-0.12, y - 0.04), w.dark.opacity(0.25), width: 0.7)
        art.line(P(0, y - 0.20), P(0, y - 0.04), w.dark.opacity(0.25), width: 0.7)
        art.line(P(0.12, y - 0.18), P(0.12, y - 0.04), w.dark.opacity(0.25), width: 0.7)
    }

    func fireHelm(_ w: MascotSwatch, badge: MascotSwatch) {
        let top = max(rig.headTop - 0.10, canvasSafeYTop)
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.24, top, 0.48, 0.22), cornerRadius: L(0.06)))
        art.solid(p, w, gloss: 0.28)
        var brim = Path()
        brim.addPath(Path(roundedRect: R(-0.28, top + 0.16, 0.56, 0.06), cornerRadius: L(0.02)))
        art.solid(brim, w, gloss: 0.2)
        art.gem(P(0, top + 0.10), L(0.03), badge.base)
    }

    func tinyCrown(_ w: MascotSwatch) {
        let y = max(rig.headTop - 0.02, canvasSafeYTop + 0.10)
        var band = Path()
        band.addPath(Path(roundedRect: R(-0.14, y, 0.28, 0.05), cornerRadius: L(0.01)))
        art.solid(band, w, gloss: 0.4)
        for x in [-0.10, 0.0, 0.10] as [CGFloat] {
            var tip = Path()
            tip.move(to: P(x - 0.03, y))
            tip.addLine(to: P(x, y - 0.08))
            tip.addLine(to: P(x + 0.03, y))
            tip.closeSubpath()
            art.solid(tip, w, gloss: 0.4)
            art.gem(P(x, y - 0.07), L(0.012), Color.white)
        }
    }

    func brimHat(_ w: MascotSwatch) {
        let y = rig.headTop + 0.01
        var crown = Path()
        crown.addPath(Path(roundedRect: R(-0.16, y - 0.12, 0.32, 0.14), cornerRadius: L(0.05)))
        art.solid(crown, w, gloss: 0.22)
        var brim = Path()
        brim.addEllipse(in: R(-0.28, y + 0.00, 0.56, 0.07))
        art.solid(brim, w, gloss: 0.18)
    }

    func robotHelm(_ w: MascotSwatch, visor: MascotSwatch, antenna: MascotSwatch) {
        let top = max(rig.headTop - 0.08, canvasSafeYTop)
        var p = Path()
        p.addPath(Path(roundedRect: R(-0.24, top, 0.48, 0.28), cornerRadius: L(0.06)))
        art.solid(p, w, gloss: 0.3)
        var v = Path()
        v.addPath(Path(roundedRect: R(-0.16, rig.eyeY - 0.09, 0.32, 0.05), cornerRadius: L(0.016)))
        art.solid(v, visor, gloss: 0.5)
        art.line(P(0, top), P(0, top - 0.08), antenna.base, width: L(0.014))
        art.dot(P(0, top - 0.09), L(0.02), antenna.base)
    }

    func aviatorCap(_ w: MascotSwatch, goggles: MascotSwatch) {
        brimHat(w)
        for side in [-1.0, 1.0] as [CGFloat] {
            art.solid(Path(ellipseIn: R(side * 0.09 - 0.07, rig.eyeY - 0.06, 0.14, 0.10)), goggles, gloss: 0.45)
        }
        art.line(P(-0.04, rig.eyeY), P(0.04, rig.eyeY), w.dark, width: L(0.012))
    }

    func softCap(_ w: MascotSwatch) {
        let y = rig.headTop + 0.02
        var p = Path()
        p.addEllipse(in: R(-0.18, y - 0.10, 0.36, 0.16))
        art.solid(p, w, gloss: 0.22)
        var bill = Path()
        bill.addPath(Path(roundedRect: R(-0.08, y + 0.04, 0.28, 0.05), cornerRadius: L(0.02)))
        art.solid(bill, w, gloss: 0.18)
    }

    func glass(at p: CGPoint, color: MascotSwatch) {
        let r = L(0.055)
        let safe = CGPoint(x: min(max(p.x, cx - L(canvasSafeX)), cx + L(canvasSafeX)),
                           y: min(max(p.y, cy + L(canvasSafeYTop)), cy + L(canvasSafeYBot)))
        art.solid(Path(ellipseIn: CGRect(x: safe.x - r, y: safe.y - r, width: r * 2, height: r * 2)), color, gloss: 0.4)
        art.solid(Path(ellipseIn: CGRect(x: safe.x - r * 0.7, y: safe.y - r * 0.7, width: r * 1.4, height: r * 1.4)), MascotSwatch(Color.white.opacity(0.35)), gloss: 0, outline: false)
        art.line(CGPoint(x: safe.x + r, y: safe.y), CGPoint(x: safe.x + r * 1.6, y: safe.y + r * 0.4), color.ink, width: L(0.014))
    }

    func lute(at p: CGPoint, color: MascotSwatch, face: MascotSwatch) {
        let safe = CGPoint(x: min(max(p.x, cx - L(0.80)), cx + L(0.80)),
                           y: min(max(p.y, cy + L(-0.70)), cy + L(0.80)))
        art.solid(Path(ellipseIn: CGRect(x: safe.x - L(0.07), y: safe.y - L(0.05), width: L(0.14), height: L(0.16))), color, gloss: 0.25)
        art.dot(safe, L(0.03), face.dark)
        art.line(CGPoint(x: safe.x, y: safe.y - L(0.05)), CGPoint(x: safe.x, y: safe.y - L(0.16)), color.ink, width: L(0.016))
    }
}
