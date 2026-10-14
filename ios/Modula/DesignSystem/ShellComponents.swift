import SwiftUI
import Combine
import AudioToolbox
import Network
import LinkPresentation
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The edge silhouette follows the Camera Control-inspired reference: a stable
/// right edge and one continuous concave-to-convex loop on the content side.
struct ModulaRailShape: Shape {
    var revealProgress: CGFloat

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let p = min(max(revealProgress, 0), 1)
        // Slightly slimmer attachment than N2: less bulbous waist/shoulder.
        let shoulder = 18 + (p * 7)
        let waist = 6 - (p * 1.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder - 22),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - shoulder),
            control2: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder + 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.minY + shoulder + 22),
            control1: CGPoint(x: rect.minX, y: rect.midY + 36 + (p * 16)),
            control2: CGPoint(x: rect.minX, y: rect.midY - 36 - (p * 16))
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.minX + waist, y: rect.minY + shoulder - 2),
            control2: CGPoint(x: rect.maxX, y: rect.minY + shoulder)
        )
        path.closeSubpath()
        return path
    }
}

struct ModulaContextRail: View {
    struct Interaction: Equatable {
        var isScrolling = false
        var keyboardVisible = false
        var immersive = false
        static let idle = Self()
    }

    let route: AppRoute
    var interaction: Interaction = .idle

    var body: some View {
        ShellEdgeLoop(route: route, interaction: interaction)
    }
}

extension View {
    @ViewBuilder
    func modulaChrome<S: Shape>(in shape: S, opaque: Bool) -> some View {
        if #available(iOS 26.0, *), !opaque {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(opaque ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.stroke(.primary.opacity(opaque ? 0.14 : 0.08), lineWidth: 0.75))
        }
    }

    @ViewBuilder
    func modulaAccessorySurface(nativeHosted: Bool, opaque: Bool) -> some View {
        if nativeHosted {
            self
        } else {
            self
                .modulaChrome(in: Capsule(), opaque: opaque)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
    }
}


/// Dismissible action-error banner shared by Home / Discover / Activity.
/// Has a real 44pt close button and is announced to VoiceOver on appear.
struct ModulaErrorBanner: View {
    let message: String
    var identifier: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: ModulaSpacing.xs) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, ModulaSpacing.md)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .onChange(of: message) { _, next in AccessibilityNotification.Announcement(next).post() }
    }
}

// MARK: - ════════════════════════════════════════════════════════════════════
// MARK: UI Ideas 30 (inline block, appended to ShellComponents.swift so no pbxproj edit)
//
// Everything below is prefixed `Lab30` to avoid clashing with existing types. Fonts are never
// set here (only system text styles inherited from Appearance); text inputs use `modulaGlass`.
// No backend calls: anything server-backed is a local placeholder marked `// PLACEHOLDER`.
// Open the gallery from the "What's new" sheet → "Try them", or via `Lab30GalleryView()`.


enum Lab30Keys {
    static let soundsEnabled = "lab30.uiSounds.enabled"
    static let whatsNewSeen = "lab30.whatsNew.seenVersion"
    static let coachMarksSeen = "lab30.coachMarks.seen"
    static let season = "lab30.season.override"          // "auto" | Lab30Season rawValue
    static let focusReader = "lab30.focusReader.enabled"
    static let gridColumns = "lab30.feed.gridColumns"
    static let drafts = "lab30.draftTray.items"
    static let collections = "lab30.collections.deck"
    static let accounts = "lab30.accounts.local"
    static let polls = "lab30.polls.votes"
    static let whatsNewVersion = "2026.10-ideas30"
}

// MARK: 20) UI sounds (with a toggle)
enum Lab30Sound: UInt32 {
    case tap = 1104, pop = 1105, success = 1407, swoosh = 1001, tick = 1157
    @MainActor static func play(_ s: Lab30Sound) {
        guard UserDefaults.standard.bool(forKey: Lab30Keys.soundsEnabled) else { return }
        AudioServicesPlaySystemSound(s.rawValue)
    }
}

struct Lab30SoundToggle: View {
    @AppStorage(Lab30Keys.soundsEnabled) private var enabled = false
    var body: some View {
        Toggle(isOn: $enabled) { Label("Interface sounds", systemImage: enabled ? "speaker.wave.2" : "speaker.slash") }
            .onChange(of: enabled) { _, on in if on { AudioServicesPlaySystemSound(Lab30Sound.pop.rawValue) } }
    }
}

// MARK: 18) Offline UI banner / states
@MainActor @Observable
final class Lab30Connectivity {
    static let shared = Lab30Connectivity()
    private(set) var isOnline = true
    private(set) var isExpensive = false
    private let monitor = NWPathMonitor()
    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                Lab30Connectivity.shared.isOnline = online
                Lab30Connectivity.shared.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "lab30.connectivity"))
    }
}

