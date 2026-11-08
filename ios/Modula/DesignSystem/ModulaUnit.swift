import SwiftUI

// MARK: - Modula Unit (brand mark)
//
// Exact port of the "Modula Unit — circle construction" (brand/modula-unit-geometry.md).
// Unit box [0,1]², y down, mark touches the box. Built from 8 equal circles + a centre hole:
//   • 4 convex lobes, radius R = 11/60, centres (0.5 ± d, 0.5 ± d), d = 0.5 − R
//   • 4 concave connections, radius r = R, centres on the axes at 0.5 ± e,
//     e = d + √((R + r)² − d²), each externally tangent to its two neighbouring lobes
//   • centre hole, radius h = 0.8·R
// The outer contour runs visually clockwise and the hole visually counter-clockwise, so the
// shape renders identically with even-odd *and* non-zero fill (safe for glass / clipShape).
// Note SwiftUI's `addArc(clockwise:)` is inverted in y-down space: visually clockwise = `false`.

/// The Modula Unit mark as a `Shape`, fitted (square, centred) into the proposed rect.
struct ModulaUnitShape: Shape {
    static let lobeRadius: CGFloat = 11.0 / 60.0
    static let connectionRadius: CGFloat = lobeRadius
    static let holeRadius: CGFloat = 0.8 * lobeRadius
    static var lobeOffset: CGFloat { 0.5 - lobeRadius }
    static var connectionOffset: CGFloat {
        let d = lobeOffset, sum = lobeRadius + connectionRadius
        return d + (sum * sum - d * d).squareRoot()
    }
    /// Angle (degrees) of the lobe/connection tangent point seen from the top connection centre (≈ 30.2726°).
    static var tangentAngle: CGFloat {
        let d = lobeOffset, e = connectionOffset
        return atan2(e - d, d) * 180 / .pi
    }
    /// Clear space around the mark, as a fraction of the mark size (= hole radius).
    static let clearSpace: CGFloat = holeRadius

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let o = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        let R = Self.lobeRadius, r = Self.connectionRadius, h = Self.holeRadius
        let d = Self.lobeOffset, e = Self.connectionOffset, a = Self.tangentAngle
        // Lobes TL, TR, BR, BL; connections T, R, B, L.
        let lobes: [(CGFloat, CGFloat)] = [(0.5 - d, 0.5 - d), (0.5 + d, 0.5 - d), (0.5 + d, 0.5 + d), (0.5 - d, 0.5 + d)]
        let connections: [(CGFloat, CGFloat)] = [(0.5, 0.5 - e), (0.5 + e, 0.5), (0.5, 0.5 + e), (0.5 - e, 0.5)]

