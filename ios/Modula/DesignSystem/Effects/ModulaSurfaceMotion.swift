import SwiftUI

/// Shared surface motion for the v3 surfaces (Profile showcase, Settings cards, Activity
/// grouping, Search scopes, onboarding picker). One spring family keeps transitions
/// predictable (Jakob's law); under Reduce Motion everything becomes a short cross-fade.
enum ModulaSurfaceMotion {
    static func animation(reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.84)
    }

    static func transition(reduce: Bool) -> AnyTransition {
        reduce
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: 6)),
                removal: .opacity
            )
    }
}

private struct ModulaSurfaceAnimationModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    func body(content: Content) -> some View {
        content.animation(ModulaSurfaceMotion.animation(reduce: ModulaEffectGate.reduceMotion(systemReduceMotion)), value: value)
    }
}

private struct ModulaSurfaceTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    func body(content: Content) -> some View {
        content.transition(ModulaSurfaceMotion.transition(reduce: ModulaEffectGate.reduceMotion(systemReduceMotion)))
    }
}

extension View {
    /// Animates changes to `value` with the surface spring, or a cross-fade under Reduce Motion.
    func modulaSurfaceAnimation<V: Equatable>(value: V) -> some View {
        modifier(ModulaSurfaceAnimationModifier(value: value))
    }

    /// Insertion/removal transition that respects Reduce Motion.
    func modulaSurfaceTransition() -> some View {
        modifier(ModulaSurfaceTransitionModifier())
    }
}
