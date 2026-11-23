import SwiftUI
import UIKit
import Observation

// MARK: - Modula glass sheet kit (feed, summary and Discover option sheets)

/// Sheet body in the Modula look: a bold title, a glass close button and glass sections, in the app's
/// font design (sheets are a separate presentation tree, so the shell's `.fontDesign` is re-applied).
struct ModulaGlassSheetScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var identifier: String
    @ViewBuilder var content: () -> Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("\(identifier).close")
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fontDesign(app.appearance.fontDesign)
        .accessibilityIdentifier(identifier)
    }
}

/// A titled glass group of rows.
struct ModulaGlassSheetSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Glass toggle row with an optional one-line explanation.
struct ModulaGlassToggleRow: View {
    let title: String
    var detail: String?
    var symbol: String
    @Binding var isOn: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ModulaGlassSheetIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .tint(.primary)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Glass action row: icon, title, optional detail and a chevron.
struct ModulaGlassActionRow: View {
    let title: String
    var detail: String?
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ModulaGlassSheetIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ModulaGlassSheetIcon: View {
    let symbol: String
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .background(Circle().fill(app.appearance.liveAccent.opacity(0.12)))
            .accessibilityHidden(true)
    }
}

struct ModulaGlassRowDivider: View {
    var body: some View { Divider().padding(.leading, 60) }
}

extension HomeMode {
    var feedSymbol: String {
        switch self {
        case .following: "person.2.fill"
        case .forYou: "sparkles"
        case .modules: "shippingbox.fill"
        }
    }
    var feedBlurb: String {
        switch self {
        case .following: "People you follow"
        case .forYou: "Picked for you"
        case .modules: "Module updates"
        }
    }
}

enum ModulaPlural {
    /// "1 post", "2 posts".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n.formatted()) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}

// MARK: - Summary

struct HomeSummarySheet: View {
    @Environment(AppEnvironment.self) private var app

    private var mode: HomeMode {
        if case .home(let mode) = app.navigation.currentRoute { return mode }
        return .following
    }

