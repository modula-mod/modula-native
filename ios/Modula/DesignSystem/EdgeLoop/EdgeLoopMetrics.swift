import CoreGraphics
import Foundation
import UIKit

/// Canonical Edge Picker metrics. Resolved from size, Dynamic Type, and density —
/// not a public customization API. Outer carved proportions stay fixed; only the
/// selection aperture height varies with label reveal.
struct EdgeLoopMetrics: Equatable, Sendable {
    /// Inward depth of the carved channel from the physical edge.
    var channelDepth: CGFloat
    /// Alias used by layout that historically said “resting depth”.
    var restingDepth: CGFloat { channelDepth }

    var selectionWidth: CGFloat
    var selectionCollapsedHeight: CGFloat
    var selectionExpandedMinHeight: CGFloat
    var selectionExpandedMaxHeight: CGFloat

    /// Height fractions (0…1 from top) for the continuous carved silhouette.
    var curveStartFraction: CGFloat
    var channelStartFraction: CGFloat
    var channelEndFraction: CGFloat
    var curveEndFraction: CGFloat

    var itemSpacing: CGFloat
    var iconSize: CGFloat
    var selectedIconScale: CGFloat
    var neighbourScale: CGFloat
    var farScale: CGFloat
    var neighbourOpacity: Double
    var farOpacity: Double
    var railHeight: CGFloat
    /// Visual channel may be narrow; hit region extends inward at least this far.
    var hitSlop: CGFloat
    var revealHold: Duration
    var autoHideDelay: Duration

    /// Legacy name for the collapsed selection height.
    var apertureHeight: CGFloat { selectionCollapsedHeight }
    /// Selection capsule width (inside the channel).
    var pillWidth: CGFloat { selectionWidth }

    var itemStride: CGFloat { iconSize + itemSpacing }

    static func resolve(
        size: EdgePickerSize = .standard,
        textScale: CGFloat = 1,
        densityScale: CGFloat = 1
    ) -> EdgeLoopMetrics {
        // Channel depth / selection width from Refinement 02 size table.
        let base: (
            depth: CGFloat,
            selection: CGFloat,
            collapsed: CGFloat,
            expandMin: CGFloat,
            expandMax: CGFloat,
            icon: CGFloat,
            gap: CGFloat,
            rail: CGFloat
        )
        // Selection is a vertical pill (taller than wide), never a circle.
        // Collapsed ≈ 1.45–1.55× height/width — matches orange reference aperture.
        switch size {
        case .compact:
            base = (40, 34, 52, 84, 112, 18, 10, 236)
        case .standard:
            base = (46, 38, 58, 96, 120, 20, 12, 260)
        case .large:
            base = (54, 44, 66, 104, 132, 22, 14, 292)
        }

        let type = min(max(textScale, 0.9), 1.35)
        let dens = min(max(densityScale, 0.84), 1.18)
        let depth = (base.depth * dens).rounded()
        let icon = (base.icon * dens).rounded()
        let gap = (base.gap * dens).rounded()
        let selection = min((base.selection * dens).rounded(), depth - 2)

        // Long S-entry / straight channel / long S-exit. Symmetric by default.
        // Upper curve start ≈ 12–16%, channel ≈ 32–68%, lower curve end ≈ 84–88%.
        let curveStart: CGFloat = 0.14
        let channelStart: CGFloat = 0.33
        let channelEnd: CGFloat = 0.67
        let curveEnd: CGFloat = 0.86

        return EdgeLoopMetrics(
            channelDepth: depth,
            selectionWidth: selection,
            selectionCollapsedHeight: (base.collapsed * dens).rounded(),
            selectionExpandedMinHeight: (base.expandMin * type).rounded(),
            selectionExpandedMaxHeight: (base.expandMax * type).rounded(),
            curveStartFraction: curveStart,
            channelStartFraction: channelStart,
            channelEndFraction: channelEnd,
            curveEndFraction: curveEnd,
            itemSpacing: gap,
            iconSize: icon,
            selectedIconScale: 1.08,
            neighbourScale: 0.9,
            farScale: 0.78,
            neighbourOpacity: 0.72,
            farOpacity: 0.22,
            railHeight: base.rail,
            hitSlop: 44,
            revealHold: .seconds(1.75),
            autoHideDelay: .seconds(4)
        )
    }

    /// Vertical aperture height for a rotated whole-word label.
    /// Rotated label height ≈ unrotated text width + padding.
    func revealLength(for label: String) -> CGFloat {
        let pointSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        let font = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let needed = textWidth + 28
        return min(max(needed, selectionExpandedMinHeight), selectionExpandedMaxHeight)
    }

    /// Drag gain under 1.0 = finger travels farther than the reel (less twitchy).
    static let dragSensitivity: CGFloat = 0.78
    /// Finger travel required before a scrub commits a new selection (fraction of stride).
    static let commitThreshold: CGFloat = 0.55
}
