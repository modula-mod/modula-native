import Observation
import SwiftUI

enum ModulaOverlayRoute: String, CaseIterable, Sendable {
    case modal
    case anchored
    case floating
    case context
    case bottom
    case fullScreen
}

enum ModulaOverlayAnchor: Sendable {
    case center
    case top
    case bottom
    case leading
    case trailing

    var alignment: Alignment {
        switch self {
        case .center: .center
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

enum ModulaOverlayBackground: Sendable {
    case none
    case dimmed
    case material
}

enum ModulaOverlayDismissBehavior: Sendable {
    case disabled
    case tapOutside
    case interactive

    var allowsTapOutside: Bool { self != .disabled }
    var allowsDrag: Bool { self == .interactive }
}

struct ModulaOverlayPresentation: Equatable, Sendable {
    var route: ModulaOverlayRoute
    var anchor: ModulaOverlayAnchor
    var background: ModulaOverlayBackground
    var dismissBehavior: ModulaOverlayDismissBehavior

    static let modal = Self(route: .modal, anchor: .center, background: .dimmed, dismissBehavior: .tapOutside)
    static let floating = Self(route: .floating, anchor: .center, background: .none, dismissBehavior: .interactive)
    static let bottom = Self(route: .bottom, anchor: .bottom, background: .dimmed, dismissBehavior: .interactive)
    static let fullScreen = Self(route: .fullScreen, anchor: .center, background: .none, dismissBehavior: .disabled)
}

/// A presentation-only host. It deliberately owns no navigation or business state.
struct ModulaOverlayHost<Content: View, Overlay: View>: View {
    @Binding var isPresented: Bool
    let presentation: ModulaOverlayPresentation
    @ViewBuilder var content: () -> Content
    @ViewBuilder var overlay: () -> Overlay

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var overlayFocused: Bool
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        content()
            .overlay {
                if isPresented {
                    ZStack(alignment: presentation.anchor.alignment) {
                        background
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard presentation.dismissBehavior.allowsTapOutside else { return }
                                dismiss()
                            }

                        overlay()
                            .offset(dragOffset)
                            .transition(transition)
                            .accessibilityFocused($overlayFocused)
                            .accessibilityAddTraits(.isModal)
                            .gesture(dismissGesture)
                    }
                    .ignoresSafeArea(presentation.route == .fullScreen ? .all : [])
                    .zIndex(1_000)
                    .onAppear {
                        overlayFocused = true
                        HapticEngine.shared.play(.contextOpened)
                    }
                }
            }
            .animation(
                ModulaMotion.animation(.overlay, personality: app.appearance.motion, reduceMotion: reduceMotion),
                value: isPresented
            )
    }

    @ViewBuilder private var background: some View {
        switch presentation.background {
        case .none:
            Color.clear
        case .dimmed:
            Color.black.opacity(0.36)
        case .material:
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch presentation.route {
        case .bottom: return AnyTransition.move(edge: .bottom).combined(with: .opacity)
        case .anchored: return AnyTransition.scale(scale: 0.92, anchor: .top).combined(with: .opacity)
        case .context: return AnyTransition.scale(scale: 0.96).combined(with: .opacity)
        case .fullScreen: return AnyTransition.opacity
        case .modal, .floating: return AnyTransition.scale(scale: 0.94).combined(with: .opacity)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($dragOffset) { value, state, _ in
                guard presentation.dismissBehavior.allowsDrag else { return }
                state = value.translation
            }
            .onEnded { value in
                guard presentation.dismissBehavior.allowsDrag else { return }
                let dominant = max(abs(value.translation.width), abs(value.translation.height))
                if dominant > 110 { dismiss() }
            }
    }

    private func dismiss() {
        withAnimation(ModulaMotion.animation(.dismissal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
            isPresented = false
        }
    }
}

extension View {
    func modulaOverlay<Overlay: View>(
        isPresented: Binding<Bool>,
        presentation: ModulaOverlayPresentation = .modal,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) -> some View {
        ModulaOverlayHost(isPresented: isPresented, presentation: presentation, content: { self }, overlay: overlay)
    }
}
