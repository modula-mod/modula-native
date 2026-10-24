import SwiftUI

// MARK: - Family 007 — Legends (The Mythic Wilds)
//
// Myths and legends as Moliboos. Every Legend is a complete character: Santa's hat, Bigfoot's fur and the Kraken's
// tentacles are drawn as part of the character, so Legends never wear wardrobe items (`MolibooFamily.supportsWardrobe`).
// Numbers 101–115; the canonical 001–100 roster is untouched.

extension MolibooFamilySpecs {
    static func addLegends(_ t: inout [ModulaMascotKind: MolibooSpec]) {
        let santaRed = c(0.88, 0.18, 0.2), skin = c(1, 0.86, 0.76), snowWhite = c(0.98, 0.98, 1)
        let fur = c(0.5, 0.34, 0.22), ice = c(0.62, 0.84, 1), gold = c(1, 0.8, 0.32)
        t[.kringle] = MolibooSpec(body: .round, size: CGSize(width: 0.98, height: 0.9), palette: .spec(santaRed, accent: c(1, 0.62, 0.62), light: c(1, 0.56, 0.52)), parts: [.feet(c(0.16, 0.12, 0.12)), .belt(c(0.16, 0.12, 0.12)), .facePatch(skin), .beard(snowWhite), .santaHat(santaRed)], form: "Santa Claus")
        t[.sasqui] = MolibooSpec(body: .pear, size: CGSize(width: 0.94, height: 0.94), palette: .spec(fur, accent: c(0.95, 0.6, 0.5), light: c(0.74, 0.56, 0.4)), parts: [.shag(c(0.36, 0.24, 0.15)), .arms(c(0.4, 0.27, 0.17)), .facePatch(c(0.86, 0.7, 0.54)), .bigFeet(c(0.32, 0.21, 0.13))], form: "Bigfoot")
        t[.lochie] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(c(0.34, 0.72, 0.52), accent: c(0.7, 0.95, 0.6), light: c(0.66, 0.9, 0.7)), parts: [.humps(c(0.34, 0.72, 0.52)), .antennae(c(0.62, 0.9, 0.62)), .featherCrest(c(0.22, 0.54, 0.4), c(0.5, 0.82, 0.56)), .waves(c(0.3, 0.56, 0.92))], feet: false, form: "Loch Ness monster")
        t[.yetti] = MolibooSpec(body: .pear, size: CGSize(width: 0.94, height: 0.94), palette: .spec(c(0.95, 0.97, 1), accent: c(0.62, 0.78, 1), light: .white, dark: c(0.76, 0.84, 0.96), outline: c(0.36, 0.46, 0.66)), parts: [.shag(c(0.86, 0.92, 1)), .arms(c(0.88, 0.92, 1)), .facePatch(c(0.6, 0.72, 0.92)), .bigFeet(c(0.62, 0.72, 0.9)), .snowflakes(4)], form: "Yeti")
        t[.krakie] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.84), palette: .spec(c(0.66, 0.24, 0.5), accent: c(1, 0.62, 0.8), light: c(0.9, 0.5, 0.74)), parts: [.tentacles(c(0.66, 0.24, 0.5)), .berries(c(0.96, 0.66, 0.84))], floats: true, feet: false, form: "Kraken")
        t[.pyra] = MolibooSpec(body: .round, size: CGSize(width: 0.88, height: 0.86), palette: .spec(c(1, 0.56, 0.2), accent: c(1, 0.86, 0.3), light: c(1, 0.86, 0.48)), parts: [.glow(c(1, 0.5, 0.15)), .wings(.eagle, c(1, 0.4, 0.16)), .tail(.plume, c(1, 0.78, 0.26)), .flameCrest(c(1, 0.32, 0.12)), .beak], floats: true, feet: false, form: "Phoenix")
        t[.unika] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(snowWhite, accent: c(1, 0.66, 0.84), light: .white, dark: c(0.86, 0.84, 0.96), outline: c(0.5, 0.42, 0.66)), parts: [.rainbowMane, .ears(.cat), .feet(c(0.84, 0.72, 0.96)), .horn(gold)], form: "Unicorn")
        t[.gryff] = MolibooSpec(body: .round, size: CGSize(width: 0.92, height: 0.88), palette: .spec(c(0.86, 0.64, 0.36), accent: c(1, 0.72, 0.5), light: c(0.98, 0.86, 0.62)), parts: [.wings(.feather, c(0.98, 0.94, 0.86)), .tail(.curl, c(0.72, 0.5, 0.26)), .facePatch(c(1, 0.98, 0.94)), .hookBeak(gold), .paws(c(0.8, 0.58, 0.32)), .featherCrest(c(1, 0.98, 0.94), c(0.86, 0.64, 0.36))], form: "Griffin")
        t[.frostie] = MolibooSpec(body: .round, size: CGSize(width: 0.86, height: 0.84), palette: .spec(c(0.8, 0.92, 1), accent: c(0.5, 0.74, 1), iris: c(0.2, 0.44, 0.86), light: .white), parts: [.glow(ice), .tail(.ribbon, c(0.86, 0.95, 1)), .frostSpikes(ice), .snowflakes(5)], floats: true, feet: false, form: "Jack Frost")
        t[.pearli] = MolibooSpec(body: .tooth, size: CGSize(width: 0.86, height: 0.94), palette: .spec(snowWhite, accent: c(1, 0.66, 0.8), light: .white, dark: c(0.86, 0.88, 0.96), outline: c(0.48, 0.5, 0.66)), parts: [.glow(c(0.8, 0.86, 1)), .wings(.fairy, c(0.7, 0.86, 1)), .toothShine, .wand(c(1, 0.8, 0.4)), .sparkles(3)], floats: true, feet: false, form: "Tooth Fairy")
        t[.kitsu] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.99, 0.96, 0.92), accent: c(0.94, 0.32, 0.28), light: .white, dark: c(0.94, 0.84, 0.76), outline: c(0.6, 0.36, 0.26)), parts: [.kitsuneTails(c(1, 0.62, 0.3), .white), .ears(.fox), .kitsuneMarks(c(0.9, 0.2, 0.24)), .orbiters(2, c(0.5, 0.82, 1))], form: "Kitsune")
        t[.chupi] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.56, 0.64, 0.52), accent: c(1, 0.4, 0.36), iris: c(0.9, 0.16, 0.16), light: c(0.78, 0.84, 0.72)), parts: [.spines(c(0.32, 0.44, 0.32)), .tail(.lizard, c(0.46, 0.56, 0.42)), .ears(.bat), .fangs, .feet(c(0.4, 0.5, 0.38))], form: "Chupacabra")
        t[.motho] = MolibooSpec(body: .drop, size: CGSize(width: 0.84, height: 0.96), palette: .spec(c(0.26, 0.24, 0.3), accent: c(1, 0.22, 0.2), iris: c(1, 0.2, 0.18), light: c(0.42, 0.4, 0.48)), parts: [.wings(.giantMoth, c(0.34, 0.3, 0.38)), .antennae(c(0.56, 0.5, 0.6)), .glowEyes(c(1, 0.16, 0.12))], floats: true, feet: false, form: "Mothman")
        t[.jacko] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.84), palette: .spec(c(0.74, 0.56, 0.4), accent: c(1, 0.7, 0.72), light: c(0.92, 0.8, 0.66)), parts: [.tail(.fluffy, .white), .antlers(c(0.92, 0.84, 0.68)), .ears(.bunny), .feet(c(0.6, 0.44, 0.3))], form: "Jackalope")
        t[.thundra] = MolibooSpec(body: .round, size: CGSize(width: 0.9, height: 0.86), palette: .spec(c(0.22, 0.4, 0.78), accent: gold, light: c(0.5, 0.66, 0.96)), parts: [.wings(.eagle, c(0.16, 0.28, 0.6)), .thunderMark(gold), .hookBeak(gold), .featherCrest(c(0.9, 0.22, 0.2), .white), .lightning], floats: true, feet: false, form: "Thunderbird")
    }

    static let legendProfiles: [ModulaMascotKind: ModulaMascotKind.Profile] = [
        .kringle: .init(number: 101, title: "The Gift Bringer", traits: ["Generous", "Jolly", "Festive"]),
        .sasqui: .init(number: 102, title: "The Forest Wanderer", traits: ["Gentle", "Elusive", "Strong"]),
        .lochie: .init(number: 103, title: "The Loch Keeper", traits: ["Shy", "Ancient", "Curious"]),
        .yetti: .init(number: 104, title: "The Snow Giant", traits: ["Cuddly", "Brave", "Wintry"]),
        .krakie: .init(number: 105, title: "The Deep Dreamer", traits: ["Mighty", "Playful", "Mysterious"]),
        .pyra: .init(number: 106, title: "The Reborn Flame", traits: ["Hopeful", "Radiant", "Resilient"]),
        .unika: .init(number: 107, title: "The Rainbow Horn", traits: ["Pure", "Magical", "Kind"]),
        .gryff: .init(number: 108, title: "The Sky Lion", traits: ["Noble", "Loyal", "Bold"]),
        .frostie: .init(number: 109, title: "The Frost Painter", traits: ["Mischievous", "Artistic", "Chilly"]),
        .pearli: .init(number: 110, title: "The Midnight Collector", traits: ["Sweet", "Secretive", "Generous"]),
        .kitsu: .init(number: 111, title: "The Nine-Tailed Fox", traits: ["Clever", "Wise", "Graceful"]),
        .chupi: .init(number: 112, title: "The Desert Prowler", traits: ["Sneaky", "Spiky", "Misunderstood"]),
        .motho: .init(number: 113, title: "The Night Watcher", traits: ["Watchful", "Quiet", "Eerie"]),
        .jacko: .init(number: 114, title: "The Antlered Hare", traits: ["Quick", "Proud", "Tall-tale"]),
        .thundra: .init(number: 115, title: "The Storm Bringer", traits: ["Powerful", "Protective", "Thunderous"]),
    ]
}

