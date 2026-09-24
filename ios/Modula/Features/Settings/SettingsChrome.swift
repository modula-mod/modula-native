import SwiftUI

// MARK: - Shared Settings chrome

/// Gradient icon banner used at the top of Settings leaves.
struct SettingsHeroBanner: View {
    var title: String
    var subtitle: String
    var symbol: String
    @Environment(AppEnvironment.self) private var app

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
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: app.appearance.accent.color.opacity(0.28), radius: 16, y: 8)
                SettingsHeroSparkles()
                    .frame(width: 96, height: 96)
                    .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    }
}
private struct SettingsHeroSparkles: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
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
struct SettingsAPIFootnote: View {
    var text: String

    var body: some View {
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
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
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SettingsHeroBanner(title: title, subtitle: subtitle, symbol: symbol)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        SettingsFeatureTile(
                            title: tile.title,
                            detail: tile.detail,
                            symbol: tile.symbol,
                            tint: app.appearance.accent.color
                        )
                    }
                }

                SettingsGroup(title: "Coming surface", subtitle: "Designed UI — actions stay inactive until a verified contract exists.") {
                    VStack(spacing: 0) {
                        ForEach(Array(previewRows.enumerated()), id: \.offset) { index, row in
                            SettingsPreviewRow(
                                title: row.title,
                                subtitle: row.subtitle,
                                symbol: row.symbol,
                                enabled: false
                            )
                            if index < previewRows.count - 1 { SettingsDivider() }
                        }
                    }
                }

                SettingsAPIFootnote(text: apiNote)
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 10)
                .padding(.bottom, 28)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
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
