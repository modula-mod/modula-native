import SwiftUI

// MARK: - Surface effects (Metal)
//
// Thin SwiftUI wrappers over `ModulaSurfaceEffects.metal`. Each wrapper:
// - freezes on a static frame (or disables itself) when Reduce Motion is on,
// - pauses its TimelineView when the effect is inactive,
// - wraps time into a small range so Float precision never degrades.

enum ModulaSurfaceClock {
    /// Seconds wrapped to keep shader math in Float range.
    static func seconds(_ date: Date) -> Float {
        Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
    }
}

/// Light sweep + grain over a hero icon tile.
struct ModulaHeroSheenModifier: ViewModifier {
    var intensity: Double = 1
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// System Reduce Motion or Settings → Battery & Data → Extra motion reduction.
    private var reduceMotion: Bool { systemReduceMotion || ModulaPreferences.extraMotionReduction }

    func body(content: Content) -> some View {
        let animate = isActive && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { context in
            let time = animate ? ModulaSurfaceClock.seconds(context.date) : 2.2
            content.visualEffect { view, proxy in
                view.colorEffect(
                    ShaderLibrary.modulaHeroSheen(
                        .float2(proxy.size),
                        .float(time),
                        .float(Float(intensity))
                    )
                )
            }
        }
    }
}

extension View {
    /// Diagonal sheen and grain. Static under Reduce Motion.
    func modulaHeroSheen(intensity: Double = 1, isActive: Bool = true) -> some View {
        modifier(ModulaHeroSheenModifier(intensity: intensity, isActive: isActive))
    }

    /// Refraction ripple from the tap point. Disabled under Reduce Motion.
    func modulaTapRipple(amplitude: Double = 9) -> some View {
        modifier(ModulaTapRippleModifier(amplitude: amplitude))
    }
}

/// Live radar scope. `energy` 1 = sweeping, 0 = static scope (no sweep, no pulse).
struct ModulaRadarScope: View {
    var tint: Color
    var energy: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// System Reduce Motion or Settings → Battery & Data → Extra motion reduction.
    private var reduceMotion: Bool { systemReduceMotion || ModulaPreferences.extraMotionReduction }

    var body: some View {
        let animate = energy > 0 && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animate)) { context in
            let time = animate ? ModulaSurfaceClock.seconds(context.date) : 0.9
            let shownEnergy = reduceMotion ? min(energy, 0.6) : energy
            Rectangle()
                .fill(Color.white)
                .visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.modulaStatusRadar(
                            .float2(proxy.size),
                            .float(time),
                            .color(tint),
                            .float(Float(shownEnergy))
                        )
                    )
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ModulaTapRippleModifier: ViewModifier {
    var amplitude: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// System Reduce Motion or Settings → Battery & Data → Extra motion reduction.
    private var reduceMotion: Bool { systemReduceMotion || ModulaPreferences.extraMotionReduction }
    @State private var origin: CGPoint = .zero
    @State private var trigger = 0

    func body(content: Content) -> some View {
        let point = origin
        let amp = amplitude
        if reduceMotion {
            content
        } else {
            content
                .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, progress in
                    view.visualEffect { effect, proxy in
                        effect.layerEffect(
                            ShaderLibrary.modulaTapRipple(
                                .float2(point),
                                .float2(proxy.size),
                                .float(Float(progress)),
                                .float(Float(amp))
                            ),
                            maxSampleOffset: CGSize(width: amp, height: amp),
                            isEnabled: progress > 0 && progress < 1
                        )
                    }
                } keyframes: { _ in
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0, duration: 0.62, timingCurve: .easeOut)
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        origin = value.location
                        trigger += 1
                    }
                )
        }
    }
}
