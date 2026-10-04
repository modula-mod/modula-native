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

/// Feed rows flow gently around the Edge Picker.
/// - Real layout: a trailing inset equal to the Gaussian peak over the row (text re-wraps, media
///   re-fits at its aspect ratio; nothing is squeezed, clipped or cut out; hit-testing is exact).
/// - Shader: a pure horizontal translation that lets each line drift back toward the picker where
///   the curve is weaker, so the row edge follows the bulge smoothly.
/// - Bulge inputs are eased (Animatable) so picker moves/expansion never snap.
/// Only rows within the falloff band do any work; Reduce Motion uses a static inset.
struct EdgeBulgeFlow: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trailingInteractionInset) private var trailingInset
    @Environment(\.leadingInteractionInset) private var leadingInset

    func body(content: Content) -> some View {
        let bulge = EdgePickerBulge.shared
        if !enabled {
            content
        } else if reduceMotion {
            content.padding(.trailing, trailingInset).padding(.leading, leadingInset)
        } else {
            let height = max(bulge.frame.height, 1)
            content.modifier(EdgeFlowShift(
                centerY: bulge.frame.midY,
                // sigma = 0.55 x bulge height: visible over roughly 2.5x the bulge height.
                sigma: height * 0.55,
                // Peak displacement a little under the bulge depth.
                amplitude: bulge.isActive ? bulge.depth * 0.85 : 0,
                trailing: bulge.trailing
            ))
            .animation(.smooth(duration: 0.45), value: bulge.frame.midY)
            .animation(.smooth(duration: 0.45), value: bulge.depth)
            .animation(.smooth(duration: 0.45), value: bulge.frame.height)
        }
    }
}

private struct EdgeFlowShift: ViewModifier, Animatable {
    var centerY: CGFloat
    var sigma: CGFloat
    var amplitude: CGFloat
    var trailing: Bool
    @State private var rowFrame: CGRect = .zero

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(centerY, AnimatablePair(sigma, amplitude)) }
        set { centerY = newValue.first; sigma = newValue.second.first; amplitude = newValue.second.second }
    }

    private func gaussian(_ y: CGFloat) -> CGFloat {
        let d = (y - centerY) / max(sigma, 1)
        return exp(-0.5 * d * d)
    }

    func body(content: Content) -> some View {
        let band = 3 * sigma
        let near = amplitude > 0.5 && rowFrame.height > 0 && rowFrame.maxY > centerY - band && rowFrame.minY < centerY + band
        // Peak of the falloff over the row's span.
        let peakG: CGFloat = near ? (rowFrame.minY...rowFrame.maxY ~= centerY ? 1 : max(gaussian(rowFrame.minY), gaussian(rowFrame.maxY))) : 0
        // Quantized to whole points so scrolling doesn't re-layout on sub-point changes.
        let inset = (amplitude * peakG).rounded()
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                let frame = proxy.frame(in: .global)
                let active = frame.maxY > centerY - band - 120 && frame.minY < centerY + band + 120
                return active ? frame.integral : CGRect(x: 0, y: -10_000, width: frame.width, height: 0)
            } action: { rowFrame = $0 }
            .distortionEffect(
                ShaderLibrary.modulaEdgeFlow(
                    .float4(Float(centerY), Float(sigma), Float(amplitude), trailing ? 1 : -1),
                    .float2(Float(rowFrame.minY), Float(inset))
                ),
                maxSampleOffset: CGSize(width: inset + 1, height: 0),
                isEnabled: inset > 0.5
            )
            .padding(trailing ? .trailing : .leading, inset)
    }
}

extension View {
    /// Full-width feed row that flows around the shell Edge Picker bulge.
    func modulaEdgeFlow(enabled: Bool = true) -> some View { modifier(EdgeBulgeFlow(enabled: enabled)) }
}
