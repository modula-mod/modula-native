import VisionKit
import SwiftUI

// MARK: - Shared Settings chrome

/// Gradient icon banner used at the top of Settings leaves.
struct SettingsHeroBanner: View {
    var title: String
    var subtitle: String
    var symbol: String
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                app.appearance.accent.color.opacity(0.95),
                                app.appearance.accent.color.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .modulaHeroSheen(intensity: 0.9)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce.up.byLayer, value: appeared)
                    }
                    .shadow(color: app.appearance.accent.color.opacity(0.28), radius: 16, y: 8)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
                SettingsHeroSparkles(spinning: appeared && !reduceMotion)
                    .frame(width: 96, height: 96)
                    .allowsHitTesting(false)
                    .opacity(appeared || reduceMotion ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(x: appeared || reduceMotion ? 0 : 10)
            .opacity(appeared || reduceMotion ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !appeared else { return }
            withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }
}
private struct SettingsHeroSparkles: View {
    var spinning = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Slow orbit; paused (and static) under Reduce Motion.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !spinning || reduceMotion)) { context in
            let angle = spinning && !reduceMotion
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40 * 360
                : 0
            sparkles.rotationEffect(.degrees(angle))
        }
    }

    private var sparkles: some View {
        ZStack {
            Circle()
                .stroke(app.appearance.accent.color.opacity(0.18), lineWidth: 1)
                .frame(width: 88, height: 88)
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .offset(y: -44)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }
}

/// Honest capability footnote shown under designed UI when Greenfield is unverified.
/// Honest capability footnote ("saved on this device", "not available
/// yet"). Copy must be plain language — no backend names or internal terms.
struct SettingsAPIFootnote: View {
    var text: String

    var body: some View {
        footnote
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
        .accessibilityIdentifier("settings.api.footnote")
    }
}

struct SettingsFeatureTile: View {
    var title: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SettingsPreviewRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var trailing: String? = nil
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(enabled ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

/// Designed leaf for capability-unavailable destinations — full UI, honest footnote.
struct SettingsDesignedUnavailableCanvas: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tiles: [(title: String, detail: String, symbol: String)]
    var previewRows: [(title: String, subtitle: String, symbol: String)]
    var apiNote: String
    /// Real destinations that help today (shown instead of disabled preview rows).
    var alternatives: [(title: String, subtitle: String, symbol: String, route: SettingsRoute)] = []
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SettingsHeroBanner(title: title, subtitle: subtitle, symbol: symbol)

                // Scope card: says plainly that nothing here is switchable in this version.
                // Planned capabilities are not rendered as disabled controls.
                ModulaCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "circle.dashed")
                            .font(.title2)
                            .foregroundStyle(app.appearance.accent.color)
                            .symbolEffect(.rotate, options: .nonRepeating)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not available in this version")
                                .font(.headline)
                            Text(apiNote)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if !alternatives.isEmpty {
                    SettingsGroup(title: "What you can do now") {
                        VStack(spacing: 0) {
                            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, row in
                                SettingsNavigationRow(title: row.title, subtitle: row.subtitle, symbol: row.symbol) {
                                    app.navigation.open(.settings(row.route))
                                }
                                if index < alternatives.count - 1 { SettingsDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.designed.unavailable")
    }
}

struct SettingsScrollCanvas<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 10)
                .padding(.bottom, SettingsInsets.bottom)
            }
            .onAppear { scroll(to: app.navigation.settingsFocusAnchor, proxy: proxy) }
            .onChange(of: app.navigation.settingsFocusAnchor) { _, anchor in
                scroll(to: anchor, proxy: proxy)
            }
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
    }

    private func scroll(to anchor: String?, proxy: ScrollViewProxy) {
        guard let anchor else { return }
        withAnimation(ModulaMotion.animation(.navigation, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
            proxy.scrollTo(anchor, anchor: .center)
        }
    }
}

// MARK: - Graphics

