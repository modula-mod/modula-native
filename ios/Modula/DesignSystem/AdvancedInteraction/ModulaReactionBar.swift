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
        .modulaGlass(in: Capsule(), interactive: false, specular: true)
        .overlay { if reduceTransparency { Capsule().stroke(.primary.opacity(0.18)) } }
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

// MARK: - Shared emoji reaction strip + summary

/// One emoji option in a reaction strip (`id` is what the caller applies; usually the emoji itself
/// or a server reaction type).
struct ModulaEmojiReactionOption: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    let title: String
}

/// The shared glass emoji reaction strip: post cards (long-press the heart), the comments sheet
/// (long-press a comment) and Reels (long-press the like button) all use this one component.
///
/// Every emoji is a plain Button (instant tap). Callers that drive a press-and-slide scrub pass
/// `hoveredID`, `magnification` and `onFrame`, and the strip renders the hover lift + name label.
struct ModulaEmojiReactionStrip: View {
    let options: [ModulaEmojiReactionOption]
    var selectedID: String? = nil
    var hoveredID: String? = nil
    var emojiSize: CGFloat = 27
    var slotWidth: CGFloat = 42
    /// Named coordinate space used for `onFrame` (scrub hit-testing); nil skips measuring.
    var coordinateSpace: String? = nil
    var onFrame: ((String, CGRect) -> Void)? = nil
    var magnification: (String) -> CGFloat = { _ in 1 }
    var onPick: (ModulaEmojiReactionOption) -> Void
    /// Shows the trailing "+" (full emoji grid). Nil hides it.
    var onMore: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var appeared = false

    static let moreID = "+"

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                slot(id: option.id, index: index, title: option.title) {
                    Button {
                        HapticEngine.shared.play(.reactionSelect)
                        onPick(option)
                    } label: {
                        Text(option.emoji)
                            .font(.system(size: emojiSize))
                            .frame(width: slotWidth, height: 44)
                            .background {
                                if selectedID == option.id {
                                    Circle().fill(Color.primary.opacity(0.14)).frame(width: 38, height: 38)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
                }
            }
            if let onMore {
                slot(id: Self.moreID, index: options.count, title: "More") {
                    Button {
                        HapticEngine.shared.play(.contextOpen)
                        onMore()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.1), in: Circle())
                            .frame(width: slotWidth, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More reactions")
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .modulaGlass(in: Capsule(), specular: true)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        // The presenter plays the open haptic (once); picks play `.reactionSelect`.
        .onAppear { withAnimation { appeared = true } }
        .onDisappear { appeared = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reactions")
    }

    @ViewBuilder
    private func slot<Content: View>(id: String, index: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        let hovered = hoveredID == id
        let scale = magnification(id)
        content()
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: hovered && !calm ? -12 : 0)
            .scaleEffect(appeared || calm ? 1 : 0.3)
            .opacity(appeared || calm ? 1 : 0)
            .animation(calm ? nil : .spring(response: 0.34, dampingFraction: 0.62).delay(Double(index) * 0.03), value: appeared)
            .animation(calm ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.62), value: scale)
            .background {
                if let coordinateSpace, let onFrame {
                    // The fixed slot is measured (not the scaled glyph) so scrub hit-testing is stable.
                    Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(coordinateSpace)) } action: { onFrame(id, $0) }
                }
            }
            .overlay(alignment: .top) {
                if hovered {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .modulaGlass(in: Capsule(), interactive: false)
                        .offset(y: calm ? -30 : -62)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(calm ? nil : .snappy(duration: 0.18), value: hovered)
            .zIndex(hovered ? 2 : 0)
    }
}

/// Shared glass reaction summary: up to three stacked top emoji plus the total count.
struct ModulaReactionSummaryLabel: View {
    let emojis: [String]
    let count: Int
    var onMedia = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: -6) {
                ForEach(Array(emojis.prefix(3).enumerated()), id: \.element) { index, emoji in
                    Text(emoji)
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(onMedia ? Color.black.opacity(0.4) : Color(uiColor: .secondarySystemBackground)))
                        .overlay(Circle().strokeBorder(onMedia ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 0.5))
                        .zIndex(Double(3 - index))
                }
            }
            if let text = ModulaCountFormat.compact(count) {
                Text(text)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(onMedia ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText(value: Double(count)))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(minHeight: 28)
        .modulaGlass(in: Capsule(), interactive: true)
    }
}
