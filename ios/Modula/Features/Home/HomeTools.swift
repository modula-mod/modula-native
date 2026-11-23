import SwiftUI
import UIKit
import Observation
import PhotosUI
import ImageIO

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
    case focus, decide, quote, breathe, water, yearProgress
    case habit, calculator, converter, photoFrame
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
        case .focus: "Focus"
        case .decide: "Decide"
        case .quote: "Quote"
        case .breathe: "Breathe"
        case .water: "Water"
        case .yearProgress: "Year"
        case .habit: "Habit"
        case .calculator: "Calculator"
        case .converter: "Converter"
        case .photoFrame: "Photo Frame"
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
        case .focus: "timer"
        case .decide: "dice"
        case .quote: "quote.opening"
        case .breathe: "wind"
        case .water: "drop.fill"
        case .yearProgress: "chart.pie.fill"
        case .habit: "checkmark.seal.fill"
        case .calculator: "plus.forwardslash.minus"
        case .converter: "arrow.left.arrow.right"
        case .photoFrame: "photo.fill"
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
        case .focus: "A focus timer with a ring"
        case .decide: "Flip a coin, roll a die, yes or no"
        case .quote: "A new line every day"
        case .breathe: "A one-minute breathing guide"
        case .water: "Tap to log a glass, resets daily"
        case .yearProgress: "How much of the year has gone"
        case .habit: "Tick off a daily habit, keep the streak"
        case .calculator: "A quick calculator"
        case .converter: "Length, weight, temperature, volume"
        case .photoFrame: "A photo from your library"
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
        case .focus: [.small, .circle, .medium, .pill, .large]
        case .decide: [.small, .circle, .medium]
        case .quote: [.medium, .small, .large, .pill]
        case .breathe: [.small, .circle, .medium, .large]
        case .water: [.small, .circle, .medium, .pill]
        case .yearProgress: [.small, .circle, .medium, .pill]
        case .habit: [.small, .medium, .pill, .circle]
        case .calculator: [.large, .tall]
        case .converter: [.medium, .large]
        case .photoFrame: [.small, .medium, .large, .tall, .circle]
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

struct BoardStopwatchState: Codable, Equatable, Sendable {
    var started: Date?
    var elapsed: TimeInterval = 0
    var laps: [TimeInterval] = []
    func total(at date: Date) -> TimeInterval { elapsed + (started.map { date.timeIntervalSince($0) } ?? 0) }
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

    /// Live reorder while dragging on one page: `id` takes `target`'s place (iOS semantics).
    func reorder(_ id: String, onto target: String, page pageID: String) {
        guard id != target else { return }
        mutate { layout in
            guard let p = layout.pages.firstIndex(where: { $0.id == pageID }),
                  let from = layout.pages[p].widgets.firstIndex(where: { $0.id == id }),
                  let to = layout.pages[p].widgets.firstIndex(where: { $0.id == target }) else { return }
            let moving = layout.pages[p].widgets.remove(at: from)
            layout.pages[p].widgets.insert(moving, at: min(to, layout.pages[p].widgets.count))
        }
    }

    func widget(_ id: String) -> BoardWidget? {
        layout.pages.lazy.flatMap(\.widgets).first { $0.id == id }
    }

    func reset() { mutate { $0 = .default } }

    // MARK: Stopwatches (model state, so edit mode / page swipes / relaunch don't reset them)

    private static let stopwatchKey = "board.stopwatch.v1"
    private(set) var stopwatches: [String: BoardStopwatchState] = {
        guard let data = UserDefaults.standard.data(forKey: BoardStore.stopwatchKey),
              let saved = try? JSONDecoder().decode([String: BoardStopwatchState].self, from: data) else { return [:] }
        return saved
    }()

    func stopwatch(_ id: String) -> BoardStopwatchState { stopwatches[id] ?? BoardStopwatchState() }

    func setStopwatch(_ id: String, _ state: BoardStopwatchState) {
        stopwatches[id] = state
        // Drop state for widgets that no longer exist.
        let live = Set(layout.pages.flatMap(\.widgets).map(\.id))
        stopwatches = stopwatches.filter { entry in
            let base = entry.key.hasPrefix("focus.") ? String(entry.key.dropFirst(6)) : entry.key
            return live.contains(base) || entry.key == id
        }
        if let data = try? JSONEncoder().encode(stopwatches) { UserDefaults.standard.set(data, forKey: Self.stopwatchKey) }
    }

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

    /// Speed: every Board render (and every frame of an edit-mode drag) re-packed every page, inserting
    /// `[Int]` arrays into a Set per occupied cell. The packing only depends on widget order and sizes, so it's
    /// memoised on exactly that (one entry per page id/order/size signature, small bounded cache).
    nonisolated(unsafe) private static var memo: [[String]: (slots: [String: Slot], rows: Int)] = [:]
    static func packCached(_ widgets: [BoardWidget], columns: Int = 4) -> (slots: [String: Slot], rows: Int) {
        let key = widgets.map { "\($0.id):\($0.size.span.0)x\($0.size.span.1)" } + ["c\(columns)"]
        if let hit = memo[key] { return hit }
        let result = ModulaSignpost.measure("BoardPack") { pack(widgets, columns: columns) }
        if memo.count > 24 { memo.removeAll() }
        memo[key] = result
        return result
    }

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
//
// Every face is laid out on a fixed design canvas (iOS-like point sizes) and scaled to the
// tile, so the grid, the gallery preview, the settings preview and Home's rail all show the
// same layout with nothing clipped. Faces read AppEnvironment as optional: a face rendered
// outside the shell (previews, drag lifts) must never trap on a missing environment object.

enum BoardMetrics {
    static let unit: CGFloat = 80
    static let gap: CGFloat = 14
    static let padding: CGFloat = 16
    static let radius: CGFloat = 22

    static func canvas(_ size: BoardWidgetSize) -> CGSize {
        let (w, h) = size.span
        let width = CGFloat(w) * unit + CGFloat(w - 1) * gap
        let height = CGFloat(h) * unit + CGFloat(h - 1) * gap
        return CGSize(width: width, height: height)
    }
}

/// Layout family for a size: what each face designs for.
enum BoardFamily {
    case inline, round, square, wide, big, tall
    init(_ size: BoardWidgetSize) {
        switch size {
        case .pill: self = .inline
        case .circle: self = .round
        case .small: self = .square
        case .medium: self = .wide
        case .large, .extraLarge: self = .big
        case .tall: self = .tall
        }
    }
}

/// Tile outline: continuous rounded rect, circle or capsule.
struct BoardTileShape: Shape {
    let size: BoardWidgetSize
    var radius: CGFloat = BoardMetrics.radius

    func path(in rect: CGRect) -> Path {
        switch size {
        case .circle: Circle().path(in: rect)
        case .pill: Capsule(style: .continuous).path(in: rect)
        default: RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }
}

/// The glass tile around a face. Lays the face out on its design canvas and scales it to fit.
struct BoardWidgetChrome<Content: View>: View {
    let size: BoardWidgetSize
    var tint: String = "glass"
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let canvas = BoardMetrics.canvas(size)
            let scale = max(0.05, min(geo.size.width / canvas.width, geo.size.height / canvas.height))
            let fitted = CGSize(width: canvas.width * scale, height: canvas.height * scale)
            let shape = BoardTileShape(size: size, radius: BoardMetrics.radius * scale)
            content
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(scale)
                .frame(width: fitted.width, height: fitted.height)
                .background { BoardTint(rawValue: tint)?.fill }
                .clipShape(shape)
                .modulaGlass(in: shape, interactive: false)
                .overlay(shape.boardHairline(Color.white.opacity(0.14), lineWidth: 0.7))
                .contentShape(shape)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private extension Shape {
    func boardHairline(_ color: Color, lineWidth: CGFloat) -> some View {
        stroke(color, lineWidth: lineWidth).padding(lineWidth / 2)
    }
}

/// Small caps-style header used by every face.
struct BoardFaceHeader: View {
    let title: String
    let symbol: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// One widget's face.
struct BoardWidgetView: View {
    let widget: BoardWidget
    var kind: BoardWidgetKind? = nil
    @Environment(AppEnvironment.self) private var app: AppEnvironment?

    private var shownKind: BoardWidgetKind { kind ?? widget.kind }
    private var size: BoardWidgetSize { widget.size }
    private var family: BoardFamily { BoardFamily(size) }

