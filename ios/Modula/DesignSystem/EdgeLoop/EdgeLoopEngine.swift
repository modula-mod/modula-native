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
///
/// Internally the reel is a continuous, unbounded position (`anchor`, in item units).
/// The list scrolls through a fixed aperture; the anchor is whatever sits at the
/// aperture centre. Looping wraps indices modulo `itemCount`; bounded clamps and
/// rubber-bands. Slots handed to the view are unbounded integers so identity is
/// stable across arbitrarily long drags.
struct EdgeLoopEngine: Equatable, Sendable {
    var itemCount: Int
    var behavior: EdgeLoopBehavior
    var selectedIndex: Int
    var dragOffset: CGFloat = 0
    var phase: EdgeLoopPhase = .resting
    private(set) var proposedIndex: Int
    /// Continuous reel position in item units. Integer at rest.
    private(set) var anchor: CGFloat
    private var dragBase: CGFloat = 0

    /// Centre-to-centre distance between plain reel icons. Overridden from metrics.
    var stride: CGFloat = EdgeLoopEngine.itemStride
    /// Centre-to-centre distance between plain reel icons: 20pt icon + 12pt gap.
    static let itemStride: CGFloat = 32
    static let iconSize: CGFloat = 20
    static let itemGap: CGFloat = 12
    /// Selected pill at rest (circle) and the notch depth from the physical edge.
    static let restingWidth: CGFloat = 46
    /// Maximum horizontal reveal width for the selected word (Standard).
    static let revealedWidth: CGFloat = 126
    static let pillWidth: CGFloat = 44
    static let apertureHeight: CGFloat = 44
    static let railHeight: CGFloat = 244
    static let hitSlop: CGFloat = 44
    static let labelHoldDuration: TimeInterval = 1.75
    static let snapThreshold: CGFloat = 18
    static let visibleRadius = 2
    /// A flick may carry at most this many items past the finger.
    static let maxFlingItems: CGFloat = 3

    init(itemCount: Int, behavior: EdgeLoopBehavior, selectedIndex: Int = 0, stride: CGFloat = EdgeLoopEngine.itemStride) {
        let count = max(0, itemCount)
        self.itemCount = count
        self.behavior = behavior
        self.stride = stride
        let clamped = Self.offsetIndex(0, by: selectedIndex, count: count, behavior: .bounded)
        self.selectedIndex = count == 0 ? 0 : clamped
        self.proposedIndex = self.selectedIndex
        self.anchor = CGFloat(self.selectedIndex)
    }

    mutating func setSelectedIndex(_ index: Int, expandingLabel: Bool = true) {
        guard itemCount > 0 else { return }
        let resolved = Self.offsetIndex(0, by: index, count: itemCount, behavior: behavior == .looping ? .looping : .bounded)
        // Move the continuous anchor along the shortest path so the reel slides,
        // never teleports, when selection changes from outside (tab tap, route change).
        if behavior == .looping {
            let current = Self.offsetIndex(0, by: Int(anchor.rounded()), count: itemCount, behavior: .looping)
            var delta = resolved - current
            if delta > itemCount / 2 { delta -= itemCount }
            if delta < -itemCount / 2 { delta += itemCount }
            anchor = anchor.rounded() + CGFloat(delta)
        } else {
            anchor = CGFloat(resolved)
        }
        selectedIndex = resolved
        proposedIndex = resolved
        dragOffset = 0
        if phase != .disabled {
            phase = expandingLabel ? .labelExpanded : .resting
        }
    }

    mutating func beginDrag() {
        guard itemCount > 0, phase != .disabled else { return }
        dragBase = anchor.rounded()
        phase = .dragging
    }

    /// Returns `true` when a new item has crossed the selection centre — play one selection haptic.
    mutating func updateDrag(translation: CGFloat) -> Bool {
        guard phase == .dragging, itemCount > 0 else { return false }
        var raw = dragBase - translation / stride
        if behavior == .bounded {
            let lo: CGFloat = 0
            let hi = CGFloat(itemCount - 1)
            if raw < lo {
                raw = lo + (raw - lo) * 0.28
            } else if raw > hi {
                raw = hi + (raw - hi) * 0.28
            }
        }
        // Soft detent gravity: lean toward the nearest item without fighting a quick flick.
        let nearest = raw.rounded()
        if behavior == .looping || (nearest >= 0 && nearest <= CGFloat(itemCount - 1)) {
            raw += (nearest - raw) * 0.12
        }
        anchor = raw
        dragOffset = -(anchor - dragBase) * stride
        let next = resolvedIndex(forSlot: Int(anchor.rounded()))
        let crossed = next != proposedIndex
        proposedIndex = next
        return crossed
    }

    /// Where a momentum release would settle, without mutating. Lets the view
    /// tune the settle spring and pre-count coast crossings for ticks.
    func previewSettleAnchor(projectedTranslation: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        var target = dragBase - projectedTranslation / stride
        target = min(max(target, anchor - Self.maxFlingItems), anchor + Self.maxFlingItems)
        var slot = target.rounded()
        if behavior == .bounded {
            slot = min(max(slot, 0), CGFloat(max(itemCount - 1, 0)))
        }
        return slot
    }

    @discardableResult
    mutating func endDrag() -> Int {
        guard itemCount > 0 else { return 0 }
        return settle(on: anchor.rounded())
    }

    /// Momentum-aware release. `projectedTranslation` is the gesture's predicted
    /// end translation; the reel coasts toward it, capped at `maxFlingItems`.
    @discardableResult
    mutating func endDrag(projectedTranslation: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        var target = dragBase - projectedTranslation / stride
        target = min(max(target, anchor - Self.maxFlingItems), anchor + Self.maxFlingItems)
        return settle(on: target.rounded())
    }

    private mutating func settle(on target: CGFloat) -> Int {
        var slot = target
        if behavior == .bounded {
            slot = min(max(slot, 0), CGFloat(max(itemCount - 1, 0)))
        }
        anchor = slot
        selectedIndex = resolvedIndex(forSlot: Int(slot))
        proposedIndex = selectedIndex
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
        anchor = anchor.rounded()
    }

    func index(offsetBy delta: Int) -> Int {
        Self.offsetIndex(selectedIndex, by: delta, count: itemCount, behavior: behavior)
    }

    func indexForDragOffset(_ offset: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        let delta = Int((-offset / stride).rounded())
        return Self.offsetIndex(selectedIndex, by: delta, count: itemCount, behavior: behavior)
    }

    /// Item index for an unbounded slot number.
    func resolvedIndex(forSlot slot: Int) -> Int {
        Self.offsetIndex(0, by: slot, count: itemCount, behavior: behavior == .looping ? .looping : .bounded)
    }

    func visualOffset(forSlot slot: Int) -> CGFloat {
        CGFloat(slot) * stride + dragOffset
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

    /// Continuous reel window for the view. Slots are unbounded integers (stable
    /// identity while scrolling); `offset` is points from the aperture centre.
    func reelSlots(radius: Int = 3) -> [(slot: Int, index: Int, offset: CGFloat)] {
        guard itemCount > 0 else { return [] }
        let center = Int(anchor.rounded())
        var slots: [(slot: Int, index: Int, offset: CGFloat)] = []
        for slot in (center - radius)...(center + radius) {
            if behavior == .bounded, slot < 0 || slot >= itemCount { continue }
            slots.append((slot, resolvedIndex(forSlot: slot), (CGFloat(slot) - anchor) * stride))
        }
        return slots
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
