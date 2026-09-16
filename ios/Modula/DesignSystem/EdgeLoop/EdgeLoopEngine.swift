import CoreGraphics
import Foundation

enum EdgeLoopBehavior: String, Hashable, Sendable {
    /// First and last items are ends. Drag rubber-bands instead of wrapping.
    case bounded
    /// The list is a circular reel. Semantically appropriate for Home / Activity / Profile modes.
    case looping
}

enum EdgeLoopPhase: String, Hashable, Sendable {
    case resting
    case dragging
    case snapping
    case selected
    case labelExpanded
    case disabled
}

enum EdgeLoopPosition: String, Hashable, Sendable {
    case trailing
    case leading
}

enum EdgeLoopPlacement: String, Hashable, Sendable {
    /// Physically cut into the screen edge.
    case shellEdge
    /// Same mechanics, contained inside a surface (font sample picker, etc.).
    case contained
}

protocol EdgeLoopItem: Identifiable, Hashable {
    var icon: String { get }
    var label: String { get }
    var badge: String? { get }
    var accessibilityLabel: String { get }
}

extension EdgeLoopItem {
    var badge: String? { nil }
    var accessibilityLabel: String { label }
}

struct EdgeLoopDescriptor: EdgeLoopItem, Sendable {
    let id: String
    let icon: String
    let label: String
    var badge: String? = nil
    var accessibilityLabel: String { label }
}

/// Pure reel math. Drag state stays here; committed selection is the only output the screen should observe.
struct EdgeLoopEngine: Equatable, Sendable {
    var itemCount: Int
    var behavior: EdgeLoopBehavior
    var selectedIndex: Int
    var dragOffset: CGFloat = 0
    var phase: EdgeLoopPhase = .resting
    private(set) var proposedIndex: Int

    static let itemStride: CGFloat = 46
    static let restingWidth: CGFloat = 46
    static let revealedWidth: CGFloat = 96
    static let apertureHeight: CGFloat = 44
    static let railHeight: CGFloat = 188
    static let hitSlop: CGFloat = 44
    static let labelHoldDuration: TimeInterval = 1.75
    static let snapThreshold: CGFloat = 18
    static let visibleRadius = 2

    init(itemCount: Int, behavior: EdgeLoopBehavior, selectedIndex: Int = 0) {
        let count = max(0, itemCount)
        self.itemCount = count
        self.behavior = behavior
        let clamped = Self.offsetIndex(0, by: selectedIndex, count: count, behavior: .bounded)
        self.selectedIndex = count == 0 ? 0 : clamped
        self.proposedIndex = self.selectedIndex
    }

    mutating func setSelectedIndex(_ index: Int, expandingLabel: Bool = true) {
        guard itemCount > 0 else { return }
        selectedIndex = Self.offsetIndex(0, by: index, count: itemCount, behavior: behavior == .looping ? .looping : .bounded)
        proposedIndex = selectedIndex
        dragOffset = 0
        if phase != .disabled {
            phase = expandingLabel ? .labelExpanded : .resting
        }
    }

    mutating func beginDrag() {
        guard itemCount > 0, phase != .disabled else { return }
        phase = .dragging
    }

    /// Returns `true` when a new item has crossed the selection centre — play one selection haptic.
    mutating func updateDrag(translation: CGFloat) -> Bool {
        guard phase == .dragging, itemCount > 0 else { return false }
        var offset = translation
        if behavior == .bounded {
            if selectedIndex == 0 && offset > 0 {
                offset *= 0.28
            } else if selectedIndex == itemCount - 1 && offset < 0 {
                offset *= 0.28
            }
        }
        dragOffset = offset
        let next = indexForDragOffset(offset)
        let crossed = next != proposedIndex
        proposedIndex = next
        return crossed
    }

    @discardableResult
    mutating func endDrag() -> Int {
        guard itemCount > 0 else { return 0 }
        selectedIndex = proposedIndex
        dragOffset = 0
        phase = .snapping
        return selectedIndex
    }

    mutating func completeSnap(expandingLabel: Bool = true) {
        if phase == .snapping || phase == .selected {
            phase = expandingLabel ? .labelExpanded : .resting
        }
    }

    mutating func collapseLabel() {
        if phase == .labelExpanded || phase == .selected || phase == .snapping {
            phase = .resting
        }
    }

    mutating func disable() {
        phase = .disabled
        dragOffset = 0
        proposedIndex = selectedIndex
    }

    func index(offsetBy delta: Int) -> Int {
        Self.offsetIndex(selectedIndex, by: delta, count: itemCount, behavior: behavior)
    }

    func indexForDragOffset(_ offset: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        let delta = Int((-offset / Self.itemStride).rounded())
        return Self.offsetIndex(selectedIndex, by: delta, count: itemCount, behavior: behavior)
    }

    func visualOffset(forSlot slot: Int) -> CGFloat {
        CGFloat(slot) * Self.itemStride + dragOffset
    }

    func visibleSlots(radius: Int = EdgeLoopEngine.visibleRadius) -> [(slot: Int, index: Int)] {
        guard itemCount > 0 else { return [] }
        let span = min(radius, max(itemCount - 1, 0))
        if behavior == .bounded {
            return (-span...span).compactMap { slot in
                let index = selectedIndex + slot
                guard index >= 0, index < itemCount else { return nil }
                return (slot, index)
            }
        }
        return (-span...span).map { slot in
            (slot, Self.offsetIndex(selectedIndex, by: slot, count: itemCount, behavior: .looping))
        }
    }

    static func offsetIndex(_ index: Int, by delta: Int, count: Int, behavior: EdgeLoopBehavior) -> Int {
        guard count > 0 else { return 0 }
        if behavior == .looping {
            let mod = (index + delta) % count
            return mod >= 0 ? mod : mod + count
        }
        return min(max(index + delta, 0), count - 1)
    }
}
