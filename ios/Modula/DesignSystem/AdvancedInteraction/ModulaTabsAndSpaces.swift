import SwiftUI

struct ModulaTabItem<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    let id: ID
    var title: String
    var systemImage: String?
    var badgeCount: Int?
    var showsNotificationDot = false
    var isEnabled = true
}

struct ModulaTabSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    private(set) var selectedID: ID

    init(_ selectedID: ID) { self.selectedID = selectedID }

    @discardableResult
    mutating func select(_ id: ID, available: Set<ID>) -> Bool {
        guard available.contains(id), id != selectedID else { return false }
        selectedID = id
        return true
    }
}

enum ModulaTabLayout: String, CaseIterable, Sendable {
    case intrinsic
    case equalWidth
    case scrollable
}

struct ModulaTabBadge: View {
    var count: Int?
    var showsNotificationDot = false
    var selected = false

    var body: some View {
        Group {
            if let count, count > 0 {
                ModulaUnreadIndicator(count: count, tone: selected ? .accent : .muted)
                    .scaleEffect(0.82)
            } else if showsNotificationDot {
                ModulaNotificationDot(tone: selected ? .accent : .muted, size: 7)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// THE segmented control. Every tab row, scope picker, filter strip and `Picker(.segmented)` in the app
/// renders through this (enforced by `scripts/verify-boundaries.py` and `ModulaComponentUnificationTests`).
/// - Apple-like: neutral glass track, raised neutral thumb that slides between segments (no accent).
/// - Up to 5 segments share the width; more scroll horizontally and the selection auto-scrolls into view.
/// - Selection haptic, VoiceOver traits/values, Reduce Motion (no slide) and Reduce Transparency (opaque track).
struct ModulaSegmentedControl<ID: Hashable>: View {
    struct Segment: Identifiable {
        let id: ID
        var title: String
        var systemImage: String? = nil
        var badgeCount: Int? = nil
        var showsNotificationDot = false
        var isEnabled = true
    }

    let segments: [Segment]
    @Binding var selection: ID
    var forceScroll = false
    var compact = false
    var accessibilityLabel = "Tabs"
    /// Per-segment UI-test identifier (keeps existing ids such as `discover.scope.people`).
    var identifier: ((ID) -> String)? = nil
    var onSelection: ((ID) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Namespace private var thumb

    static var maxFixedSegments: Int { 5 }

    init(segments: [Segment], selection: Binding<ID>, forceScroll: Bool = false, compact: Bool = false,
         accessibilityLabel: String = "Tabs", identifier: ((ID) -> String)? = nil, onSelection: ((ID) -> Void)? = nil) {
        self.segments = segments
        self.identifier = identifier
        self._selection = selection
        self.forceScroll = forceScroll
        self.compact = compact
        self.accessibilityLabel = accessibilityLabel
        self.onSelection = onSelection
    }

    /// Fixed list of (value, title) pairs — the replacement for `Picker { Text(..).tag(..) }.pickerStyle(.segmented)`.
    init(_ accessibilityLabel: String, selection: Binding<ID>, segments: [(ID, String)], compact: Bool = false,
         identifier: ((ID) -> String)? = nil, onSelection: ((ID) -> Void)? = nil) {
        self.init(segments: segments.map { Segment(id: $0.0, title: $0.1) }, selection: selection, compact: compact,
                  accessibilityLabel: accessibilityLabel, identifier: identifier, onSelection: onSelection)
    }

    /// Options + title (and optional symbol) closures, e.g. `options: Tab.allCases`.
    init<C: Sequence>(_ accessibilityLabel: String, selection: Binding<ID>, options: C, compact: Bool = false,
                      symbol: ((ID) -> String?)? = nil, identifier: ((ID) -> String)? = nil, onSelection: ((ID) -> Void)? = nil,
                      title: (ID) -> String) where C.Element == ID {
        self.init(segments: options.map { Segment(id: $0, title: title($0), systemImage: symbol?($0)) }, selection: selection,
                  compact: compact, accessibilityLabel: accessibilityLabel, identifier: identifier, onSelection: onSelection)
    }

    private var scrolls: Bool { forceScroll || segments.count > Self.maxFixedSegments }

    var body: some View {
        Group {
            if scrolls {
                scrollingRow
            } else {
                // Never truncate: share the width when every label fits at its natural size,
                // otherwise fall back to a horizontally scrolling row.
                ViewThatFits(in: .horizontal) {
                    row(scrolling: false)
                    scrollingRow
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("modula.segmented")
    }

    private var scrollingRow: some View {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        row(scrolling: true).padding(.horizontal, 2)
                    }
                    .modulaHorizontalRail()
                    .scrollClipDisabled()
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, value in
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { proxy.scrollTo(value, anchor: .center) }
                    }
                }
    }

    private func row(scrolling: Bool) -> some View {
        ModulaSegmentGlassContainer {
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    button(segment, scrolling: scrolling)
                        .frame(maxWidth: scrolling ? nil : .infinity)
                        .id(segment.id)
                }
            }
            .padding(3)
            .modulaGlass(in: Capsule(), interactive: false)
        }
    }

    private func button(_ segment: Segment, scrolling: Bool) -> some View {
        let selected = selection == segment.id
        return Button {
            guard segment.isEnabled, !selected else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.12)) { selection = segment.id }
            HapticEngine.shared.play(.selection)
            onSelection?(segment.id)
        } label: {
            HStack(spacing: 6) {
                if let image = segment.systemImage {
                    Image(systemName: image)
                        .symbolVariant(selected ? .fill : .none)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                if !compact || segment.systemImage == nil {
                    Text(segment.title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                ModulaTabBadge(count: segment.badgeCount, showsNotificationDot: segment.showsNotificationDot, selected: selected)
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(segment.isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(maxWidth: scrolling ? nil : .infinity, minHeight: compact ? 32 : 36)
            .background {
                if selected {
                    ModulaSegmentThumb(dark: scheme == .dark)
                        .matchedGeometryEffect(id: "modula.segmented.thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!segment.isEnabled)
        .accessibilityLabel(segment.title)
        .accessibilityValue(segment.badgeCount.map { "\($0) new" } ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(identifier?(segment.id) ?? "modula.segmented.\(segment.title)")
    }
}

extension ModulaSegmentedControl where ID: Sendable {
    /// Bridge for `ModulaTabItem` (badges, dots, disabled) — the former `ModulaTabStrip` signature.
    init(items: [ModulaTabItem<ID>], selection: Binding<ID>, layout: ModulaTabLayout = .intrinsic, compact: Bool = false,
         accessibilityLabel: String = "Tabs", onSelection: ((ID) -> Void)? = nil) {
        self.init(segments: items.map {
            Segment(id: $0.id, title: $0.title, systemImage: $0.systemImage, badgeCount: $0.badgeCount,
                    showsNotificationDot: $0.showsNotificationDot, isEnabled: $0.isEnabled)
        }, selection: selection, forceScroll: layout == .scrollable, compact: compact,
           accessibilityLabel: accessibilityLabel, onSelection: onSelection)
    }
}

/// Neutral raised thumb (white on light, graphite on dark) — never the accent.
private struct ModulaSegmentThumb: View {
    var dark: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency, !ModulaGlassSettings.shared.lighter {
            // Liquid Glass selected pill (interactive), morphing inside the track's glass container.
            Capsule()
                .fill(Color.white.opacity(dark ? 0.06 : 0.35))
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityHidden(true)
        } else {
            // Reduce Transparency / Lighter effects: solid raised thumb.
            Capsule()
                .fill(dark ? Color(white: 0.36) : Color.white)
                .shadow(color: .black.opacity(dark ? 0.3 : 0.12), radius: 3, y: 1)
                .accessibilityHidden(true)
        }
    }
}

/// Groups the segmented track and its glass pill so iOS 26 blends/morphs them as one glass.
private struct ModulaSegmentGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 2) { content }
        } else {
            content
        }
    }
}

struct ModulaSpace<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    let id: ID
    var title: String
    var systemImage: String
    var badgeCount: Int?
    var showsNotificationDot = false
}

struct ModulaSpaceBadge: View {
    var count: Int?
    var showsNotificationDot = false
    var selected = false

    var body: some View {
        ModulaTabBadge(
            count: count,
            showsNotificationDot: showsNotificationDot,
            selected: selected
        )
    }
}

enum ModulaSpaceOrder {
    static func moving<ID>(_ ids: [ID], from source: Int, to destination: Int) -> [ID] {
        guard ids.indices.contains(source), destination >= 0, destination <= ids.count else { return ids }
        var result = ids
        let item = result.remove(at: source)
        result.insert(item, at: min(destination, result.count))
        return result
    }
}

struct ModulaSpaceSwitcher<ID: Hashable & Sendable>: View {
    let spaces: [ModulaSpace<ID>]
    @Binding var selection: ID
    var compact = false
    var onSelection: ((ID) -> Void)?

    var body: some View {
        ModulaSegmentedControl(
            items: spaces.map {
                ModulaTabItem(
                    id: $0.id,
                    title: $0.title,
                    systemImage: $0.systemImage,
                    badgeCount: $0.badgeCount,
                    showsNotificationDot: $0.showsNotificationDot
                )
            },
            selection: $selection,
            layout: .scrollable,
            compact: compact,
            accessibilityLabel: "Spaces",
            onSelection: onSelection
        )
        .accessibilityIdentifier("modula.space.switcher")
    }
}

struct ModulaSpaceItem<ID: Hashable & Sendable>: View {
    let space: ModulaSpace<ID>
    var selected: Bool
    var action: () -> Void

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: space.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(selected ? app.appearance.liveAccent : .secondary)
                Text(space.title)
                    .font(.body.weight(selected ? .semibold : .regular))
                Spacer()
                ModulaSpaceBadge(
                    count: space.badgeCount,
                    showsNotificationDot: space.showsNotificationDot,
                    selected: selected
                )
                if selected { Image(systemName: "checkmark").foregroundStyle(.primary) }
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct ModulaSpaceEditorRow<ID: Hashable & Sendable>: View {
    let space: ModulaSpace<ID>
    var enabled = true
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: space.systemImage).frame(width: 24)
            Text(space.title)
            Spacer()
            Button(action: onToggle) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            }
            .accessibilityLabel(enabled ? "Hide \(space.title)" : "Show \(space.title)")
        }
        .accessibilityElement(children: .contain)
    }
}