struct Lab30OfflineBanner: View {
    @State private var net = Lab30Connectivity.shared
    @State private var showBackOnline = false
    var body: some View {
        Group {
            if !net.isOnline {
                Label("You're offline. Showing saved content", systemImage: "wifi.slash")
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .modulaGlass(in: Capsule(), tint: .orange)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if showBackOnline {
                Label("Back online", systemImage: "wifi")
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .modulaGlass(in: Capsule(), tint: .green)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.top, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: net.isOnline)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showBackOnline)
        .onChange(of: net.isOnline) { was, now in
            guard !was, now else { return }
            showBackOnline = true
            Task { try? await Task.sleep(for: .seconds(2)); showBackOnline = false }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Lab30OfflineState: View {
    var retry: () -> Void = {}
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash").font(.largeTitle).foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
            Text("No connection").font(.headline)
            Text("We'll refresh as soon as you're back online.").font(.subheadline).foregroundStyle(.secondary)
            Button("Try again", action: retry).buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center).padding(32)
    }
}

// MARK: 8) Mascot empty states  +  24) Mascot pull-to-refresh tricks
struct Lab30MascotEmptyState: View {
    var title: String
    var message: String
    var mood: MascotMood = .sleepy
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(paused: reduceMotion)) { ctx in
                ModulaMascotFigure(kind: ModulaMascotKind(rawValue: kindRaw) ?? .pip,
                                   pose: MascotPose(t: ctx.date.timeIntervalSinceReferenceDate, mood: mood, amp: reduceMotion ? 0 : 1),
                                   size: 56)
            }
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}

/// Wrap a scrollable list: pulling plays a mascot trick (hop, spin, celebrate) before refreshing.
struct Lab30MascotRefreshTrick: ViewModifier {
    var action: @Sendable () async -> Void
    @State private var trick: MascotMood = .idle
    @State private var spin = 0.0
    @State private var showing = false
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let tricks: [MascotMood] = [.excited, .celebrate, .dance, .laughing, .wave, .surprised]

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showing, let kind = ModulaMascotKind(rawValue: kindRaw) {
                    TimelineView(.animation(paused: reduceMotion)) { ctx in
                        ModulaMascotFigure(kind: kind, pose: MascotPose(t: ctx.date.timeIntervalSinceReferenceDate, mood: trick, amp: reduceMotion ? 0 : 1), size: 34)
                    }
                    .rotationEffect(.degrees(spin))
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .refreshable {
                trick = Self.tricks.randomElement() ?? .excited
                withAnimation(.spring) { showing = true }
                if !reduceMotion { withAnimation(.easeInOut(duration: 0.8)) { spin += 360 } }
                await MainActor.run { Lab30Sound.play(.pop) }
                await action()
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut) { showing = false }
            }
    }
}

extension View {
    func lab30MascotRefresh(_ action: @escaping @Sendable () async -> Void) -> some View { modifier(Lab30MascotRefreshTrick(action: action)) }
}

// MARK: 9) Seasonal themes
enum Lab30Season: String, CaseIterable, Identifiable {
    case winter, spring, summer, autumn, halloween, festive
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .winter: "snowflake"; case .spring: "leaf"; case .summer: "sun.max"; case .autumn: "wind"; case .halloween: "moon.stars"; case .festive: "gift" }
    }
    var colors: [Color] {
        switch self {
        case .winter: [.cyan, .blue.opacity(0.6)]
        case .spring: [.green, .pink.opacity(0.6)]
        case .summer: [.yellow, .orange]
        case .autumn: [.orange, .brown]
        case .halloween: [.orange, .purple]
        case .festive: [.red, .green]
        }
    }
    static func current(_ date: Date = .now) -> Lab30Season {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        switch (c.month ?? 1, c.day ?? 1) {
        case (10, 20...31): return .halloween
        case (12, 10...31): return .festive
        case (12, _), (1, _), (2, _): return .winter
        case (3...5, _): return .spring
        case (6...8, _): return .summer
        default: return .autumn
        }
    }
    static var active: Lab30Season {
        let raw = UserDefaults.standard.string(forKey: Lab30Keys.season) ?? "auto"
        return Lab30Season(rawValue: raw) ?? current()
    }
}

struct Lab30SeasonalBackdrop: View {
    @AppStorage(Lab30Keys.season) private var raw = "auto"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let season = Lab30Season(rawValue: raw) ?? .current()
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<18 {
                    let seed = Double(i) * 37.1
                    let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.6 + seed) * 12
                    let y = (t * (14 + Double(i % 5) * 4) + seed * 9).truncatingRemainder(dividingBy: size.height + 20) - 10
                    g.opacity = 0.35
                    g.draw(Text(Image(systemName: season.symbol)).foregroundStyle(season.colors[i % 2]), at: CGPoint(x: x, y: y))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Lab30SeasonPicker: View {
    @AppStorage(Lab30Keys.season) private var raw = "auto"
    var body: some View {
        Picker("Seasonal theme", selection: $raw) {
            Text("Automatic").tag("auto")
            Text("Off").tag("off")
            ForEach(Lab30Season.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
        }
    }
}

// MARK: 10) Scroll-reactive headers
struct Lab30ScrollReactiveHeader<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 24)
            .scaleEffect(max(0.82, 1 - max(0, offset) / 400), anchor: .topLeading)
            .opacity(Double(max(0, 1 - max(0, offset) / 120)))
            .blur(radius: max(0, offset) / 40)
            content()
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, new in offset = new }
        .safeAreaInset(edge: .top, spacing: 0) {
            if offset > 70 {
                Text(title).font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .modulaGlass(in: Capsule())
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: offset > 70)
    }
}

// MARK: 23) Odometer counters
struct Lab30Odometer: View {
    var value: Int
    var body: some View {
        Text(Lab30Odometer.compact(value))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy, value: value)
    }
    static func compact(_ v: Int) -> String {
        switch abs(v) {
        case 1_000_000...: String(format: "%.1fM", Double(v) / 1_000_000)
        case 10_000...: String(format: "%.0fK", Double(v) / 1_000)
        case 1_000...: String(format: "%.1fK", Double(v) / 1_000)
        default: "\(v)"
        }
    }
}

// MARK: 19) Badges with 3D tilt
struct Lab30TiltBadge: View {
    var title: String
    var symbol: String
    var tint: Color = .accentColor
    @State private var drag: CGSize = .zero
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: UnitPoint(x: 0.5 - drag.width / 120, y: 0), endPoint: .center)).blendMode(.screen))
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), specular: true)
        .rotation3DEffect(.degrees(Double(drag.width) / 4), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-drag.height) / 4), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in drag = CGSize(width: max(-60, min(60, v.translation.width)), height: max(-60, min(60, v.translation.height))) }
            .onEnded { _ in withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { drag = .zero } })
        .accessibilityElement(children: .combine)
    }
}