// MARK: - Legend parts

extension ModulaMascotFigure {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @ViewBuilder
    func legendPart(_ part: MolibooPart, spec: MolibooSpec, layer: SpecLayer, s: CGFloat, pal: ModulaMascotKind.Palette, t: Double, a: CGFloat, seed: Double) -> some View {
        let da = Double(a)
        let line = max(s * 0.024, 0.9)
        let bw = s * spec.size.width, bh = s * spec.size.height
        let top = -s * (spec.size.height / 2 - kind.bodyOffsetY)
        let cy = s * kind.bodyOffsetY
        switch (part, layer) {
        // ── Back ─────────────────────────────────────────────────
        case (.shag(let c), .back):
            // Shaggy fur tips poking out all round the silhouette.
            ForEach(0..<20, id: \.self) { k in
                let ang = Double(k) / 20 * 2 * .pi
                MascotTriangle().fill(LinearGradient(colors: [pal.mid, c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(pal.outline.opacity(0.4), lineWidth: line * 0.8))
                    .frame(width: s * 0.13, height: s * 0.15)
                    .rotationEffect(.radians(ang + .pi / 2))
                    .offset(x: CGFloat(cos(ang)) * (bw / 2 + s * 0.02), y: cy + CGFloat(sin(ang)) * (bh / 2 + s * 0.02))
            }
        case (.humps(let c), .back):
            // Two humps and a tail tip trailing behind the head, out of the loch.
            ZStack {
                ForEach(0..<2, id: \.self) { k in
                    Circle().fill(RadialGradient(colors: [pal.light, c, pal.dark], center: UnitPoint(x: 0.4, y: 0.25), startRadius: 0, endRadius: s * 0.2))
                        .overlay(Circle().stroke(pal.outline.opacity(0.55), lineWidth: line))
                        .frame(width: s * [0.34, 0.26][k])
                        .offset(x: s * [0.6, 0.86][k], y: s * [0.0, 0.03][k])
                }
                MascotTriangle().fill(c).overlay(MascotTriangle().stroke(pal.outline.opacity(0.55), lineWidth: line))
                    .frame(width: s * 0.12, height: s * 0.2).rotationEffect(.degrees(28)).offset(x: -s * 0.66, y: -s * 0.02)
            }
            .offset(y: cy + bh * 0.34 + CGFloat(sin(t * 1.2)) * s * 0.01 * a)
        case (.tentacles(let c), .back):
            ForEach(0..<6, id: \.self) { k in
                let u = Double(k) / 5 - 0.5
                let ph = t * 1.3 + Double(k) * 1.7 + 0.6
                ZStack {
                    MascotTentacle(phase: ph, amp: max(a, 0.55))
                        .stroke(pal.outline.opacity(0.45), style: StrokeStyle(lineWidth: s * 0.1 + line * 1.6, lineCap: .round))
                    MascotTentacle(phase: ph, amp: max(a, 0.55))
                        .stroke(LinearGradient(colors: [c, pal.mid, pal.accent], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
                }
                    .frame(width: s * 0.2, height: s * 0.42)
                    .rotationEffect(.degrees(u * 70), anchor: .top)
                    .offset(x: CGFloat(u) * bw * 0.72, y: cy + bh * 0.28 + s * 0.21)
            }
        case (.rainbowMane, .back):
            let rainbow = [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 1, green: 0.7, blue: 0.35), Color(red: 1, green: 0.9, blue: 0.4),
                           Color(red: 0.5, green: 0.86, blue: 0.56), Color(red: 0.45, green: 0.7, blue: 1), Color(red: 0.72, green: 0.52, blue: 1)]
            ZStack {
                ForEach(0..<6, id: \.self) { k in
                    Ellipse().fill(LinearGradient(colors: [rainbow[k].opacity(0.85), rainbow[k]], startPoint: .top, endPoint: .bottom))
                        .overlay(Ellipse().stroke(pal.outline.opacity(0.35), lineWidth: line * 0.8))
                        .frame(width: s * 0.2, height: s * 0.34)
                        .offset(y: -s * 0.4)
                        .rotationEffect(.degrees(-100 + Double(k) * 24 + 3 * sin(t * 1.5 + Double(k)) * da))
                }
                ForEach(0..<3, id: \.self) { k in
                    MascotTail().stroke(rainbow[k * 2], style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                        .frame(width: s * 0.4, height: s * 0.34)
                        .offset(x: bw * 0.5 + s * 0.12, y: s * (0.18 + CGFloat(k) * 0.05))
                }
            }
            .offset(y: cy - s * 0.04)
        case (.kitsuneTails(let c, let tip), .back):
            // A fan of fox tails with white tips, rising behind one shoulder.
            ForEach(0..<7, id: \.self) { k in
                let ang = -6.0 + Double(k) * 19 + 4 * sin(t * 1.4 + Double(k)) * da
                Ellipse().fill(LinearGradient(colors: [tip, c, c.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(pal.outline.opacity(0.45), lineWidth: line))
                    .frame(width: s * 0.22, height: s * 0.5)
                    .offset(y: -s * 0.22)
                    .rotationEffect(.degrees(ang), anchor: .bottom)
                    .offset(x: bw * 0.2, y: cy + bh * 0.18 - s * 0.25)
            }
        case (.spines(let c), .back):
            ForEach(0..<5, id: \.self) { k in
                MascotTriangle().fill(LinearGradient(colors: [pal.accent.opacity(0.9), c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(pal.outline.opacity(0.5), lineWidth: line))
                    .frame(width: s * 0.12, height: s * [0.24, 0.3, 0.34, 0.3, 0.24][k])
                    .offset(y: -max(bw, bh) * 0.48 - s * 0.08)
                    .rotationEffect(.degrees(Double(k - 2) * 26 + 3 * sin(t * 2 + Double(k)) * da))
                    .offset(y: cy)
            }
        // ── Front (under the face) ────────────────────────────────
        case (.facePatch(let c), .front):
            Ellipse().fill(RadialGradient(colors: [c.opacity(0.98), c], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.3))
                .overlay(Ellipse().stroke(pal.outline.opacity(0.18), lineWidth: line * 0.8))
                .frame(width: s * (kind.eyeSpread * 2 + kind.eyeSize * 1.5), height: s * (kind.mouthY - kind.eyeY + 0.26))
                .offset(y: s * (kind.eyeY + kind.mouthY) / 2 + s * 0.01)
        case (.beard(let c), .front):
            let fluff = LinearGradient(colors: [.white, c, Color(red: 0.88, green: 0.9, blue: 0.95)], startPoint: .top, endPoint: .bottom)
            ZStack {
                ForEach(0..<9, id: \.self) { k in
                    Circle().fill(fluff)
                        .overlay(Circle().stroke(pal.outline.opacity(0.16), lineWidth: line * 0.8))
                        .frame(width: s * [0.16, 0.18, 0.2, 0.21, 0.22, 0.21, 0.2, 0.18, 0.16][k])
                        .offset(x: s * [-0.31, -0.25, -0.16, -0.08, 0, 0.08, 0.16, 0.25, 0.31][k], y: s * [0.0, 0.07, 0.12, 0.15, 0.16, 0.15, 0.12, 0.07, 0.0][k])
                }
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse().fill(fluff).overlay(Ellipse().stroke(pal.outline.opacity(0.2), lineWidth: line * 0.8))
                        .frame(width: s * 0.15, height: s * 0.075)
                        .rotationEffect(.degrees(side * -14))
                        .offset(x: side * s * 0.075, y: -s * 0.065)
                }
            }
            .offset(y: s * (kind.mouthY + 0.05))
        case (.belt(let c), .front):
            ZStack {
                Capsule().fill(c).overlay(Capsule().stroke(pal.outline.opacity(0.4), lineWidth: line))
                    .frame(width: bw * 0.84, height: s * 0.09)
                RoundedRectangle(cornerRadius: s * 0.02).stroke(Color(red: 1, green: 0.82, blue: 0.3), lineWidth: s * 0.025)
                    .frame(width: s * 0.13, height: s * 0.1)
            }
            .offset(y: cy + bh * 0.3)
        case (.bigFeet(let c), .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack(alignment: .top) {
                    Ellipse().fill(LinearGradient(colors: [pal.mid, c], startPoint: .top, endPoint: .bottom))
                        .overlay(Ellipse().stroke(pal.outline.opacity(0.55), lineWidth: line))
                        .frame(width: s * 0.3, height: s * 0.14)
                    HStack(spacing: s * 0.012) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(c).overlay(Circle().stroke(pal.outline.opacity(0.5), lineWidth: line * 0.8)).frame(width: s * 0.065)
                        }
                    }
                    .offset(x: side * s * 0.04, y: -s * 0.025)
                }
                .offset(x: side * bw * 0.26, y: cy + bh * 0.48)
            }
        case (.waves(let c), .front):
            ZStack {
                MascotWaveBand(phase: t * 1.4).fill(LinearGradient(colors: [c.opacity(0.92), c, c.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                MascotWaveBand(phase: t * 1.4).stroke(Color.white.opacity(0.75), lineWidth: line * 1.2).mask(
                    Rectangle().frame(height: s * 0.08).frame(maxHeight: .infinity, alignment: .top)
                )
                ForEach(0..<3, id: \.self) { k in
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: s * [0.16, 0.12, 0.1][k], height: max(s * 0.018, 1))
                        .offset(x: s * [-0.5, 0.36, -0.06][k], y: s * [0.07, 0.1, 0.13][k])
                }
            }
            .frame(width: s * 1.9, height: s * 0.24)
            .offset(y: cy + bh * 0.34 + s * 0.1)
        case (.hookBeak(let c), .front):
            MascotHookBeak().fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), c], startPoint: .top, endPoint: .bottom))
                .overlay(MascotHookBeak().stroke(pal.outline.opacity(0.5), lineWidth: line))
                .frame(width: s * 0.14, height: s * 0.12)
                .offset(y: s * (kind.eyeY + kind.mouthY) / 2 + s * 0.02)
        case (.kitsuneMarks(let c), .front):
            ZStack {
                MascotDropShape().fill(c).frame(width: s * 0.07, height: s * 0.12).offset(y: top + bh * 0.16 - cy)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    ForEach(0..<2, id: \.self) { k in
                        Capsule().fill(c.opacity(0.9)).frame(width: s * 0.1, height: max(s * 0.022, 1))
                            .rotationEffect(.degrees(side * (8 - Double(k) * 16)))
                            .offset(x: side * s * 0.36, y: s * (kind.eyeY + 0.1 + CGFloat(k) * 0.045) - cy)
                    }
                }
            }
            .offset(y: cy)
        case (.fangs, .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().rotation(.degrees(180)).fill(.white)
                    .overlay(MascotTriangle().rotation(.degrees(180)).stroke(pal.outline.opacity(0.5), lineWidth: line * 0.7))
                    .frame(width: s * 0.05, height: s * 0.07)
                    .offset(x: side * s * 0.045, y: s * (kind.mouthY + 0.04))
            }
        case (.glowEyes(let c), .front):
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(RadialGradient(colors: [c.opacity(0.85), c.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.17))
                    .frame(width: s * 0.36)
                    .offset(x: side * s * kind.eyeSpread, y: s * kind.eyeY)
                    .opacity(0.8 + 0.2 * sin(t * 2.2))
            }
        case (.toothShine, .front):
            ZStack {
                MascotSparkleShape().fill(.white).frame(width: s * 0.12, height: s * 0.12)
                    .shadow(color: Color(red: 0.6, green: 0.8, blue: 1), radius: s * 0.03)
                    .offset(x: -bw * 0.3, y: top + bh * 0.14 - cy)
                Capsule().fill(pal.accent.opacity(0.35)).frame(width: bw * 0.5, height: s * 0.035).offset(y: s * (kind.mouthY + 0.1) - cy)
            }
            .offset(y: cy)
        case (.thunderMark(let c), .front):
            Path(roundedPolygon: [CGPoint(x: 0.6, y: 0), CGPoint(x: 0.12, y: 0.56), CGPoint(x: 0.44, y: 0.56), CGPoint(x: 0.3, y: 1),
                                  CGPoint(x: 0.88, y: 0.4), CGPoint(x: 0.56, y: 0.4), CGPoint(x: 0.76, y: 0)].map { CGPoint(x: $0.x * s * 0.16, y: $0.y * s * 0.2) }, radius: s * 0.008)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.7), c], startPoint: .top, endPoint: .bottom))
                .shadow(color: c.opacity(0.8), radius: s * 0.03)
                .frame(width: s * 0.16, height: s * 0.2)
                .offset(y: cy + bh * 0.3)
        // ── Top (over the face) ───────────────────────────────────
        case (.santaHat(let c), .top):
            ZStack {
                ZStack(alignment: .topTrailing) {
                    MascotCapShape().fill(LinearGradient(colors: [c.opacity(0.92), c], startPoint: .top, endPoint: .bottom))
                        .overlay(MascotCapShape().stroke(pal.outline.opacity(0.55), lineWidth: line))
                    Circle().fill(RadialGradient(colors: [.white, Color(red: 0.9, green: 0.92, blue: 0.96)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.08))
                        .overlay(Circle().stroke(pal.outline.opacity(0.2), lineWidth: line * 0.8))
                        .frame(width: s * 0.15).offset(x: s * 0.05, y: -s * 0.04)
                }
                .frame(width: bw * 0.78, height: s * 0.38)
                .offset(x: s * 0.02, y: -s * 0.14)
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.88, green: 0.9, blue: 0.95)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(pal.outline.opacity(0.2), lineWidth: line))
                    .frame(width: bw * 0.86, height: s * 0.12)
                    .offset(y: s * 0.04)
            }
            .rotationEffect(.degrees(-4 + 2 * sin(t * 0.8) * da))
            .offset(y: top - s * 0.02)
        case (.flameCrest(let c), .top):
            ForEach(0..<3, id: \.self) { k in
                MascotDropShape().fill(LinearGradient(colors: [c, Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.92, blue: 0.45)], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotDropShape().stroke(pal.outline.opacity(0.35), lineWidth: line * 0.8))
                    .frame(width: s * [0.13, 0.17, 0.13][k], height: s * [0.24, 0.32, 0.24][k])
                    .rotationEffect(.degrees(Double(k - 1) * 24 + 5 * sin(t * 5 + Double(k)) * da), anchor: .bottom)
                    .offset(x: s * CGFloat(k - 1) * 0.09, y: top - s * 0.11)
            }
        case (.horn(let c), .top):
            ZStack {
                MascotTriangle().fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.8), c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(Color(red: 0.62, green: 0.44, blue: 0.1).opacity(0.65), lineWidth: line))
                ForEach(0..<3, id: \.self) { k in
                    Capsule().fill(Color(red: 0.8, green: 0.58, blue: 0.16).opacity(0.7))
                        .frame(width: s * (0.05 + CGFloat(k) * 0.025), height: max(s * 0.016, 0.8))
                        .rotationEffect(.degrees(-22))
                        .offset(y: s * (-0.06 + CGFloat(k) * 0.07))
                }
            }
            .frame(width: s * 0.14, height: s * 0.32)
            .shadow(color: c.opacity(0.6), radius: s * 0.03)
            .offset(y: top - s * 0.13)
        case (.featherCrest(let c, let tip), .top):
            ForEach(0..<3, id: \.self) { k in
                MascotLeaf().fill(LinearGradient(colors: [tip, c], startPoint: .leading, endPoint: .trailing))
                    .overlay(MascotLeaf().stroke(pal.outline.opacity(0.45), lineWidth: line * 0.8))
                    .frame(width: s * [0.22, 0.28, 0.22][k], height: s * 0.09)
                    .offset(x: -s * [0.11, 0.14, 0.11][k])
                    .rotationEffect(.degrees(90 + Double(k - 1) * 30 + 4 * sin(t * 1.6 + Double(k)) * da), anchor: .center)
                    .offset(y: top - s * 0.1)
            }
        case (.snowflakes(let n), .top):
            ForEach(0..<n, id: \.self) { k in
                Image(systemName: "snowflake").font(.system(size: s * [0.13, 0.1, 0.11, 0.09, 0.12][k % 5], weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.4, green: 0.6, blue: 1).opacity(0.9), radius: s * 0.02)
                    .offset(x: s * [0.6, -0.62, 0.5, -0.5, 0.0][k % 5], y: cy + s * [-0.38, -0.24, 0.32, 0.4, -0.66][k % 5])
                    .opacity(0.6 + 0.4 * abs(sin(t * 1.2 + Double(k))))
            }
        case (.frostSpikes(let c), .top):
            // Spiky icicle hair across the top of the head.
            ForEach(0..<7, id: \.self) { k in
                MascotTriangle().fill(LinearGradient(colors: [.white, c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(Color(red: 0.3, green: 0.5, blue: 0.86).opacity(0.6), lineWidth: line * 0.8))
                    .shadow(color: c.opacity(0.6), radius: s * 0.02)
                    .frame(width: s * 0.11, height: s * [0.16, 0.22, 0.27, 0.32, 0.27, 0.22, 0.16][k])
                    .offset(y: -bh * 0.5 - s * [0.04, 0.06, 0.08, 0.1, 0.08, 0.06, 0.04][k])
                    .rotationEffect(.degrees(Double(k - 3) * 17))
                    .offset(y: cy)
            }
        case (.wand(let c), .top):
            ZStack {
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.8, green: 0.82, blue: 0.9)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(s * 0.03, 1), height: s * 0.3)
                    .offset(y: s * 0.13)
                MascotStarShape().fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.7), c], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotStarShape().stroke(Color(red: 0.7, green: 0.5, blue: 0.1).opacity(0.6), lineWidth: line * 0.8))
                    .shadow(color: c.opacity(0.8), radius: s * 0.04)
                    .frame(width: s * 0.17, height: s * 0.17)
            }
            .rotationEffect(.degrees(18 + 8 * sin(t * 1.8) * da), anchor: .bottom)
            .offset(x: bw * 0.56, y: cy - s * 0.12)
        default:
            EmptyView()
        }
    }
}

