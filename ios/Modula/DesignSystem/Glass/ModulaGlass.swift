import SwiftUI

// MARK: - Shared Liquid Glass primitives
//
// One place decides how a floating control is drawn:
// - iOS 26+: real Liquid Glass (`glassEffect`), interactive, morphing inside a
//   `ModulaGlassGroup` (GlassEffectContainer) via `modulaGlassID`.
// - Reduce Transparency, or iOS 18–25: an opaque-enough material with a hairline,
//   so text stays legible and nothing pretends to be glass.

struct ModulaGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

private struct ModulaGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: shape)
                .background((tint ?? .clear).opacity(0.18), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.6))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var value = Glass.regular
        if let tint { value = value.tint(tint.opacity(0.55)) }
        return interactive ? value.interactive() : value
    }
}

private struct ModulaGlassIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: true)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 (material fallback when unavailable or with Reduce Transparency).
    func modulaGlass<S: Shape>(in shape: S, interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(ModulaGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    /// Identity for glass morphing between states inside a `ModulaGlassGroup`.
    func modulaGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(ModulaGlassIDModifier(id: id, namespace: namespace))
    }
}

/// Round Liquid Glass icon button (attach, mic, close, reload…).
struct ModulaGlassIconButton: View {
    let title: String
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color? = nil
    var foreground: Color = .primary
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), tint: tint)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }
}

/// Liquid Glass search field used by every custom search bar.
struct ModulaGlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .modulaGlass(in: Capsule())
    }
}