// MARK: 3) Peek profile cards on long-press of avatars
struct Lab30PeekProfile: Identifiable, Hashable {
    var id: String { handle }
    var name: String
    var handle: String
    var bio: String = ""
    var followers: Int = 0
    var following: Int = 0
    var avatarURL: URL? = nil
}

struct Lab30PeekCard: View {
    var profile: Lab30PeekProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Lab30Avatar(name: profile.name, url: profile.avatarURL, size: 52)
                VStack(alignment: .leading) {
                    Text(profile.name).font(.headline)
                    Text("@\(profile.handle)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !profile.bio.isEmpty { Text(profile.bio).font(.subheadline).lineLimit(3) }
            HStack(spacing: 16) {
                HStack(spacing: 4) { Lab30Odometer(value: profile.followers).bold(); Text("followers").foregroundStyle(.secondary) }
                HStack(spacing: 4) { Lab30Odometer(value: profile.following).bold(); Text("following").foregroundStyle(.secondary) }
            }.font(.footnote)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }
}

struct Lab30Avatar: View {
    var name: String
    var url: URL? = nil
    var size: CGFloat = 32
    var body: some View {
        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hue: Double(abs(name.hashValue % 360)) / 360, saturation: 0.45, brightness: 0.75))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }
}

extension View {
    /// Long-press an avatar to peek the profile; tap "View profile" to open it.
    func lab30ProfilePeek(_ profile: Lab30PeekProfile, open: @escaping () -> Void) -> some View {
        contextMenu {
            Button("View profile", systemImage: "person.crop.circle", action: open)
            Button("Copy handle", systemImage: "doc.on.doc") { UIPasteboard.general.string = "@\(profile.handle)" }
        } preview: { Lab30PeekCard(profile: profile) }
    }
}

// MARK: 4) Curved thread lines in replies
struct Lab30ThreadCurve: Shape {
    var depth: Int
    var indent: CGFloat = 18
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = CGFloat(max(0, depth - 1)) * indent + indent / 2
        p.move(to: CGPoint(x: x, y: rect.minY))
        p.addLine(to: CGPoint(x: x, y: rect.midY - 10))
        p.addQuadCurve(to: CGPoint(x: x + indent * 0.9, y: rect.midY), control: CGPoint(x: x, y: rect.midY))
        return p
    }
}

struct Lab30ThreadedRow<Content: View>: View {
    var depth: Int
    var isLast = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.leading, CGFloat(depth) * 18)
            .background(alignment: .leading) {
                if depth > 0 {
                    ZStack(alignment: .topLeading) {
                        Lab30ThreadCurve(depth: depth).stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        if !isLast {
                            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1.5)
                                .padding(.leading, CGFloat(depth - 1) * 18 + 8.25)
                        }
                    }
                }
            }
    }
}

// MARK: 5) Focus reader mode
struct Lab30FocusReader: View {
    var title: String
    var author: String
    var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var progress: CGFloat = 0
    @State private var scale: CGFloat = 1
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title.bold())
                Text(author).font(.subheadline).foregroundStyle(.secondary)
                Text(text).font(.body).lineSpacing(6 * scale).textSelection(.enabled)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { g in
            let max = g.contentSize.height - g.containerSize.height
            return max > 0 ? min(1, Swift.max(0, g.contentOffset.y / max)) : 0
        }) { _, new in progress = new }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    .frame(width: 36, height: 36).modulaGlass(in: Circle())
                Spacer()
                ProgressView(value: progress).frame(width: 120)
                Spacer()
                Button { scale = scale >= 1.6 ? 1 : scale + 0.3 } label: { Image(systemName: "text.line.spacing") }.buttonStyle(.plain)
                    .frame(width: 36, height: 36).modulaGlass(in: Circle())
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: 6) Pinch-out grid in feeds
struct Lab30PinchGrid<Item: Identifiable, Cell: View>: View {
    var items: [Item]
    @ViewBuilder var cell: (Item, Int) -> Cell
    @AppStorage(Lab30Keys.gridColumns) private var columns = 1
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(items) { cell($0, columns) }
            }
            .padding(.horizontal, columns == 1 ? 0 : 4)
            .scaleEffect(min(1.08, max(0.92, pinch)))
        }
        .simultaneousGesture(MagnifyGesture()
            .updating($pinch) { v, s, _ in s = v.magnification }
            .onEnded { v in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if v.magnification < 0.85 { columns = min(3, columns + 1) }
                    else if v.magnification > 1.15 { columns = max(1, columns - 1) }
                }
                Lab30Sound.play(.tick)
            })
        .sensoryFeedback(.selection, trigger: columns)
    }
}

// MARK: 7) Shared-element media viewer transition
struct Lab30MediaItem: Identifiable, Hashable { let id: String; var url: URL?; var color: Color = .gray }

struct Lab30SharedMediaGrid: View {
    var items: [Lab30MediaItem]
    @Namespace private var ns
    @State private var selected: Lab30MediaItem?
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
            ForEach(items) { item in
                Button { selected = item } label: { thumb(item).aspectRatio(1, contentMode: .fill) }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: item.id, in: ns)
            }
        }
        .fullScreenCover(item: $selected) { item in
            thumb(item).aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .overlay(alignment: .topTrailing) {
                    ModulaGlassIconButton(title: "Close", systemImage: "xmark") { selected = nil }.padding()
                }
                .navigationTransition(.zoom(sourceID: item.id, in: ns))
        }
    }
    @ViewBuilder private func thumb(_ item: Lab30MediaItem) -> some View {
        AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { item.color }
            .clipped()
    }
}