enum SettingsGraphicStyle: Hashable {
    case waves, rings, constellation, meter, filmstrip, orbit, grid, pulse, radar, stack, ribbon, badges
}

struct SettingsSceneGraphic: View {
    var style: SettingsGraphicStyle
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            switch style {
            case .waves: SettingsWaveBarsGraphic()
            case .rings: SettingsRingsGraphic()
            case .constellation: SettingsConstellationGraphic()
            case .meter: SettingsMeterGraphic()
            case .filmstrip: SettingsFilmstripGraphic()
            case .orbit: SettingsOrbitGraphic()
            case .grid: SettingsTileGridGraphic()
            case .pulse: SettingsPulseGraphic()
            case .radar: SettingsRadarGraphic()
            case .stack: SettingsCardStackGraphic()
            case .ribbon: SettingsRibbonGraphic()
            case .badges: SettingsBadgesGraphic()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            app.appearance.accent.color.opacity(0.14),
                            app.appearance.accent.color.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(app.appearance.accent.color.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct SettingsWaveBarsGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<22, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(app.appearance.accent.color.opacity(0.3 + Double(index % 5) * 0.12))
                    .frame(width: 7, height: CGFloat(16 + (index * 7 % 11) * 6))
            }
        }
        .padding(.horizontal, 18)
    }
}

struct SettingsRingsGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { ring in
                Circle()
                    .stroke(app.appearance.accent.color.opacity(0.45 - Double(ring) * 0.1), lineWidth: 2)
                    .frame(width: CGFloat(36 + ring * 22), height: CGFloat(36 + ring * 22))
            }
            Circle()
                .fill(app.appearance.accent.color.gradient)
                .frame(width: 18, height: 18)
        }
    }
}

struct SettingsConstellationGraphic: View {
    @Environment(AppEnvironment.self) private var app

    private let points: [CGPoint] = [
        .init(x: 0.18, y: 0.62), .init(x: 0.32, y: 0.28), .init(x: 0.48, y: 0.55),
        .init(x: 0.62, y: 0.22), .init(x: 0.78, y: 0.48), .init(x: 0.88, y: 0.72)
    ]

    var body: some View {
        GeometryReader { geo in
            let mapped = points.map { CGPoint(x: $0.x * geo.size.width, y: $0.y * geo.size.height) }
            Path { path in
                guard let first = mapped.first else { return }
                path.move(to: first)
                for point in mapped.dropFirst() { path.addLine(to: point) }
            }
            .stroke(app.appearance.accent.color.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            ForEach(Array(mapped.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(app.appearance.accent.color)
                    .frame(width: 8, height: 8)
                    .position(point)
                    .shadow(color: app.appearance.accent.color.opacity(0.4), radius: 4)
            }
        }
        .padding(16)
    }
}

struct SettingsMeterGraphic: View {
    @Environment(AppEnvironment.self) private var app
    var progress: CGFloat = 0.62

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)
                .frame(width: 84, height: 84)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [app.appearance.accent.color.opacity(0.35), app.appearance.accent.color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))")
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsFilmstripGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(app.appearance.accent.color.opacity(0.18 + Double(index) * 0.08))
                    .frame(width: 52, height: 72)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.white.opacity(0.55))
                            .frame(width: 18, height: 4)
                            .padding(.bottom, 8)
                    }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct SettingsOrbitGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            Circle()
                .stroke(app.appearance.accent.color.opacity(0.2), lineWidth: 1)
                .frame(width: 88, height: 88)
            Circle()
                .stroke(app.appearance.accent.color.opacity(0.28), lineWidth: 1)
                .frame(width: 56, height: 56)
            Circle()
                .fill(app.appearance.accent.color)
                .frame(width: 14, height: 14)
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .offset(y: index == 0 ? -44 : (index == 1 ? -28 : 0))
                    .offset(x: index == 2 ? 44 : 0)
                    .rotationEffect(.degrees(Double(index) * 40))
            }
        }
    }
}