// MARK: - Legend shapes

/// A molar: rounded crown with two little roots (Pearli, the Tooth Fairy).
struct MascotToothShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        var p = Path()
        p.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.1))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.3), control1: CGPoint(x: x + w * 0.7, y: y - h * 0.04), control2: CGPoint(x: x + w, y: y))
        p.addCurve(to: CGPoint(x: x + w * 0.82, y: y + h * 0.97), control1: CGPoint(x: x + w, y: y + h * 0.6), control2: CGPoint(x: x + w * 0.9, y: y + h * 0.78))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.62, y: y + h * 0.97), control: CGPoint(x: x + w * 0.72, y: y + h * 1.04))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.78), control: CGPoint(x: x + w * 0.6, y: y + h * 0.78))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.38, y: y + h * 0.97), control: CGPoint(x: x + w * 0.4, y: y + h * 0.78))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.18, y: y + h * 0.97), control: CGPoint(x: x + w * 0.28, y: y + h * 1.04))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.3), control1: CGPoint(x: x + w * 0.1, y: y + h * 0.78), control2: CGPoint(x: x, y: y + h * 0.6))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.1), control1: CGPoint(x: x, y: y), control2: CGPoint(x: x + w * 0.3, y: y - h * 0.04))
        p.closeSubpath()
        return p
    }
}