// MARK: 11) Draft tray
struct Lab30Draft: Codable, Identifiable, Hashable { var id = UUID(); var text: String; var updated = Date() }

@MainActor @Observable
final class Lab30DraftTray {
    static let shared = Lab30DraftTray()
    private(set) var drafts: [Lab30Draft] = []
    private init() { load() }
    func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        drafts.removeAll { $0.text == trimmed }
        drafts.insert(Lab30Draft(text: trimmed), at: 0)
        drafts = Array(drafts.prefix(20)); persist()
    }
    func remove(_ d: Lab30Draft) { drafts.removeAll { $0.id == d.id }; persist() }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(drafts), forKey: Lab30Keys.drafts) }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Lab30Keys.drafts) else { return }
        drafts = (try? JSONDecoder().decode([Lab30Draft].self, from: data)) ?? []
    }
}

struct Lab30DraftTrayView: View {
    var onPick: (Lab30Draft) -> Void
    @State private var tray = Lab30DraftTray.shared
    var body: some View {
        if !tray.drafts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tray.drafts) { d in
                        Button { onPick(d) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.text).lineLimit(2).font(.footnote)
                                Text(d.updated, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 150, alignment: .leading).padding(10)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contextMenu { Button("Delete draft", systemImage: "trash", role: .destructive) { tray.remove(d) } }
                    }
                }.padding(.horizontal, 16)
            }
        }
    }
}

// MARK: 12) Inline polls (local placeholder)
struct Lab30InlinePoll: View {
    var pollID: String
    var question: String
    var options: [String]
    var seedVotes: [Int]   // PLACEHOLDER: server counts; local only, nothing is sent.
    @AppStorage(Lab30Keys.polls) private var votesRaw = ""
    var body: some View {
        let mine = myVote
        let counts = options.indices.map { (seedVotes.indices.contains($0) ? seedVotes[$0] : 0) + (mine == $0 ? 1 : 0) }
        let total = max(1, counts.reduce(0, +))
        VStack(alignment: .leading, spacing: 8) {
            Text(question).font(.subheadline.weight(.semibold))
            ForEach(options.indices, id: \.self) { i in
                Button { vote(i) } label: {
                    HStack {
                        Text(options[i]); Spacer()
                        if mine != nil { Text("\(Int(Double(counts[i]) / Double(total) * 100))%").monospacedDigit() }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(mine == i ? 0.35 : 0.15))
                                .frame(width: mine == nil ? 0 : g.size.width * CGFloat(counts[i]) / CGFloat(total))
                        }
                    }
                    .modulaGlass(in: Capsule(), interactive: mine == nil)
                }
                .buttonStyle(.plain)
                .disabled(mine != nil)
            }
            Text("\(total) votes · local preview").font(.caption).foregroundStyle(.secondary)
        }
        .animation(.spring, value: mine)
    }
    private var myVote: Int? {
        votesRaw.split(separator: ";").compactMap { pair -> Int? in
            let parts = pair.split(separator: "="); guard parts.count == 2, String(parts[0]) == pollID else { return nil }
            return Int(parts[1])
        }.first
    }
    private func vote(_ i: Int) { votesRaw += "\(pollID)=\(i);"; Lab30Sound.play(.pop) }
}

// MARK: 13) Rich link cards

struct Lab30RichLinkCard: View {
    var url: URL
    @State private var title: String?
    @State private var image: UIImage?
    var body: some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 0) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 140).clipped()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title ?? url.host() ?? url.absoluteString).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Label(url.host() ?? "", systemImage: "link").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: url) { await load() }
    }
    private func load() async {
        // On-device metadata fetch of the public page (no Modula backend involved).
        let provider = LPMetadataProvider()
        guard let meta = try? await provider.startFetchingMetadata(for: url) else { return }
        title = meta.title
        if let ip = meta.imageProvider {
            let img: UIImage? = await withCheckedContinuation { c in
                _ = ip.loadObject(ofClass: UIImage.self) { obj, _ in c.resume(returning: obj as? UIImage) }
            }
            image = img
        }
    }
}

// MARK: 14) Coach marks
struct Lab30CoachMark: Identifiable, Equatable { let id: String; var title: String; var message: String; var symbol: String }

struct Lab30CoachMarksOverlay: View {
    var marks: [Lab30CoachMark]
    @AppStorage(Lab30Keys.coachMarksSeen) private var seen = false
    @State private var index = 0
    var body: some View {
        if !seen, marks.indices.contains(index) {
            let mark = marks[index]
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: next)
                VStack(alignment: .leading, spacing: 10) {
                    Label(mark.title, systemImage: mark.symbol).font(.headline)
                    Text(mark.message).font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("\(index + 1) of \(marks.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Skip") { seen = true }.buttonStyle(.borderless)
                        Button(index == marks.count - 1 ? "Done" : "Next", action: next).buttonStyle(.borderedProminent)
                    }
                }
                .padding(18)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 110)
                .id(mark.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
        }
    }
    private func next() {
        Lab30Sound.play(.tap)
        if index >= marks.count - 1 { seen = true } else { index += 1 }
    }
    static let defaultMarks: [Lab30CoachMark] = [
        .init(id: "edge", title: "Edge picker", message: "Swipe along the screen edge to jump between modules.", symbol: "hand.draw"),
        .init(id: "peek", title: "Peek profiles", message: "Long-press any avatar to preview a profile.", symbol: "person.crop.circle.badge.questionmark"),
        .init(id: "grid", title: "Pinch the feed", message: "Pinch in to switch to a grid, pinch out to go back.", symbol: "square.grid.2x2"),
        .init(id: "cmd", title: "Command palette", message: "Pull down with two fingers, or press ⌘K, to run anything.", symbol: "command")
    ]
}

