import SwiftUI

/// The edge silhouette follows the Camera Control-inspired reference: a stable
/// right edge and one continuous concave-to-convex loop on the content side.
struct ModulaRailShape: Shape {
    var revealProgress: CGFloat

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let p = min(max(revealProgress, 0), 1)
        // Slightly slimmer attachment than N2: less bulbous waist/shoulder.
        let shoulder = 18 + (p * 7)
        let waist = 6 - (p * 1.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder - 22),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - shoulder),
            control2: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder + 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.minY + shoulder + 22),
            control1: CGPoint(x: rect.minX, y: rect.midY + 36 + (p * 16)),
            control2: CGPoint(x: rect.minX, y: rect.midY - 36 - (p * 16))
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.minX + waist, y: rect.minY + shoulder - 2),
            control2: CGPoint(x: rect.maxX, y: rect.minY + shoulder)
        )
        path.closeSubpath()
        return path
    }
}

struct ModulaContextRail: View {
    struct Interaction: Equatable {
        var isScrolling = false
        var keyboardVisible = false
        var immersive = false
        static let idle = Self()
    }

    let route: AppRoute
    var interaction: Interaction = .idle

    var body: some View {
        ShellEdgeLoop(route: route, interaction: interaction)
    }
}

extension View {
    @ViewBuilder
    func modulaChrome<S: Shape>(in shape: S, opaque: Bool) -> some View {
        if #available(iOS 26.0, *), !opaque {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(opaque ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.stroke(.primary.opacity(opaque ? 0.14 : 0.08), lineWidth: 0.75))
        }
    }

    @ViewBuilder
    func modulaAccessorySurface(nativeHosted: Bool, opaque: Bool) -> some View {
        if nativeHosted {
            self
        } else {
            self
                .modulaChrome(in: Capsule(), opaque: opaque)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
    }
}


/// Dismissible action-error banner shared by Home / Discover / Activity.
/// Has a real 44pt close button and is announced to VoiceOver on appear.
struct ModulaErrorBanner: View {
    let message: String
    var identifier: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: ModulaSpacing.xs) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, ModulaSpacing.md)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .onChange(of: message) { _, next in AccessibilityNotification.Announcement(next).post() }
    }
}