struct SettingsTileGridGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(app.appearance.accent.color.opacity(index.isMultiple(of: 3) ? 0.4 : 0.16))
                    .frame(height: 36)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}

struct SettingsPulseGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let midY = geo.size.height * 0.55
                path.move(to: CGPoint(x: 0, y: midY))
                var x: CGFloat = 0
                var up = true
                while x < geo.size.width {
                    let peak = midY + (up ? -28 : 28)
                    path.addQuadCurve(
                        to: CGPoint(x: x + 28, y: midY),
                        control: CGPoint(x: x + 14, y: peak)
                    )
                    x += 28
                    up.toggle()
                }
            }
            .stroke(app.appearance.accent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: app.appearance.accent.color.opacity(0.35), radius: 6)
        }
        .padding(.horizontal, 16)
    }
}

struct SettingsStatChip: View {
    var label: String
    var value: String
    var symbol: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(app.appearance.accent.color)
                .frame(width: 28, height: 28)
                .background(app.appearance.accent.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline.monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsRadarGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ModulaRadarScope(tint: app.appearance.accent.color, energy: 0.8)
            .frame(width: 112, height: 112)
    }
}

/// Vector radar kept for previews and catalog comparisons.
struct SettingsStaticRadarGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(app.appearance.accent.color.opacity(0.2), lineWidth: 1)
                    .frame(width: CGFloat(40 + ring * 28), height: CGFloat(40 + ring * 28))
            }
            Path { path in
                path.move(to: .init(x: 60, y: 60))
                path.addLine(to: .init(x: 60, y: 18))
                path.addLine(to: .init(x: 92, y: 42))
                path.closeSubpath()
            }
            .fill(app.appearance.accent.color.opacity(0.28))
            .frame(width: 120, height: 120)
            Circle()
                .fill(app.appearance.accent.color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 120, height: 120)
    }
}

struct SettingsCardStackGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(app.appearance.accent.color.opacity(0.18 + Double(index) * 0.12))
                    .frame(width: 150 - CGFloat(index) * 12, height: 78)
                    .offset(y: CGFloat(index) * -10)
                    .rotationEffect(.degrees(Double(index) * -4))
            }
        }
        .padding(.top, 18)
    }
}

struct SettingsRibbonGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(app.appearance.accent.color.opacity(0.2 + Double(index % 3) * 0.18))
                    .frame(width: 18, height: CGFloat(28 + (index % 4) * 14))
                    .rotationEffect(.degrees(-18))
                    .offset(y: index.isMultiple(of: 2) ? -6 : 8)
            }
        }
        .padding(.horizontal, 24)
    }
}

struct SettingsBadgesGraphic: View {
    @Environment(AppEnvironment.self) private var app
    private let symbols = ["star.fill", "flame.fill", "bolt.fill", "heart.fill", "leaf.fill"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                ZStack {
                    Circle()
                        .fill(app.appearance.accent.color.opacity(0.16 + Double(index) * 0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .foregroundStyle(app.appearance.accent.color)
                }
                .offset(y: index.isMultiple(of: 2) ? -8 : 10)
            }
        }
    }
}