// MARK: 27) 'What's new' sheet
struct Lab30WhatsNewSheet: View {
    var onTry: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, String, String)] = [
        ("square.grid.2x2", "Pinch-out grid", "Pinch any feed into a grid."),
        ("person.crop.circle", "Peek profiles", "Long-press avatars for a quick look."),
        ("text.bubble", "Smart replies", "Suggested replies from Nodus, on device."),
        ("wifi.slash", "Offline mode", "Clear banners when you lose signal."),
        ("speaker.wave.2", "Interface sounds", "Optional taps and pops. Off by default."),
        ("sparkles", "Seasonal themes", "A little weather for every season.")
    ]
    var body: some View {
        VStack(spacing: 22) {
            Text("What's new in Modula").font(.title2.bold()).padding(.top, 28)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows, id: \.1) { row in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: row.0).font(.title3).foregroundStyle(Color.accentColor).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) { Text(row.1).font(.headline); Text(row.2).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }.padding(.horizontal, 24)
            Spacer(minLength: 0)
            Button { dismiss(); onTry() } label: { Text("Try them").frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.plain).foregroundStyle(.white)
                .modulaGlass(in: Capsule(), tint: .accentColor, prominent: true)
                .padding(.horizontal, 24)
            Button("Not now") { dismiss() }.padding(.bottom, 16)
        }
        .presentationDetents([.large])
    }
}

/// Shows "What's new" once per `Lab30Keys.whatsNewVersion`, then offers the gallery.
struct Lab30WhatsNewPresenter: ViewModifier {
    @AppStorage(Lab30Keys.whatsNewSeen) private var seenVersion = ""
    @State private var showWhatsNew = false
    @State private var showGallery = false
    func body(content: Content) -> some View {
        content
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                if seenVersion != Lab30Keys.whatsNewVersion { showWhatsNew = true }
            }
            .sheet(isPresented: $showWhatsNew, onDismiss: { seenVersion = Lab30Keys.whatsNewVersion }) {
                Lab30WhatsNewSheet { Task { try? await Task.sleep(for: .milliseconds(400)); showGallery = true } }
            }
            .sheet(isPresented: $showGallery) { NavigationStack { Lab30GalleryView() } }
            .onReceive(NotificationCenter.default.publisher(for: Lab30GalleryView.openNotification)) { _ in showGallery = true }
    }
}

// MARK: 15) Settings redesign (grouped glass cards with search)
struct Lab30SettingsSection: Identifiable { let id = UUID(); var title: String; var rows: [Lab30SettingsRow] }
struct Lab30SettingsRow: Identifiable { let id = UUID(); var title: String; var symbol: String; var tint: Color; var detail: String = "" }

struct Lab30SettingsRedesignPreview: View {
    @State private var query = ""
    private let sections: [Lab30SettingsSection] = [
        .init(title: "You", rows: [.init(title: "Account", symbol: "person.crop.circle", tint: .blue), .init(title: "Privacy", symbol: "hand.raised", tint: .indigo), .init(title: "Notifications", symbol: "bell.badge", tint: .red)]),
        .init(title: "Look & feel", rows: [.init(title: "Appearance", symbol: "paintpalette", tint: .pink), .init(title: "Seasonal theme", symbol: "snowflake", tint: .cyan), .init(title: "Sounds", symbol: "speaker.wave.2", tint: .orange)]),
        .init(title: "Modula", rows: [.init(title: "Modules", symbol: "square.grid.3x3", tint: .purple), .init(title: "Nodus", symbol: "sparkles", tint: .teal), .init(title: "About", symbol: "info.circle", tint: .gray)])
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ModulaGlassSearchField(prompt: "Search settings", text: $query)
                ForEach(sections) { section in
                    let rows = section.rows.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 6)
                            VStack(spacing: 0) {
                                ForEach(rows) { row in
                                    HStack(spacing: 12) {
                                        Image(systemName: row.symbol).foregroundStyle(.white).frame(width: 30, height: 30)
                                            .background(row.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        Text(row.title); Spacer()
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    if row.id != rows.last?.id { Divider().padding(.leading, 56) }
                                }
                            }
                            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                        }
                    }
                }
                VStack(spacing: 0) { Lab30SoundToggle().padding(14); Divider(); Lab30SeasonPicker().padding(14) }
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            }.padding(16)
        }
        .navigationTitle("Settings (preview)")
    }
}

// MARK: 16) Module launcher
struct Lab30ModuleTile: Identifiable, Hashable { var id: String; var name: String; var symbol: String; var tint: Color }

