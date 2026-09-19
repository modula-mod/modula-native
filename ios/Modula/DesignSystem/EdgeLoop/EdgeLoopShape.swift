import SwiftUI

/// Continuous edge-carved silhouette for the shell Edge Picker.
///
/// One path — the physical screen edge bends inward through long cubic
/// transitions into a nearly straight central channel, then exits with a
/// mirrored lower curve. The outer silhouette is stable; label reveal expands
/// only the selection aperture inside the channel.
///
/// Left and right are mirrored mathematically. Content (icons/text) is never
/// flipped with a negative scale.
typealias EdgePickerCarvedShape = EdgeLoopShape

struct EdgeLoopShape: Shape {
    /// Visible channel depth from the physical edge, in points.
    var depth: CGFloat = 46
    var position: EdgeLoopPosition = .trailing

    /// Height fractions (0…1 from top). Defaults match Standard orange-reference geometry.
    var curveStartFraction: CGFloat = 0.14
    var channelStartFraction: CGFloat = 0.33
    var channelEndFraction: CGFloat = 0.67
    var curveEndFraction: CGFloat = 0.86

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    init(
        depth: CGFloat = 46,
        position: EdgeLoopPosition = .trailing,
        curveStartFraction: CGFloat = 0.14,
        channelStartFraction: CGFloat = 0.33,
        channelEndFraction: CGFloat = 0.67,
        curveEndFraction: CGFloat = 0.86
    ) {
        self.depth = depth
        self.position = position
        self.curveStartFraction = curveStartFraction
        self.channelStartFraction = channelStartFraction
        self.channelEndFraction = channelEndFraction
        self.curveEndFraction = curveEndFraction
    }

    init(depth: CGFloat, position: EdgeLoopPosition, metrics: EdgeLoopMetrics) {
        self.init(
            depth: depth,
            position: position,
            curveStartFraction: metrics.curveStartFraction,
            channelStartFraction: metrics.channelStartFraction,
            channelEndFraction: metrics.channelEndFraction,
            curveEndFraction: metrics.curveEndFraction
        )
    }

    /// Legacy waist-based init — waist is ignored; proportions come from defaults.
    /// Kept so older call sites compile during refinement.
    init(depth: CGFloat, position: EdgeLoopPosition, waistHalf: CGFloat) {
        self.init(depth: depth, position: position)
        _ = waistHalf
    }

    nonisolated func path(in rect: CGRect) -> Path {
        Self.carvedPath(
            in: rect,
            depth: depth,
            position: position,
            curveStartFraction: curveStartFraction,
            channelStartFraction: channelStartFraction,
            channelEndFraction: channelEndFraction,
            curveEndFraction: curveEndFraction
        )
    }

    /// Pure geometry helper for unit tests.
    nonisolated static func carvedPath(
        in rect: CGRect,
        depth: CGFloat,
        position: EdgeLoopPosition,
        curveStartFraction: CGFloat = 0.14,
        channelStartFraction: CGFloat = 0.33,
        channelEndFraction: CGFloat = 0.67,
        curveEndFraction: CGFloat = 0.86
    ) -> Path {
        let carved = min(max(depth, 28), max(rect.width, 28))
        let h = max(rect.height, 1)

        // Clamp fractions to a monotonic order.
        var y1 = min(max(curveStartFraction, 0.06), 0.28) * h
        var y2 = min(max(channelStartFraction, 0.22), 0.42) * h
        var y3 = min(max(channelEndFraction, 0.58), 0.78) * h
        var y4 = min(max(curveEndFraction, 0.72), 0.94) * h
        if y2 <= y1 { y2 = y1 + h * 0.12 }
        if y3 <= y2 { y3 = y2 + h * 0.2 }
        if y4 <= y3 { y4 = y3 + h * 0.12 }
        y1 = min(y1, h * 0.4)
        y4 = min(max(y4, y3 + 1), h)

        let edgeX = position == .trailing ? rect.maxX : rect.minX
        let waistX = position == .trailing ? rect.maxX - carved : rect.minX + carved

        // Long S-transitions: stay near the edge until the curve zone, then
        // strengthen the bend and arrive vertically into the straight channel.
        let upperSpan = max(y2 - y1, 1)
        let lowerSpan = max(y4 - y3, 1)

        var path = Path()
        // Down the physical edge, then inward via lower curve, up the channel,
        // outward via upper curve. Fill = carved glass between edge and waist.
        path.move(to: CGPoint(x: edgeX, y: rect.minY))
        path.addLine(to: CGPoint(x: edgeX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: waistX, y: y3),
            control1: CGPoint(x: edgeX, y: y4),
            control2: CGPoint(x: waistX, y: y3 + lowerSpan * 0.55)
        )
        path.addLine(to: CGPoint(x: waistX, y: y2))
        path.addCurve(
            to: CGPoint(x: edgeX, y: rect.minY),
            control1: CGPoint(x: waistX, y: y2 - upperSpan * 0.55),
            control2: CGPoint(x: edgeX, y: y1)
        )
        path.closeSubpath()
        return path
    }

    /// Key Y landmarks in the given rect (for debug overlays / tests).
    nonisolated static func landmarks(
        in rect: CGRect,
        curveStartFraction: CGFloat = 0.14,
        channelStartFraction: CGFloat = 0.33,
        channelEndFraction: CGFloat = 0.67,
        curveEndFraction: CGFloat = 0.86
    ) -> (curveStart: CGFloat, channelTop: CGFloat, channelBottom: CGFloat, curveEnd: CGFloat, selectionCentre: CGFloat) {
        let h = max(rect.height, 1)
        let y1 = curveStartFraction * h
        let y2 = channelStartFraction * h
        let y3 = channelEndFraction * h
        let y4 = curveEndFraction * h
        return (y1, y2, y3, y4, (y2 + y3) / 2)
    }
}

/// Contained reel silhouette — same aperture idea, not docked to the device edge.
struct ContainedLoopShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.42
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        return path
    }
}
