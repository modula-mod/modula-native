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

struct ModulaTabIndicator: View {
    var selected = true

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Capsule()
            .fill(app.appearance.liveAccent.opacity(selected ? 0.15 : 0))
            .accessibilityHidden(true)
    }
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

struct ModulaTabStrip<ID: Hashable & Sendable>: View {
    let items: [ModulaTabItem<ID>]
    @Binding var selection: ID
    var layout: ModulaTabLayout = .intrinsic
    var compact = false
    var accessibilityLabel = "Tabs"
    var onSelection: ((ID) -> Void)?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicatorNamespace

    var body: some View {
        Group {
            if layout == .scrollable {
                ScrollView(.horizontal, showsIndicators: false) { tabRow }
            } else {
                tabRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var tabRow: some View {
        HStack(spacing: compact ? ModulaSpacing.xs : ModulaSpacing.sm) {
            ForEach(items) { item in
                tabButton(item)
                    .frame(maxWidth: layout == .equalWidth ? .infinity : nil)
            }
        }
        .padding(.horizontal, compact ? ModulaSpacing.xs : ModulaSpacing.sm)
        .padding(.vertical, ModulaSpacing.xxs)
        .modulaMaterial(.control, in: Capsule())
    }

    private func tabButton(_ item: ModulaTabItem<ID>) -> some View {
        let selected = selection == item.id
        return Button {
            guard item.isEnabled, !selected else { return }
            withAnimation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                selection = item.id
            }
            HapticEngine.shared.play(.selectionChanged)
            onSelection?(item.id)
        } label: {
            HStack(spacing: 6) {
                if let image = item.systemImage {
                    Image(systemName: image)
                        .symbolVariant(selected ? .fill : .none)
                }
                if !compact || item.systemImage == nil {
                    Text(item.title).lineLimit(1)
                }
                ModulaTabBadge(
                    count: item.badgeCount,
                    showsNotificationDot: item.showsNotificationDot,
                    selected: selected
                )
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? app.appearance.liveAccent : .primary)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(minHeight: ModulaLayout.minimumTouch)
            .background {
                if selected {
                    ModulaTabIndicator()
                        .matchedGeometryEffect(id: "modula.tab.indicator", in: indicatorNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.badgeCount.map { "\($0)" } ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
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
        ModulaTabStrip(
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
                if selected { Image(systemName: "checkmark").foregroundStyle(app.appearance.liveAccent) }
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