struct Lab30ModuleLauncher: View {
    var modules: [Lab30ModuleTile]
    var open: (Lab30ModuleTile) -> Void
    @State private var query = ""
    @State private var pressed: String?
    var body: some View {
        VStack(spacing: 14) {
            ModulaGlassSearchField(prompt: "Find a module", text: $query)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 18) {
                ForEach(modules.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { m in
                    Button { Lab30Sound.play(.tap); open(m) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: m.symbol).font(.title2).foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(m.tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(m.name).font(.caption).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(pressed == m.id ? 0.9 : 1)
                    .onLongPressGesture(minimumDuration: 0.01, pressing: { p in withAnimation(.snappy) { pressed = p ? m.id : nil } }, perform: {})
                }
            }
        }
        .padding(16)
    }
}

// MARK: 17) Account switcher (local list; the live session stays owned by AuthenticationStore)
struct Lab30LocalAccount: Codable, Identifiable, Hashable { var id: String { handle }; var name: String; var handle: String }

struct Lab30AccountSwitcher: View {
    var current: Lab30LocalAccount
    var others: [Lab30LocalAccount]
    var onSwitch: (Lab30LocalAccount) -> Void   // PLACEHOLDER: real multi-session switching needs auth support.
    var onAdd: () -> Void
    @Namespace private var ns
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(current, selected: true)
            ForEach(others) { a in Divider().padding(.leading, 60); Button { Lab30Sound.play(.swoosh); onSwitch(a) } label: { row(a, selected: false) }.buttonStyle(.plain) }
            Divider().padding(.leading, 60)
            Button(action: onAdd) {
                Label("Add account", systemImage: "plus.circle").padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
    }
    private func row(_ a: Lab30LocalAccount, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Lab30Avatar(name: a.name, size: 36)
            VStack(alignment: .leading) { Text(a.name).font(.subheadline.weight(.semibold)); Text("@\(a.handle)").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
        }.padding(14).contentShape(Rectangle())
    }
}

// MARK: 21) Tools quick-actions shelf
struct Lab30QuickAction: Identifiable { let id = UUID(); var title: String; var symbol: String; var action: () -> Void }

struct Lab30QuickActionsShelf: View {
    var actions: [Lab30QuickAction]
    var body: some View {
        ModulaGlassGroup(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(actions) { a in
                        Button { Lab30Sound.play(.tap); a.action() } label: {
                            Label(a.title, systemImage: a.symbol).font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), specular: true)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }
}

// MARK: 22) @mention autocomplete
struct Lab30MentionField: View {
    @Binding var text: String
    var candidates: [Lab30PeekProfile]
    var prompt = "Write a reply…"
    private var query: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let q = query {
                let matches = candidates.filter { q.isEmpty || $0.handle.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }.prefix(5)
                if !matches.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(matches)) { p in
                            Button { complete(p) } label: {
                                HStack(spacing: 10) { Lab30Avatar(name: p.name, url: p.avatarURL, size: 28); Text(p.name).font(.subheadline); Text("@\(p.handle)").font(.caption).foregroundStyle(.secondary); Spacer() }
                                    .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            TextField(prompt, text: $text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .animation(.snappy, value: query)
    }
    private func complete(_ p: Lab30PeekProfile) {
        var parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !parts.isEmpty { parts[parts.count - 1] = "@\(p.handle) " }
        text = parts.joined(separator: " ")
        Lab30Sound.play(.tick)
    }
}

// MARK: 28) Nodus smart replies (UI only, stubbed suggestions, NO model inference)
enum Lab30SmartReplyStub {
    static func suggestions(for message: String) -> [String] {
        let m = message.lowercased()
        if m.contains("?") { return ["Yes, sounds good!", "Let me check", "Not sure yet"] }
        if m.contains("thank") { return ["You're welcome!", "Any time 🙌", "Happy to help"] }
        if m.contains("congrat") || m.contains("launch") { return ["Congrats! 🎉", "Huge, well done", "Love this"] }
        return ["👍", "Nice!", "Tell me more"]
    }
}

struct Lab30SmartReplies: View {
    var message: String
    var onPick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.secondary).accessibilityHidden(true)
                ForEach(Lab30SmartReplyStub.suggestions(for: message), id: \.self) { s in
                    Button { Lab30Sound.play(.tap); onPick(s) } label: { Text(s).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 7) }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule())
                }
            }.padding(.horizontal, 16)
        }
        .accessibilityLabel("Suggested replies")
    }
}

// MARK: 25) Story viewer polish (segmented progress, hold-to-pause, haptic edges)
struct Lab30StoryProgress: View {
    var count: Int
    var index: Int
    var progress: Double
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: g.size.width * (i < index ? 1 : i == index ? progress : 0))
                        }
                }.frame(height: 3)
            }
        }
        .padding(.horizontal, 10)
    }
}

struct Lab30StoryPlayer: View {
    var colors: [Color]
    @State private var index = 0
    @State private var progress = 0.0
    @State private var paused = false
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var body: some View {
        ZStack(alignment: .top) {
            (colors.indices.contains(index) ? colors[index] : .black).ignoresSafeArea()
                .scaleEffect(paused ? 0.96 : 1).animation(.spring, value: paused)
            Lab30StoryProgress(count: colors.count, index: index, progress: progress).padding(.top, 8)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { step(-1) }
                Color.clear.contentShape(Rectangle()).onTapGesture { step(1) }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.2).onChanged { _ in paused = true }.sequenced(before: DragGesture(minimumDistance: 0)).onEnded { _ in paused = false })
        }
        .gesture(DragGesture().onEnded { v in if v.translation.height > 120 { dismiss() } })
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        .onReceive(timer) { _ in
            guard !paused else { return }
            progress += 0.05 / 5
            if progress >= 1 { step(1) }
        }
    }
    private func step(_ d: Int) {
        progress = 0
        let n = index + d
        if n >= colors.count { dismiss() } else { index = max(0, n) }
    }
}

// MARK: 26) Collections deck
struct Lab30DeckCard: Identifiable, Hashable { var id: String; var title: String; var count: Int; var tint: Color }

struct Lab30CollectionsDeck: View {
    var cards: [Lab30DeckCard]
    var open: (Lab30DeckCard) -> Void
    @State private var top = 0
    @State private var drag: CGSize = .zero
    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { i, card in
                let pos = (i - top + cards.count) % max(1, cards.count)
                if pos < 4 {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(card.tint.gradient)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading) { Text(card.title).font(.title3.bold()); Text("\(card.count) saved").font(.subheadline).opacity(0.85) }
                                .foregroundStyle(.white).padding(20)
                        }
                        .frame(height: 200)
                        .offset(x: pos == 0 ? drag.width : 0, y: CGFloat(pos) * -14)
                        .scaleEffect(1 - CGFloat(pos) * 0.05)
                        .rotationEffect(.degrees(pos == 0 ? Double(drag.width) / 20 : 0))
                        .zIndex(Double(-pos))
                        .onTapGesture { if pos == 0 { open(card) } }
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 50)
        .gesture(DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    if abs(v.translation.width) > 100, !cards.isEmpty { top = (top + 1) % cards.count; Lab30Sound.play(.swoosh) }
                    drag = .zero
                }
            })
    }
}

