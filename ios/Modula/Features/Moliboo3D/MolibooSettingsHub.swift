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
    var ambience: MolibooAmbience = .resolved()

    private var hillFar: Color {
        switch ambience {
        case .night: Color(red: 0.16, green: 0.24, blue: 0.30)
        case .evening: Color(red: 0.50, green: 0.52, blue: 0.40)
        default: Color(red: 0.62, green: 0.82, blue: 0.56)
        }
    }
    private var hillNear: Color {
        switch ambience {
        case .night: Color(red: 0.10, green: 0.18, blue: 0.20)
        case .evening: Color(red: 0.34, green: 0.42, blue: 0.30)
        default: Color(red: 0.42, green: 0.70, blue: 0.40)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Sky, light and particles: the shared moving background (paused off-screen / Reduce Motion).
                MolibooAmbientBackground(ambience: ambience, animated: animating)
                HStack(spacing: w * 0.06) {
                    ForEach(0..<4, id: \.self) { _ in
                        UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)
                            .stroke((ambience.isDark ? Color(white: 0.55) : Color(red: 0.86, green: 0.80, blue: 0.74)).opacity(ambience.isDark ? 0.35 : 0.85), lineWidth: 9)
                            .frame(width: w * 0.16, height: h * 0.42)
                    }
                }
                .position(x: w * 0.5 + parallax * 0.2, y: h * 0.42)
                .blur(radius: 1.2)
                MolibooGardenHill(height: 0.40, wave: 0.05).fill(hillFar).offset(x: parallax * 0.3)
                MolibooGardenHill(height: 0.26, wave: 0.07).fill(hillNear).offset(x: parallax * 0.5)
                MolibooSwayingFlowers(animating: animating, dim: ambience.isDark)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Flowers along the front edge; its own low-rate timeline so the scene above stays static.
struct MolibooSwayingFlowers: View {
    var animating: Bool
    var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !animating || reduceMotion)) { ctx in
            let t = animating && !reduceMotion ? ctx.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ForEach(0..<9, id: \.self) { i in
                    MolibooFlower(petal: [Color.pink, .white, Color(red: 1, green: 0.8, blue: 0.4), Color(red: 0.75, green: 0.6, blue: 1)][i % 4])
                        .frame(width: 18, height: 34)
                        .rotationEffect(.degrees(sin(t * 1.3 + Double(i)) * 6), anchor: .bottom)
                        .position(x: w * (0.04 + 0.12 * Double(i)), y: h * (0.86 + 0.03 * Double(i % 3)))
                        .opacity(dim ? 0.7 : 1)
                }
            }
        }
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
