import SwiftUI

// MARK: - Material tokens

/// Semantic materials. Views ask for meaning, not a hardcoded `.ultraThinMaterial`.
enum ModulaMaterial: String, CaseIterable, Sendable {
    case none
    case content
    case floating
    case control
    case immersiveOverlay

    @MainActor
    func style(opaque: Bool, scheme: ColorScheme) -> AnyShapeStyle {
        if opaque {
            switch self {
            case .none:
                return AnyShapeStyle(Color.clear)
            case .content:
                return AnyShapeStyle(Color(uiColor: scheme == .dark ? .secondarySystemBackground : .systemBackground))
            case .floating, .control:
                return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            case .immersiveOverlay:
                return AnyShapeStyle(Color.black.opacity(0.42))
            }
        }
        switch self {
        case .none:
            return AnyShapeStyle(Color.clear)
        case .content:
            return AnyShapeStyle(.thinMaterial)
        case .floating:
            return AnyShapeStyle(.regularMaterial)
        case .control:
            return AnyShapeStyle(.ultraThinMaterial)
        case .immersiveOverlay:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

// MARK: - Shape roles

enum ModulaShapeRole: String, CaseIterable, Sendable {
    case canvas
    case contentCard
    case control
    case capsule
    case floatingControl
    case media
    case edgeLoop
    case avatarPocket

    func radius(for interface: AppearanceStore.InterfaceShape) -> CGFloat {
        let (soft, balanced, precise): (CGFloat, CGFloat, CGFloat) = switch self {
        case .canvas: (0, 0, 0)
        case .contentCard: (24, 17, 10)
        case .control: (18, 14, 10)
        case .capsule: (999, 999, 999)
        case .floatingControl: (22, 18, 14)
        case .media: (22, 16, 10)
        case .edgeLoop: (28, 24, 18)
        case .avatarPocket: (56, 52, 48)
        }
        switch interface {
        case .soft: return soft
        case .balanced: return balanced
        case .precise: return precise
        }
    }
}

enum ModulaDepth: String, CaseIterable, Sendable {
    case none
    case raised
    case floating
    case overlay

    var shadowRadius: CGFloat {
        switch self {
        case .none: 0
        case .raised: 6
        case .floating: 12
        case .overlay: 18
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .none: 0
        case .raised: 2
        case .floating: 6
        case .overlay: 10
        }
    }

    var shadowOpacity: CGFloat {
        switch self {
        case .none: 0
        case .raised: 0.06
        case .floating: 0.1
        case .overlay: 0.16
        }
    }
}

// MARK: - Trailing interaction safe area

/// Shared layout inset so the shell Edge Loop and in-content PostActionRail do not collide.
enum TrailingInteractionSafeArea {
    /// Visible resting depth of the shell Edge Loop, including a small optical gap.
    static let edgeLoop: CGFloat = 52
    /// In-content action rail width plus gap from the media edge.
    static let postActionRail: CGFloat = 56
    /// Minimum extra trailing inset applied to feed/profile content when the shell loop is visible.
    static let contentClearance: CGFloat = 36
}

private struct TrailingInteractionInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var trailingInteractionInset: CGFloat {
        get { self[TrailingInteractionInsetKey.self] }
        set { self[TrailingInteractionInsetKey.self] = newValue }
    }
}

// MARK: - Count formatting

enum ModulaCountFormat {
    static func compact(_ value: Int) -> String? {
        guard value > 0 else { return nil }
        if value < 1000 { return "\(value)" }
        if value < 10_000 {
            return decimalKilo(Double(value) / 1000.0)
        }
        if value < 100_000 {
            return decimalKilo(Double(value) / 1000.0)
        }
        if value < 1_000_000 {
            return "\(value / 1000)K"
        }
        return decimalKilo(Double(value) / 1_000_000.0).replacingOccurrences(of: "K", with: "M")
    }

    private static func decimalKilo(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))K"
        }
        return String(format: "%.1fK", rounded)
    }
}

// MARK: - View application

private struct ModulaMaterialModifier<S: Shape>: ViewModifier {
    let material: ModulaMaterial
    let shape: S
    var depth: ModulaDepth = .none
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let styled = content
            .background(material.style(opaque: opaque, scheme: scheme), in: shape)
        if material == .none || depth == .none {
            styled
        } else {
            styled.shadow(
                color: .black.opacity(depth.shadowOpacity),
                radius: depth.shadowRadius,
                y: depth.shadowY
            )
        }
    }
}

extension View {
    func modulaMaterial<S: Shape>(
        _ material: ModulaMaterial,
        in shape: S,
        depth: ModulaDepth = .none
    ) -> some View {
        modifier(ModulaMaterialModifier(material: material, shape: shape, depth: depth))
    }

    func modulaShapeRadius(_ role: ModulaShapeRole) -> CGFloat {
        // Fallback when the environment is unavailable (previews / tests).
        role.radius(for: .balanced)
    }
}

extension AppearanceStore.InterfaceShape {
    func radius(for role: ModulaShapeRole) -> CGFloat {
        role.radius(for: self)
    }
}