        var path = Path()
        for i in 0..<4 {
            let rot = CGFloat(i) * 90
            // Concave side i: (180 − a) → a, visually counter-clockwise (119.45°).
            let c = connections[i]
            // The left connection is the only one whose start is past 360° (≈ 419.7°).
            // Shift both ends by the same whole turn so the signed sweep stays −119.45°.
            addArc(&path, center: p(c.0, c.1), radius: r * s,
                   start: rot + 180 - a, end: rot + a, clockwise: true)
            // Following lobe (TR, BR, BL, TL): (a − 180) → (90 − a), visually clockwise (209.45°).
            let l = lobes[(i + 1) % 4]
            addArc(&path, center: p(l.0, l.1), radius: R * s,
                   start: rot - 180 + a, end: rot + 90 - a, clockwise: false)
        }
        path.closeSubpath()
        // Hole, visually counter-clockwise. End at 180 then 360, not −180:
        // −180 is the same ray as 180, so the second semicircle retraces the first
        // and `contains` leaves the centre filled under both fill rules.
        let centre = p(0.5, 0.5)
        path.move(to: CGPoint(x: centre.x + h * s, y: centre.y))
        path.addArc(center: centre, radius: h * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        path.addArc(center: centre, radius: h * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Keeps a start angle that is a whole turn past 360° from being the only arc in that range.
    /// Both ends move by the same multiple of 360, so the rays and the signed sweep do not change.
    private func addArc(_ path: inout Path, center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, clockwise: Bool) {
        var start = start
        var end = end
        if start >= 360 {
            let turns = (start / 360).rounded(.down)
            start -= turns * 360
            end -= turns * 360
        }
        path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: clockwise)
    }
}

// MARK: - Brand colours

enum ModulaUnitPalette {
    /// Charcoal ink of the solid mark.
    static let ink = Color(red: 0x24 / 255, green: 0x28 / 255, blue: 0x2B / 255)
    static let tealTop = Color(red: 0x2F / 255, green: 0xB8 / 255, blue: 0xC6 / 255)
    static let tealBottom = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x66 / 255)
    static let charcoalTop = Color(red: 0x45 / 255, green: 0x48 / 255, blue: 0x4C / 255)
    static let charcoalBottom = Color(red: 0x1E / 255, green: 0x23 / 255, blue: 0x26 / 255)
    static let neon = Color(red: 0x22 / 255, green: 0xE5 / 255, blue: 0xF2 / 255)
    static let goldLight = Color(red: 0xF6 / 255, green: 0xDF / 255, blue: 0x9A / 255)
    static let gold = Color(red: 0xD9 / 255, green: 0xAE / 255, blue: 0x4E / 255)
    static let goldDeep = Color(red: 0xA9 / 255, green: 0x7A / 255, blue: 0x24 / 255)
}

// MARK: - Mark view

/// The Modula Unit mark in one of its brand styles. Size it with `.frame`; it stays square.
/// Use `ModulaUnitShape` directly for custom fills, clips or badges (e.g. Premium / identity badges).
struct ModulaUnitMark: View {
    enum Style: Equatable {
        /// Brand charcoal ink (light-on-dark automatically in Dark mode unless `color` is given).
        case solid(Color? = nil)
        /// Single colour following the current foreground style (template use).
        case mono
        /// Neon outline with a cyan glow (static under Reduce Motion / Reduce Transparency).
        case neon(Color = ModulaUnitPalette.neon)
        /// Liquid Glass via `modulaGlass`, optionally tinted.
        case glass(Color? = nil)
        /// Premium: gold Liquid Glass (solid gold gradient under Reduce Transparency).
        case premiumGold
    }

    var style: Style = .solid()
    var accessibilityLabel: String = "Modula"

    var body: some View {
        ModulaUnitMarkBody(style: style)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("modula.unit")
    }
}