    var body: some View {
        Group {
            switch shownKind {
            case .clock: BoardClockFace(style: widget.setting("style", "analog"), size: size, showsSeconds: widget.setting("seconds", "on") == "on")
            case .worldClock: BoardWorldClock(size: size, zones: widget.setting("zones", "Europe/London,America/New_York,Asia/Tokyo"))
            case .activity: BoardActivityFace(size: size)
            case .today: BoardTodayFace(size: size)
            case .notes: BoardNotesFace(size: size, text: widget.setting("text", ""))
            case .battery: BoardBatteryFace(size: size)
            case .moliboo: BoardMolibooFace(size: size)
            case .messages: BoardMessagesFace(size: size)
            case .streak: BoardStreakFace(size: size)
            case .quickActions: BoardQuickActions(size: size)
            case .modules: BoardModulesFace(size: size)
            case .countdown: BoardCountdownFace(size: size, title: widget.setting("title", "Weekend"), target: widget.setting("date", ""))
            case .stopwatch: BoardStopwatchFace(size: size, widgetID: widget.id)
            case .callsFavourites: BoardFavouritesFace(size: size)
            case .connectNumber: BoardConnectFace(size: size)
            case .focus: BoardFocusFace(size: size, widgetID: widget.id, minutes: Int(widget.setting("minutes", "25")) ?? 25)
            case .decide: BoardDecideFace(size: size, mode: widget.setting("mode", "coin"))
            case .quote: BoardQuoteFace(size: size)
            case .breathe: BoardBreatheFace(size: size)
            case .water: BoardWaterFace(size: size, widgetID: widget.id, goal: Int(widget.setting("goal", "8")) ?? 8)
            case .yearProgress: BoardYearFace(size: size)
            case .habit: BoardHabitFace(size: size, widgetID: widget.id, title: widget.setting("title", "Read 10 pages"))
            case .calculator: BoardCalculatorFace(size: size)
            case .converter: BoardConverterFace(size: size, category: widget.setting("category", "length"))
            case .photoFrame: BoardPhotoFrameFace(size: size, widgetID: widget.id)
            case .weather, .nowPlaying, .photos: BoardGatedFace(kind: shownKind, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Big number + caption, shared by streak / modules / unread at compact sizes.
struct BoardMetricFace: View {
    let size: BoardWidgetSize
    let value: String
    let label: String
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        switch BoardFamily(size) {
        case .inline:
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        case .round:
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(24)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(value).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(BoardMetrics.padding)
        }
    }
}

// MARK: Clock

struct BoardClockFace: View {
    let style: String
    let size: BoardWidgetSize
    var showsSeconds = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: showsSeconds ? 1 : 30)) { ctx in
            let now = ctx.date
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    BoardAnalogClock(date: now, showsSeconds: false).frame(width: 52, height: 52)
                    Text(now, format: .dateTime.hour().minute()).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer(minLength: 0)
                    Text(now, format: .dateTime.weekday(.abbreviated).day()).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            case .wide:
                HStack(spacing: 18) {
                    BoardAnalogClock(date: now, showsSeconds: showsSeconds).frame(width: 142, height: 142)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(now, format: .dateTime.weekday(.wide)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        Text(now, format: .dateTime.hour().minute()).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(now, format: .dateTime.day().month(.wide)).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(BoardMetrics.padding)
            default:
                if style == "digital" {
                    VStack(spacing: 2) {
                        Text(now, format: .dateTime.weekday(.wide)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        Text(now, format: .dateTime.hour().minute()).font(.system(size: size == .small || size == .circle ? 46 : 86, weight: .semibold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        if showsSeconds {
                            Text(now, format: .dateTime.second(.twoDigits)).font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .padding(BoardMetrics.padding)
                } else {
                    BoardAnalogClock(date: now, showsSeconds: showsSeconds).padding(size == .circle ? 10 : 14)
                }
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
        Canvas { ctx, canvasSize in
            let r = min(canvasSize.width, canvasSize.height) / 2
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.92)))
            for i in 0..<60 {
                let a = Double(i) / 60 * 2 * .pi
                let major = i % 5 == 0
                let inner = r * (major ? 0.82 : 0.88)
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * inner, y: c.y - cos(a) * inner))
                p.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.93, y: c.y - cos(a) * r * 0.93))
                ctx.stroke(p, with: .color(.black.opacity(major ? 0.85 : 0.3)), style: StrokeStyle(lineWidth: major ? r * 0.035 : r * 0.012, lineCap: .round))
            }
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let s = Double(comps.second ?? 0)
            let m = Double(comps.minute ?? 0) + s / 60
            let h = Double((comps.hour ?? 0) % 12) + m / 60
            func hand(_ fraction: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
                let a = fraction * 2 * .pi
                var p = Path()
                p.move(to: CGPoint(x: c.x - sin(a) * r * 0.08, y: c.y + cos(a) * r * 0.08))
                p.addLine(to: CGPoint(x: c.x + sin(a) * length, y: c.y - cos(a) * length))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(h / 12, r * 0.5, r * 0.07, .black)
            hand(m / 60, r * 0.74, r * 0.05, .black)
            if showsSeconds { hand(s / 60, r * 0.82, r * 0.018, .orange) }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.05, y: c.y - r * 0.05, width: r * 0.1, height: r * 0.1)), with: .color(showsSeconds ? .orange : .black))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct BoardWorldClock: View {
    let size: BoardWidgetSize
    let zones: String

    private var cities: [TimeZone] {
        let ids = zones.split(separator: ",").map(String.init).compactMap(TimeZone.init(identifier:))
        return ids.isEmpty ? [TimeZone.current] : ids
    }

    static func city(_ tz: TimeZone) -> String {
        (tz.identifier.split(separator: "/").last.map(String.init) ?? tz.identifier).replacingOccurrences(of: "_", with: " ")
    }

    static func offset(_ tz: TimeZone, at date: Date) -> String {
        let diff = (tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        return diff == 0 ? "Local" : (diff > 0 ? "+\(diff)h" : "\(diff)h")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 18) {
                    ForEach(cities.prefix(3), id: \.identifier) { tz in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.city(tz)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                            Text(time(now, tz)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
            case .wide:
                HStack(spacing: 10) {
                    ForEach(cities.prefix(4), id: \.identifier) { tz in
                        VStack(spacing: 6) {
                            BoardAnalogClock(date: shifted(now, tz), showsSeconds: false).frame(width: 64, height: 64)
                            Text(Self.city(tz)).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(Self.offset(tz, at: now)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(BoardMetrics.padding)
            case .round, .square:
                VStack(alignment: .leading, spacing: 8) {
                    BoardFaceHeader(title: "World", symbol: "globe")
                    ForEach(cities.prefix(size == .circle ? 2 : 3), id: \.identifier) { tz in
                        HStack {
                            Text(Self.city(tz)).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            Text(time(now, tz)).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(size == .circle ? 30 : BoardMetrics.padding)
            case .big, .tall:
                VStack(alignment: .leading, spacing: 12) {
                    BoardFaceHeader(title: "World Clock", symbol: "globe")
                    ForEach(cities.prefix(6), id: \.identifier) { tz in
                        HStack(spacing: 12) {
                            BoardAnalogClock(date: shifted(now, tz), showsSeconds: false).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Self.city(tz)).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                Text(Self.offset(tz, at: now)).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(time(now, tz)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(BoardMetrics.padding)
            }
        }
    }

    private func time(_ date: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = tz
        return date.formatted(style)
    }

    /// The analog dial uses the device calendar, so shift the instant by the zone difference.
    private func shifted(_ date: Date, _ tz: TimeZone) -> Date {
        date.addingTimeInterval(TimeInterval(tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)))
    }
}

// MARK: Activity / streak

struct BoardActivityFace: View {
    let size: BoardWidgetSize
    private let goal = 30

    var body: some View {
        let store = BoardStore.shared
        let today = store.minutesToday()
        let week = (0..<7).reversed().map { store.minutes(daysAgo: $0) }
        let peak = max(goal, week.max() ?? 1)
        let progress = min(1, Double(today) / Double(goal))
        Group {
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    ring(progress, line: 7).frame(width: 40, height: 40)
                    Text("\(today)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("min today").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    bars(week, peak: peak, height: 30, width: 6)
                }
                .padding(.horizontal, 24)
            case .round:
                ZStack {
                    ring(progress, line: 12)
                    VStack(spacing: 0) {
                        Text("\(today)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("min").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            case .square:
                VStack(alignment: .leading, spacing: 6) {
                    BoardFaceHeader(title: "Activity", symbol: "chart.bar.fill")
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(today)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("min").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    bars(week, peak: peak, height: 34, width: 10)
                }
                .padding(BoardMetrics.padding)
            case .wide, .big, .tall:
                VStack(alignment: .leading, spacing: 10) {
                    BoardFaceHeader(title: "Activity", symbol: "chart.bar.fill", trailing: "Goal \(goal) min")
                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(today)").font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("minutes today").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        ring(progress, line: 10).frame(width: 74, height: 74)
                    }
                    Spacer(minLength: 0)
                    bars(week, peak: peak, height: size == .medium ? 34 : 120, width: size == .tall ? 12 : 22, labelled: true)
                    if size == .large || size == .extraLarge || size == .tall {
                        HStack {
                            stat("Week", "\(week.reduce(0, +)) min")
                            Spacer()
                            stat("Average", "\(week.reduce(0, +) / 7) min")
                            Spacer()
                            stat("Streak", "\(store.streak) d")
                        }
                    }
                }
                .padding(BoardMetrics.padding)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity: \(today) minutes in Modula today")
    }

    private func ring(_ progress: Double, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: max(0.02, progress))
                .stroke(Color.green, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func bars(_ values: [Int], peak: Int, height: CGFloat, width: CGFloat, labelled: Bool = false) -> some View {
        let cal = Calendar.current
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: 3) {
                    Capsule()
                        .fill(i == values.count - 1 ? Color.green : Color.primary.opacity(0.35))
                        .frame(width: width, height: max(4, height * CGFloat(values[i]) / CGFloat(max(peak, 1))))
                        .frame(height: height, alignment: .bottom)
                    if labelled {
                        let day = cal.date(byAdding: .day, value: i - (values.count - 1), to: Date()) ?? Date()
                        Text(day, format: .dateTime.weekday(.narrow)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: labelled ? .infinity : nil)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }
}

struct BoardStreakFace: View {
    let size: BoardWidgetSize
    var body: some View {
        let streak = max(BoardStore.shared.streak, MascotProgressStore.shared.streak)
        switch BoardFamily(size) {
        case .wide, .big, .tall:
            VStack(alignment: .leading, spacing: 12) {
                BoardFaceHeader(title: "Streak", symbol: "flame.fill")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(streak)").font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(streak == 1 ? "day" : "days").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        let lit = (6 - i) < streak
                        let day = Calendar.current.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
                        VStack(spacing: 4) {
                            Image(systemName: lit ? "flame.fill" : "circle").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(lit ? Color.orange : Color.primary.opacity(0.25))
                            Text(day, format: .dateTime.weekday(.narrow)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(BoardMetrics.padding)
        default:
            BoardMetricFace(size: size, value: "\(streak)", label: streak == 1 ? "day streak" : "day streak", symbol: "flame.fill", tint: .orange)
        }
    }
}

// MARK: Today

struct BoardTodayFace: View {
    let size: BoardWidgetSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let cal = Calendar.current
            let progress = now.timeIntervalSince(cal.startOfDay(for: now)) / 86_400
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 10) {
                    Text(now, format: .dateTime.weekday(.wide)).font(.system(size: 17, weight: .semibold)).foregroundStyle(.red)
                    Text(now, format: .dateTime.day().month(.wide)).font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("\(Int(progress * 100))%").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 24)
            case .round:
                VStack(spacing: 0) {
                    Text(now, format: .dateTime.weekday(.abbreviated)).font(.system(size: 15, weight: .bold)).foregroundStyle(.red).textCase(.uppercase)
                    Text(now, format: .dateTime.day()).font(.system(size: 64, weight: .light, design: .rounded))
                }
            case .square:
                VStack(alignment: .leading, spacing: 0) {
                    Text(now, format: .dateTime.weekday(.wide)).font(.system(size: 13, weight: .bold)).foregroundStyle(.red).textCase(.uppercase)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(now, format: .dateTime.day()).font(.system(size: 56, weight: .light, design: .rounded))
                        .lineLimit(1).padding(.top, -2)
                    Text(now, format: .dateTime.month(.wide)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ProgressView(value: progress).tint(.primary)
                    Text("\(Int(progress * 100))% of today").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BoardMetrics.padding)
            case .wide:
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(now, format: .dateTime.weekday(.wide)).font(.system(size: 13, weight: .bold)).foregroundStyle(.red).textCase(.uppercase)
                        Text(now, format: .dateTime.day()).font(.system(size: 56, weight: .light, design: .rounded))
                        Text(now, format: .dateTime.month(.wide)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        weekStrip(now)
                        Spacer(minLength: 0)
                        ProgressView(value: progress).tint(.primary)
                        Text("\(Int(progress * 100))% of today · week \(cal.component(.weekOfYear, from: now))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(BoardMetrics.padding)
            case .big, .tall:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(now, format: .dateTime.month(.wide)).font(.system(size: 17, weight: .bold)).foregroundStyle(.red)
                        Spacer(minLength: 0)
                        Text(now, format: .dateTime.weekday(.wide).day()).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    monthGrid(now, compact: size == .tall)
                    Spacer(minLength: 0)
                    ProgressView(value: progress).tint(.primary)
                    Text("\(Int(progress * 100))% of today").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(BoardMetrics.padding)
            }
        }
    }

    private func weekStrip(_ now: Date) -> some View {
        let cal = Calendar.current
        return HStack(spacing: 2) {
            ForEach(-3...3, id: \.self) { offset in
                let d = cal.date(byAdding: .day, value: offset, to: now) ?? now
                VStack(spacing: 3) {
                    Text(d, format: .dateTime.weekday(.narrow)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(d, format: .dateTime.day()).font(.system(size: 14, weight: offset == 0 ? .bold : .regular, design: .rounded))
                        .foregroundStyle(offset == 0 ? Color.white : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(offset == 0 ? Color.red : .clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(_ now: Date, compact: Bool) -> some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let today = cal.component(.day, from: now)
        let cells: [Int] = Array(repeating: 0, count: lead) + Array(1...days)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return VStack(spacing: compact ? 4 : 6) {
            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: compact ? 4 : 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    Text(day == 0 ? "" : "\(day)")
                        .font(.system(size: compact ? 11 : 14, weight: day == today ? .bold : .regular, design: .rounded))
                        .foregroundStyle(day == today ? Color.white : Color.primary)
                        .frame(width: compact ? 20 : 30, height: compact ? 20 : 30)
                        .background(Circle().fill(day == today ? Color.red : .clear))
                }
            }
        }
    }
}

// MARK: Notes / Moliboo / Connect / gated

struct BoardNotesFace: View {
    let size: BoardWidgetSize
    let text: String

    var body: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = empty ? "Tap Edit, then this note, to write something." : text
        VStack(alignment: .leading, spacing: 8) {
            BoardFaceHeader(title: "Note", symbol: "note.text")
            Text(shown)
                .font(.system(size: size == .small ? 15 : 17, weight: empty ? .regular : .medium))
                .foregroundStyle(empty ? .secondary : .primary)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(size == .circle ? 30 : BoardMetrics.padding)
        .background(alignment: .top) {
            LinearGradient(colors: [Color.yellow.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

struct BoardMolibooFace: View {
    let size: BoardWidgetSize
    @State private var pets = 0
    @State private var bounce = false
    @State private var reaction: String?
    private static let reactions = ["Hehe!", "More pats!", "♥", "Yay!", "That tickles!", "Best day!"]

    var body: some View {
        face
            .scaleEffect(bounce ? 1.08 : 1, anchor: .bottom)
            .animation(.spring(response: 0.22, dampingFraction: 0.42), value: bounce)
            .overlay(alignment: .top) {
                if let reaction {
                    Text(reaction)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                        .foregroundStyle(.black)
                        .padding(.top, 10)
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                        .id(reaction + "\(pets)")
                }
            }
            .contentShape(Rectangle())
            // Pet Moliboo: a 2D bounce, a haptic and a little speech bubble.
            .onTapGesture {
                pets += 1
                bounce = true
                HapticEngine.shared.play(.lightImpact)
                let line = Self.reactions.randomElement() ?? "♥"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { reaction = line }
                let count = pets
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    bounce = false
                    try? await Task.sleep(for: .milliseconds(1000))
                    if pets == count { withAnimation(.easeOut(duration: 0.25)) { reaction = nil } }
                }
            }
            .accessibilityAction(named: "Pet Moliboo") { pets += 1; HapticEngine.shared.play(.lightImpact) }
    }

    @ViewBuilder
    private var face: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let line = HomeMolibooGreeting.mood(hour: hour, streak: MascotProgressStore.shared.streak)
        switch BoardFamily(size) {
        case .round, .inline:
            MolibooEmptyArt(mood: .happy, size: size == .pill ? 52 : 92)
        case .square:
            VStack(spacing: 6) {
                MolibooEmptyArt(mood: .happy, size: 84)
                Text(line).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .padding(BoardMetrics.padding)
        case .wide:
            HStack(spacing: 14) {
                MolibooEmptyArt(mood: .happy, size: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Moliboo").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Text(line).font(.system(size: 17, weight: .semibold)).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(BoardMetrics.padding)
        case .big, .tall:
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                MolibooEmptyArt(mood: .happy, size: 150)
                Text(line).font(.system(size: 19, weight: .semibold)).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                Text("\(MascotProgressStore.shared.streak)-day streak").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(BoardMetrics.padding)
        }
    }
}

struct BoardConnectFace: View {
    let size: BoardWidgetSize
    var body: some View {
        let raw = ModulaNumberStore.shared.number
        let shown = raw.count > 4 ? String(raw.prefix(4)) + " " + String(raw.dropFirst(4)) : raw
        switch BoardFamily(size) {
        case .inline:
            HStack(spacing: 12) {
                ModulaConnectMark(size: 34, animated: false)
                Text(shown.isEmpty ? "Modula Number" : shown).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
        case .round:
            VStack(spacing: 6) {
                ModulaConnectMark(size: 48, animated: false)
                Text("Connect").font(.system(size: 14, weight: .semibold))
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                ModulaConnectMark(size: 36, animated: false)
                Spacer(minLength: 0)
                Text("Modula Number").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Text(shown.isEmpty ? "Get yours" : shown).font(.system(size: size == .small ? 24 : 32, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(BoardMetrics.padding)
        }
    }
}

struct BoardGatedFace: View {
    let kind: BoardWidgetKind
    let size: BoardWidgetSize
    var body: some View {
        Group {
            if size == .pill {
                HStack(spacing: 10) {
                    Image(systemName: kind.symbol).font(.system(size: 20, weight: .semibold))
                    Text(kind.title).font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("Coming soon").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: kind.symbol).font(.system(size: size == .small || size == .circle ? 30 : 44, weight: .semibold))
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                    Text(kind.title).font(.system(size: 16, weight: .semibold))
                    Text("Coming soon").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(BoardMetrics.padding)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title), coming soon")
    }
}

// MARK: Battery

struct BoardBatteryFace: View {
    let size: BoardWidgetSize
    @State private var level: Float = UIDevice.current.batteryLevel
    @State private var charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

    var body: some View {
        let pct = level < 0 ? nil : Int(level * 100)
        let tint: Color = pct.map { $0 <= 20 } == true ? .red : .green
        Group {
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    Image(systemName: charging ? "bolt.fill" : "iphone").font(.system(size: 18, weight: .semibold))
                    Capsule().fill(Color.primary.opacity(0.14)).frame(height: 12)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * CGFloat(max(0.03, level))) }
                        }
                    Text(pct.map { "\($0)%" } ?? "—").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .padding(.horizontal, 24)
            case .round, .square:
                ring(pct, tint: tint, line: 10, font: 26).padding(size == .circle ? 22 : 26)
            case .wide, .big, .tall:
                HStack(spacing: 20) {
                    ring(pct, tint: tint, line: 12, font: 30).frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iPhone").font(.system(size: 17, weight: .semibold))
                        Text(charging ? "Charging" : (pct.map { $0 <= 20 } == true ? "Low battery" : "On battery"))
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(BoardMetrics.padding)
            }
        }
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

    private func ring(_ pct: Int?, tint: Color, line: CGFloat, font: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(max(0, level)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: level)
            VStack(spacing: 2) {
                Image(systemName: charging ? "bolt.fill" : "iphone").font(.system(size: 16, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: charging)
                Text(pct.map { "\($0)%" } ?? "—").font(.system(size: font, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: App-backed faces (AppEnvironment optional)

struct BoardMessagesFace: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app: AppEnvironment?

    var body: some View {
        let unread = app?.messaging.accountUnreadCount ?? 0
        let all = app?.messaging.visibleConversations ?? []
        switch BoardFamily(size) {
        case .inline, .round, .square:
            BoardMetricFace(size: size, value: "\(unread)", label: unread == 1 ? "unread chat" : "unread chats", symbol: "bubble.left.and.bubble.right.fill")
        case .wide, .big, .tall:
            let recent = Array(all.prefix(size == .medium ? 2 : 6))
            VStack(alignment: .leading, spacing: 10) {
                BoardFaceHeader(title: "Messages", symbol: "bubble.left.and.bubble.right.fill", trailing: unread > 0 ? "\(unread) unread" : nil)
                if recent.isEmpty {
                    Spacer(minLength: 0)
                    HStack { Spacer(); Label("All caught up", systemImage: "checkmark.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary); Spacer() }
                    Spacer(minLength: 0)
                } else {
                    ForEach(recent) { c in
                        HStack(spacing: 10) {
                            let p = c.participants.first
                            ModulaAvatar(initials: p?.initials ?? "?", url: p?.avatarURL, size: 36, name: c.title)
                            Text(c.title).font(.system(size: 15, weight: c.isUnread ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                            if c.isUnread { Circle().fill(Color.primary).frame(width: 8, height: 8) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(BoardMetrics.padding)
        }
    }
}

struct BoardModulesFace: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app: AppEnvironment?

    var body: some View {
        let ids = app?.catalogue.installedIDs ?? []
        let products = (app?.catalogue.products ?? []).filter { ids.contains($0.moduleId) }
        switch BoardFamily(size) {
        case .inline, .round, .square:
            BoardMetricFace(size: size, value: "\(ids.count)", label: ids.count == 1 ? "module" : "modules", symbol: "shippingbox.fill")
        case .wide, .big, .tall:
            VStack(alignment: .leading, spacing: 12) {
                BoardFaceHeader(title: "Modules", symbol: "shippingbox.fill", trailing: "\(ids.count) installed")
                if products.isEmpty {
                    Spacer(minLength: 0)
                    Text("Install modules from Product Hub.").font(.system(size: 15)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(products.prefix(size == .medium ? 4 : 12)) { product in
                            Button {
                                app?.navigation.open(.module(product.moduleId, localPath: nil))
                                HapticEngine.shared.play(.navigation)
                            } label: {
                                VStack(spacing: 4) {
                                    ProductArtwork(product: product, size: 52)
                                    Text(product.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(BoardMetrics.padding)
        }
    }
}

struct BoardQuickActions: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app: AppEnvironment?

    private static let all: [(String, String, AppRoute)] = [
        ("Write", "square.and.pencil", .compose(.post)), ("Search", "magnifyingglass", .search(.root(nil))),
        ("Chats", "bubble.left.and.bubble.right", .messages(.inbox)), ("Calls", "phone", .messages(.calls)),
        ("Saved", "bookmark", .saved(.root)), ("Drafts", "doc.text", .drafts(.root)),
        ("Reels", "play.rectangle", .reels(.feed)), ("Settings", "gearshape", .settings(.root))
    ]

    var body: some View {
        switch BoardFamily(size) {
        case .inline:
            HStack(spacing: 0) {
                ForEach(Self.all.prefix(4), id: \.0) { item in button(item, diameter: 50, labelled: false).frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 14)
        case .round, .square:
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Self.all.prefix(4), id: \.0) { item in button(item, diameter: 60, labelled: false) }
            }
            .padding(size == .circle ? 26 : BoardMetrics.padding)
        case .wide:
            VStack(alignment: .leading, spacing: 14) {
                BoardFaceHeader(title: "Quick Actions", symbol: "bolt.fill")
                HStack(spacing: 0) {
                    ForEach(Self.all.prefix(4), id: \.0) { item in button(item, diameter: 52, labelled: true).frame(maxWidth: .infinity) }
                }
                Spacer(minLength: 0)
            }
            .padding(BoardMetrics.padding)
        case .big, .tall:
            VStack(alignment: .leading, spacing: 16) {
                BoardFaceHeader(title: "Quick Actions", symbol: "bolt.fill")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: size == .tall ? 2 : 4), spacing: 18) {
                    ForEach(Self.all, id: \.0) { item in button(item, diameter: 56, labelled: true) }
                }
                Spacer(minLength: 0)
            }
            .padding(BoardMetrics.padding)
        }
    }

    private func button(_ item: (String, String, AppRoute), diameter: CGFloat, labelled: Bool) -> some View {
        Button {
            HapticEngine.shared.play(.navigation)
            app?.navigation.push(item.2)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.1).font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(Color.modulaOnPrimary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Color.modulaPrimaryFill))
                if labelled {
                    Text(item.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .accessibilityLabel(item.0)
    }
}

struct BoardFavouritesFace: View {
    let size: BoardWidgetSize
    @Environment(AppEnvironment.self) private var app: AppEnvironment?

    var body: some View {
        let favs: [CallsContact] = app.map { app in app.calls.favourites.compactMap { CallsDirectory.contact(forConversation: $0, app: app) } } ?? []
        let family = BoardFamily(size)
        let limit = family == .inline ? 4 : (family == .square || family == .round ? 4 : (family == .wide ? 4 : 8))
        let shown = Array(favs.prefix(limit))
        Group {
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "star.circle.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.yellow)
                    Text("No favourites").font(.system(size: 15, weight: .semibold))
                    if family != .inline {
                        Text("Star people in Calls").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .padding(BoardMetrics.padding)
            } else {
                switch family {
                case .inline:
                    HStack(spacing: 0) { ForEach(shown) { c in avatar(c, 50, labelled: false).frame(maxWidth: .infinity) } }
                        .padding(.horizontal, 14)
                case .round, .square:
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(shown) { c in avatar(c, 60, labelled: false) }
                    }
                    .padding(size == .circle ? 26 : BoardMetrics.padding)
                case .wide, .big, .tall:
                    VStack(alignment: .leading, spacing: 14) {
                        BoardFaceHeader(title: "Favourites", symbol: "star.fill")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: size == .tall ? 2 : 4), spacing: 16) {
                            ForEach(shown) { c in avatar(c, 56, labelled: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(BoardMetrics.padding)
                }
            }
        }
    }

    private func avatar(_ c: CallsContact, _ d: CGFloat, labelled: Bool) -> some View {
        Button {
            if let app, let id = c.conversationID { CallsActions.call(id, kind: .audio, app: app) }
        } label: {
            VStack(spacing: 5) {
                ModulaAvatar(initials: c.initials, url: c.avatarURL, size: d, name: c.name)
                if labelled { Text(c.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7) }
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: .selection))
        .accessibilityLabel("Call \(c.name)")
    }
}

// MARK: Countdown / stopwatch

struct BoardCountdownFace: View {
    let size: BoardWidgetSize
    let title: String
    let target: String

    private var targetDate: Date {
        if let d = BoardISO.date(target) { return d }
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? Date()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let cal = Calendar.current
            let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: ctx.date), to: cal.startOfDay(for: targetDate)).day ?? 0)
            let unit = days == 1 ? "day" : "days"
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 10) {
                    Image(systemName: "hourglass").font(.system(size: 18, weight: .semibold))
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("\(days)").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            case .round:
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 30)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    BoardFaceHeader(title: title, symbol: "hourglass")
                    Spacer(minLength: 0)
                    Text("\(days)").font(.system(size: size == .small ? 56 : 72, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(unit) to go").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    Text(targetDate, format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(BoardMetrics.padding)
            }
        }
    }
}

struct BoardStopwatchFace: View {
    let size: BoardWidgetSize
    var widgetID: String = ""
    private var state: BoardStopwatchState { BoardStore.shared.stopwatch(widgetID) }
    private var started: Date? { state.started }
    private var laps: [TimeInterval] { state.laps }

    private func update(_ change: (inout BoardStopwatchState) -> Void) {
        var next = state
        change(&next)
        withAnimation(.snappy) { BoardStore.shared.setStopwatch(widgetID, next) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: started == nil ? 60 : 0.1)) { ctx in
            let total = state.total(at: ctx.date)
            let family = BoardFamily(size)
            Group {
                switch family {
                case .inline:
                    HStack(spacing: 10) {
                        time(total, 30)
                        Spacer(minLength: 0)
                        controls(total, 44)
                    }
                    .padding(.leading, 26).padding(.trailing, 18)
                case .round, .square:
                    VStack(spacing: 12) {
                        time(total, 34)
                        HStack(spacing: 12) { controls(total, 48) }
                    }
                    .padding(BoardMetrics.padding)
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        BoardFaceHeader(title: "Stopwatch", symbol: "stopwatch")
                        HStack {
                            time(total, 46)
                            Spacer(minLength: 0)
                            controls(total, 50)
                        }
                        ForEach(Array(laps.prefix(family == .wide ? 1 : 6).enumerated()), id: \.offset) { i, lap in
                            HStack {
                                Text("Lap \(laps.count - i)").foregroundStyle(.secondary)
                                Spacer()
                                Text(Self.format(lap)).monospacedDigit()
                            }
                            .font(.system(size: 15))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(BoardMetrics.padding)
                }
            }
            .animation(.snappy, value: laps)
        }
    }

    private func time(_ total: TimeInterval, _ font: CGFloat) -> some View {
        Text(Self.format(total)).font(.system(size: font, weight: .semibold, design: .rounded)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private func controls(_ total: TimeInterval, _ d: CGFloat) -> some View {
        Button {
            if started != nil { update { $0.laps.insert(total, at: 0) } } else { update { $0.elapsed = 0; $0.laps = [] } }
            HapticEngine.shared.play(.selection)
        } label: {
            Image(systemName: started != nil ? "flag.fill" : "arrow.counterclockwise").font(.system(size: d * 0.36, weight: .semibold))
                .frame(width: d, height: d).background(Circle().fill(Color.primary.opacity(0.14)))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .accessibilityLabel(started != nil ? "Lap" : "Reset")
        Button { toggle() } label: {
            Image(systemName: started == nil ? "play.fill" : "pause.fill").font(.system(size: d * 0.38, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: d, height: d)
                .background(Circle().fill(Color.modulaPrimaryFill)).foregroundStyle(Color.modulaOnPrimary)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: .selection))
        .accessibilityLabel(started == nil ? "Start" : "Pause")
    }

    private func toggle() {
        update { st in
            if let s = st.started { st.elapsed += Date().timeIntervalSince(s); st.started = nil } else { st.started = Date() }
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let cs = Int(t * 10) % 10, s = Int(t) % 60, m = Int(t) / 60
        return String(format: "%02d:%02d.%d", m, s, cs)
    }
}

// MARK: Board screen

struct BoardView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var systemScheme
    private var store: BoardStore { BoardStore.shared }
    @State private var editing = false
    // Reopens on the page you last looked at.
    @AppStorage("board.lastPage") private var page = 0
    @State private var showsGallery = false
    @State private var configuringID: BoardConfigTarget?
    @State private var renaming = false
    @State private var pageName = ""
    // Custom reorder (no system drag preview: it renders outside the app environment).
    @State private var dragID: String?
    @State private var dragOrigin: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var lastSwap = Date.distantPast

    static let gap: CGFloat = 14
    static let labelRoom: CGFloat = 22

    var body: some View {
        let layout = store.layout
        GeometryReader { outer in
            let bottomClearance = outer.safeAreaInsets.bottom + 44
            ZStack {
                BoardWallpaper(name: layout.wallpaper).ignoresSafeArea()
                TabView(selection: $page) {
                    ForEach(Array(layout.pages.enumerated()), id: \.element.id) { index, boardPage in
                        pageView(boardPage, bottomClearance: bottomClearance).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Widgets scroll under the floating glass tab bar (so it reads as glass, not a slab).
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .overlay(alignment: .bottom) {
                if layout.pages.count > 1 { pageDots(count: layout.pages.count).padding(.bottom, 10) }
            }
        }
        .environment(\.colorScheme, layout.wallpaper == "none" ? systemScheme : .dark)
        .navigationTitle(layout.pages.indices.contains(page) ? layout.pages[page].name : "Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showsGallery) { BoardWidgetGallery(page: min(page, max(0, store.layout.pages.count - 1))) }
        .sheet(item: $configuringID) { target in BoardWidgetSettingsSheet(widgetID: target.id) }
        .alert("Rename Page", isPresented: $renaming) {
            TextField("Name", text: $pageName)
            Button("Save") {
                let name = pageName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let index = page
                store.mutate { layout in
                    guard layout.pages.indices.contains(index) else { return }
                    layout.pages[index].name = String(name.prefix(24))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: page) { _, _ in HapticEngine.shared.play(.selection) }
        .onChange(of: store.layout.pages.count) { _, count in
            if page >= count { page = max(0, count - 1) }
        }
        .onAppear {
            if page >= store.layout.pages.count { page = 0 }
            store.appBecameActive()
        }
        .onChange(of: phase) { _, p in
            if p == .active { store.appBecameActive() } else if p == .background { store.appResigned() }
        }
        .accessibilityIdentifier("board.root")
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == page ? 0.95 : 0.4))
                    .frame(width: i == page ? 18 : 7, height: 7)
                    .onTapGesture { withAnimation(.snappy) { page = i } }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modulaGlass(in: Capsule(), interactive: false)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(count)")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button { stopEditing() } label: {
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
                        dragID = nil
                        page = 0
                        withAnimation(.spring) { store.reset() }
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
        guard !editing else { return }
        HapticEngine.shared.play(.success)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { editing = true }
    }

    private func stopEditing() {
        dragID = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { editing = false }
    }

    private func pageView(_ boardPage: BoardPage, bottomClearance: CGFloat) -> some View {
        GeometryReader { geo in
            let inset = ModulaLayout.contentInset
            let cell = max(40, (geo.size.width - inset * 2 - Self.gap * 3) / 4)
            let widgets = boardPage.widgets
            let packed = BoardGridPacker.packCached(widgets)
            let labelRoom: CGFloat = store.layout.showsLabels ? Self.labelRoom : 0
            let rowHeight = cell + labelRoom / 2
            let frames = Self.frames(packed.slots, cell: cell, rowHeight: rowHeight, labelRoom: labelRoom)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(height: CGFloat(packed.rows) * (rowHeight + Self.gap))
                    ForEach(widgets) { widget in
                        if let frame = frames[widget.id] {
                            let isDragged = dragID == widget.id
                            let origin = isDragged
                                ? CGPoint(x: dragOrigin.x + dragTranslation.width, y: dragOrigin.y + dragTranslation.height)
                                : frame.origin
                            BoardWidgetTile(widget: widget, editing: editing, lifted: isDragged, showsLabel: store.layout.showsLabels,
                                            labelRoom: labelRoom,
                                            onTap: { tapped(widget) },
                                            onRemove: { remove(widget.id) },
                                            onLongPress: { startEditing() },
                                            onDuplicate: { duplicate(widget, page: boardPage.id) },
                                            onEditBoard: { startEditing() })
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: origin.x, y: origin.y)
                                .zIndex(isDragged ? 10 : 0)
                                .highPriorityGesture(reorderGesture(widget.id, frame: frame, frames: frames, pageID: boardPage.id),
                                                     including: editing ? .all : .subviews)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 14)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: widgets)
                if widgets.isEmpty { emptyPage }
                Color.clear.frame(height: bottomClearance)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(dragID != nil)
            .contentShape(Rectangle())
            // Tap empty space to finish editing, like the Home Screen.
            .onTapGesture { if editing && dragID == nil { stopEditing() } }
            .onLongPressGesture(minimumDuration: 0.5) { startEditing() }
        }
    }

    static func frames(_ slots: [String: BoardGridPacker.Slot], cell: CGFloat, rowHeight: CGFloat, labelRoom: CGFloat) -> [String: CGRect] {
        slots.mapValues { slot in
            let w = CGFloat(slot.w) * cell + CGFloat(slot.w - 1) * gap
            let h = CGFloat(slot.h) * rowHeight + CGFloat(slot.h - 1) * gap
            return CGRect(x: CGFloat(slot.x) * (cell + gap), y: CGFloat(slot.y) * (rowHeight + gap), width: w, height: h)
        }
    }

    private func reorderGesture(_ id: String, frame: CGRect, frames: [String: CGRect], pageID: String) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard editing else { return }
                if dragID != id {
                    dragOrigin = frame.origin
                    dragID = id
                    HapticEngine.shared.play(.selection)
                }
                dragTranslation = value.translation
                let center = CGPoint(x: dragOrigin.x + value.translation.width + frame.width / 2,
                                     y: dragOrigin.y + value.translation.height + frame.height / 2)
                guard Date().timeIntervalSince(lastSwap) > 0.22,
                      let target = frames.first(where: { $0.key != id && $0.value.insetBy(dx: 10, dy: 10).contains(center) })?.key else { return }
                lastSwap = Date()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { store.reorder(id, onto: target, page: pageID) }
                HapticEngine.shared.play(.selection)
            }
            .onEnded { _ in
                guard dragID != nil else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    dragID = nil
                    dragTranslation = .zero
                }
            }
    }

    private func duplicate(_ widget: BoardWidget, page pageID: String) {
        var copy = widget
        copy.id = UUID().uuidString
        HapticEngine.shared.play(.success)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            store.mutate { layout in
                guard let p = layout.pages.firstIndex(where: { $0.id == pageID }),
                      let i = layout.pages[p].widgets.firstIndex(where: { $0.id == widget.id }) else { return }
                layout.pages[p].widgets.insert(copy, at: i + 1)
            }
        }
    }

    private func remove(_ id: String) {
        if dragID == id { dragID = nil }
        if configuringID?.id == id { configuringID = nil }
        HapticEngine.shared.play(.warning)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { store.remove(id) }
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
        guard store.widget(widget.id) != nil else { return }
        if editing {
            configuringID = BoardConfigTarget(id: widget.id)
            return
        }
        HapticEngine.shared.play(.navigation)
        switch widget.kind {
        case .messages: app.navigation.push(.messages(.inbox))
        case .callsFavourites: app.navigation.push(.messages(.calls))
        case .modules: app.navigation.push(.productHub(.collection(.installed)))
        case .connectNumber: app.navigation.open(.module(ConnectPreview.moduleID, localPath: nil))
        case .moliboo: app.navigation.push(.settings(.moliboo))
        case .quickActions, .stopwatch, .focus, .decide, .breathe, .water, .habit, .calculator, .converter: break
        default: configuringID = BoardConfigTarget(id: widget.id)
        }
    }
}

/// Sheet item that carries only the id, so the sheet re-reads the live widget (or closes if it's gone).
struct BoardConfigTarget: Identifiable, Hashable { let id: String }

struct BoardWidgetTile: View {
    let widget: BoardWidget
    let editing: Bool
    var lifted = false
    var showsLabel = true
    var labelRoom: CGFloat = 22
    var onTap: () -> Void
    var onRemove: () -> Void
    var onLongPress: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stackIndex = 0
    @State private var stackTouchedAt = Date.distantPast
    @Environment(\.scenePhase) private var tileScenePhase
    var onDuplicate: (() -> Void)? = nil
    var onEditBoard: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            BoardWidgetChrome(size: widget.size, tint: widget.setting("tint", "glass")) {
                if widget.stack.isEmpty {
                    BoardWidgetView(widget: widget)
                } else {
                    let kinds = widget.kinds
                    TabView(selection: $stackIndex) {
                        ForEach(Array(kinds.enumerated()), id: \.offset) { i, kind in
                            BoardWidgetView(widget: widget, kind: kind).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .trailing) {
                        VStack(spacing: 4) {
                            ForEach(kinds.indices, id: \.self) { i in
                                Capsule().fill(Color.primary.opacity(i == stackIndex ? 0.9 : 0.3)).frame(width: 5, height: i == stackIndex ? 14 : 6)
                            }
                        }
                        .padding(.trailing, 7)
                        .animation(.snappy, value: stackIndex)
                    }
                    .onChange(of: kinds.count) { _, count in if stackIndex >= count { stackIndex = 0 } }
                    // Auto-rotate (Edit Widget › Smart Stack): flips every 8 s while visible and not editing; a manual
                    // swipe pauses it for 20 s so it never fights your finger.
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in stackTouchedAt = Date() })
                    .task(id: "\(widget.setting("rotate", "off"))|\(editing)|\(tileScenePhase == .active)|\(kinds.count)") {
                        guard widget.setting("rotate", "off") == "on", !editing, tileScenePhase == .active, kinds.count > 1 else { return }
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(8))
                            guard !Task.isCancelled else { return }
                            if Date().timeIntervalSince(stackTouchedAt) < 20 { continue }
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { stackIndex = (stackIndex + 1) % kinds.count }
                        }
                    }
                }
            }
            .allowsHitTesting(!editing)
            .scaleEffect(lifted ? 1.06 : 1)
            .shadow(color: .black.opacity(lifted ? 0.35 : 0.12), radius: lifted ? 18 : 6, y: lifted ? 10 : 3)
            if showsLabel {
                Text(widget.stack.isEmpty ? widget.kind.title : "Smart Stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: labelRoom - 6)
                    .opacity(lifted ? 0 : 1)
            }
        }
        // Remove badge sits outside the top-left corner, above the content (Home Screen style).
        .overlay(alignment: .topLeading) {
            if editing && !lifted {
                Button(action: onRemove) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(white: 0.92)))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.85, haptic: nil))
                .offset(x: -19, y: -19)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
                .accessibilityLabel("Remove \(widget.kind.title)")
                .accessibilityIdentifier("board.remove.\(widget.kind.rawValue)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .modifier(BoardTileMenu(enabled: !editing, onEdit: onTap, onEditBoard: onEditBoard ?? onLongPress,
                                onDuplicate: onDuplicate, onRemove: onRemove))
        .modifier(BoardJiggle(active: editing && !lifted && !reduceMotion, seed: widget.id, size: widget.size))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(widget.kind.title)
        .accessibilityHint(editing ? "Opens widget settings. Drag to reorder." : "Long-press to edit the Board")
        .accessibilityAction(named: "Remove") { onRemove() }
        .accessibilityIdentifier("board.widget.\(widget.kind.rawValue)")
    }

}

/// iOS-style long-press menu on a widget (off while jiggling so it can't fight the reorder drag).
struct BoardTileMenu: ViewModifier {
    let enabled: Bool
    let onEdit: () -> Void
    let onEditBoard: () -> Void
    let onDuplicate: (() -> Void)?
    let onRemove: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                Button("Edit Widget", systemImage: "info.circle") { onEdit() }
                Button("Edit Board", systemImage: "square.grid.2x2") { onEditBoard() }
                if let onDuplicate { Button("Duplicate", systemImage: "plus.square.on.square") { onDuplicate() } }
                Divider()
                Button("Remove Widget", systemImage: "minus.circle", role: .destructive) { onRemove() }
            }
        } else {
            content
        }
    }
}

/// Home Screen jiggle: a steady ±1.3° rock (≈0.14 s per swing) with a tiny drift, a per-widget
/// phase so neighbours don't move in lockstep, and a short fade in/out. Driven by the frame
/// clock rather than a repeat-forever animation, so it can't leak into other animations
/// (that leak was the "jiggling a lot"). Larger widgets rock less so their corners don't swing.
struct BoardJiggle: ViewModifier {
    let active: Bool
    let seed: String
    let size: BoardWidgetSize
    @State private var since = Date()

    private var phase: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997 * 2 * .pi
    }
    private var amplitude: Double {
        switch size {
        case .small, .circle: 1.4
        case .medium, .pill: 0.9
        case .tall: 0.8
        case .large: 0.6
        case .extraLarge: 0.45
        }
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSince(since)
            let envelope = active ? min(1, t / 0.18) : 0
            let swing = sin(t * 2 * .pi / 0.28 + phase)
            content
                .rotationEffect(.degrees(amplitude * swing * envelope))
                .offset(y: 0.4 * cos(t * 2 * .pi / 0.28 + phase) * envelope)
        }
        .onChange(of: active) { _, on in if on { since = Date() } }
        .onAppear { since = Date() }
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
                        BoardWidgetChrome(size: widget.size, tint: widget.setting("tint", "glass")) { BoardWidgetView(widget: widget) }
                            .frame(width: CGFloat(w) * 78 + CGFloat(w - 1) * 8, height: CGFloat(h) * 70)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: widget)
                        group("Size and shape") {
                            ModulaSegmentedControl(segments: widget.kind.sizes.map { .init(id: $0, title: $0.title) },
                                                   selection: Binding(get: { widget.size }, set: { v in var copy = widget; copy.size = v; store.update(copy) }),
                                                   accessibilityLabel: "Size", identifier: { "board.size.\($0.rawValue)" })
                        }
                        group("Style") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(BoardTint.allCases) { t in
                                        let on = widget.setting("tint", "glass") == t.rawValue
                                        Button {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { set(widget, "tint", t.rawValue) }
                                            HapticEngine.shared.play(.selection)
                                        } label: {
                                            VStack(spacing: 6) {
                                                Circle()
                                                    .fill(t.swatch)
                                                    .frame(width: 40, height: 40)
                                                    .overlay(Circle().stroke(Color.primary.opacity(on ? 0.9 : 0.15), lineWidth: on ? 2.5 : 1).padding(-3))
                                                    .overlay { if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white).transition(.scale.combined(with: .opacity)) } }
                                                Text(t.title).font(.caption2.weight(.semibold)).foregroundStyle(on ? .primary : .secondary)
                                            }
                                            .frame(minWidth: 48)
                                        }
                                        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                                        .accessibilityLabel("\(t.title) style")
                                        .accessibilityAddTraits(on ? .isSelected : [])
                                    }
                                }
                                .padding(.vertical, 4).padding(.horizontal, 2)
                            }
                        }
                        options(widget)
                        group("Smart Stack", footer: "Swipe on the widget to flip between everything in the stack.") {
                            if !widget.stack.isEmpty {
                                Toggle("Rotate automatically", isOn: Binding(get: { widget.setting("rotate", "off") == "on" }, set: { on in
                                    var copy = widget; copy.settings["rotate"] = on ? "on" : "off"; store.update(copy)
                                }))
                                .frame(minHeight: 40)
                                .accessibilityHint("Shows the next widget in the stack every 8 seconds")
                            }
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
                    BoardISO.date(widget.setting("date", "")) ?? Date().addingTimeInterval(86_400 * 7)
                }, set: { d in set(widget, "date", BoardISO.formatter.string(from: d)) }), displayedComponents: .date)
            }
        case .focus:
            group("Focus length") {
                ModulaSegmentedControl(segments: ["10", "25", "45", "60"].map { .init(id: $0, title: "\($0) min") },
                                       selection: binding(widget, "minutes", "25"), accessibilityLabel: "Focus length", identifier: { "board.focus.\($0)" })
            }
        case .water:
            group("Daily goal") {
                ModulaSegmentedControl(segments: ["6", "8", "10", "12"].map { .init(id: $0, title: "\($0) glasses") },
                                       selection: binding(widget, "goal", "8"), accessibilityLabel: "Water goal", identifier: { "board.water.\($0)" })
            }
        case .habit:
            group("Habit") {
                TextField("What do you want to do daily?", text: binding(widget, "title", "Read 10 pages"))
                    .padding(12).modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .converter:
            group("Units") {
                ModulaSegmentedControl(segments: BoardUnitCategory.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                                       selection: binding(widget, "category", "length"), accessibilityLabel: "Unit type", identifier: { "board.converter.\($0)" })
            }
        case .photoFrame:
            group("Photo") {
                BoardPhotoPickerButton(widgetID: widget.id)
            }
        case .decide:
            group("Decide") {
                ModulaSegmentedControl(segments: [.init(id: "coin", title: "Coin"), .init(id: "dice", title: "Dice"), .init(id: "yesno", title: "Yes / No")],
                                       selection: binding(widget, "mode", "coin"), accessibilityLabel: "Decide mode", identifier: { "board.decide.\($0)" })
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
                        BoardWidgetChrome(size: widget.size, tint: widget.setting("tint", "glass")) { BoardWidgetView(widget: widget) }
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


// MARK: - Board extras (3:30 round): tints, Focus, Decide, Quote

/// Per-widget colour wash under the glass (Edit Widget › Style).
enum BoardTint: String, CaseIterable, Identifiable {
    case glass, graphite, ocean, sunset, forest, rose, lavender
    var id: Self { self }
    var title: String { rawValue.capitalized }
    private var colors: [Color] {
        switch self {
        case .glass: [.clear, .clear]
        case .graphite: [Color(white: 0.28), Color(white: 0.08)]
        case .ocean: [Color(red: 0.10, green: 0.45, blue: 0.95), Color(red: 0.02, green: 0.18, blue: 0.45)]
        case .sunset: [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 0.75, green: 0.15, blue: 0.45)]
        case .forest: [Color(red: 0.20, green: 0.65, blue: 0.40), Color(red: 0.03, green: 0.25, blue: 0.18)]
        case .rose: [Color(red: 1.0, green: 0.55, blue: 0.70), Color(red: 0.60, green: 0.15, blue: 0.35)]
        case .lavender: [Color(red: 0.70, green: 0.58, blue: 1.0), Color(red: 0.30, green: 0.18, blue: 0.60)]
        }
    }
    var swatch: AnyShapeStyle {
        self == .glass
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    @ViewBuilder var fill: some View {
        if self != .glass {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.62)
        }
    }
}

/// Focus timer: ring + remaining time. State lives in BoardStore (survives edit mode and relaunch).
struct BoardFocusFace: View {
    let size: BoardWidgetSize
    let widgetID: String
    let minutes: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var key: String { "focus.\(widgetID)" }
    private var state: BoardStopwatchState { BoardStore.shared.stopwatch(key) }
    private var length: TimeInterval { TimeInterval(max(1, minutes) * 60) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: state.started == nil ? 60 : 1)) { ctx in
            let used = min(length, state.total(at: ctx.date))
            let remaining = length - used
            let done = remaining <= 0.5
            let progress = used / length
            Group {
                switch BoardFamily(size) {
                case .inline:
                    HStack(spacing: 12) {
                        ring(progress, done: done, width: 6).frame(width: 40, height: 40)
                        Text(done ? "Done" : Self.format(remaining)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Spacer(minLength: 0)
                        controls(done: done, d: 44)
                    }
                    .padding(.leading, 22).padding(.trailing, 18)
                case .round, .square:
                    ZStack {
                        ring(progress, done: done, width: 10).padding(size == .circle ? 18 : 16)
                        VStack(spacing: 6) {
                            Text(done ? "Done" : Self.format(remaining)).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .lineLimit(1).minimumScaleFactor(0.6)
                            HStack(spacing: 10) { controls(done: done, d: 38) }
                        }
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        BoardFaceHeader(title: "Focus", symbol: "timer", trailing: "\(minutes) min")
                        HStack(spacing: 18) {
                            ring(progress, done: done, width: 12).frame(width: 96, height: 96)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(done ? "Done" : Self.format(remaining)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .contentTransition(.numericText(countsDown: true))
                                Text(done ? "Nice work. Take a break." : state.started == nil ? (used > 0 ? "Paused" : "Ready when you are") : "Stay with it")
                                    .font(.system(size: 14)).foregroundStyle(.secondary)
                                HStack(spacing: 10) { controls(done: done, d: 42) }
                            }
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(BoardMetrics.padding)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: progress)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus timer, \(minutes) minutes")
    }

    private func ring(_ progress: Double, done: Bool, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.14), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(done ? Color.green : Color.primary, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder
    private func controls(done: Bool, d: CGFloat) -> some View {
        let running = state.started != nil && !done
        Button {
            var next = state
            if done { next = BoardStopwatchState() }
            else if let s = next.started { next.elapsed += Date().timeIntervalSince(s); next.started = nil }
            else { next.started = Date() }
            withAnimation(.snappy) { BoardStore.shared.setStopwatch(key, next) }
            HapticEngine.shared.play(running ? .selection : .mediumImpact)
        } label: {
            Image(systemName: done ? "arrow.counterclockwise" : running ? "pause.fill" : "play.fill")
                .font(.system(size: d * 0.38, weight: .bold))
                .foregroundStyle(Color.modulaOnPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: d, height: d)
                .background(Circle().fill(Color.modulaPrimaryFill))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .accessibilityLabel(done ? "Restart" : running ? "Pause" : "Start")
        if !done, state.elapsed > 0 || state.started != nil, size != .circle {
            Button {
                withAnimation(.snappy) { BoardStore.shared.setStopwatch(key, BoardStopwatchState()) }
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: "xmark").font(.system(size: d * 0.32, weight: .bold))
                    .frame(width: d, height: d).background(Circle().fill(Color.primary.opacity(0.14)))
            }
            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
            .accessibilityLabel("Reset")
            .transition(.scale.combined(with: .opacity))
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Coin, die or yes/no: tap to decide (2D flip/tumble; a crossfade under Reduce Motion).
struct BoardDecideFace: View {
    let size: BoardWidgetSize
    let mode: String
    @State private var result: String?
    @State private var spins = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var options: [String] {
        switch mode {
        case "dice": ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]
        case "yesno": ["Yes", "No", "Maybe", "Ask again"]
        default: ["Heads", "Tails"]
        }
    }
    private var title: String { mode == "dice" ? "Roll" : mode == "yesno" ? "Ask" : "Flip" }

    var body: some View {
        Button(action: roll) {
            VStack(spacing: size == .medium ? 10 : 6) {
                if size == .medium { BoardFaceHeader(title: "Decide", symbol: "dice") }
                Spacer(minLength: 0)
                Text(result ?? (mode == "dice" ? "⚅" : mode == "yesno" ? "?" : "🪙"))
                    .font(.system(size: mode == "dice" ? 64 : (result == nil ? 46 : 30), weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(spins) * 360), axis: mode == "coin" ? (x: 1, y: 0, z: 0) : (x: 0, y: 0, z: 1))
                    .id(result ?? "none")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                Text(result == nil ? "Tap to \(title.lowercased())" : "Tap again")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(size == .circle ? 26 : BoardMetrics.padding)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
        .accessibilityLabel(result.map { "Result: \($0). Tap to \(title.lowercased()) again" } ?? "\(title)")
    }

    private func roll() {
        HapticEngine.shared.play(.mediumImpact)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.7)) {
            spins += 1
            result = options.randomElement()
        }
    }
}

/// The quote of the day (same list as the Home quote card).
struct BoardQuoteFace: View {
    let size: BoardWidgetSize
    var body: some View {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        let q = HomeQuoteCard.quotes[day % HomeQuoteCard.quotes.count]
        switch BoardFamily(size) {
        case .inline:
            HStack(spacing: 10) {
                Image(systemName: "quote.opening").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
                Text(q.0).font(.system(size: 15, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
        default:
            VStack(alignment: .leading, spacing: 10) {
                BoardFaceHeader(title: "Quote", symbol: "quote.opening")
                Text(q.0)
                    .font(.system(size: size == .small ? 16 : size == .medium ? 19 : 26, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text("— \(q.1)").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(BoardMetrics.padding)
        }
    }
}


/// 2D breathing guide: tap to start a one-minute in-4 / out-6 session.
struct BoardBreatheFace: View {
    let size: BoardWidgetSize
    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cycle: Double = 10, session: Double = 60

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: startedAt == nil)) { ctx in
            let t = startedAt.map { ctx.date.timeIntervalSince($0) } ?? 0
            let running = startedAt != nil && t < Self.session
            let phase = t.truncatingRemainder(dividingBy: Self.cycle)
            let inhale = phase < 4
            // 0…1 breath depth: up over 4 s, down over 6 s.
            let depth = running ? (inhale ? phase / 4 : 1 - (phase - 4) / 6) : 0.35
            let eased = 0.5 - cos(depth * .pi) / 2
            VStack(spacing: 8) {
                if size == .medium || size == .large { BoardFaceHeader(title: "Breathe", symbol: "wind", trailing: running ? "\(Int(Self.session - t))s" : nil) }
                Spacer(minLength: 0)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.cyan.opacity(0.22 - Double(i) * 0.05))
                            .scaleEffect(reduceMotion ? 0.8 : 0.45 + eased * (0.45 + Double(i) * 0.12))
                    }
                    Circle().fill(Color.cyan.opacity(0.55)).scaleEffect(reduceMotion ? 0.5 : 0.3 + eased * 0.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(running ? (inhale ? "Breathe in" : "Breathe out") : "Tap to breathe")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: inhale)
                Spacer(minLength: 0)
            }
            .padding(size == .circle ? 24 : BoardMetrics.padding)
            .onChange(of: running) { _, now in
                if !now, startedAt != nil { startedAt = nil; HapticEngine.shared.play(.success) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            startedAt = startedAt == nil ? Date() : nil
            HapticEngine.shared.play(.selection)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(startedAt == nil ? "Start a one-minute breathing session" : "Stop breathing session")
    }
}

/// Glasses of water today (on this iPhone; resets at midnight).
struct BoardWaterFace: View {
    let size: BoardWidgetSize
    let widgetID: String
    let goal: Int
    @AppStorage("board.water.v1") private var raw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var today: String { Self.dayKey(Date()) }
    private var count: Int {
        // raw = "<widgetID>|<day>|<count>;…"
        for entry in raw.split(separator: ";") {
            let p = entry.split(separator: "|")
            if p.count == 3, p[0] == widgetID, p[1] == today { return Int(p[2]) ?? 0 }
        }
        return 0
    }

    var body: some View {
        let n = count, progress = min(1, Double(n) / Double(max(1, goal)))
        Group {
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.cyan)
                    Text("\(n)/\(goal)").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText(value: Double(n)))
                    ProgressView(value: progress).tint(.cyan)
                    addButton(36)
                }
                .padding(.horizontal, 20)
            default:
                VStack(spacing: 8) {
                    if size == .medium { BoardFaceHeader(title: "Water", symbol: "drop.fill", trailing: "Goal \(goal)") }
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cyan.opacity(0.12))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                            .scaleEffect(x: 1, y: max(0.02, progress), anchor: .bottom)
                        Text("\(n)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(n)))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: size == .medium ? 90 : nil)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: n)
                    HStack {
                        Text(n >= goal ? "Goal met" : "\(goal - n) to go").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        addButton(32)
                    }
                }
                .padding(size == .circle ? 26 : BoardMetrics.padding)
            }
        }
        .contextMenu {
            Button("Undo One", systemImage: "minus.circle") { set(max(0, count - 1)) }
            Button("Reset Today", systemImage: "arrow.counterclockwise") { set(0) }
        }
    }

    private func addButton(_ d: CGFloat) -> some View {
        Button {
            set(count + 1)
            HapticEngine.shared.play(count + 1 == goal ? .success : .lightImpact)
        } label: {
            Image(systemName: "plus").font(.system(size: d * 0.42, weight: .bold))
                .foregroundStyle(Color.modulaOnPrimary)
                .frame(width: d, height: d).background(Circle().fill(Color.modulaPrimaryFill))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.88, haptic: nil))
        .accessibilityLabel("Add a glass of water")
    }

    private func set(_ value: Int) {
        var kept = raw.split(separator: ";").map(String.init).filter { !$0.hasPrefix("\(widgetID)|") }
        kept.append("\(widgetID)|\(today)|\(value)")
        raw = kept.suffix(24).joined(separator: ";")
    }

    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Percent of the year gone, as a ring (or bar on the pill).
struct BoardYearFace: View {
    let size: BoardWidgetSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { ctx in
            let cal = Calendar.current
            let year = cal.component(.year, from: ctx.date)
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? ctx.date
            let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? ctx.date
            let p = max(0, min(1, ctx.date.timeIntervalSince(start) / end.timeIntervalSince(start)))
            let left = cal.dateComponents([.day], from: ctx.date, to: end).day ?? 0
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    Text(String(year)).font(.system(size: 18, weight: .bold, design: .rounded))
                    ProgressView(value: p).tint(.primary)
                    Text("\(Int(p * 100))%").font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .padding(.horizontal, 22)
            default:
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.14), lineWidth: 10)
                        Circle().trim(from: 0, to: p).stroke(Color.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(p * 100))%").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(String(year)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(size == .circle ? 8 : 0)
                    if size == .medium {
                        VStack(alignment: .leading, spacing: 4) {
                            BoardFaceHeader(title: "Year", symbol: "chart.pie.fill")
                            Text("\(left) days left").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("Make them count.").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(size == .circle ? 22 : BoardMetrics.padding)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Speed: shared ISO formatter

/// Speed: the Countdown face built a new `ISO8601DateFormatter` (an ICU-backed object) every time it read its
/// target date — several times per render, every minute, per countdown widget. One shared, thread-safe formatter
/// plus a tiny parse cache replaces those allocations.
enum BoardISO {
    nonisolated(unsafe) static let formatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static var cache: [String: Date] = [:]
    static func date(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        if let hit = cache[string] { return hit }
        guard let d = formatter.date(from: string) else { return nil }
        if cache.count > 32 { cache.removeAll() }
        cache[string] = d
        return d
    }
}

// MARK: - Habit

/// Daily habit: tap to tick today; the last 7 days and the current run. Stored per widget on device.
struct BoardHabitFace: View {
    let size: BoardWidgetSize
    let widgetID: String
    let title: String
    // raw = "<widgetID>|<y-m-d>,<y-m-d>…;…" (last 60 days kept)
    @AppStorage("board.habit.v1") private var raw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var days: Set<String> {
        for entry in raw.split(separator: ";") where entry.hasPrefix("\(widgetID)|") {
            return Set(entry.dropFirst(widgetID.count + 1).split(separator: ",").map(String.init))
        }
        return []
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func streak(_ done: Set<String>, now: Date) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        if !done.contains(Self.key(day)) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while done.contains(Self.key(day)) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    var body: some View {
        let now = Date()
        let done = days
        let today = done.contains(Self.key(now))
        let run = streak(done, now: now)
        Group {
            switch BoardFamily(size) {
            case .inline:
                HStack(spacing: 12) {
                    tick(today, d: 38)
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Label("\(run)", systemImage: "flame.fill").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(run > 0 ? .orange : .secondary)
                }
                .padding(.horizontal, 20)
            case .round:
                VStack(spacing: 4) {
                    tick(today, d: 52)
                    Text("\(run) day\(run == 1 ? "" : "s")").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    BoardFaceHeader(title: "Habit", symbol: "checkmark.seal.fill", trailing: run > 0 ? "🔥 \(run)" : nil)
                    Text(title).font(.system(size: size == .medium ? 18 : 15, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    HStack(spacing: size == .medium ? 8 : 4) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = Calendar.current.date(byAdding: .day, value: i - 6, to: now) ?? now
                            let on = done.contains(Self.key(day))
                            Circle().fill(on ? Color.primary : Color.primary.opacity(0.12))
                                .frame(width: size == .medium ? 14 : 10, height: size == .medium ? 14 : 10)
                                .scaleEffect(on && i == 6 ? 1.15 : 1)
                        }
                        Spacer(minLength: 0)
                        tick(today, d: size == .medium ? 40 : 34)
                    }
                }
                .padding(BoardMetrics.padding)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: today)
        .accessibilityElement(children: .contain)
    }

    private func tick(_ on: Bool, d: CGFloat) -> some View {
        Button { toggleToday(on) } label: {
            Image(systemName: on ? "checkmark" : "plus")
                .font(.system(size: d * 0.42, weight: .bold))
                .foregroundStyle(on ? Color.modulaOnPrimary : Color.primary)
                .frame(width: d, height: d)
                .background(Circle().fill(on ? AnyShapeStyle(Color.modulaPrimaryFill) : AnyShapeStyle(Color.primary.opacity(0.1))))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.88, haptic: nil))
        .accessibilityLabel(on ? "Done today, \(title). Tap to undo" : "Mark \(title) done today")
    }

    private func toggleToday(_ on: Bool) {
        var set = days
        let k = Self.key(Date())
        if on { set.remove(k) } else { set.insert(k) }
        // Keep the last 60 days only.
        let cal = Calendar.current
        let keep = Set((0..<60).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()).map(Self.key) })
        set.formIntersection(keep)
        var entries = raw.split(separator: ";").map(String.init).filter { !$0.hasPrefix("\(widgetID)|") }
        entries.append("\(widgetID)|" + set.sorted().joined(separator: ","))
        raw = entries.joined(separator: ";")
        HapticEngine.shared.play(on ? .lightImpact : .success)
    }
}

// MARK: - Calculator

struct BoardCalculatorFace: View {
    let size: BoardWidgetSize
    @State private var display = "0"
    @State private var stored: Double?
    @State private var op: String?
    @State private var fresh = true

    private static let rows: [[String]] = [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]]

    var body: some View {
        VStack(spacing: 8) {
            Text(display)
                .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: display)
                .textSelection(.enabled)
                .accessibilityLabel("Result \(display)")
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Text(key).font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(isOp(key) && op == key && fresh ? Color.modulaOnPrimary : Color.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Capsule().fill(isOp(key) && op == key && fresh ? AnyShapeStyle(Color.modulaPrimaryFill)
                                                                                         : AnyShapeStyle(Color.primary.opacity(isOp(key) || key == "=" ? 0.14 : 0.07))))
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.9))
                        .accessibilityLabel(Self.spoken(key))
                    }
                }
            }
        }
        .padding(BoardMetrics.padding)
    }

    private func isOp(_ k: String) -> Bool { ["÷", "×", "−", "+"].contains(k) }
    private static func spoken(_ k: String) -> String {
        switch k { case "÷": "divide"; case "×": "multiply"; case "−": "minus"; case "+": "plus"; case "±": "plus minus"
        case "⌫": "delete"; case "C": "clear"; case "%": "percent"; case "=": "equals"; case ".": "point"; default: k }
    }

    private var value: Double { Double(display) ?? 0 }

    private func show(_ v: Double) {
        guard v.isFinite else { display = "Error"; return }
        if v == v.rounded(), abs(v) < 1e15 { display = String(Int64(v)) }
        else { display = String(format: "%.10g", v) }
    }

    private func press(_ k: String) {
        switch k {
        case "0"..."9":
            if fresh || display == "0" || display == "Error" { display = k } else if display.count < 15 { display += k }
            fresh = false
        case ".":
            if fresh || display == "Error" { display = "0."; fresh = false } else if !display.contains(".") { display += "." }
        case "C": display = "0"; stored = nil; op = nil; fresh = true
        case "⌫":
            if !fresh, display.count > 1 { display.removeLast() } else { display = "0"; fresh = true }
        case "±": show(-value)
        case "%": show(value / 100)
        case "=":
            compute(); op = nil; fresh = true
        default:
            if !fresh || stored == nil { compute() }
            stored = value; op = k; fresh = true
        }
    }

    private func compute() {
        guard let a = stored, let op else { return }
        let b = value
        let r: Double
        switch op { case "+": r = a + b; case "−": r = a - b; case "×": r = a * b; default: r = b == 0 ? .nan : a / b }
        show(r)
        stored = r.isFinite ? r : nil
    }
}

// MARK: - Unit converter

enum BoardUnitCategory: String, CaseIterable, Identifiable {
    case length, weight, temperature, volume
    var id: String { rawValue }
    var title: String { switch self { case .length: "Length"; case .weight: "Weight"; case .temperature: "Temp"; case .volume: "Volume" } }
    var units: [(String, Dimension)] {
        switch self {
        case .length: [("km", UnitLength.kilometers), ("mi", UnitLength.miles), ("m", UnitLength.meters), ("ft", UnitLength.feet), ("cm", UnitLength.centimeters), ("in", UnitLength.inches)]
        case .weight: [("kg", UnitMass.kilograms), ("lb", UnitMass.pounds), ("g", UnitMass.grams), ("oz", UnitMass.ounces), ("st", UnitMass.stones)]
        case .temperature: [("°C", UnitTemperature.celsius), ("°F", UnitTemperature.fahrenheit), ("K", UnitTemperature.kelvin)]
        case .volume: [("L", UnitVolume.liters), ("pt", UnitVolume.imperialPints), ("ml", UnitVolume.milliliters), ("gal", UnitVolume.imperialGallons), ("cup", UnitVolume.cups)]
        }
    }
}

struct BoardConverterFace: View {
    let size: BoardWidgetSize
    let category: String
    @State private var input = "1"
    @State private var from = 0
    @State private var to = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var cat: BoardUnitCategory { BoardUnitCategory(rawValue: category) ?? .length }

    private var result: String {
        let units = cat.units
        guard let v = Double(input.replacingOccurrences(of: ",", with: ".")), units.indices.contains(from), units.indices.contains(to) else { return "—" }
        let out = Measurement(value: v, unit: units[from].1).converted(to: units[to].1).value
        return out.formatted(.number.precision(.significantDigits(1...6)))
    }

    var body: some View {
        let units = cat.units
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BoardFaceHeader(title: cat.title, symbol: "arrow.left.arrow.right")
                if focused {
                    Button("Done") { focused = false }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.modulaOnPrimary)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(Color.modulaPrimaryFill))
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityIdentifier("board.converter.done")
                }
            }
            .animation(.snappy(duration: 0.2), value: focused)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("0", text: $input)
                        .keyboardType(.decimalPad).focused($focused)
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .submitLabel(.done)
                        .onSubmit { focused = false }
                        // Keyboard toolbar only while this field is focused, so several converters never stack
                        // duplicate Done buttons; the in-widget Done below works even where the toolbar can't show.
                        .toolbar { if focused { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } } }
                        .onChange(of: input) { _, v in
                            let cleaned = String(v.filter { "0123456789.,-".contains($0) }.prefix(12))
                            if cleaned != v { input = cleaned }
                        }
                    unitMenu(units, selection: $from)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) { swap(&from, &to) }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36).background(Circle().fill(Color.primary.opacity(0.1)))
                        .rotationEffect(.degrees(from < to ? 0 : 180))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap units")
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy(duration: 0.2), value: result)
                        .textSelection(.enabled)
                    unitMenu(units, selection: $to)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(BoardMetrics.padding)
        .onChange(of: category) { _, _ in from = 0; to = 1 }
    }

    private func unitMenu(_ units: [(String, Dimension)], selection: Binding<Int>) -> some View {
        Menu {
            ForEach(units.indices, id: \.self) { i in Button(units[i].0) { selection.wrappedValue = i } }
        } label: {
            HStack(spacing: 3) {
                Text(units.indices.contains(selection.wrappedValue) ? units[selection.wrappedValue].0 : "—")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Photo frame


/// One library photo per frame, copied (downsampled to 1600 px) into Application Support; decoded off the main
/// thread at display size and cached, so the Board never decodes a full-resolution photo.
enum BoardPhotoStore {
    static let versionKey = "board.photoFrame.v1"
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func url(_ id: String) -> URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("BoardPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id).jpg")
    }

    static func downsample(_ data: Data, maxPixels: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }

    static func save(_ data: Data, id: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let cg = downsample(data, maxPixels: 1600),
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.86) else { return false }
            do { try jpeg.write(to: url(id), options: .atomic); return true } catch { return false }
        }.value
    }

    static func image(_ id: String, token: String, maxPixels: CGFloat) async -> UIImage? {
        let key = "\(id)|\(token)|\(Int(maxPixels))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img: UIImage? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url(id)), let cg = downsample(data, maxPixels: maxPixels) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let img { cache.setObject(img, forKey: key) }
        return img
    }

    static func token(_ raw: String, id: String) -> String? {
        for entry in raw.split(separator: ";") {
            let p = entry.split(separator: "=")
            if p.count == 2, p[0] == id { return String(p[1]) }
        }
        return nil
    }

    static func setToken(_ raw: inout String, id: String) {
        var entries = raw.split(separator: ";").map(String.init).filter { !$0.hasPrefix("\(id)=") }
        entries.append("\(id)=\(Int(Date().timeIntervalSince1970))")
        raw = entries.joined(separator: ";")
    }
}

struct BoardPhotoPickerButton: View {
    let widgetID: String
    @AppStorage(BoardPhotoStore.versionKey) private var raw = ""
    @State private var item: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            HStack {
                Image(systemName: "photo.on.rectangle")
                Text(working ? "Adding…" : (BoardPhotoStore.token(raw, id: widgetID) == nil ? "Choose Photo" : "Change Photo"))
                Spacer()
                if working { ProgressView() }
            }
            .font(.body.weight(.semibold)).foregroundStyle(.primary)
            .padding(14)
        }
        // Glass applied outside the picker's nonisolated label closure (Swift 6 region isolation).
        .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        .disabled(working)
        .onChange(of: item) { _, new in
            guard let new else { return }
            working = true
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), await BoardPhotoStore.save(data, id: widgetID) {
                    BoardPhotoStore.setToken(&raw, id: widgetID)
                    HapticEngine.shared.play(.success)
                } else {
                    HapticEngine.shared.play(.failure)
                }
                working = false
                item = nil
            }
        }
    }
}

struct BoardPhotoFrameFace: View {
    let size: BoardWidgetSize
    let widgetID: String
    @AppStorage(BoardPhotoStore.versionKey) private var raw = ""
    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let token = BoardPhotoStore.token(raw, id: widgetID)
        GeometryReader { g in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                        .transition(.opacity)
                } else if token == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 26, weight: .semibold))
                        if size != .circle { Text("Tap to choose a photo").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: image != nil)
            .task(id: "\(token ?? "")|\(Int(max(g.size.width, g.size.height)))") {
                guard let token, g.size.width > 0 else { image = nil; return }
                image = await BoardPhotoStore.image(widgetID, token: token, maxPixels: max(g.size.width, g.size.height) * scale)
            }
        }
        .accessibilityLabel(token == nil ? "Photo frame, no photo chosen" : "Photo frame")
    }
}