/// Water band with a wavy top edge (the loch around Lochie).
struct MascotWaveBand: Shape {
    var phase: Double = 0
    func path(in r: CGRect) -> Path {
        var p = Path()
        let crest = r.height * 0.14
        p.move(to: CGPoint(x: r.minX, y: r.minY + crest))
        for i in 0...48 {
            let u = Double(i) / 48
            p.addLine(to: CGPoint(x: r.minX + r.width * CGFloat(u), y: r.minY + crest + CGFloat(sin(u * .pi * 8 + phase)) * crest))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.3), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

/// Hooked raptor beak (Gryff, Thundra).
struct MascotHookBeak: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: r.midX + r.width * 0.06, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.75))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15), control: CGPoint(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

// MARK: - Wardrobe state for Legends

/// Shown instead of item grids while a Legend is selected. Saved outfits and owned items are untouched and return
/// with any wardrobe-capable Moliboo.
struct MolibooLegendLookCard: View {
    let kind: ModulaMascotKind
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 12) {
            ModulaMascotFigure(kind: kind, pose: .still(.happy), size: 64)
                .frame(width: 128, height: 112)
                .accessibilityHidden(true)
            Label("Legends wear their own look", systemImage: "sparkles")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(kind.name) comes complete, so hats, outfits and items stay off. Your wardrobe and saved outfits are kept for your other Moliboos.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: shape, interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wardrobe.legendLook")
    }
}
