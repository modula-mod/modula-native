import SwiftUI

/// Cut-in silhouette for `ModulaEdgeLoop`.
///
/// Camera-Control style bump: the notch is one fixed size — a flat waist deep
/// enough for the fully grown word pill, blended into the physical edge with
/// tangent-smooth shoulders. It never grows or shrinks with selection; the reel
/// scrolls through it.
struct EdgeLoopShape: Shape {
    /// Visible depth from the physical edge to the waist, in points.
    var restingDepth: CGFloat = EdgeLoopEngine.restingWidth
    var position: EdgeLoopPosition = .trailing

    nonisolated func path(in rect: CGRect) -> Path {
        let depth = min(max(restingDepth + 6, 30), rect.width)
        // Flat waist tall enough for the fully grown pill plus a neighbour icon
        // and its gaps on each side — first neighbours always sit inside the notch.
        let waistHalf = min(
            EdgeLoopEngine.revealedWidth / 2 + EdgeLoopEngine.itemGap + EdgeLoopEngine.iconSize + 6,
            rect.height * 0.4
        )
        let shoulder = max((rect.height / 2) - waistHalf, 24)
        let edgeX = position == .trailing ? rect.maxX : rect.minX
        let waistX = position == .trailing ? rect.maxX - depth : rect.minX + depth

        var path = Path()
        path.move(to: CGPoint(x: edgeX, y: rect.minY))
        path.addLine(to: CGPoint(x: edgeX, y: rect.maxY))
        // Bottom shoulder: leave the edge vertically, arrive at the waist vertically.
        path.addCurve(
            to: CGPoint(x: waistX, y: rect.midY + waistHalf),
            control1: CGPoint(x: edgeX, y: rect.maxY - shoulder * 0.62),
            control2: CGPoint(x: waistX, y: rect.midY + waistHalf + shoulder * 0.62)
        )
        path.addLine(to: CGPoint(x: waistX, y: rect.midY - waistHalf))
        // Top shoulder, mirrored.
        path.addCurve(
            to: CGPoint(x: edgeX, y: rect.minY),
            control1: CGPoint(x: waistX, y: rect.midY - waistHalf - shoulder * 0.62),
            control2: CGPoint(x: edgeX, y: rect.minY + shoulder * 0.62)
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
