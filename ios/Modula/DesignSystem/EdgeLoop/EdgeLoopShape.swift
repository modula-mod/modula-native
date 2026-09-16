import SwiftUI

/// Cut-in silhouette for `ModulaEdgeLoop`.
///
/// The notch height is stable. Items move through a centred aperture; the outer
/// rail does not grow and shrink with every selection.
struct EdgeLoopShape: Shape {
    /// Visible depth from the physical trailing edge, in points.
    var restingDepth: CGFloat = EdgeLoopEngine.restingWidth
    var position: EdgeLoopPosition = .trailing

    nonisolated func path(in rect: CGRect) -> Path {
        position == .leading ? leadingPath(in: rect) : trailingPath(in: rect)
    }

    nonisolated private func trailingPath(in rect: CGRect) -> Path {
        let depth = min(max(restingDepth, 28), rect.width)
        let left = rect.maxX - depth
        let aperture: CGFloat = 38
        let shoulder: CGFloat = 26
        let waistPull: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: left + waistPull, y: rect.midY + aperture + shoulder),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - shoulder),
            control2: CGPoint(x: left + waistPull, y: rect.maxY - 10)
        )
        path.addCurve(
            to: CGPoint(x: left + waistPull, y: rect.midY - aperture - shoulder),
            control1: CGPoint(x: left - 4, y: rect.midY + aperture),
            control2: CGPoint(x: left - 4, y: rect.midY - aperture)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: left + waistPull, y: rect.minY + 10),
            control2: CGPoint(x: rect.maxX, y: rect.minY + shoulder)
        )
        path.closeSubpath()
        return path
    }

    nonisolated private func leadingPath(in rect: CGRect) -> Path {
        let depth = min(max(restingDepth, 28), rect.width)
        let right = rect.minX + depth
        let aperture: CGFloat = 38
        let shoulder: CGFloat = 26
        let waistPull: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: right - waistPull, y: rect.midY + aperture + shoulder),
            control1: CGPoint(x: rect.minX, y: rect.maxY - shoulder),
            control2: CGPoint(x: right - waistPull, y: rect.maxY - 10)
        )
        path.addCurve(
            to: CGPoint(x: right - waistPull, y: rect.midY - aperture - shoulder),
            control1: CGPoint(x: right + 4, y: rect.midY + aperture),
            control2: CGPoint(x: right + 4, y: rect.midY - aperture)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: right - waistPull, y: rect.minY + 10),
            control2: CGPoint(x: rect.minX, y: rect.minY + shoulder)
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