/// Human-readable label for a raw enum value ("reduceMotion" -> "Reduce
/// Motion", "oled" -> "OLED") instead of `rawValue.capitalized`.
func settingsDisplayTitle(_ raw: String) -> String {
    let special: [String: String] = ["oled": "OLED", "ui": "UI", "ai": "AI", "id": "ID"]
    if let match = special[raw.lowercased()] { return match }
    var words: [String] = []
    var current = ""
    for character in raw {
        if character == "_" || character == "-" || character == " " {
            if !current.isEmpty { words.append(current); current = "" }
        } else if character.isUppercase, !current.isEmpty {
            words.append(current); current = String(character)
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { words.append(current) }
    return words.map { special[$0.lowercased()] ?? ($0.prefix(1).uppercased() + $0.dropFirst()) }.joined(separator: " ")
}


/// iOS-Settings-style coloured rounded-square icon tile.
struct SettingsIconTile: View {
    let symbol: String
    var size: CGFloat = 30

    static func color(for symbol: String) -> Color {
        let map: [(String, Color)] = [
            ("person", .blue), ("lock", .gray), ("faceid", .green), ("hand.raised", .blue), ("shield", .indigo),
            ("bell", .red), ("moon", .indigo), ("paintpalette", .cyan), ("accessibility", .blue), ("globe", .blue),
            ("pawprint", .orange), ("bubble", .green), ("photo", .pink), ("speaker", .pink), ("rectangle.stack", .orange),
            ("internaldrive", .gray), ("battery", .green), ("network", .blue), ("shippingbox", .brown), ("sparkles", .purple),
            ("questionmark", .blue), ("info", .gray), ("hammer", .gray), ("brain", .purple), ("slider", .gray),
            ("hand.draw", .teal), ("keyboard", .gray), ("magnifyingglass", .gray), ("square.and.arrow.up", .blue),
            ("nosign", .red), ("key", .gray), ("trash", .red), ("envelope", .blue), ("at", .teal), ("laptop", .gray),
        ]
        return map.first { symbol.hasPrefix($0.0) || symbol.contains($0.0) }?.1 ?? .accentColor
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.color(for: symbol).gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 52pt row: tile · title (+ optional subtitle) · value · chevron.
struct SettingsTileRow: View {
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var symbol: String
    var showsChevron = true
    var action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let value, !value.isEmpty {
                    Text(value).foregroundStyle(.secondary).lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 52pt toggle row with a tile; standard-size system switch.
struct SettingsTileToggle: View {
    var title: String
    var symbol: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: symbol)
                Text(title).lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .frame(minHeight: 52)
    }
}

/// Liquid Glass grouped card.
struct SettingsGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
    }
}

/// Compact identity row: avatar · name / handle · chevron (opens profile edit).
struct SettingsProfileHeaderRow: View {
    var name: String
    var handle: String?
    var initials: String
    var avatarURL: URL?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ModulaAvatar(initials: initials, url: avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(handle.map { "\($0) · Edit profile" } ?? "Sign in").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.identity.row")
    }
}

/// Bottom clearance for every Settings page (tab bar + home indicator + floating buttons).
enum SettingsInsets {
    static let bottom: CGFloat = 120
}

/// Routes that only preview features without a backend. Shown in DEBUG only.
enum SettingsAudit {
    static func previewOnly(_ route: SettingsRoute) -> Bool {
        switch route {
        case .privacy(.glassPrivacy), .connectors, .integrations, .monetisation, .family,
             .widgets, .location, .passkeys, .labs, .developer, .features, .updates:
            return true
        default:
            return false
        }
    }
}


/// Gestures + Typing + Search + Sharing + Photos + Focus: six thin pages folded into one.
/// Same storage keys as the old pages. Toggles no code reads (double-tap like, swipe to reply,
/// composer tool swipe) are not shown.
struct GeneralBehaviourSettingsPage: View {
    @AppStorage("settings.gestures.edgeBack") private var edgeBack = true
    @AppStorage("settings.gestures.shakeUndo") private var shakeUndo = false
    @AppStorage("settings.keyboard.periodShortcut") private var autocorrect = true
    @AppStorage("settings.keyboard.capsLock") private var autoCaps = true
    @AppStorage("settings.finder.includeModules") private var includeModules = true
    @AppStorage("settings.finder.peopleFirst") private var peopleFirst = false
    @AppStorage("settings.sharing.includeHandle") private var includeHandle = true
    @AppStorage("settings.sharing.preferNativeSheet") private var preferNative = true
    @AppStorage("settings.sharing.copyAsLink") private var copyAsLink = false
    @AppStorage("settings.photos.autoSaveStories") private var autoSaveStories = false
    @AppStorage("settings.photos.limitedLibraryHint") private var limitedHint = true
    @AppStorage("settings.focus.hideBadges") private var hideBadges = false
    @AppStorage("settings.focus.dimActivity") private var dimActivity = true
    @AppStorage("settings.focus.allowMentions") private var allowMentions = true

    var body: some View {
        SettingsScrollCanvas {
            SettingsGroup(title: "Gestures") {
                SettingsTileToggle(title: "Edge swipe to go back", symbol: "hand.draw.fill", isOn: $edgeBack).settingsAnchor("gestures.edgeBack")
                SettingsDivider()
                SettingsTileToggle(title: "Shake to undo", symbol: "iphone.radiowaves.left.and.right", isOn: $shakeUndo)
            }
            SettingsGroup(title: "Typing") {
                SettingsTileToggle(title: "Autocorrect in composers", symbol: "keyboard", isOn: $autocorrect)
                SettingsDivider()
                SettingsTileToggle(title: "Auto-capitalise sentences", symbol: "textformat", isOn: $autoCaps)
            }
            SettingsGroup(title: "Search") {
                SettingsTileToggle(title: "Include modules in results", symbol: "magnifyingglass", isOn: $includeModules)
                SettingsDivider()
                SettingsTileToggle(title: "Show people first", symbol: "person.2.fill", isOn: $peopleFirst)
            }
            SettingsGroup(title: "Sharing") {
                SettingsTileToggle(title: "Use the system share sheet", symbol: "square.and.arrow.up", isOn: $preferNative).settingsAnchor("sharing.sheet")
                SettingsDivider()
                SettingsTileToggle(title: "Include @handle in share text", symbol: "at", isOn: $includeHandle)
                SettingsDivider()
                SettingsTileToggle(title: "Copy link instead of opening sheet", symbol: "link", isOn: $copyAsLink)
            }
            SettingsGroup(title: "Photos") {
                SettingsTileToggle(title: "Save Stories you post to Photos", symbol: "photo.fill", isOn: $autoSaveStories)
                SettingsDivider()
                SettingsTileToggle(title: "Explain photo access in the composer", symbol: "photo.badge.exclamationmark", isOn: $limitedHint)
            }
            SettingsGroup(title: "During iOS Focus") {
                SettingsTileToggle(title: "Hide tab badges", symbol: "moon.fill", isOn: $hideBadges)
                SettingsDivider()
                SettingsTileToggle(title: "Dim Activity", symbol: "moon.stars.fill", isOn: $dimActivity).settingsAnchor("focus.dimActivity")
                SettingsDivider()
                SettingsTileToggle(title: "Still allow @mentions", symbol: "at.badge.plus", isOn: $allowMentions)
            }
        }
        .navigationTitle("Gestures, Typing & Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.general-behaviour")
    }
}

/// Battery & Data + Network folded into one page (same keys).
struct BatteryNetworkSettingsPage: View {
    @AppStorage("settings.battery.dataSaver") private var dataSaver = false
    @AppStorage("settings.battery.reduceMotionExtra") private var reduceMotionExtra = false
    @AppStorage("settings.battery.pauseAutoplayOnLowPower") private var pauseAutoplay = true
    @AppStorage("settings.network.preferWiFiUploads") private var preferWiFi = true
    @AppStorage("settings.network.preloadMedia") private var preload = true

    var body: some View {
        SettingsScrollCanvas {
            SettingsGroup(title: "Battery") {
                SettingsTileToggle(title: "Data saver", symbol: "battery.100.bolt", isOn: $dataSaver).settingsAnchor("battery.dataSaver")
                SettingsDivider()
                SettingsTileToggle(title: "Pause autoplay in Low Power Mode", symbol: "bolt.slash.fill", isOn: $pauseAutoplay).settingsAnchor("battery.lowPower")
                SettingsDivider()
                SettingsTileToggle(title: "Extra motion reduction", symbol: "waveform.path", isOn: $reduceMotionExtra)
            }
            SettingsGroup(title: "Network", subtitle: "Uploads over 25 MB wait for Wi‑Fi on cellular or Low Data Mode.") {
                SettingsTileToggle(title: "Prefer Wi‑Fi for large uploads", symbol: "network", isOn: $preferWiFi)
                SettingsDivider()
                SettingsTileToggle(title: "Preload feed media on Wi‑Fi", symbol: "arrow.down.circle.fill", isOn: $preload)
            }
        }
        .navigationTitle("Battery & Network")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.battery-network")
    }
}

/// Privacy, Glass Privacy (debug), Blocked, Security, App Lock and Face ID on one page.
struct PrivacySafetySettingsPage: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsSetup = false
    @State private var showsChange = false
    @State private var confirmSignOutReset = false
    @State private var setupMethod: AppLockMethod?

    var body: some View {
        let lock = app.appLock
        SettingsScrollCanvas {
            SettingsGroup(title: "Privacy", subtitle: "Your email and phone number are never shown on your profile.") {
                SettingsTileRow(title: "Blocked Accounts", symbol: "nosign") { app.navigation.open(.settings(.privacy(.blocked))) }
                SettingsDivider()
                SettingsTileRow(title: "Safety & Reporting", subtitle: "Muted words, sensitive content", symbol: "shield.checkered") { app.navigation.open(.settings(.safety(.root))) }
                SettingsDivider()
                SettingsTileRow(title: "Export Your Data", symbol: "square.and.arrow.up") { app.navigation.open(.settings(.dataStorage(.export))) }
                SettingsDivider()
                SettingsTileRow(title: "Make a Privacy Request", symbol: "hand.raised.fill") { app.navigation.open(.settings(.help(.contact))) }
            }
            SettingsGroup(title: "Security", subtitle: "App Lock protects the signed-in app on this device. It doesn’t replace account login.") {
                SettingsTileToggle(title: "App Lock", symbol: "lock.fill", isOn: Binding(
                    get: { lock.enabled },
                    set: { value in
                        if value, (try? lock.setEnabled(true)) == nil {
                            showsSetup = true
                        } else if !value {
                            try? lock.setEnabled(false)
                            app.refreshLaunchState()
                        }
                    }
                ))
                .accessibilityIdentifier("settings.applock.enable")
                if lock.enabled {
                    SettingsDivider()
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "timer")
                        Text("Require")
                        Spacer()
                        Picker("Require", selection: Binding(get: { lock.settings.interval }, set: { lock.setInterval($0) })) {
                            ForEach(AppLockInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(minHeight: 52)
                    SettingsDivider()
                    SettingsTileRow(title: "Change Passcode", symbol: "key.fill") { showsChange = true }
                }
                SettingsDivider()
                SettingsTileToggle(title: "Unlock with \(lock.biometricAvailability.kind.title)", symbol: "faceid", isOn: Binding(
                    get: { lock.settings.biometricsEnabled },
                    set: { lock.setBiometricsEnabled($0) }
                ))
                .disabled(!lock.biometricAvailability.isUsable)
                SettingsDivider()
                SettingsTileToggle(title: "Hide in App Switcher", symbol: "eye.slash.fill", isOn: Binding(
                    get: { lock.settings.hideInAppSwitcher },
                    set: { lock.setHideInAppSwitcher($0) }
                ))
            }
            if lock.enabled {
                SettingsGroup(title: "Unlock Method", subtitle: "Your passcode always works as a backup, so you can’t get locked out.") {
                    ForEach(Array(AppLockMethod.allCases.enumerated()), id: \.element) { offset, method in
                        if offset > 0 { SettingsDivider() }
                        SettingsTileRow(
                            title: method.title,
                            subtitle: method.subtitle,
                            value: lock.settings.method == method ? "On" : (method != .passcode && !lock.hasSecret(for: method) ? "Set Up" : nil),
                            symbol: method.symbol
                        ) {
                            if method == .passcode || lock.hasSecret(for: method) {
                                lock.setMethod(method)
                            } else {
                                setupMethod = method
                            }
                        }
                        .accessibilityIdentifier("settings.applock.method.\(method.rawValue)")
                    }
                    if lock.settings.method != .passcode {
                        SettingsDivider()
                        SettingsTileRow(title: "Change \(lock.settings.method.title)", symbol: "arrow.triangle.2.circlepath") { setupMethod = lock.settings.method }
                    }
                }
                SettingsGroup(title: "Lock Screen") {
                    SettingsTileToggle(title: "Unlock Effects", symbol: "sparkles", isOn: Binding(
                        get: { lock.settings.effectsEnabled }, set: { lock.setEffectsEnabled($0) }))
                    SettingsDivider()
                    SettingsTileToggle(title: "Time & Greeting", symbol: "clock.fill", isOn: Binding(
                        get: { lock.settings.showsGreeting }, set: { lock.setShowsGreeting($0) }))
                    SettingsDivider()
                    SettingsTileToggle(title: "Hide Pattern Trail", symbol: "eye.slash", isOn: Binding(
                        get: { lock.settings.hidesPatternTrail }, set: { lock.setHidesPatternTrail($0) }))
                    SettingsDivider()
                    SettingsTileToggle(title: "Lock Haptics", symbol: "iphone.radiowaves.left.and.right", isOn: Binding(
                        get: { lock.settings.hapticsEnabled }, set: { lock.setHapticsEnabled($0) }))
                }
            }
            SettingsGroup(title: "Account security") {
                SettingsTileRow(title: "Password", value: "Reset by email", symbol: "key") { app.navigation.open(.settings(.account(.password))) }
                SettingsDivider()
                SettingsTileRow(title: "Sessions", symbol: "laptopcomputer.and.iphone") { app.navigation.open(.settings(.account(.sessions))) }
            }
            if lock.enabled {
                Button("Forgot Passcode? Sign Out and Reset App Lock", role: .destructive) { confirmSignOutReset = true }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .navigationTitle("Privacy & Safety")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                PasscodeSetupView(title: "App Lock") { passcode in
                    try app.appLock.setPasscode(passcode)
                    try app.appLock.setEnabled(true)
                    app.refreshLaunchState()
                }
            }
        }
        .sheet(isPresented: $showsChange) {
            NavigationStack {
                PasscodeSetupView(title: "Change Passcode") { passcode in
                    try app.appLock.setPasscode(passcode)
                }
            }
        }
        .sheet(item: $setupMethod) { method in
            NavigationStack {
                LockSecretSetupView(method: method) { secret in
                    try app.appLock.setAlternativeSecret(secret, for: method)
                }
            }
        }
        .confirmationDialog("Sign out and reset App Lock?", isPresented: $confirmSignOutReset, titleVisibility: .visible) {
            Button("Sign Out and Reset", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("settings.privacy-security")
    }
}

// MARK: - Telegram-style Settings kit (PR L)


/// Telegram "avatar into the Dynamic Island" merge. Rendered as a full-screen,
/// non-interactive overlay that follows the real avatar's on-screen frame; as it
/// nears the island it shrinks, blurs, darkens and joins it as a metaball
/// (blur + alpha threshold in a Canvas). No island → fades into the top edge.
struct IslandAvatarMerge<Avatar: View>: View {
    /// Avatar frame in global (window) coordinates.
    var frame: CGRect
    var reduceMotion: Bool
    @ViewBuilder var avatar: Avatar

    static var safeTop: CGFloat { ProfileFullBleedMetrics.windowSafeAreaTop }
    static var hasIsland: Bool { safeTop >= 58 }

    static func islandRect(width: CGFloat) -> CGRect {
        let h: CGFloat = 37, w: CGFloat = 125
        return CGRect(x: (width - w) / 2, y: max(safeTop - 48, 9), width: w, height: h)
    }

    static func smooth(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 0 = avatar at rest · 1 = fully absorbed by the island / top edge.
    static func progress(for frame: CGRect) -> CGFloat {
        guard frame.height > 0 else { return 0 }
        let target = hasIsland ? max(safeTop - 48, 9) + 18.5 : 0
        let range: CGFloat = 190
        let d = frame.midY - target
        return min(max(1 - d / range, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let p = Self.progress(for: frame)
            if p > 0, frame.width > 0 {
                let w = geo.size.width
                let island = Self.islandRect(width: w)
                let targetY = Self.hasIsland ? island.midY : -10
                let cx = frame.midX + (w / 2 - frame.midX) * p
                let cy = max(frame.midY, targetY)
                let size = max(frame.width * (1 - 0.78 * p), 6)
                ZStack {
                    if reduceMotion {
                        avatar
                            .frame(width: frame.width, height: frame.width)
                            .clipShape(Circle())
                            .position(x: frame.midX, y: frame.midY)
                            .opacity(Double(1 - p))
                    } else {
                        if Self.hasIsland, p > 0.3 {
                            // Gooey drop: island capsule + disc, blurred then alpha-thresholded so
                            // they fuse with a soft liquid neck (no hard bridge geometry). Drawn in
                            // pure black so it reads as part of the Dynamic Island.
                            let r = size / 2
                            Canvas { ctx, _ in
                                ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
                                ctx.addFilter(.blur(radius: 7))
                                ctx.drawLayer { layer in
                                    layer.fill(Capsule(style: .continuous).path(in: island), with: .color(.black))
                                    layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: size, height: size)), with: .color(.black))
                                }
                            }
                            .opacity(Double(Self.smooth(p, 0.3, 0.55)))
                        }
                        avatar
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            // The photo dissolves into (or emerges out of) the drop, no dark veil.
                            .opacity(Self.hasIsland ? Double(1 - Self.smooth(p, 0.55, 0.88)) : Double(1 - p))
                            .position(x: cx, y: cy)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Solid inset-grouped card (Telegram): ~16pt margins, 11pt radius.
struct TelegramSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Hairline that starts where the row text starts (16 + 30 tile + 14).
struct TelegramDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, 60)
    }
}

struct TelegramRow: View {
    var title: String
    var symbol: String
    var tint: Color
    var value: String? = nil
    var badge: Int? = nil
    var titleColor: Color? = nil
    var action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(titleColor ?? .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color.red, in: Capsule())
                }
                if let value, !value.isEmpty {
                    Text(value).foregroundStyle(.secondary).lineLimit(1)
                }
                if titleColor == nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue([value, badge.map { "\($0) new" }].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Full-screen QR modal (scales in) with Close and an on-device Scan QR.
struct SettingsQRModal: View {
    var onClose: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var scanning = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let profile = app.profile.ownProfile {
                ModulaProfileCodeView(profile: profile, onDismiss: onClose)
            } else {
                ContentUnavailableView("No profile yet", systemImage: "qrcode", description: Text("Sign in to get your Modula code."))
            }
            VStack {
                // The profile card has its own "Done"; a second X crammed beside the top-bar
                // pills only when there's no card.
                if app.profile.ownProfile == nil {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .modulaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                }
                Spacer()
                if DataScannerViewController.isSupported {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color, prominent: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            SettingsQRScanner { url in
                scanning = false
                onClose()
                _ = ModulaLinkRouter.handle(url, source: nil)
            } onCancel: { scanning = false }
            .ignoresSafeArea()
        }
    }
}

private struct SettingsQRScanner: UIViewControllerRepresentable {
    var onURL: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in onCancel() })
        try? scanner.startScanning()
        return UINavigationController(rootViewController: scanner)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onURL: onURL) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onURL: (URL) -> Void
        private var done = false
        init(onURL: @escaping (URL) -> Void) { self.onURL = onURL }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue, let url = URL(string: text), url.scheme != nil {
                    done = true
                    dataScanner.stopScanning()
                    HapticEngine.shared.play(.success)
                    onURL(url)
                    return
                }
            }
        }
    }
}