// MARK: 29) Glass share sheet
struct Lab30GlassShareSheet: View {
    var url: URL
    var people: [Lab30PeekProfile]
    var onSendTo: (Lab30PeekProfile) -> Void   // PLACEHOLDER: route to Messages when wired.
    @State private var copied = false
    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(people) { p in
                        Button { onSendTo(p) } label: { VStack { Lab30Avatar(name: p.name, url: p.avatarURL, size: 56); Text(p.name).font(.caption).lineLimit(1) }.frame(width: 64) }
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }
            HStack(spacing: 14) {
                shareButton(copied ? "Copied" : "Copy link", copied ? "checkmark" : "link") { UIPasteboard.general.url = url; copied = true; Lab30Sound.play(.success) }
                ShareLink(item: url) { VStack(spacing: 6) { Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 56, height: 56).modulaGlass(in: Circle()); Text("More").font(.caption) } }
                    .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(260)])
        .presentationBackground(.clear)
        .background(Color.clear.modulaGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: false).ignoresSafeArea())
        .sensoryFeedback(.success, trigger: copied)
    }
    private func shareButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) { Image(systemName: symbol).font(.title3).contentTransition(.symbolEffect(.replace)).frame(width: 56, height: 56).modulaGlass(in: Circle()); Text(title).font(.caption) }
        }.buttonStyle(.plain)
    }
}

// MARK: 30) 'Seen by' avatars
struct Lab30SeenBy: View {
    var viewers: [Lab30PeekProfile]
    var body: some View {
        if !viewers.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: -8) {
                    ForEach(viewers.prefix(3)) { v in Lab30Avatar(name: v.name, url: v.avatarURL, size: 18).overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)) }
                }
                Text(viewers.count == 1 ? "Seen by \(viewers[0].name)" : "Seen by \(viewers[0].name) and \(viewers.count - 1) other\(viewers.count == 2 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: 1) Dynamic Island / Live Activity (app side; widget UI lives in the extension target)
#if canImport(ActivityKit)
/// Must be byte-identical to the copy in the ModulaWidgets extension (ActivityKit matches by type).
struct ModulaLiveActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable { case upload, call }
    struct ContentState: Codable, Hashable {
        var progress: Double
        var status: String
        var startedAt: Date
    }
    var kind: Kind
    var title: String
}

@MainActor
enum Lab30LiveActivity {
    private static var current: Activity<ModulaLiveActivityAttributes>?
    static func start(_ kind: ModulaLiveActivityAttributes.Kind, title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ModulaLiveActivityAttributes.ContentState(progress: 0, status: kind == .upload ? "Uploading…" : "Connecting…", startedAt: .now)
        current = try? Activity.request(attributes: .init(kind: kind, title: title), content: .init(state: state, staleDate: nil), pushType: nil)
    }
    static func update(progress: Double, status: String) {
        guard let a = current else { return }
        let state = ModulaLiveActivityAttributes.ContentState(progress: progress, status: status, startedAt: a.content.state.startedAt)
        let id = a.id
        Task.detached { for act in Activity<ModulaLiveActivityAttributes>.activities where act.id == id { await act.update(.init(state: state, staleDate: nil)) } }
    }
    static func end(status: String = "Done") {
        guard let a = current else { return }
        let state = ModulaLiveActivityAttributes.ContentState(progress: 1, status: status, startedAt: a.content.state.startedAt)
        let id = a.id
        Task.detached { for act in Activity<ModulaLiveActivityAttributes>.activities where act.id == id { await act.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4)) } }
        current = nil
    }
    /// Demo used by the gallery: simulated upload (no network).
    static func demoUpload() {
        start(.upload, title: "Demo video")
        Task {
            for step in 1...10 { try? await Task.sleep(for: .milliseconds(600)); update(progress: Double(step) / 10, status: "Uploading \(step * 10)%") }
            end(status: "Uploaded")
        }
    }
}
#endif

// MARK: 2) Widgets: app side writes a snapshot to the App Group the extension reads.
enum Lab30WidgetSnapshot {
    static let appGroup = "group.digital.modula.app.native"   // Mac step: enable this App Group on both targets.
    static func write(unread: Int, streak: Int, headline: String) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        d.set(unread, forKey: "widget.unread"); d.set(streak, forKey: "widget.streak"); d.set(headline, forKey: "widget.headline"); d.set(Date(), forKey: "widget.updated")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Gallery (one screen to try all 30)
struct Lab30GalleryView: View {
    static let openNotification = Notification.Name("lab30.gallery.open")
    @State private var reply = ""
    @State private var counter = 1_234
    @State private var showReader = false
    @State private var showStory = false
    @State private var showShare = false
    @State private var showSettings = false
    @AppStorage(Lab30Keys.season) private var season = "auto"
    private let people: [Lab30PeekProfile] = [
        .init(name: "Ava Stone", handle: "ava", bio: "Designer. Glass enjoyer.", followers: 12_400, following: 310),
        .init(name: "Ben Ito", handle: "ben", bio: "Builds modules.", followers: 980, following: 120),
        .init(name: "Cleo Park", handle: "cleo", followers: 3_210, following: 400),
        .init(name: "Dev Rao", handle: "dev", followers: 77, following: 50)
    ]
    private struct Cell: Identifiable { let id: Int }