    var body: some View {
        let summary = app.home.summary(for: mode)
        ModulaGlassSheetScaffold(
            title: "\(mode.heroSubtitle) at a glance",
            subtitle: summary.postCount == 0 ? nil : "Across the \(ModulaPlural.count(summary.postCount, "post")) loaded right now.",
            identifier: "home.summary"
        ) {
            if summary.postCount == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Nothing loaded yet").font(.headline)
                    Text("Pull to refresh \(mode.heroSubtitle), then check back here.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            } else {
                ModulaGlassGroup(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        stat("Posts", summary.postCount, "text.alignleft")
                        stat("Likes", summary.likeCount, "heart.fill")
                        stat("Replies", summary.replyCount, "bubble.left.and.bubble.right.fill")
                        stat("With media", summary.mediaCount, "photo.fill")
                        if summary.moduleCount > 0 { stat("Module posts", summary.moduleCount, "shippingbox.fill") }
                    }
                }
                if !summary.authorNames.isEmpty {
                    ModulaGlassSheetSection(title: "Most active") {
                        ForEach(Array(summary.authorNames.enumerated()), id: \.offset) { i, name in
                            if i > 0 { ModulaGlassRowDivider() }
                            HStack(spacing: 12) {
                                ModulaAvatar(initials: String(name.prefix(2)).uppercased(), size: 32, name: name)
                                Text(name).font(.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                if i == 0 { Image(systemName: "crown.fill").foregroundStyle(.yellow).accessibilityLabel("Most posts") }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaGlassSheetIcon(symbol: symbol)
            Text(value.formatted()).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Feeds (switcher + display options + following)

/// Former "Tools" sheet: refresh and Manage following now live in the Feeds sheet / accessory once each.
typealias HomeFeedToolsSheet = HomeFeedsSheet

struct HomeFeedsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var mode: HomeMode {
        if case .home(let mode) = app.navigation.currentRoute { return mode }
        return .following
    }

    var body: some View {
        let options = app.home.displayOptions(for: mode)
        ModulaGlassSheetScaffold(title: "Feeds", identifier: "home.feeds") {
            ModulaGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(HomeMode.allCases, id: \.self) { feed in feedCard(feed) }
                }
            }
            ModulaGlassSheetSection(title: "Show in \(mode.heroSubtitle)") {
                ModulaGlassToggleRow(title: "Media only", detail: "Photos and videos", symbol: "photo.on.rectangle", isOn: Binding(
                    get: { options.mediaOnly },
                    set: { value in
                        var next = options
                        next.mediaOnly = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.media-only")
                ModulaGlassRowDivider()
                ModulaGlassToggleRow(title: "Hide module posts", detail: "Only posts from people", symbol: "shippingbox", isOn: Binding(
                    get: { options.hideModules },
                    set: { value in
                        var next = options
                        next.hideModules = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.hide-modules")
            }
            ModulaGlassSheetSection {
                ModulaGlassActionRow(title: "Manage following", detail: "Find people to follow or unfollow", symbol: "person.2") {
                    dismiss()
                    app.navigation.open(.discover(.people))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.feeds.following")
                ModulaGlassRowDivider()
                ModulaGlassActionRow(
                    title: "Muted words",
                    detail: app.home.mutedWords.isEmpty ? "Hide posts that mention a word or #tag" : "\(app.home.mutedWords.count) muted",
                    symbol: "text.badge.xmark"
                ) {
                    dismiss()
                    app.navigation.open(.settings(.safety(.muted)))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.feeds.muted-words")
            }
        }
    }

    private func feedCard(_ feed: HomeMode) -> some View {
        let selected = feed == mode
        let accent = app.appearance.liveAccent
        return Button {
            app.navigation.replaceContext(with: .home(feed))
            HapticEngine.shared.play(.navigation)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: feed.feedSymbol)
                    .font(.headline)
                    .foregroundStyle(selected ? .white : accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.12))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.heroSubtitle).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    Text(feed.feedBlurb).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(12)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.primary).padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true,
                     tint: selected ? accent.opacity(0.18) : nil)
        .accessibilityLabel("\(feed.heroSubtitle). \(feed.feedBlurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.feeds.\(feed.rawValue)")
    }
}

// MARK: - Board (t240u): a home-screen-style console of widgets

/// Widget footprint on the 4-column Board grid.
enum BoardWidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge, circle, pill, tall
    var id: Self { self }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .circle: "Circle"
        case .pill: "Pill"
        case .tall: "Tall"
        }
    }
    /// Columns × rows on the 4-column grid.
    var span: (w: Int, h: Int) {
        switch self {
        case .small, .circle: (2, 2)
        case .medium: (4, 2)
        case .large: (4, 4)
        case .extraLarge: (4, 6)
        case .pill: (4, 1)
        case .tall: (2, 4)
        }
    }
    var isCompact: Bool { self == .small || self == .circle || self == .pill }
}

/// Every built-in widget. Modules add theirs through `ModuleWidgetManifest` (capability-gated).
enum BoardWidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock, worldClock, activity, weather, today, notes, battery, moliboo, messages, streak
    case quickActions, modules, nowPlaying, photos, countdown, stopwatch, callsFavourites, connectNumber
    var id: Self { self }

    var title: String {
        switch self {
        case .clock: "Clock"
        case .worldClock: "World Clock"
        case .activity: "Activity"
        case .weather: "Weather"
        case .today: "Today"
        case .notes: "Notes"
        case .battery: "Battery"
        case .moliboo: "Moliboo"
        case .messages: "Messages"
        case .streak: "Streak"
        case .quickActions: "Quick Actions"
        case .modules: "Modules"
        case .nowPlaying: "Now Playing"
        case .photos: "Memories"
        case .countdown: "Countdown"
        case .stopwatch: "Stopwatch"
        case .callsFavourites: "Favourites"
        case .connectNumber: "Modula Number"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .worldClock: "globe"
        case .activity: "chart.bar.fill"
        case .weather: "cloud.sun.fill"
        case .today: "calendar"
        case .notes: "note.text"
        case .battery: "battery.75percent"
        case .moliboo: "pawprint.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .streak: "flame.fill"
        case .quickActions: "square.grid.2x2.fill"
        case .modules: "shippingbox.fill"
        case .nowPlaying: "music.note"
        case .photos: "photo.on.rectangle"
        case .countdown: "hourglass"
        case .stopwatch: "stopwatch"
        case .callsFavourites: "star.fill"
        case .connectNumber: "antenna.radiowaves.left.and.right"
        }
    }

    var blurb: String {
        switch self {
        case .clock: "Analog or digital, with seconds"
        case .worldClock: "Three cities at a glance"
        case .activity: "Your time in Modula today"
        case .weather: "Forecast (needs location, coming soon)"
        case .today: "Date, week and day progress"
        case .notes: "A note you pin to the Board"
        case .battery: "Battery level and charging"
        case .moliboo: "Your companion, on the Board"
        case .messages: "Unread chats"
        case .streak: "Days in a row"
        case .quickActions: "Write, search, chats, calls"
        case .modules: "Jump into your modules"
        case .nowPlaying: "Music controls (coming soon)"
        case .photos: "On this day (coming soon)"
        case .countdown: "Days until something good"
        case .stopwatch: "Start, stop, lap"
        case .callsFavourites: "Call your favourites"
        case .connectNumber: "Your Modula Number"
        }
    }

    var sizes: [BoardWidgetSize] {
        switch self {
        case .quickActions: [.medium, .small, .pill]
        case .callsFavourites, .messages: [.medium, .small, .large, .pill]
        case .clock: [.small, .circle, .medium, .large, .pill]
        case .notes: [.small, .medium, .large, .tall]
        case .today: [.small, .medium, .large, .tall]
        case .moliboo: [.small, .circle, .medium, .large, .tall]
        default: [.small, .medium, .circle, .pill, .large]
        }
    }

    var defaultSize: BoardWidgetSize { sizes[0] }

    /// Widgets whose data source isn't available yet show an honest placeholder.
    var isGated: Bool { self == .weather || self == .nowPlaying || self == .photos }
}

struct BoardWidget: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var kind: BoardWidgetKind
    var size: BoardWidgetSize
    var settings: [String: String] = [:]
    /// Extra kinds you swipe through in a Smart Stack (the main `kind` comes first).
    var stack: [BoardWidgetKind] = []

    var kinds: [BoardWidgetKind] { [kind] + stack }
    func setting(_ key: String, _ fallback: String) -> String { settings[key] ?? fallback }
}

struct BoardPage: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var widgets: [BoardWidget]
}

struct BoardLayout: Codable, Equatable, Sendable {
    var pages: [BoardPage]
    /// "spectral" or a nature scene raw value; "none" for the plain canvas.
    var wallpaper = "spectral"
    var showsLabels = true

    static let `default` = BoardLayout(pages: [
        BoardPage(name: "Console", widgets: [
            BoardWidget(kind: .clock, size: .small, settings: ["style": "analog"]),
            BoardWidget(kind: .today, size: .small),
            BoardWidget(kind: .quickActions, size: .medium),
            BoardWidget(kind: .messages, size: .small),
            BoardWidget(kind: .streak, size: .circle),
            BoardWidget(kind: .activity, size: .medium),
            BoardWidget(kind: .notes, size: .medium, settings: ["text": "Long-press the Board to edit. Tap a widget in edit mode to change its size and settings."])
        ]),
        BoardPage(name: "Life", widgets: [
            BoardWidget(kind: .worldClock, size: .medium),
            BoardWidget(kind: .battery, size: .small),
            BoardWidget(kind: .moliboo, size: .small),
            BoardWidget(kind: .countdown, size: .medium),
            BoardWidget(kind: .stopwatch, size: .pill),
            BoardWidget(kind: .connectNumber, size: .small),
            BoardWidget(kind: .callsFavourites, size: .small)
        ])
    ])
}

/// Contract for module-provided widgets (Board now, iOS Home Screen later via WidgetKit).
/// A module's manifest may list these under `widgets`; the host only shows ones whose
/// `capability` the server grants. Rendering runs through the module runtime snapshot API
/// (not built yet), so module widgets are listed but not drawn today.
struct ModuleWidgetManifest: Codable, Identifiable, Hashable, Sendable {
    struct SettingField: Codable, Hashable, Sendable {
        var key: String
        var title: String
        /// "text", "toggle", "choice", "date"
        var type: String
        var options: [String]? = nil
        var defaultValue: String? = nil
    }
    var moduleID: String
    var widgetID: String
    var title: String
    var sizes: [BoardWidgetSize]
    var capability: String?
    /// Minimum refresh interval the host honours (seconds, ≥ 300 on the Home Screen).
    var refreshSeconds: Int = 900
    var settings: [SettingField] = []
    /// Deep link opened when the widget is tapped, e.g. modula://module/<id>/path.
    var deepLink: String?
    var id: String { "\(moduleID)/\(widgetID)" }
}

enum BoardWidgetRegistry {
    /// Module widgets the current account may use (none until modules ship manifests).
    static func moduleWidgets(granted capabilities: Set<String>) -> [ModuleWidgetManifest] {
        declared.filter { $0.capability.map(capabilities.contains) ?? true }
    }
    static let declared: [ModuleWidgetManifest] = []
}

/// Persists the Board on this iPhone and tracks a light, local activity signal.
@MainActor @Observable
final class BoardStore {
    static let shared = BoardStore()
    private static let key = "board.layout.v1"
    private(set) var layout: BoardLayout

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(BoardLayout.self, from: data), !saved.pages.isEmpty {
            layout = saved
        } else {
            layout = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func mutate(_ change: (inout BoardLayout) -> Void) {
        change(&layout)
        if layout.pages.isEmpty { layout.pages = [BoardPage(name: "Board", widgets: [])] }
        save()
    }

    func add(_ widget: BoardWidget, page: Int) {
        mutate { $0.pages[min(page, $0.pages.count - 1)].widgets.append(widget) }
    }

    func remove(_ id: String) {
        mutate { layout in for i in layout.pages.indices { layout.pages[i].widgets.removeAll { $0.id == id } } }
    }

    func update(_ widget: BoardWidget) {
        mutate { layout in
            for i in layout.pages.indices {
                if let j = layout.pages[i].widgets.firstIndex(where: { $0.id == widget.id }) { layout.pages[i].widgets[j] = widget }
            }
        }
    }

    /// Moves `id` to just before `target` (same or another page).
    func move(_ id: String, before target: String) {
        guard id != target else { return }
        mutate { layout in
            var moving: BoardWidget?
            for i in layout.pages.indices {
                if let j = layout.pages[i].widgets.firstIndex(where: { $0.id == id }) { moving = layout.pages[i].widgets.remove(at: j) }
            }
            guard let moving else { return }
            for i in layout.pages.indices {
                if let j = layout.pages[i].widgets.firstIndex(where: { $0.id == target }) {
                    layout.pages[i].widgets.insert(moving, at: j)
                    return
                }
            }
            layout.pages[0].widgets.append(moving)
        }
    }

    func widget(_ id: String) -> BoardWidget? {
        layout.pages.lazy.flatMap(\.widgets).first { $0.id == id }
    }

    func reset() { mutate { $0 = .default } }

    // MARK: Local activity (minutes in Modula today) and day streak

    private var activeSince: Date?

    func appBecameActive() {
        activeSince = Date()
        let defaults = UserDefaults.standard
        let today = Self.dayKey(Date())
        let last = defaults.string(forKey: "board.streak.last")
        if last != today {
            let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            let streak = last == yesterday ? defaults.integer(forKey: "board.streak.count") + 1 : 1
            defaults.set(streak, forKey: "board.streak.count")
            defaults.set(today, forKey: "board.streak.last")
        }
    }

    func appResigned() {
        guard let since = activeSince else { return }
        activeSince = nil
        let key = "board.activity.\(Self.dayKey(Date()))"
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: key) + Date().timeIntervalSince(since), forKey: key)
    }

    func minutesToday() -> Int {
        let stored = UserDefaults.standard.double(forKey: "board.activity.\(Self.dayKey(Date()))")
        let live = activeSince.map { Date().timeIntervalSince($0) } ?? 0
        return Int((stored + live) / 60)
    }

    func minutes(daysAgo: Int) -> Int {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        if daysAgo == 0 { return minutesToday() }
        return Int(UserDefaults.standard.double(forKey: "board.activity.\(Self.dayKey(day))") / 60)
    }

    var streak: Int { max(1, UserDefaults.standard.integer(forKey: "board.streak.count")) }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Greedy packer for the 4-column grid: each widget takes the first free slot (row-major).
enum BoardGridPacker {
    struct Slot: Equatable { let x: Int; let y: Int; let w: Int; let h: Int }

    static func pack(_ widgets: [BoardWidget], columns: Int = 4) -> (slots: [String: Slot], rows: Int) {
        var occupied = Set<[Int]>()
        var slots: [String: Slot] = [:]
        var rows = 0
        for widget in widgets {
            let (w, h) = widget.size.span
            var y = 0
            search: while true {
                for x in 0...(columns - w) where fits(x, y, w, h, occupied) {
                    for dx in 0..<w { for dy in 0..<h { occupied.insert([x + dx, y + dy]) } }
                    slots[widget.id] = Slot(x: x, y: y, w: w, h: h)
                    rows = max(rows, y + h)
                    break search
                }
                y += 1
            }
        }
        return (slots, rows)
    }

    private static func fits(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ occupied: Set<[Int]>) -> Bool {
        for dx in 0..<w { for dy in 0..<h where occupied.contains([x + dx, y + dy]) { return false } }
        return true
    }
}

// MARK: Board widget rendering

/// One widget's face. Every kind adapts to compact (small/circle/pill) and roomy sizes.
struct BoardWidgetView: View {
    let widget: BoardWidget
    var kind: BoardWidgetKind? = nil
    @Environment(AppEnvironment.self) private var app

    private var shownKind: BoardWidgetKind { kind ?? widget.kind }
    private var size: BoardWidgetSize { widget.size }

    var body: some View {
        Group {
            switch shownKind {
            case .clock: BoardClockFace(style: widget.setting("style", "analog"), size: size, showsSeconds: widget.setting("seconds", "on") == "on")
            case .worldClock: BoardWorldClock(size: size, zones: widget.setting("zones", "Europe/London,America/New_York,Asia/Tokyo"))
            case .activity: BoardActivityFace(size: size)
            case .today: BoardTodayFace(size: size)
            case .notes: notes
            case .battery: BoardBatteryFace(size: size)
            case .moliboo: moliboo
            case .messages: messages
            case .streak: metric(value: "\(max(BoardStore.shared.streak, MascotProgressStore.shared.streak))", label: "day streak", symbol: "flame.fill")
            case .quickActions: BoardQuickActions(size: size)
            case .modules: metric(value: "\(app.catalogue.installedIDs.count)", label: "modules", symbol: "shippingbox.fill")
            case .countdown: BoardCountdownFace(size: size, title: widget.setting("title", "Weekend"), target: widget.setting("date", ""))
            case .stopwatch: BoardStopwatchFace(size: size)
            case .callsFavourites: BoardFavouritesFace(size: size)
            case .connectNumber: connect
            case .weather, .nowPlaying, .photos: gated
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "note.text").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(widget.setting("text", "Tap Edit, then this note, to write something."))
                .font(size.isCompact ? .footnote.weight(.medium) : .body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
    }

    private var moliboo: some View {
        VStack(spacing: 4) {
            MolibooEmptyArt(mood: .happy, size: size == .large || size == .tall ? 64 : 36)
            if !size.isCompact || size == .small {
                Text(HomeMolibooGreeting.mood(hour: Calendar.current.component(.hour, from: Date()), streak: MascotProgressStore.shared.streak))
                    .font(.caption.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.primary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(8)
    }

    private var messages: some View {
        let unread = app.messaging.accountUnreadCount ?? 0
        let recent = Array(app.messaging.visibleConversations.prefix(size == .large ? 5 : 3))
        return Group {
            if size.isCompact {
                metric(value: "\(unread)", label: unread == 1 ? "unread chat" : "unread chats", symbol: "bubble.left.and.bubble.right.fill")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill").font(.caption.weight(.bold))
                        Spacer()
                        if unread > 0 { Text("\(unread)").font(.caption.weight(.heavy)).contentTransition(.numericText()) }
                    }
                    ForEach(recent) { c in
                        HStack(spacing: 8) {
                            let p = c.participants.first
                            ModulaAvatar(initials: p?.initials ?? "?", url: p?.avatarURL, size: 26, name: c.title)
                            Text(c.title).font(.footnote.weight(c.isUnread ? .bold : .regular)).lineLimit(1)
                            Spacer(minLength: 0)
                            if c.isUnread { Circle().fill(Color.primary).frame(width: 7, height: 7) }
                        }
                    }
                    if recent.isEmpty { Text("No chats yet").font(.footnote).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }

    private var connect: some View {
        let raw = ModulaNumberStore.shared.number
        let shown = raw.count > 4 ? raw.prefix(4) + " " + raw.dropFirst(4) : Substring(raw)
        return VStack(alignment: .leading, spacing: 6) {
            ModulaConnectMark(size: size.isCompact ? 26 : 32, animated: false)
            Spacer(minLength: 0)
            Text(String(shown)).font(.system(size: size.isCompact ? 18 : 26, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("Modula Number").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private var gated: some View {
        VStack(spacing: 6) {
            Image(systemName: shownKind.symbol).font(.title2.weight(.semibold)).symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(shownKind.title).font(.footnote.weight(.bold))
            if !size.isCompact || size == .small {
                Text("Coming soon").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shownKind.title), coming soon")
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        Group {
            if size == .pill {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.headline)
                    Text(value).font(.title3.weight(.heavy)).contentTransition(.numericText())
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: symbol).font(size == .circle ? .callout : .title3).symbolEffect(.bounce, value: value)
                    Text(value).font(.system(size: size == .circle ? 26 : 34, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText()).minimumScaleFactor(0.5).lineLimit(1)
                    Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BoardClockFace: View {
    let style: String
    let size: BoardWidgetSize
    var showsSeconds = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: showsSeconds ? 1 : 30)) { ctx in
            let date = ctx.date
            if style == "digital" || size == .pill || size == .medium {
                VStack(alignment: size == .pill ? .center : .leading, spacing: 2) {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.system(size: size == .pill ? 28 : (size == .large ? 64 : 44), weight: .bold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.5).lineLimit(1)
                    if size != .pill {
                        Text(date, format: .dateTime.weekday(.wide).day().month(.wide)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .pill ? .center : .leading)
                .padding(.horizontal, 16)
                .animation(.snappy, value: date)
            } else {
                BoardAnalogClock(date: date, showsSeconds: showsSeconds).padding(size == .large ? 22 : 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Date(), format: .dateTime.hour().minute()))
    }
}

struct BoardAnalogClock: View {
    let date: Date
    var showsSeconds = true

    var body: some View {
        Canvas { ctx, s in
            let r = min(s.width, s.height) / 2
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            for i in 0..<60 {
                let a = Double(i) / 60 * 2 * .pi
                let long = i % 5 == 0
                let p1 = CGPoint(x: c.x + sin(a) * r * (long ? 0.82 : 0.9), y: c.y - cos(a) * r * (long ? 0.82 : 0.9))
                let p2 = CGPoint(x: c.x + sin(a) * r * 0.97, y: c.y - cos(a) * r * 0.97)
                var p = Path(); p.move(to: p1); p.addLine(to: p2)
                ctx.stroke(p, with: .color(.primary.opacity(long ? 0.9 : 0.3)), lineWidth: long ? 2 : 1)
            }
            let comps = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let sec = Double(comps.second ?? 0)
            let min = Double(comps.minute ?? 0) + sec / 60
            let hr = Double((comps.hour ?? 0) % 12) + min / 60
            func hand(_ f: Double, _ len: Double, _ w: Double, _ color: Color) {
                let a = f * 2 * .pi
                var p = Path(); p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + sin(a) * r * len, y: c.y - cos(a) * r * len))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            hand(hr / 12, 0.5, 4, .primary)
            hand(min / 60, 0.74, 3, .primary)
            if showsSeconds { hand(sec / 60, 0.84, 1.2, .orange) }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(.primary))
        }
    }
}

struct BoardWorldClock: View {
    let size: BoardWidgetSize
    let zones: String

    var body: some View {
        let ids = zones.split(separator: ",").map(String.init).compactMap(TimeZone.init(identifier:))
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            Group {
                if size.isCompact, let first = ids.first {
                    VStack(spacing: 2) {
                        Text(city(first)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(time(ctx.date, first)).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(ids.prefix(size == .large ? 4 : 3), id: \.identifier) { zone in
                            VStack(spacing: 4) {
                                BoardAnalogClock(date: shifted(ctx.date, zone), showsSeconds: false).frame(width: 54, height: 54)
                                Text(city(zone)).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                                Text(time(ctx.date, zone)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func city(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }
    private func time(_ date: Date, _ zone: TimeZone) -> String {
        var f = Date.FormatStyle.dateTime.hour().minute()
        f.timeZone = zone
        return date.formatted(f)
    }
    /// Analog hands read the local calendar, so shift the instant by the zone offset difference.
    private func shifted(_ date: Date, _ zone: TimeZone) -> Date {
        date.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)))
    }
}

struct BoardActivityFace: View {
    let size: BoardWidgetSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let store = BoardStore.shared
            let days = (0..<7).reversed().map { store.minutes(daysAgo: $0) }
            let peak = max(days.max() ?? 1, 30)
            let today = days.last ?? 0
            Group {
                if size.isCompact {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                        Circle().trim(from: 0, to: min(1, Double(today) / 60)).stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(today)").font(.title3.weight(.heavy)).contentTransition(.numericText())
                            Text("min").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Activity", systemImage: "chart.bar.fill").font(.caption.weight(.bold))
                            Spacer()
                            Text("\(today) min today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array(days.enumerated()), id: \.offset) { i, m in
                                Capsule().fill(Color.primary.opacity(i == 6 ? 1 : 0.35))
                                    .frame(height: max(4, CGFloat(m) / CGFloat(peak) * 60))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: days)
                    }
                    .padding(14)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity: \(BoardStore.shared.minutesToday()) minutes in Modula today")
    }
}

struct BoardTodayFace: View {
    let size: BoardWidgetSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let cal = Calendar.current
            let start = cal.startOfDay(for: ctx.date)
            let progress = ctx.date.timeIntervalSince(start) / 86_400
            VStack(alignment: .leading, spacing: 6) {
                Text(ctx.date, format: .dateTime.weekday(.wide)).font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(ctx.date, format: .dateTime.day()).font(.system(size: size.isCompact ? 40 : 52, weight: .heavy, design: .rounded))
                if !size.isCompact || size == .small {
                    ProgressView(value: progress).tint(.primary)
                    Text("\(Int(progress * 100))% of today").font(.caption2).foregroundStyle(.secondary)
                }
                if size == .medium || size == .large || size == .tall {
                    HStack(spacing: 4) {
                        ForEach(-3...3, id: \.self) { offset in
                            let d = cal.date(byAdding: .day, value: offset, to: ctx.date) ?? ctx.date
                            VStack(spacing: 2) {
                                Text(d, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                                Text(d, format: .dateTime.day()).font(.caption.weight(offset == 0 ? .heavy : .regular))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(offset == 0 ? Color.primary.opacity(0.15) : .clear))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BoardBatteryFace: View {
    let size: BoardWidgetSize
    @State private var level: Float = UIDevice.current.batteryLevel
    @State private var charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

    var body: some View {
        let pct = level < 0 ? nil : Int(level * 100)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
            Circle().trim(from: 0, to: CGFloat(max(0, level)))
                .stroke(pct.map { $0 <= 20 } == true ? Color.red : Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: level)
            VStack(spacing: 0) {
                Image(systemName: charging ? "bolt.fill" : "iphone").font(.caption.weight(.bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: charging)
                Text(pct.map { "\($0)%" } ?? "—").font(.headline.weight(.heavy)).contentTransition(.numericText())
            }
        }
        .padding(18)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            level = UIDevice.current.batteryLevel
            charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in level = UIDevice.current.batteryLevel }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(pct.map { "\($0) percent" } ?? "unknown")\(charging ? ", charging" : "")")
    }
}

struct BoardQuickActions: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app

    private var actions: [(String, String, AppRoute)] {
        [("Write", "square.and.pencil", .compose(.post)), ("Search", "magnifyingglass", .search(.root(nil))),
         ("Chats", "bubble.left.and.bubble.right", .messages(.inbox)), ("Calls", "phone", .messages(.calls))]
    }

    var body: some View {
        let shown = size == .small ? Array(actions.prefix(4)) : actions
        let columns = size == .small ? 2 : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(shown, id: \.0) { item in
                Button {
                    HapticEngine.shared.play(.navigation)
                    app.navigation.push(item.2)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.1).font(.system(size: 17, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.modulaPrimaryFill))
                            .foregroundStyle(Color.modulaOnPrimary)
                        if size != .pill && size != .small { Text(item.0).font(.caption2.weight(.semibold)).foregroundStyle(.primary) }
                    }
                }
                .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                .accessibilityLabel(item.0)
            }
        }
        .padding(12)
    }
}

struct BoardCountdownFace: View {
    let size: BoardWidgetSize
    let title: String
    let target: String

    private var targetDate: Date {
        if let d = ISO8601DateFormatter().date(from: target) { return d }
        // Default: next Saturday.
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? Date()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: ctx.date),
                                                              to: Calendar.current.startOfDay(for: targetDate)).day ?? 0)
            VStack(alignment: size == .pill ? .center : .leading, spacing: 2) {
                if size == .pill {
                    Text("\(title) in \(days) \(days == 1 ? "day" : "days")").font(.headline)
                } else {
                    Label(title, systemImage: "hourglass").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(days)").font(.system(size: size.isCompact ? 40 : 54, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    Text(days == 1 ? "day to go" : "days to go").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .pill ? .center : .leading)
            .padding(14)
        }
    }
}

struct BoardStopwatchFace: View {
    let size: BoardWidgetSize
    @State private var started: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var laps: [TimeInterval] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: started == nil ? 60 : 0.1)) { ctx in
            let total = elapsed + (started.map { ctx.date.timeIntervalSince($0) } ?? 0)
            let content = HStack(spacing: 12) {
                Text(Self.format(total)).font(.system(size: size == .pill ? 26 : 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).minimumScaleFactor(0.5).lineLimit(1)
                Spacer(minLength: 0)
                Button { toggle() } label: {
                    Image(systemName: started == nil ? "play.fill" : "pause.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.modulaPrimaryFill)).foregroundStyle(Color.modulaOnPrimary)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: .selection))
                .accessibilityLabel(started == nil ? "Start" : "Pause")
                Button {
                    if started != nil { laps.insert(total, at: 0) } else { elapsed = 0; laps = [] }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: started != nil ? "flag.fill" : "arrow.counterclockwise")
                        .frame(width: 40, height: 40).modulaGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(started != nil ? "Lap" : "Reset")
            }
            VStack(alignment: .leading, spacing: 6) {
                content
                if !size.isCompact {
                    ForEach(Array(laps.prefix(size == .large ? 6 : 2).enumerated()), id: \.offset) { i, lap in
                        HStack { Text("Lap \(laps.count - i)").foregroundStyle(.secondary); Spacer(); Text(Self.format(lap)).monospacedDigit() }
                            .font(.footnote).transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .animation(.snappy, value: laps)
        }
    }

    private func toggle() {
        if let s = started { elapsed += Date().timeIntervalSince(s); started = nil } else { started = Date() }
    }

    static func format(_ t: TimeInterval) -> String {
        let cs = Int(t * 10) % 10, s = Int(t) % 60, m = Int(t) / 60
        return String(format: "%02d:%02d.%d", m, s, cs)
    }
}

struct BoardFavouritesFace: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let favs = app.calls.favourites.compactMap { id in CallsDirectory.contact(forConversation: id, app: app) }
        let shown = Array(favs.prefix(size == .large ? 8 : (size.isCompact ? 2 : 4)))
        Group {
            if shown.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "star").font(.title3)
                    Text("Add favourites in Calls").font(.caption.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: size.isCompact ? 2 : 4), spacing: 8) {
                    ForEach(shown) { c in
                        Button { if let id = c.conversationID { CallsActions.call(id, kind: .audio, app: app) } } label: {
                            VStack(spacing: 3) {
                                ModulaAvatar(initials: c.initials, url: c.avatarURL, size: size.isCompact ? 36 : 44, name: c.name)
                                if !size.isCompact { Text(c.name).font(.caption2.weight(.semibold)).lineLimit(1) }
                            }
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: .selection))
                        .accessibilityLabel("Call \(c.name)")
                    }
                }
                .padding(10)
            }
        }
    }
}

// MARK: Board screen

struct BoardView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    private var store: BoardStore { BoardStore.shared }
    @State private var editing = false
    @State private var page = 0
    @State private var showsGallery = false
    @State private var configuring: BoardWidget?
    @State private var dragging: String?
    @State private var renaming = false
    @State private var pageName = ""
    @Namespace private var widgetNS

    private static let gap: CGFloat = 14

    var body: some View {
        let layout = store.layout
        ZStack {
            BoardWallpaper(name: layout.wallpaper).ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(layout.pages.enumerated()), id: \.element.id) { index, boardPage in
                    pageView(boardPage).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: layout.pages.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        }
        .navigationTitle(layout.pages.indices.contains(page) ? layout.pages[page].name : "Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showsGallery) { BoardWidgetGallery(page: page) }
        .sheet(item: $configuring) { widget in BoardWidgetSettingsSheet(widgetID: widget.id) }
        .alert("Rename Page", isPresented: $renaming) {
            TextField("Name", text: $pageName)
            Button("Save") {
                let name = pageName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                store.mutate { $0.pages[min(page, $0.pages.count - 1)].name = String(name.prefix(24)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { store.appBecameActive() }
        .onChange(of: phase) { _, p in
            if p == .active { store.appBecameActive() } else if p == .background { store.appResigned() }
        }
        .accessibilityIdentifier("board.root")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = false } } label: {
                    Text("Done").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.modulaPrimary)
                .accessibilityIdentifier("board.done")
            } else {
                Menu {
                    Button("Add Widget", systemImage: "plus.square.on.square") { showsGallery = true }
                    Button("Edit Board", systemImage: "square.and.pencil") { startEditing() }
                    Divider()
                    Button("New Page", systemImage: "plus.rectangle.on.rectangle") {
                        store.mutate { $0.pages.append(BoardPage(name: "Page \($0.pages.count + 1)", widgets: [])) }
                        withAnimation(.snappy) { page = store.layout.pages.count - 1 }
                    }
                    Button("Rename Page", systemImage: "character.cursor.ibeam") {
                        pageName = store.layout.pages.indices.contains(page) ? store.layout.pages[page].name : ""
                        renaming = true
                    }
                    if store.layout.pages.count > 1 {
                        Button("Delete Page", systemImage: "trash", role: .destructive) {
                            let index = page
                            withAnimation(.snappy) { page = max(0, index - 1) }
                            store.mutate { if $0.pages.indices.contains(index) { $0.pages.remove(at: index) } }
                        }
                    }
                    Divider()
                    Menu("Wallpaper", systemImage: "photo.artframe") {
                        Picker("Wallpaper", selection: Binding(get: { store.layout.wallpaper }, set: { v in withAnimation(.easeInOut(duration: 0.4)) { store.mutate { $0.wallpaper = v } } })) {
                            Text("Spectral").tag("spectral")
                            ForEach(NatureWallpaperView.Kind.allCases, id: \.rawValue) { kind in
                                Text(MessagesWallpaperTheme(rawValue: kind.rawValue)?.title ?? kind.rawValue.capitalized).tag(kind.rawValue)
                            }
                            Text("None").tag("none")
                        }
                    }
                    Toggle("Widget Labels", isOn: Binding(get: { store.layout.showsLabels }, set: { v in store.mutate { $0.showsLabels = v } }))
                    Button("Reset Board", systemImage: "arrow.counterclockwise", role: .destructive) {
                        withAnimation(.spring) { store.reset(); page = 0 }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Board options")
                .accessibilityIdentifier("board.menu")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsGallery = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add widget")
                .accessibilityIdentifier("board.add")
        }
    }

    private func startEditing() {
        HapticEngine.shared.play(.success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { editing = true }
    }

    private func pageView(_ boardPage: BoardPage) -> some View {
        GeometryReader { geo in
            let inset = ModulaLayout.contentInset
            let cell = (geo.size.width - inset * 2 - Self.gap * 3) / 4
            let packed = BoardGridPacker.pack(boardPage.widgets)
            let labelRoom: CGFloat = store.layout.showsLabels ? 18 : 0
            let rowHeight = cell + (labelRoom / 2)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(height: CGFloat(packed.rows) * (rowHeight + Self.gap) + 120)
                    ForEach(boardPage.widgets) { widget in
                        if let slot = packed.slots[widget.id] {
                            let w = CGFloat(slot.w) * cell + CGFloat(slot.w - 1) * Self.gap
                            let h = CGFloat(slot.h) * rowHeight + CGFloat(slot.h - 1) * Self.gap - labelRoom
                            BoardWidgetTile(widget: widget, editing: editing, dragging: dragging == widget.id, showsLabel: store.layout.showsLabels,
                                            onTap: { tapped(widget) },
                                            onRemove: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.remove(widget.id) } },
                                            onLongPress: { if !editing { startEditing() } })
                                .frame(width: w, height: h + labelRoom)
                                .matchedGeometryEffect(id: widget.id, in: widgetNS)
                                .offset(x: CGFloat(slot.x) * (cell + Self.gap), y: CGFloat(slot.y) * (rowHeight + Self.gap))
                                .draggable(widget.id) {
                                    BoardWidgetChrome(size: widget.size) { BoardWidgetView(widget: widget) }
                                        .frame(width: w, height: h).onAppear { dragging = widget.id }
                                }
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first else { return false }
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { store.move(id, before: widget.id) }
                                    HapticEngine.shared.play(.selection)
                                    dragging = nil
                                    return true
                                }
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 12)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: boardPage.widgets)
                if boardPage.widgets.isEmpty { emptyPage }
            }
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) { if !editing { startEditing() } }
        }
    }

    private var emptyPage: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .semibold)).symbolEffect(.bounce, value: page)
            Text("An empty page").font(.title3.weight(.bold))
            Text("Add clocks, notes, chats, your Modula Number and more.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add Widget") { showsGallery = true }.buttonStyle(.modulaPrimary)
        }
        .padding(28)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, ModulaLayout.contentInset)
        .modulaAppear()
    }

    private func tapped(_ widget: BoardWidget) {
        if editing {
            configuring = widget
            return
        }
        HapticEngine.shared.play(.navigation)
        switch widget.kind {
        case .messages: app.navigation.push(.messages(.inbox))
        case .callsFavourites: app.navigation.push(.messages(.calls))
        case .modules: app.navigation.push(.productHub(.collection(.installed)))
        case .connectNumber: app.navigation.open(.module(ConnectPreview.moduleID, localPath: nil))
        case .moliboo: app.navigation.push(.settings(.moliboo))
        case .quickActions, .stopwatch: break
        default: configuring = widget
        }
    }
}

/// The glass shape around a widget: rounded rect, circle or capsule.
struct BoardWidgetChrome<Content: View>: View {
    let size: BoardWidgetSize
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            switch size {
            case .circle:
                content.clipShape(Circle()).modulaGlass(in: Circle(), interactive: true)
            case .pill:
                content.clipShape(Capsule()).modulaGlass(in: Capsule(), interactive: true)
            default:
                let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
                content.clipShape(shape).modulaGlass(in: shape, interactive: true)
            }
        }
    }
}

struct BoardWidgetTile: View {
    let widget: BoardWidget
    let editing: Bool
    var dragging = false
    var showsLabel = true
    var onTap: () -> Void
    var onRemove: () -> Void
    var onLongPress: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false
    @State private var stackIndex = 0

    var body: some View {
        VStack(spacing: 4) {
            BoardWidgetChrome(size: widget.size) {
                if widget.stack.isEmpty {
                    BoardWidgetView(widget: widget)
                } else {
                    TabView(selection: $stackIndex) {
                        ForEach(Array(widget.kinds.enumerated()), id: \.offset) { i, kind in
                            BoardWidgetView(widget: widget, kind: kind).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .trailing) {
                        VStack(spacing: 3) {
                            ForEach(widget.kinds.indices, id: \.self) { i in
                                Capsule().fill(Color.primary.opacity(i == stackIndex ? 0.9 : 0.25)).frame(width: 4, height: i == stackIndex ? 12 : 5)
                            }
                        }
                        .padding(.trailing, 6)
                        .animation(.snappy, value: stackIndex)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.45) { onLongPress() }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button(action: onRemove) {
                        Image(systemName: "minus").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.modulaOnPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.modulaPrimaryFill))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Remove \(widget.kind.title)")
                }
            }
            if showsLabel {
                Text(widget.stack.isEmpty ? widget.kind.title : "Smart Stack")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .frame(height: 14)
            }
        }
        .opacity(dragging ? 0.4 : 1)
        .rotationEffect(.degrees(editing && !reduceMotion ? (wiggle ? 1.4 : -1.4) : 0))
        .animation(editing && !reduceMotion
                   ? .easeInOut(duration: 0.13 + Double(abs(widget.id.hashValue % 5)) * 0.01).repeatForever(autoreverses: true)
                   : .spring(response: 0.3), value: wiggle)
        .onChange(of: editing) { _, on in wiggle = on }
        .onAppear { if editing { wiggle = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(widget.kind.title)
        .accessibilityHint(editing ? "Opens widget settings. Drag to reorder." : "Long-press to edit the Board")
        .accessibilityAction(named: "Remove") { onRemove() }
        .accessibilityIdentifier("board.widget.\(widget.kind.rawValue)")
    }
}

struct BoardWallpaper: View {
    let name: String
    var body: some View {
        if name == "spectral" {
            SpectralRibbonsView(intensity: 0.75)
        } else if let kind = NatureWallpaperView.Kind(rawValue: name) {
            NatureWallpaperView(kind: kind)
        } else {
            Color(uiColor: .systemBackground)
        }
    }
}

// MARK: Gallery and settings

struct BoardWidgetGallery: View {
    let page: Int
    @Environment(\.dismiss) private var dismiss
    @State private var sizes: [BoardWidgetKind: BoardWidgetSize] = [:]
    @State private var query = ""
    @State private var added: BoardWidgetKind?

    private var kinds: [BoardWidgetKind] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return BoardWidgetKind.allCases.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.blurb.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(kinds) { kind in card(kind) }
                    if !BoardWidgetRegistry.declared.isEmpty {
                        Text("Module widgets appear here when your modules offer them.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.bottom, 32)
            }
            .searchable(text: $query, prompt: "Search widgets")
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
    }

    private func card(_ kind: BoardWidgetKind) -> some View {
        let size = sizes[kind] ?? kind.defaultSize
        let preview = BoardWidget(kind: kind, size: size)
        let (w, h) = size.span
        let unit: CGFloat = 70
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).font(.headline).frame(width: 34, height: 34).modulaGlass(in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).font(.headline)
                    Text(kind.blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            BoardWidgetChrome(size: size) { BoardWidgetView(widget: preview) }
                .frame(width: CGFloat(w) * unit + CGFloat(w - 1) * 8, height: CGFloat(h) * unit * 0.85)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: size)
            ModulaSegmentedControl(segments: kind.sizes.map { .init(id: $0, title: $0.title) },
                                   selection: Binding(get: { size }, set: { sizes[kind] = $0 }),
                                   accessibilityLabel: "\(kind.title) size",
                                   identifier: { "board.gallery.\(kind.rawValue).\($0.rawValue)" })
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    BoardStore.shared.add(BoardWidget(kind: kind, size: size), page: page)
                    added = kind
                }
                HapticEngine.shared.play(.success)
            } label: {
                Label(added == kind ? "Added" : "Add Widget", systemImage: added == kind ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.modulaPrimary)
            .accessibilityIdentifier("board.gallery.add.\(kind.rawValue)")
        }
        .padding(16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct BoardWidgetSettingsSheet: View {
    let widgetID: String
    @Environment(\.dismiss) private var dismiss
    private var store: BoardStore { BoardStore.shared }

    var body: some View {
        NavigationStack {
            if let widget = store.widget(widgetID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        let (w, h) = widget.size.span
                        BoardWidgetChrome(size: widget.size) { BoardWidgetView(widget: widget) }
                            .frame(width: CGFloat(w) * 78 + CGFloat(w - 1) * 8, height: CGFloat(h) * 70)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: widget)
                        group("Size and shape") {
                            ModulaSegmentedControl(segments: widget.kind.sizes.map { .init(id: $0, title: $0.title) },
                                                   selection: Binding(get: { widget.size }, set: { v in var copy = widget; copy.size = v; store.update(copy) }),
                                                   accessibilityLabel: "Size", identifier: { "board.size.\($0.rawValue)" })
                        }
                        options(widget)
                        group("Smart Stack", footer: "Swipe on the widget to flip between everything in the stack.") {
                            ForEach(widget.stack, id: \.self) { kind in
                                HStack {
                                    Label(kind.title, systemImage: kind.symbol)
                                    Spacer()
                                    Button { var copy = widget; copy.stack.removeAll { $0 == kind }; store.update(copy) } label: {
                                        Image(systemName: "minus.circle.fill").font(.title3)
                                    }
                                    .buttonStyle(.plain).accessibilityLabel("Remove \(kind.title) from stack")
                                }
                                .frame(minHeight: 40)
                            }
                            Menu {
                                ForEach(BoardWidgetKind.allCases.filter { !widget.kinds.contains($0) }) { kind in
                                    Button(kind.title, systemImage: kind.symbol) { var copy = widget; copy.stack.append(kind); store.update(copy) }
                                }
                            } label: {
                                Label("Add to Stack", systemImage: "square.stack.3d.up").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.modulaSecondary)
                        }
                        Button(role: .destructive) {
                            store.remove(widgetID)
                            dismiss()
                        } label: {
                            Label("Remove Widget", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.modulaSecondary)
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.bottom, 28)
                }
                .navigationTitle(widget.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
            } else {
                ContentUnavailableView("Widget removed", systemImage: "square.dashed")
            }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
    }

    @ViewBuilder
    private func options(_ widget: BoardWidget) -> some View {
        switch widget.kind {
        case .clock:
            group("Clock") {
                ModulaSegmentedControl(segments: [.init(id: "analog", title: "Analog"), .init(id: "digital", title: "Digital")],
                                       selection: binding(widget, "style", "analog"), accessibilityLabel: "Clock style", identifier: { "board.clock.\($0)" })
                Toggle("Show seconds", isOn: Binding(get: { widget.setting("seconds", "on") == "on" },
                                                     set: { v in set(widget, "seconds", v ? "on" : "off") }))
                    .frame(minHeight: 44)
            }
        case .worldClock:
            group("Cities", footer: "Up to four. The first one shows on small sizes.") {
                ForEach(Self.cities, id: \.self) { zone in
                    let on = widget.setting("zones", "Europe/London,America/New_York,Asia/Tokyo").split(separator: ",").map(String.init).contains(zone)
                    Toggle(zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone, isOn: Binding(get: { on }, set: { v in
                        var list = widget.setting("zones", "Europe/London,America/New_York,Asia/Tokyo").split(separator: ",").map(String.init)
                        if v { if list.count < 4 { list.append(zone) } } else { list.removeAll { $0 == zone } }
                        set(widget, "zones", list.joined(separator: ","))
                    }))
                    .frame(minHeight: 40)
                }
            }
        case .notes:
            group("Note") {
                TextField("Write something", text: binding(widget, "text", ""), axis: .vertical)
                    .lineLimit(3...8)
                    .padding(12)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .countdown:
            group("Countdown") {
                TextField("Title", text: binding(widget, "title", "Weekend"))
                    .padding(12).modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                DatePicker("Date", selection: Binding(get: {
                    ISO8601DateFormatter().date(from: widget.setting("date", "")) ?? Date().addingTimeInterval(86_400 * 7)
                }, set: { d in set(widget, "date", ISO8601DateFormatter().string(from: d)) }), displayedComponents: .date)
            }
        default:
            if widget.kind.isGated {
                group(widget.kind.title) {
                    Text("This widget needs a data source that isn't switched on yet. It will fill in automatically when it is.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let cities = ["Europe/London", "Europe/Paris", "Europe/Bucharest", "America/New_York", "America/Los_Angeles", "Asia/Dubai", "Asia/Tokyo", "Australia/Sydney"]

    private func binding(_ widget: BoardWidget, _ key: String, _ fallback: String) -> Binding<String> {
        Binding(get: { widget.setting(key, fallback) }, set: { set(widget, key, $0) })
    }

    private func set(_ widget: BoardWidget, _ key: String, _ value: String) {
        var copy = widget
        copy.settings[key] = value
        store.update(copy)
    }

    private func group(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Home strip: the first few Board widgets as a horizontal rail (Edit Home › Board).
struct HomeBoardRail: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let widgets = Array(BoardStore.shared.layout.pages.first?.widgets.filter { $0.size == .small || $0.size == .circle }.prefix(6) ?? [])
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Board").font(.headline)
                Spacer()
                Button("Open") { app.navigation.push(.board); HapticEngine.shared.play(.navigation) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(widgets) { widget in
                        BoardWidgetChrome(size: widget.size) { BoardWidgetView(widget: widget) }
                            .frame(width: 132, height: 132)
                            .onTapGesture { app.navigation.push(.board) }
                    }
                    if widgets.isEmpty {
                        Button { app.navigation.push(.board) } label: {
                            Label("Set up your Board", systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).frame(height: 44)
                        }
                        .buttonStyle(.plain).modulaGlass(in: Capsule(), interactive: true)
                    }
                }
            }
            .modulaHorizontalRail()
            .scrollClipDisabled()
        }
        .accessibilityIdentifier("home.board")
    }
}

// MARK: - Developer › Call Screens (t240u): mock previews of every call state. No real calls.

enum CallPreviewState: String, CaseIterable, Identifiable {
    case incomingVoice, incomingVideo, banner, outgoingRinging, connecting, activeVoice, activeVideo, reconnecting, onHold, ended, missed, declined
    var id: Self { self }
    var title: String {
        switch self {
        case .incomingVoice: "Incoming voice (full screen)"
        case .incomingVideo: "Incoming video (full screen)"
        case .banner: "Incoming call banner"
        case .outgoingRinging: "Outgoing, ringing"
        case .connecting: "Connecting"
        case .activeVoice: "Voice call, active"
        case .activeVideo: "Video call, active"
        case .reconnecting: "Reconnecting"
        case .onHold: "On hold"
        case .ended: "Call ended"
        case .missed: "Missed call"
        case .declined: "Declined"
        }
    }
    var symbol: String {
        switch self {
        case .incomingVoice, .outgoingRinging: "phone.arrow.down.left"
        case .incomingVideo, .activeVideo: "video.fill"
        case .banner: "rectangle.topthird.inset.filled"
        case .connecting, .reconnecting: "antenna.radiowaves.left.and.right"
        case .activeVoice: "phone.fill"
        case .onHold: "pause.circle.fill"
        case .ended, .declined: "phone.down.fill"
        case .missed: "phone.badge.waveform"
        }
    }
}

struct CallScreensGallery: View {
    @State private var preview: CallPreviewState?

    var body: some View {
        List {
            Section {
                ForEach(CallPreviewState.allCases) { state in
                    Button { preview = state } label: {
                        Label(state.title, systemImage: state.symbol).foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("developer.calls.\(state.rawValue)")
                }
            } footer: {
                Text("Mock data only. Nothing here rings anyone, opens CallKit or touches the network.")
            }
        }
        .navigationTitle("Call Screens")
        .fullScreenCover(item: $preview) { state in CallScreenPreview(initial: state) }
    }
}

/// A self-contained replica of the call UI driven by mock state, with a state switcher on top.
struct CallScreenPreview: View {
    let initial: CallPreviewState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: CallPreviewState = .incomingVoice
    @State private var muted = false
    @State private var speaker = false
    @State private var camera = true
    @State private var pulse = false
    @State private var started = Date()

    private let party = CallParty(id: "preview", handle: "sophia.chen", displayName: "Sophia Chen", avatarURL: nil)

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            if state == .banner {
                bannerScene
            } else {
                VStack(spacing: 0) {
                    topBar
                    if state != .activeVideo { identity.padding(.top, 40) }
                    Spacer(minLength: 24)
                    controls.padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
                if state == .activeVideo && camera {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#3A3F58"), Color(hex: "#20232F")], startPoint: .top, endPoint: .bottom))
                        .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.5)))
                        .frame(width: 104, height: 152)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 110).padding(.trailing, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .safeAreaInset(edge: .top) { switcher }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: state)
        .onAppear {
            state = initial
            started = Date()
            pulse = true
        }
        .accessibilityIdentifier("developer.calls.preview")
    }

    private var switcher: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close preview")
            Menu {
                Picker("State", selection: $state) {
                    ForEach(CallPreviewState.allCases) { s in Label(s.title, systemImage: s.symbol).tag(s) }
                }
            } label: {
                Label(state.title, systemImage: "slider.horizontal.3").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).frame(height: 40).background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Text("PREVIEW").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var backdrop: some View {
        if state == .activeVideo {
            ZStack {
                LinearGradient(colors: [Color(hex: "#2B3A55"), Color(hex: "#5C4A6E"), Color(hex: "#1D2230")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "person.fill").font(.system(size: 160)).foregroundStyle(.white.opacity(0.12))
            }
            .overlay(alignment: .top) { LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: 180) }
            .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).frame(height: 260) }
        } else if state == .banner {
            SpectralRibbonsView(intensity: 0.6)
        } else {
            ZStack {
                Color.black
                RadialGradient(colors: [Color(hex: "#6A4BFF").opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 520)
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var topBar: some View {
        HStack {
            if !isRinging && !isOver {
                Image(systemName: "chevron.down").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if state == .activeVideo {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(party.name).font(.subheadline.weight(.semibold))
                    status.font(.caption)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: 52)
    }

    private var identity: some View {
        VStack(spacing: 14) {
            ZStack {
                if isRinging && !reduceMotion {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(.white.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 112, height: 112)
                            .scaleEffect(pulse ? 1.9 : 1)
                            .opacity(pulse ? 0 : 0.8)
                            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: pulse)
                    }
                }
                CallAvatar(party: party, size: 112)
                    .overlay(alignment: .bottomTrailing) {
                        if state == .onHold {
                            Image(systemName: "pause.fill").font(.caption.weight(.bold)).foregroundStyle(.black)
                                .frame(width: 30, height: 30).background(Circle().fill(.white)).transition(.scale)
                        }
                    }
            }
            Text(party.name).font(.title2.weight(.semibold))
            status.font(.callout).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .incomingVoice: Text("Incoming voice call")
        case .incomingVideo: Text("Incoming video call")
        case .banner: Text("Incoming call")
        case .outgoingRinging: Text("Ringing…")
        case .connecting: Text("Connecting…")
        case .reconnecting: HStack(spacing: 6) { ProgressView().tint(.white).controlSize(.small); Text("Reconnecting…") }
        case .onHold: Text("On hold")
        case .ended: Text("Call ended · 4:12")
        case .missed: Text("Missed call")
        case .declined: Text("Declined")
        case .activeVoice, .activeVideo:
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                Text(CallCopy.duration(ms: Int(ctx.date.timeIntervalSince(started) * 1000))).monospacedDigit()
            }
        }
    }

    private var isRinging: Bool { state == .incomingVoice || state == .incomingVideo || state == .outgoingRinging }
    private var isOver: Bool { state == .ended || state == .missed || state == .declined }

    @ViewBuilder
    private var controls: some View {
        if state == .incomingVoice || state == .incomingVideo {
            VStack(spacing: 30) {
                HStack(spacing: 40) {
                    CallControlButton(symbol: "alarm", title: "Remind Me", style: .toggle(false)) {}
                    CallControlButton(symbol: "message.fill", title: "Message", style: .toggle(false)) {}
                }
                HStack(spacing: 72) {
                    CallControlButton(symbol: "phone.down.fill", title: "Decline", style: .destructive) { state = .declined }
                    CallControlButton(symbol: state == .incomingVideo ? "video.fill" : "phone.fill", title: "Accept", style: .accept) {
                        started = Date()
                        state = state == .incomingVideo ? .activeVideo : .activeVoice
                    }
                }
            }
        } else if isOver {
            HStack(spacing: 40) {
                CallControlButton(symbol: "phone.fill", title: "Call Back", style: .accept) { state = .outgoingRinging }
                CallControlButton(symbol: "message.fill", title: "Message", style: .toggle(false)) {}
                CallControlButton(symbol: "xmark", title: "Close", style: .toggle(false)) { dismiss() }
            }
        } else {
            VStack(spacing: 28) {
                HStack(spacing: 22) {
                    CallControlButton(symbol: muted ? "mic.slash.fill" : "mic.fill", title: "Mute", style: .toggle(muted)) { muted.toggle() }
                    CallControlButton(symbol: "speaker.wave.2.fill", title: "Speaker", style: .toggle(speaker)) { speaker.toggle() }
                    if state == .activeVideo {
                        CallControlButton(symbol: camera ? "video.fill" : "video.slash.fill", title: "Camera", style: .toggle(!camera)) { camera.toggle() }
                        CallControlButton(symbol: "arrow.triangle.2.circlepath.camera.fill", title: "Flip", style: .toggle(false)) {}
                    } else {
                        CallControlButton(symbol: state == .onHold ? "play.fill" : "pause.fill", title: state == .onHold ? "Resume" : "Hold",
                                          style: .toggle(state == .onHold)) { state = state == .onHold ? .activeVoice : .onHold }
                    }
                }
                CallControlButton(symbol: "phone.down.fill", title: "End", style: .destructive) { state = .ended }
            }
        }
    }

    /// Lock-screen style banner sliding down over a fake app screen.
    private var bannerScene: some View {
        VStack {
            HStack(spacing: 12) {
                CallAvatar(party: party, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(party.name).font(.subheadline.weight(.semibold))
                    Text("Modula voice call").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                Button { state = .declined } label: {
                    Image(systemName: "phone.down.fill").foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(Color.red))
                }
                .accessibilityLabel("Decline")
                Button { started = Date(); state = .activeVoice } label: {
                    Image(systemName: "phone.fill").foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(Color.green))
                        .symbolEffect(.wiggle, options: .repeating, isActive: !reduceMotion)
                }
                .accessibilityLabel("Accept")
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .foregroundStyle(.white)
            Spacer()
        }
    }
}