private struct ModulaUnitMarkBody: View {
    let style: ModulaUnitMark.Style
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch style {
        case .solid(let color):
            ModulaUnitShape().fill(color ?? (scheme == .dark ? Color.white : ModulaUnitPalette.ink), style: FillStyle(eoFill: true))
        case .mono:
            ModulaUnitShape().fill(.foreground, style: FillStyle(eoFill: true))
        case .neon(let color):
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ModulaUnitNeon(color: color, side: side, animated: !reduceMotion, glow: !reduceTransparency)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        case .glass(let tint):
            Color.clear
                .contentShape(ModulaUnitShape())
                .modulaGlass(in: ModulaUnitShape(), interactive: false, tint: tint, specular: true)
        case .premiumGold:
            gold
        }
    }

    private var goldGradient: LinearGradient {
        LinearGradient(colors: [ModulaUnitPalette.goldLight, ModulaUnitPalette.gold, ModulaUnitPalette.goldDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private var gold: some View {
        if reduceTransparency {
            ModulaUnitShape().fill(goldGradient, style: FillStyle(eoFill: true))
        } else {
            ModulaUnitShape().fill(goldGradient.opacity(0.55), style: FillStyle(eoFill: true))
                .modulaGlass(in: ModulaUnitShape(), interactive: false, tint: ModulaUnitPalette.gold, specular: true)
                .overlay {
                    ModulaUnitShape()
                        .stroke(LinearGradient(colors: [.white.opacity(0.75), ModulaUnitPalette.goldLight.opacity(0.2), ModulaUnitPalette.goldDeep.opacity(0.5)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct ModulaUnitNeon: View {
    let color: Color
    let side: CGFloat
    let animated: Bool
    let glow: Bool
    @State private var pulse = false

    var body: some View {
        let line = max(1, side * 0.028)
        ZStack {
            ModulaUnitShape().fill(color.opacity(0.07), style: FillStyle(eoFill: true))
            if glow {
                ModulaUnitShape().stroke(color, lineWidth: line).blur(radius: side * (pulse ? 0.07 : 0.05)).opacity(pulse ? 0.95 : 0.75)
                ModulaUnitShape().stroke(color, lineWidth: line).blur(radius: side * 0.018)
            }
            ModulaUnitShape().stroke(glow ? Color.white.opacity(0.92) : color, lineWidth: line * 0.62)
                .shadow(color: color, radius: glow ? line : 0)
        }
        .onAppear {
            guard animated, glow else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - App-icon tile

/// The Modula app-icon tile drawn natively (white mark on the brand gradient), for in-app brand
/// moments such as the sign-in mark or the QR-code centre. Mark = 58 % of the tile, like the icon.
struct ModulaUnitTile: View {
    enum Variant { case teal, charcoal, light }
    var variant: Variant = .teal
    /// Corner radius as a fraction of the side (iOS icon ≈ 0.225).
    var cornerFraction: CGFloat = 0.225

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: side * cornerFraction, style: .continuous)
            ZStack {
                shape.fill(background)
                ModulaUnitShape()
                    .fill(variant == .light ? ModulaUnitPalette.ink : .white, style: FillStyle(eoFill: true))
                    .frame(width: side * 0.58, height: side * 0.58)
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var background: LinearGradient {
        switch variant {
        case .teal: LinearGradient(colors: [ModulaUnitPalette.tealTop, ModulaUnitPalette.tealBottom], startPoint: .top, endPoint: .bottom)
        case .charcoal: LinearGradient(colors: [ModulaUnitPalette.charcoalTop, ModulaUnitPalette.charcoalBottom], startPoint: .top, endPoint: .bottom)
        case .light: LinearGradient(colors: [.white, Color(white: 0.95)], startPoint: .top, endPoint: .bottom)
        }
    }
}

#if DEBUG
/// `--debug-modula-unit`: every mark style and tile on one screen, for simulator screenshots.
struct ModulaUnitGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ModulaUnitMark(style: .solid()).frame(width: 180, height: 180).padding(.top, 24)
                Text("MODULA UNIT").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                    GridRow {
                        cell("Solid") { ModulaUnitMark(style: .solid()) }
                        cell("Mono") { ModulaUnitMark(style: .mono).foregroundStyle(.tint) }
                        cell("Neon") { ModulaUnitMark(style: .neon()).padding(6).background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                    }
                    GridRow {
                        cell("Glass") { ModulaUnitMark(style: .glass()) }
                        cell("Premium") { ModulaUnitMark(style: .premiumGold) }
                        cell("Glass tint") { ModulaUnitMark(style: .glass(ModulaUnitPalette.tealTop)) }
                    }
                }
                HStack(spacing: 16) {
                    ModulaUnitTile(variant: .light).frame(width: 72, height: 72).shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    ModulaUnitTile(variant: .charcoal).frame(width: 72, height: 72)
                    ModulaUnitTile(variant: .teal).frame(width: 72, height: 72)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [ModulaUnitPalette.tealTop.opacity(0.25), Color(uiColor: .systemBackground), ModulaUnitPalette.gold.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
    }

    private func cell<V: View>(_ title: String, @ViewBuilder _ mark: () -> V) -> some View {
        VStack(spacing: 8) {
            mark().frame(width: 84, height: 84)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
