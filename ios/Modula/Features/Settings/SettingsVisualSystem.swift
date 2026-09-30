import SwiftUI

// MARK: - Geometry

enum SettingsVisualMetrics {
    static let coverHeight: CGFloat = 132
    static let avatarSize: CGFloat = 88
    static let avatarOverlap: CGFloat = 38
    static let avatarBorder: CGFloat = 3
    static let graphicHeight: CGFloat = 168
    static let cardRadius: CGFloat = 26
    static let sectionSpacing: CGFloat = 26
    static let maxCoverStretch: CGFloat = 32
}

// MARK: - Search focus

struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    var id: String { RouteSerializer.serialize(.settings(destination.route)) + (anchor ?? "") }
    let destination: SettingsDestination
    let anchor: String?
}

extension SettingsRegistry {
    static func searchEntries(query: String, includeDeveloper: Bool) -> [SettingsSearchEntry] {
        search(query: query, includeDeveloper: includeDeveloper).map {
            SettingsSearchEntry(destination: $0, anchor: $0.anchor)
        }
    }
}

struct SettingsAnchorHighlight: ViewModifier {
    let anchor: String
    @Environment(AppEnvironment.self) private var app
    @State private var emphasized = false

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(app.appearance.accent.color.opacity(emphasized ? 0.18 : 0))
            }
            .onAppear { flashIfNeeded() }
            .onChange(of: app.navigation.settingsFocusAnchor) { _, _ in flashIfNeeded() }
    }

    private func flashIfNeeded() {
        guard app.navigation.settingsFocusAnchor == anchor else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { emphasized = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { emphasized = false }
            if app.navigation.settingsFocusAnchor == anchor {
                app.navigation.settingsFocusAnchor = nil
            }
        }
    }
}

extension View {
    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorHighlight(anchor: anchor))
    }
}

// MARK: - Cover header

struct SettingsCoverHeader: View {
    var coverURL: URL?
    var displayName: String
    var handle: String?
    var initials: String
    var avatarURL: URL?
    var namespace: Namespace.ID
    var progress: CGFloat
    var onIdentityTap: () -> Void
    var onEdit: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat { ModulaScrollProgress.clamp(progress) }

