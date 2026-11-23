import SwiftUI

struct ModulaReactionItem<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    let id: ID
    var title: String
    var systemImage: String
    var count: Int?
    var isEnabled = true
}

struct ModulaReactionSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    private(set) var selectedID: ID?

    init(_ selectedID: ID? = nil) { self.selectedID = selectedID }

    @discardableResult
    mutating func replace(with id: ID?) -> ID? {
        let previous = selectedID
        selectedID = id
        return previous
    }

    mutating func toggle(_ id: ID) { selectedID = selectedID == id ? nil : id }
}

enum ModulaReactionGesture {
    static func itemIndex(
        at x: CGFloat,
        itemCount: Int,
        itemWidth: CGFloat,
        spacing: CGFloat,
        leadingInset: CGFloat = 0
    ) -> Int? {
        guard itemCount > 0, itemWidth > 0 else { return nil }
        let local = x - leadingInset
        guard local >= 0 else { return nil }
        let stride = itemWidth + spacing
        let index = Int(local / stride)
        guard index >= 0, index < itemCount else { return nil }
        let withinItem = local - CGFloat(index) * stride
        return withinItem <= itemWidth ? index : nil
    }
}

struct ModulaReactionBar<ID: Hashable & Sendable>: View {
    let items: [ModulaReactionItem<ID>]
    var selectedID: ID?
    var compact = false
    var maximumVisibleItems = 6
    var onSelect: (ID?) -> Void
    var onOverflow: (() -> Void)?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var highlightedID: ID?
    @State private var lastHapticID: ID?

    private var visibleItems: [ModulaReactionItem<ID>] { Array(items.prefix(maximumVisibleItems)) }
    private var itemWidth: CGFloat { compact ? 38 : 46 }
    private let itemSpacing: CGFloat = 4
    private let horizontalInset: CGFloat = 8

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(visibleItems) { item in reactionButton(item) }
            if items.count > visibleItems.count || onOverflow != nil {
                Button(action: { onOverflow?() }) {
                    Image(systemName: "ellipsis")
                        .frame(width: itemWidth, height: ModulaLayout.minimumTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More reactions")
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, compact ? 4 : 6)
        .background(background)
        .overlay(Capsule().stroke(.primary.opacity(reduceTransparency ? 0.18 : 0.08)))
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.12), radius: 12, y: 4)
        .gesture(scrubGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reactions")
        .accessibilityIdentifier("modula.reaction.bar")
        .onAppear {
            highlightedID = selectedID
            HapticEngine.shared.play(.contextOpened)
        }
        .onChange(of: selectedID) { _, value in highlightedID = value }
    }

    private var background: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.thinMaterial)
    }

    private func reactionButton(_ item: ModulaReactionItem<ID>) -> some View {
        let highlighted = highlightedID == item.id
        let selected = selectedID == item.id
        return Button {
            commit(item.id)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: item.systemImage)
                    .font(.system(size: highlighted ? (compact ? 19 : 23) : (compact ? 17 : 20), weight: .semibold))
                    .symbolVariant(selected ? .fill : .none)
                if let count = item.count, count > 0, !compact {
                    Text(ModulaCountFormat.compact(count) ?? "")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(highlighted || selected ? app.appearance.liveAccent : .primary)
            .frame(width: itemWidth, height: compact ? 42 : 52)
            .background((highlighted ? app.appearance.liveAccent.opacity(0.14) : .clear), in: Capsule())
            .scaleEffect(highlighted && !reduceMotion ? 1.08 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.count.map { "\($0)" } ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard let index = ModulaReactionGesture.itemIndex(
                    at: value.location.x,
                    itemCount: visibleItems.count,
                    itemWidth: itemWidth,
                    spacing: itemSpacing,
                    leadingInset: horizontalInset
                ) else { return }
                let item = visibleItems[index]
                guard item.isEnabled, highlightedID != item.id else { return }
                highlightedID = item.id
                if lastHapticID != item.id {
                    lastHapticID = item.id
                    HapticEngine.shared.play(.reactionChanged)
                }
            }
            .onEnded { _ in
                if let highlightedID { commit(highlightedID) }
                lastHapticID = nil
            }
    }

    private func commit(_ id: ID) {
        let replacement: ID? = selectedID == id ? nil : id
        highlightedID = replacement
        HapticEngine.shared.play(.reactionCommitted)
        onSelect(replacement)
    }
}
