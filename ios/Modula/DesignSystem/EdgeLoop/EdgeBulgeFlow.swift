import SwiftUI

/// Live geometry of the shell Edge Picker's carved outline, published for content that flows around it.
@MainActor @Observable
final class EdgePickerBulge {
    static let shared = EdgePickerBulge()
    /// Global frame of the picker rail (the rect `EdgeLoopShape` is drawn in).
    var frame: CGRect = .zero
    /// Current visual depth (animates with quiet / expanded states); 0 when hidden.
    var depth: CGFloat = 0
    var trailing = true
    var fractions = SIMD4<Double>(0.14, 0.33, 0.67, 0.86)
    /// Live picker drag, -1…1 (0 at rest); rows near the picker follow it a touch.
    var drag: CGFloat = 0

    var isActive: Bool { depth > 0.5 && frame.height > 0 }

    func publish(frame: CGRect, depth: CGFloat, trailing: Bool, metrics: EdgeLoopMetrics) {
        let next = SIMD4<Double>(Double(metrics.curveStartFraction), Double(metrics.channelStartFraction), Double(metrics.channelEndFraction), Double(metrics.curveEndFraction))
        if self.frame != frame { self.frame = frame }
        if self.depth != depth { self.depth = depth }
        if self.trailing != trailing { self.trailing = trailing }
        if fractions != next { fractions = next }
    }

    func hide() { if depth != 0 { depth = 0 } }

    /// x of the picker's real outline at a global y (nil outside the rail).
    func outlineX(atGlobalY y: CGFloat) -> CGFloat? {
        guard isActive, y > frame.minY, y < frame.maxY else { return nil }
        let d = EdgeLoopShape.outlineDepth(
            atY: y - frame.minY, height: frame.height, width: frame.width, depth: depth,
            curveStartFraction: fractions.x, channelStartFraction: fractions.y,
            channelEndFraction: fractions.z, curveEndFraction: fractions.w
        )
        guard d > 0.25 else { return nil }
        return trailing ? frame.maxX - d : frame.minX + d
    }
}

/// Feed rows make room for the Edge Picker with a plain, constant layout inset per row that hugs the
/// picker's real outline (same path math, live frame) plus a small consistent gap. No shader touches
/// content: media stays perfectly rectangular, text is never warped and hit-testing is exact.
/// Only rows overlapping the rail compute anything; Reduce Motion uses the static shell inset.
struct EdgeBulgeFlow: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trailingInteractionInset) private var trailingInset
    @Environment(\.leadingInteractionInset) private var leadingInset
    @State private var rowFrame: CGRect = .zero

    /// Gap between content and the picker outline.
    private static let spacing: CGFloat = 7

    func body(content: Content) -> some View {
        let bulge = EdgePickerBulge.shared
        if !enabled {
            content
        } else if reduceMotion {
            content.padding(.trailing, trailingInset).padding(.leading, leadingInset)
        } else {
            let inset = requiredInset(bulge)
            // Very slight follow: rows beside the picker drift ≤2pt with its drag and lean ≤1pt away.
            let proximity = bulge.depth > 0 ? min(inset / max(bulge.depth, 1), 1) : 0
            let follow = bulge.drag * proximity
            content
                .padding(bulge.trailing ? .trailing : .leading, inset)
                .offset(x: (bulge.trailing ? -1 : 1) * abs(follow) * 1, y: follow * 2)
                // Measured outside the inset: the row's full-width outer frame (no feedback loop).
                .onGeometryChange(for: CGRect.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    let rail = EdgePickerBulge.shared.frame
                    let near = frame.maxY > rail.minY - 80 && frame.minY < rail.maxY + 80
                    // Quantised to 12pt so a scrolling row re-lays out ~1/12 as often (no per-frame storm).
                    guard near else { return CGRect(x: 0, y: -10_000, width: frame.width, height: 0) }
                    return CGRect(x: frame.minX.rounded(), y: (frame.minY / 12).rounded() * 12,
                                  width: frame.width.rounded(), height: (frame.height / 4).rounded() * 4)
                } action: { rowFrame = $0 }
                .animation(.smooth(duration: 0.3), value: inset)
        }
    }

    /// Deepest intrusion of the outline into this row's span, plus the gap (eased in from 0 so the
    /// row starts moving exactly where the curve leaves the edge).
    private func requiredInset(_ bulge: EdgePickerBulge) -> CGFloat {
        guard bulge.isActive, rowFrame.height > 0,
              rowFrame.maxY > bulge.frame.minY, rowFrame.minY < bulge.frame.maxY else { return 0 }
        let outerEdge = bulge.trailing ? rowFrame.maxX : rowFrame.minX
        var intrusion: CGFloat = 0
        var y = max(rowFrame.minY, bulge.frame.minY)
        let end = min(rowFrame.maxY, bulge.frame.maxY)
        while y <= end {
            if let x = bulge.outlineX(atGlobalY: y) {
                intrusion = max(intrusion, bulge.trailing ? outerEdge - x : x - outerEdge)
            }
            y += 4
        }
        if let x = bulge.outlineX(atGlobalY: end) {
            intrusion = max(intrusion, bulge.trailing ? outerEdge - x : x - outerEdge)
        }
        guard intrusion > 0 else { return 0 }
        let gap = Self.spacing * min(intrusion / Self.spacing, 1)
        // 4pt steps: text reflows only when the inset meaningfully changes.
        return ((intrusion + gap) / 4).rounded(.up) * 4
    }
}

extension View {
    /// Full-width feed row that makes room for the shell Edge Picker outline.
    func modulaEdgeFlow(enabled: Bool = true) -> some View { modifier(EdgeBulgeFlow(enabled: enabled)) }
}

/// Whether a page-level feed is actively scrolling. Decorative TimelineViews / shaders
/// read this to drop their frame rate so scrolling keeps the GPU budget.
@MainActor @Observable
final class ModulaScrollActivity {
    static let shared = ModulaScrollActivity()
    private(set) var isScrolling = false
    func set(_ scrolling: Bool) { if isScrolling != scrolling { isScrolling = scrolling } }
}
