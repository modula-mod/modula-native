import SwiftUI

/// Live geometry of the shell Edge Picker's carved bulge, published for content that flows around it.
@MainActor @Observable
final class EdgePickerBulge {
    static let shared = EdgePickerBulge()
    /// Global frame of the picker rail (full carved silhouette height).
    var frame: CGRect = .zero
    /// Current visual depth (animates with quiet / expanded states); 0 when hidden.
    var depth: CGFloat = 0
    var trailing = true
    var fractions = SIMD4<Float>(0.14, 0.33, 0.67, 0.86)

    var isActive: Bool { depth > 0.5 && frame.height > 0 }

    func publish(frame: CGRect, depth: CGFloat, trailing: Bool, metrics: EdgeLoopMetrics) {
        let next = SIMD4<Float>(Float(metrics.curveStartFraction), Float(metrics.channelStartFraction), Float(metrics.channelEndFraction), Float(metrics.curveEndFraction))
        if self.frame != frame { self.frame = frame }
        if self.depth != depth { self.depth = depth }
        if self.trailing != trailing { self.trailing = trailing }
        if fractions != next { fractions = next }
    }

    func hide() { if depth != 0 { depth = 0 } }

    /// Bulge depth at a global y.
    func depth(atGlobalY y: CGFloat) -> CGFloat {
        guard isActive else { return 0 }
        let t = Float((y - frame.minY) / max(frame.height, 1))
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let u = min(max((x - a) / (b - a), 0), 1); return u * u * (3 - 2 * u) }
        let profile = min(smooth(fractions.x, fractions.y, t), 1 - smooth(fractions.z, fractions.w, t))
        return depth * CGFloat(max(profile, 0))
    }

    /// Smallest depth over a vertical span (the row's uniform squeeze, keeps hit-testing aligned).
    func minimumDepth(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
        guard isActive, bottom > frame.minY, top < frame.maxY else { return 0 }
        var lowest = CGFloat.greatestFiniteMagnitude
        var y = top
        while y <= bottom { lowest = min(lowest, depth(atGlobalY: y)); y += 6 }
        return min(lowest, depth(atGlobalY: bottom))
    }
}

/// Feed rows flow around the Edge Picker: a uniform horizontal scale (real geometry, so taps land
/// where content is drawn) plus a Metal distortion for the per-line curve. Only rows that intersect
/// the bulge do any work; Reduce Motion uses a static inset.
struct EdgeBulgeFlow: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trailingInteractionInset) private var trailingInset
    @Environment(\.leadingInteractionInset) private var leadingInset
    @State private var rowFrame: CGRect = .zero

    func body(content: Content) -> some View {
        let bulge = EdgePickerBulge.shared
        if !enabled {
            content
        } else if reduceMotion {
            content.padding(.trailing, trailingInset).padding(.leading, leadingInset)
        } else {
            let intersects = bulge.isActive && rowFrame.maxY > bulge.frame.minY && rowFrame.minY < bulge.frame.maxY && rowFrame.width > 0
            let minDepth = intersects ? bulge.minimumDepth(from: rowFrame.minY, to: rowFrame.maxY) : 0
            let width = max(rowFrame.width, 1)
            let rowScale = intersects ? (width - minDepth) / width : 1
            content
                // Only rows near the picker report frames each scroll frame; others stay quiet.
                .onGeometryChange(for: CGRect.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    let band = EdgePickerBulge.shared.frame.insetBy(dx: 0, dy: -240)
                    return frame.intersects(band) ? frame.integral : CGRect(x: 0, y: -10_000, width: frame.width, height: 0)
                } action: { rowFrame = $0 }
                .distortionEffect(
                    ShaderLibrary.modulaEdgeFlow(
                        .float4(Float(bulge.frame.minY), Float(bulge.frame.height), Float(bulge.depth), bulge.trailing ? 1 : -1),
                        .float4(bulge.fractions.x, bulge.fractions.y, bulge.fractions.z, bulge.fractions.w),
                        .float3(Float(rowFrame.minY), Float(width), Float(rowScale))
                    ),
                    maxSampleOffset: CGSize(width: bulge.depth + 2, height: 0),
                    isEnabled: intersects
                )
                .scaleEffect(x: rowScale, y: 1, anchor: bulge.trailing ? .leading : .trailing)
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: bulge.depth)
        }
    }
}

extension View {
    /// Full-width feed row that flows around the shell Edge Picker bulge.
    func modulaEdgeFlow(enabled: Bool = true) -> some View { modifier(EdgeBulgeFlow(enabled: enabled)) }
}
