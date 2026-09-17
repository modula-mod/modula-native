import SwiftUI

/// Continuous edge-carved silhouette for `ModulaEdgeLoop`.
///
/// One path — the screen edge bends inward into a flat waist sized for the
/// selection aperture. Depth grows when the label reveals horizontally.
/// Left and right are mirrored paths, never a 180° rotation.
struct EdgeLoopShape: Shape {
    /// Visible depth from the physical edge to the waist, in points.
    var depth: CGFloat = EdgeLoopEngine.restingWidth
    var position: EdgeLoopPosition = .trailing
    /// Half-height of the flat waist (selection aperture region).
    var waistHalf: CGFloat = 72

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(depth, waistHalf) }
        set {
            depth = newValue.first
            waistHalf = newValue.second
        }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let carved = min(max(depth, 28), rect.width)
        let half = min(max(waistHalf, 36), rect.height * 0.42)
        let shoulder = max((rect.height / 2) - half, 28)
        let edgeX = position == .trailing ? rect.maxX : rect.minX
        let waistX = position == .trailing ? rect.maxX - carved : rect.minX + carved

        var path = Path()
        path.move(to: CGPoint(x: edgeX, y: rect.minY))
        path.addLine(to: CGPoint(x: edgeX, y: rect.maxY))
        // Bottom shoulder: leave the edge vertically, arrive at the waist vertically.
        path.addCurve(
            to: CGPoint(x: waistX, y: rect.midY + half),
            control1: CGPoint(x: edgeX, y: rect.maxY - shoulder * 0.55),
            control2: CGPoint(x: waistX, y: rect.midY + half + shoulder * 0.55)
        )
        path.addLine(to: CGPoint(x: waistX, y: rect.midY - half))
        // Top shoulder, mirrored.
        path.addCurve(
            to: CGPoint(x: edgeX, y: rect.minY),
            control1: CGPoint(x: waistX, y: rect.midY - half - shoulder * 0.55),
            control2: CGPoint(x: edgeX, y: rect.minY + shoulder * 0.55)
        )
        path.closeSubpath()
        return path
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