    var body: some View {
        List {
            Section("Feed") {
                HStack { Text("Odometer"); Spacer(); Lab30Odometer(value: counter).font(.title3.bold()); Button("+", action: { counter += Int.random(in: 1...900) }) }
                HStack(spacing: 12) {
                    ForEach(people) { p in Lab30Avatar(name: p.name, size: 40).lab30ProfilePeek(p) {} }
                    Text("Long-press").font(.caption).foregroundStyle(.secondary)
                }
                Lab30InlinePoll(pollID: "demo-poll", question: "Best Moliboo?", options: ["Pip", "Pebble", "Bolt"], seedVotes: [12, 30, 9])
                Lab30RichLinkCard(url: URL(string: "https://www.apple.com")!)
                Lab30SeenBy(viewers: people)
                NavigationLink("Pinch-out grid") {
                    Lab30PinchGrid(items: (0..<60).map(Cell.init)) { c, cols in
                        RoundedRectangle(cornerRadius: cols == 1 ? 0 : 8).fill(Color(hue: Double(c.id % 12) / 12, saturation: 0.5, brightness: 0.85)).frame(height: cols == 1 ? 220 : 120)
                    }.navigationTitle("Pinch me")
                }
                NavigationLink("Shared-element media") { ScrollView { Lab30SharedMediaGrid(items: (0..<15).map { Lab30MediaItem(id: "m\($0)", color: Color(hue: Double($0) / 15, saturation: 0.6, brightness: 0.8)) }) } }
                NavigationLink("Scroll-reactive header") {
                    Lab30ScrollReactiveHeader(title: "Discover", subtitle: "Scroll to shrink") { ForEach(0..<40) { Text("Row \($0)").padding().frame(maxWidth: .infinity, alignment: .leading) } }
                }
                Button("Focus reader") { showReader = true }
                Button("Story viewer") { showStory = true }
            }
            Section("Replies") {
                Lab30ThreadedRow(depth: 0) { Text("Root comment") }
                Lab30ThreadedRow(depth: 1) { Text("Reply with a curved line") }
                Lab30ThreadedRow(depth: 2, isLast: true) { Text("Nested reply") }
                Lab30SmartReplies(message: "Are you coming tonight?") { reply = $0 }.listRowInsets(EdgeInsets())
                Lab30MentionField(text: $reply, candidates: people)
                Button("Save as draft") { Lab30DraftTray.shared.save(reply); reply = "" }
                Lab30DraftTrayView { reply = $0.text }.listRowInsets(EdgeInsets())
            }
            Section("Moliboo") {
                Lab30MascotEmptyState(title: "Nothing here yet", message: "When people post, it'll show up here.")
                Text("Pull this list down for a Moliboo trick").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Shell") {
                Lab30QuickActionsShelf(actions: [
                    .init(title: "New post", symbol: "square.and.pencil") {}, .init(title: "Scan", symbol: "qrcode.viewfinder") {},
                    .init(title: "Nodus", symbol: "sparkles") {}, .init(title: "Timer", symbol: "timer") {}
                ]).listRowInsets(EdgeInsets())
                Lab30ModuleLauncher(modules: [
                    .init(id: "notes", name: "Notes", symbol: "note.text", tint: .yellow), .init(id: "tasks", name: "Tasks", symbol: "checklist", tint: .blue),
                    .init(id: "music", name: "Music", symbol: "music.note", tint: .pink), .init(id: "maps", name: "Places", symbol: "map", tint: .green)
                ]) { _ in }
                Lab30AccountSwitcher(current: .init(name: "Andy", handle: "andy"), others: [.init(name: "Modula Studio", handle: "modula")], onSwitch: { _ in }, onAdd: {})
                Lab30CollectionsDeck(cards: [.init(id: "a", title: "Inspiration", count: 42, tint: .purple), .init(id: "b", title: "Recipes", count: 12, tint: .orange), .init(id: "c", title: "Read later", count: 7, tint: .teal)]) { _ in }
                    .frame(height: 280)
                HStack { Lab30TiltBadge(title: "Early bird", symbol: "sunrise.fill", tint: .orange); Lab30TiltBadge(title: "Creator", symbol: "star.fill", tint: .purple) }
                Button("Glass share sheet") { showShare = true }
                Button("Settings redesign") { showSettings = true }
                Button("Replay coach marks") { UserDefaults.standard.set(false, forKey: Lab30Keys.coachMarksSeen) }
                Button("Replay 'What's new'") { UserDefaults.standard.set("", forKey: Lab30Keys.whatsNewSeen) }
                #if canImport(ActivityKit)
                Button("Start demo Live Activity") { Lab30LiveActivity.demoUpload() }
                #endif
                Button("Refresh widget snapshot") { Lab30WidgetSnapshot.write(unread: counter % 30, streak: 5, headline: "3 new replies") }
            }
            Section("Preferences") { Lab30SoundToggle(); Lab30SeasonPicker() }
            Section("Offline") { Lab30OfflineState() }
        }
        .background(alignment: .top) { if season != "off" { Lab30SeasonalBackdrop().frame(height: 300) } }
        .lab30MascotRefresh { try? await Task.sleep(for: .seconds(1)) }
        .navigationTitle("30 new ideas")
        .fullScreenCover(isPresented: $showReader) { Lab30FocusReader(title: "On Liquid Glass", author: "Modula team", text: String(repeating: "Glass that bends light and gets out of the way. ", count: 80)) }
        .fullScreenCover(isPresented: $showStory) { Lab30StoryPlayer(colors: [.purple, .orange, .teal, .pink]) }
        .sheet(isPresented: $showShare) { Lab30GlassShareSheet(url: URL(string: "https://modula.digital")!, people: people) { _ in showShare = false } }
        .sheet(isPresented: $showSettings) { NavigationStack { Lab30SettingsRedesignPreview() } }
        .overlay { Lab30CoachMarksOverlay(marks: Lab30CoachMarksOverlay.defaultMarks) }
    }
}
