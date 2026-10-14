import SwiftUI

// MARK: - Settings → Moliboo hub (MOL-03)
//
// Illustrated, living hero + Liquid Glass (iOS 26 `glassEffect` via `modulaGlass` / `ModulaGlassGroup`;
// opaque material fallback on iOS 18–25 or Reduce Transparency). Every control writes the same storage
// keys as before, so nothing about saved choices or behaviour changes.

enum MolibooHubSegment: String, CaseIterable, Identifiable {
    case collection, studio, settings, originals
    var id: String { rawValue }
    var title: String {
        switch self { case .collection: "Collection"; case .studio: "Studio"; case .settings: "Settings"; case .originals: "The Originals" }
    }
    var icon: String {
        switch self { case .collection: "square.grid.2x2.fill"; case .studio: "tshirt.fill"; case .settings: "gearshape.fill"; case .originals: "crown.fill" }
    }
}

/// Garden scene behind the hero: sky, sun glow, distant arches, hills, swaying flowers, drifting petals.
/// One `TimelineView` at 20 fps, paused unless `animating` (scene active, motion allowed).
struct MolibooGardenScene: View {
    var animating: Bool
    var parallax: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { ctx in
            let t = animating ? ctx.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.98), Color(red: 0.86, green: 0.93, blue: 0.99), Color(red: 1.0, green: 0.93, blue: 0.86)],
                                   startPoint: .top, endPoint: .bottom)
                    // Sun glow
                    RadialGradient(colors: [Color(red: 1, green: 0.96, blue: 0.8).opacity(0.95), .clear], center: .init(x: 0.72, y: 0.18), startRadius: 4, endRadius: w * 0.55)
                    // Soft clouds
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(.white.opacity(0.75)).frame(width: w * (0.32 + 0.08 * Double(i)), height: 26 + 6 * Double(i))
                            .blur(radius: 6)
                            .position(x: (w * (0.2 + 0.33 * Double(i)) + CGFloat(t * (3 + Double(i)))).truncatingRemainder(dividingBy: w * 1.3) - w * 0.1,
                                      y: h * (0.12 + 0.06 * Double(i)))
                    }
                    // Distant arches (ruined garden colonnade)
                    HStack(spacing: w * 0.06) {
                        ForEach(0..<4, id: \.self) { _ in
                            UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)
                                .stroke(Color(red: 0.86, green: 0.80, blue: 0.74).opacity(0.85), lineWidth: 9)
                                .frame(width: w * 0.16, height: h * 0.42)
                        }
                    }
                    .position(x: w * 0.5 + parallax * 0.2, y: h * 0.42)
                    .blur(radius: 1.2)
                    MolibooGardenHill(height: 0.40, wave: 0.05).fill(Color(red: 0.62, green: 0.82, blue: 0.56)).offset(x: parallax * 0.3)
                    MolibooGardenHill(height: 0.26, wave: 0.07).fill(Color(red: 0.42, green: 0.70, blue: 0.40)).offset(x: parallax * 0.5)
                    // Swaying flowers along the front edge
                    ForEach(0..<9, id: \.self) { i in
                        let x = w * (0.04 + 0.12 * Double(i))
                        let sway = sin(t * 1.3 + Double(i)) * 6
                        MolibooFlower(petal: [Color.pink, .white, Color(red: 1, green: 0.8, blue: 0.4), Color(red: 0.75, green: 0.6, blue: 1)][i % 4])
                            .frame(width: 18, height: 34)
                            .rotationEffect(.degrees(sway), anchor: .bottom)
                            .position(x: x, y: h * (0.86 + 0.03 * Double(i % 3)))
                    }
                    // Drifting petals and dust
                    ForEach(0..<12, id: \.self) { i in
                        let seed = Double(i) * 1.618
                        let px = (seed * 97).truncatingRemainder(dividingBy: 1) * w + CGFloat(sin(t * 0.5 + seed) * 16)
                        let py = ((seed * 0.37 + t * 0.03 * (1 + Double(i % 3) * 0.4)).truncatingRemainder(dividingBy: 1)) * h
                        Group {
                            if i % 3 == 0 { Circle().fill(.white.opacity(0.8)).frame(width: 3, height: 3) }
                            else { Ellipse().fill(Color.pink.opacity(0.7)).frame(width: 7, height: 4).rotationEffect(.degrees(t * 40 + seed * 50)) }
                        }
                        .position(x: px, y: py)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MolibooGardenHill: Shape {
    var height: CGFloat
    var wave: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.maxY - r.height * height
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: top))
        p.addCurve(to: CGPoint(x: r.maxX, y: top + r.height * wave),
                   control1: CGPoint(x: r.width * 0.35, y: top - r.height * wave * 2),
                   control2: CGPoint(x: r.width * 0.7, y: top + r.height * wave * 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct MolibooFlower: View {
    var petal: Color
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Ellipse().fill(petal).frame(width: 6, height: 9).offset(y: -4).rotationEffect(.degrees(Double(i) * 72))
                }
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.3)).frame(width: 5, height: 5)
            }
            .frame(height: 16)
            Rectangle().fill(Color(red: 0.25, green: 0.55, blue: 0.28)).frame(width: 2)
        }
    }
}

/// Mossy rock pedestal with a soft pulsing glow.
struct MolibooMossRock: View {
    var pulse: Bool
    var body: some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [Color(red: 0.75, green: 1, blue: 0.7).opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: 120))
                .frame(width: 240, height: 70).scaleEffect(pulse ? 1.08 : 0.94).opacity(pulse ? 1 : 0.7)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.52, blue: 0.5), Color(red: 0.36, green: 0.34, blue: 0.33)], startPoint: .top, endPoint: .bottom))
                .frame(width: 190, height: 52).offset(y: 12)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.80, blue: 0.38), Color(red: 0.30, green: 0.58, blue: 0.26)], startPoint: .top, endPoint: .bottom))
                .frame(width: 176, height: 34)
            ForEach(0..<7, id: \.self) { i in
                Capsule().fill(Color(red: 0.36, green: 0.66, blue: 0.30)).frame(width: 3, height: 10 + CGFloat(i % 3) * 3)
                    .rotationEffect(.degrees(Double(i * 9 - 27)))
                    .offset(x: CGFloat(i * 26 - 78), y: -14)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Character art: approved portrait render when available (keeps Pebble's Signature Cap), otherwise the 2D figure.
struct MolibooHubArt: View {
    let kind: ModulaMascotKind
    var size: CGFloat
    var body: some View {
        if let img = MolibooPortrait.image(for: kind.rawValue) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            ModulaMascotFigure(kind: kind, pose: .still(), size: size * 0.42).frame(width: size, height: size)
        }
    }
}

/// Pressable spring for cards.
struct MolibooSpringPress: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled ? 0.95 : 1)
            .animation(enabled ? .spring(response: 0.28, dampingFraction: 0.6) : nil, value: configuration.isPressed)
    }
}
