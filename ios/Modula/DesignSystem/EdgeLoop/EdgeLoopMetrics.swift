import CoreGraphics
import Foundation
import UIKit

/// Internal semantic metrics for the Edge Picker. Resolved from size, Dynamic Type,
/// and density — not a public customization API.
struct EdgeLoopMetrics: Equatable, Sendable {
    var restingDepth: CGFloat
    var apertureHeight: CGFloat
    var pillWidth: CGFloat
    var revealMinWidth: CGFloat
    var revealMaxWidth: CGFloat
    var itemSpacing: CGFloat
    var iconSize: CGFloat
    var selectedIconScale: CGFloat
    var neighbourScale: CGFloat
    var farScale: CGFloat
    var neighbourOpacity: Double
    var farOpacity: Double
    var railHeight: CGFloat
    var hitSlop: CGFloat
    var revealHold: Duration
    var autoHideDelay: Duration
    var waistExtra: CGFloat

    var itemStride: CGFloat { iconSize + itemSpacing }

    static func resolve(
        size: EdgePickerSize = .standard,
        textScale: CGFloat = 1,
        densityScale: CGFloat = 1
    ) -> EdgeLoopMetrics {
        let base: (depth: CGFloat, aperture: CGFloat, icon: CGFloat, gap: CGFloat, revealMin: CGFloat, revealMax: CGFloat, rail: CGFloat)
        switch size {
        case .compact:
            base = (40, 40, 18, 10, 78, 112, 220)
        case .standard:
            base = (46, 44, 20, 12, 84, 126, 244)
        case .large:
            base = (54, 50, 22, 14, 96, 148, 280)
        }
        let type = min(max(textScale, 0.9), 1.35)
        let dens = min(max(densityScale, 0.84), 1.18)
        let depth = (base.depth * dens).rounded()
        let icon = (base.icon * dens).rounded()
        let gap = (base.gap * dens).rounded()
        return EdgeLoopMetrics(
            restingDepth: depth,
            apertureHeight: (base.aperture * dens).rounded(),
            pillWidth: max(depth - 2, 36),
            revealMinWidth: (base.revealMin * type).rounded(),
            revealMaxWidth: (base.revealMax * type).rounded(),
            itemSpacing: gap,
            iconSize: icon,
            selectedIconScale: 1.1,
            neighbourScale: 0.92,
            farScale: 0.82,
            neighbourOpacity: 0.85,
            farOpacity: 0.28,
            railHeight: base.rail,
            hitSlop: 44,
            revealHold: .seconds(1.75),
            autoHideDelay: .seconds(4),
            waistExtra: icon + gap + 6
        )
    }

    /// Measured horizontal reveal width for a label, clamped to semantic min/max.
    func revealWidth(for label: String) -> CGFloat {
        let pointSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        let font = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
        let text = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let content = text + iconSize + 28
        return min(max(content, revealMinWidth), revealMaxWidth)
    }
}