    var body: some View {
        VStack(spacing: 10) {
            cover
            identity
            Button(action: onEdit) {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 18)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("settings.identity.edit")
        }
        .frame(maxWidth: .infinity)
        .opacity(reduceMotion ? (clamped > 0.55 ? 0 : 1) : Double(max(0, 1 - clamped * 1.15)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.identity.hero")
    }

    private var topBleed: CGFloat { ProfileFullBleedMetrics.windowSafeAreaTop }
    private var coverHeight: CGFloat { SettingsVisualMetrics.coverHeight + topBleed }

    private var cover: some View {
        GeometryReader { proxy in
            let stretch = coverStretch(proxy)
            ZStack(alignment: .bottom) {
                fallback
                if let coverURL {
                    ModulaRemoteImage(url: coverURL, cacheKey: "settings-cover:\(coverURL.path)", maximumPixelSize: 2_000) { phase in
                        if case .success(let image) = phase {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if case .failure = phase {
                            fallback
                        } else {
                            fallback.overlay(ProgressView().tint(.white.opacity(0.8)))
                        }
                    }
                }
                LinearGradient(
                    colors: [Color.black.opacity(scheme == .dark ? 0.35 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: topBleed + 56)
                .frame(maxHeight: .infinity, alignment: .top)
                bottomBlur
            }
            .frame(width: proxy.size.width, height: coverHeight + stretch)
            .clipped()
            .offset(y: reduceMotion ? 0 : -stretch)
        }
        .frame(height: coverHeight)
        .padding(.horizontal, -ModulaLayout.contentInset)
        .accessibilityLabel(coverURL == nil ? "Profile cover, accent background" : "Profile cover photo")
        .accessibilityIdentifier("settings.cover")
    }

    private var bottomBlur: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.35),
                            .init(color: .white.opacity(0.85), location: 0.7),
                            .init(color: .white, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: canvas.opacity(0.2), location: 0.45),
                    .init(color: canvas.opacity(0.82), location: 0.82),
                    .init(color: canvas, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 92)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Button(action: onIdentityTap) {
                ModulaAvatar(initials: initials, url: avatarURL, size: SettingsVisualMetrics.avatarSize)
                    .overlay {
                        Circle().stroke(canvas, lineWidth: SettingsVisualMetrics.avatarBorder)
                    }
                    .matchedGeometryEffect(id: "settings.identity.avatar", in: namespace, isSource: clamped < 0.55)
                    .accessibilityLabel("Account")
            }
            .buttonStyle(.plain)
            .offset(y: -SettingsVisualMetrics.avatarOverlap)
            .padding(.bottom, -SettingsVisualMetrics.avatarOverlap)

            Button(action: onIdentityTap) {
                VStack(spacing: 2) {
                    Text(displayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let handle {
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(handle.map { "\(displayName), \($0)" } ?? displayName)
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    app.appearance.accent.color.opacity(scheme == .dark ? 0.85 : 0.95),
                    app.appearance.accent.color.opacity(scheme == .dark ? 0.35 : 0.45),
                    canvas
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(app.appearance.accent.color.opacity(0.35))
                .frame(width: 180, height: 180)
                .blur(radius: 8)
                .offset(x: 90, y: -20)
        }
        .accessibilityHidden(true)
    }

    private var canvas: Color {
        ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
    }

    private func coverStretch(_ proxy: GeometryProxy) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let pull = proxy.frame(in: .named("modula.progressive")).minY
        return min(SettingsVisualMetrics.maxCoverStretch, max(0, pull))
    }
}

// MARK: - Intelligence card

struct SettingsIntelligenceCard: View {
    var status: String
    var detail: String
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsNodusMark()
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligence")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("On-device models, knowledge and privacy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.appearance.accent.color)
                    Spacer()
                    Text(detail)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: SettingsVisualMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsVisualMetrics.cardRadius, style: .continuous)
                    .strokeBorder(app.appearance.accent.color.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Intelligence. \(status). \(detail)")
        .accessibilityIdentifier("settings.intelligence.card")
    }
}

struct SettingsNodusMark: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let accent = app.appearance.accent.color
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - 54, y: center.y - 22, width: 108, height: 44))
            context.stroke(ring, with: .color(accent.opacity(scheme == .dark ? 0.7 : 0.55)), lineWidth: 1.5)
            var core = Path()
            core.addEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
            context.fill(core, with: .color(accent))
            for point in [CGPoint(x: center.x - 70, y: center.y), CGPoint(x: center.x + 70, y: center.y), CGPoint(x: center.x, y: center.y - 28)] {
                var node = Path()
                node.addEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                context.fill(node, with: .color(accent.opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Domain graphics

struct SettingsGraphicFrame<Content: View>: View {
    var caption: String
    @ViewBuilder var content: () -> Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
                .frame(maxWidth: .infinity)
                .frame(minHeight: SettingsVisualMetrics.graphicHeight)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: SettingsVisualMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsVisualMetrics.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FocusAdaptationGraphic: View {
    var dimActivity: Bool
    var hideBadges: Bool
    var allowMentions: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: adaptationCaption) {
            HStack(spacing: 18) {
                node("Activity", "bell", dimmed: dimActivity)
                ZStack {
                    Circle().stroke(app.appearance.accent.color.opacity(0.35), lineWidth: 1).frame(width: 78, height: 78)
                    Circle().stroke(app.appearance.accent.color.opacity(0.55), lineWidth: 1.5).frame(width: 48, height: 48)
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(app.appearance.accent.color)
                }
                VStack(spacing: 16) {
                    node("Feed", "rectangle.stack", dimmed: hideBadges)
                    node("Chats", "bubble.left.and.bubble.right", dimmed: !allowMentions)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var adaptationCaption: String {
        let enabled = [dimActivity, hideBadges, allowMentions].filter { $0 }.count
        return "Focus adaptations · \(enabled) enabled"
    }

    private func node(_ title: String, _ symbol: String, dimmed: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(dimmed ? Color.secondary : app.appearance.accent.color)
                .frame(width: 36, height: 36)
                .background((dimmed ? Color.secondary : app.appearance.accent.color).opacity(0.14), in: Circle())
            Text(title).font(.caption2).foregroundStyle(dimmed ? Color.secondary : Color.primary)
            Text(dimmed ? "Adapted" : "Open").font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(dimmed ? 0.55 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: dimmed)
    }
}

struct SharingFlowGraphic: View {
    var preferSheet: Bool
    var copyAsLink: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: copyAsLink ? "Copy link is preferred" : (preferSheet ? "System sheet is preferred" : "Link share is preferred")) {
            VStack(spacing: 12) {
                Label("Post", systemImage: "text.below.photo")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    tile("Link", "link", emphasized: copyAsLink || !preferSheet)
                    tile("Sheet", "square.and.arrow.up", emphasized: preferSheet && !copyAsLink)
                    tile("Module", "shippingbox", emphasized: false)
                }
            }
        }
    }

    private func tile(_ title: String, _ symbol: String, emphasized: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(emphasized ? app.appearance.accent.color : Color.secondary)
            Text(title).font(.caption.weight(.semibold))
            Text(emphasized ? "Preferred" : "Available").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background((emphasized ? app.appearance.accent.color : Color.primary).opacity(emphasized ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(emphasized ? app.appearance.accent.color.opacity(0.45) : Color.clear, lineWidth: 1.5)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: emphasized)
    }
}

struct FeedCompositionGraphic: View {
    var mode: String
    @Environment(AppEnvironment.self) private var app

    private var modes: [(String, String)] { [("following", "Following"), ("for-you", "For You"), ("modules", "Modules")] }

    var body: some View {
        SettingsGraphicFrame(caption: "Default Home · \(modes.first { $0.0 == mode }?.1 ?? "Following")") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(modes, id: \.0) { item in
                        Text(item.1)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(item.0 == mode ? app.appearance.accent.color : Color.primary.opacity(0.06), in: Capsule())
                            .foregroundStyle(item.0 == mode ? Color.white : Color.primary)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(app.appearance.accent.color.opacity(0.35)).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.18)).frame(width: 120, height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)).frame(width: 180, height: 8)
                        RoundedRectangle(cornerRadius: 8).fill(app.appearance.accent.color.opacity(0.2)).frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct BatteryDataGraphic: View {
    var dataSaver: Bool
    var pauseAutoplay: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: "Illustration of the settings, not live system meters") {
            VStack(alignment: .leading, spacing: 12) {
                meter("Battery", symbol: "battery.75percent", fraction: pauseAutoplay ? 0.72 : 0.48)
                meter("Data", symbol: "antenna.radiowaves.left.and.right", fraction: dataSaver ? 0.34 : 0.7)
            }
            .padding(.horizontal, 6)
        }
    }

    private func meter(_ title: String, symbol: String, fraction: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(app.appearance.accent.color)
                        .frame(width: max(12, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: fraction)
    }
}

struct MediaQualityGraphic: View {
    var quality: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let saver = quality == "saver"
        SettingsGraphicFrame(caption: saver ? "Data saver is selected" : (quality == "high" ? "High quality is selected" : "Auto balances data and quality")) {
            HStack(alignment: .bottom, spacing: 16) {
                bar("Saver", height: 36, selected: quality == "saver")
                bar("Auto", height: 64, selected: quality == "auto")
                bar("High", height: 92, selected: quality == "high")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func bar(_ title: String, height: CGFloat, selected: Bool) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? app.appearance.accent.color : app.appearance.accent.color.opacity(0.2))
                .frame(width: 42, height: height)
            Text(title).font(.caption2.weight(selected ? .semibold : .regular))
            Text(selected ? "Selected" : " ").font(.caption2).foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selected)
    }
}

struct ChatsPrivacyGraphic: View {
    var receipts: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: receipts ? "Read receipts shown" : "Read receipts hidden") {
            HStack(spacing: 0) {
                bubble("You", leading: true)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(app.appearance.accent.color)
                    .frame(width: 36)
                bubble(receipts ? "Seen" : "Private", leading: false)
            }
        }
    }

    private func bubble(_ title: String, leading: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((leading ? Color.primary : app.appearance.accent.color).opacity(leading ? 0.08 : 0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity)
    }
}

struct NotificationStackGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: "Example cards. Not your notification history.") {
            VStack(spacing: 8) {
                card("Modula", "Someone mentioned you in a post")
                card("Modula", "A module you follow published an update")
            }
        }
    }

    private func card(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.fill").foregroundStyle(app.appearance.accent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PrivacyLayersGraphic: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: "Layers describe settings areas. They are not an encryption claim.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(["Identity", "Permissions", "Local data", "Network"].enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 10) {
                        Image(systemName: index == 0 ? "person" : (index == 3 ? "network" : "lock"))
                            .foregroundStyle(app.appearance.accent.color)
                            .frame(width: 22)
                        Text(title).font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .padding(.leading, CGFloat(index) * 14)
                }
            }
        }
    }
}

struct ModuleOrbitGraphic: View {
    var installedCount: Int
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: "\(installedCount) installed on this account") {
            VStack(spacing: 10) {
                Text("Modula").font(.caption.weight(.semibold)).foregroundStyle(app.appearance.accent.color)
                HStack(spacing: 12) {
                    ForEach(["Notes", "Tasks", "More"], id: \.self) { name in
                        Text(name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(app.appearance.accent.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }
}

struct AccessibilityPreviewGraphic: View {
    var sample: String
    var scale: CGFloat
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsGraphicFrame(caption: "Preview only. Global text size changes when you pick a size.") {
            Text(sample)
                .font(.body)
                .scaleEffect(scale, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(app.appearance.accent.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: scale)
        }
    }
}
