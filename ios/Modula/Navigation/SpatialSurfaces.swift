import SwiftUI

// MARK: - Spatial surfaces: the Profile sheet from the right
//
// The existing profile, unchanged, presented as a near full-width sheet that slides in from
// the right over a dimmed, lightly blurred Home. A 10 pt strip of Home stays visible on the
// left; tap it, swipe right, press Escape or the close button to dismiss. Drags only drive
// offset / opacity / blur (render properties), so tracking stays at display rate.

/// Context for views rendered inside a spatial sheet.
struct SpatialSheetContext: Equatable, Sendable {
    /// Root of the sheet's own stack (shows Close instead of the sidebar trigger).
    var isRoot: Bool
}

private struct SpatialSheetContextKey: EnvironmentKey {
    static let defaultValue: SpatialSheetContext? = nil
}

extension EnvironmentValues {
    var spatialSheetContext: SpatialSheetContext? {
        get { self[SpatialSheetContextKey.self] }
        set { self[SpatialSheetContextKey.self] = newValue }
    }
}

/// Horizontal drag tracking that locks to an axis once, so a vertical scroll never turns into
/// a dismiss halfway through (and vice versa).
struct SpatialDragTrack: Equatable {
    enum Axis: Equatable { case undecided, horizontal, rejected }
    var axis: Axis = .undecided
    var translation: CGFloat = 0
}

struct SpatialSurfaceContainer<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorScheme) private var scheme

    /// Edge-swipe open (negative = finger moving left from the right edge).
    @GestureState(resetTransaction: Transaction(animation: SpatialSheetMetrics.settleSpring))
    private var openDrag: CGFloat = 0
    @GestureState(resetTransaction: Transaction(animation: SpatialSheetMetrics.settleSpring))
    private var closeDrag = SpatialDragTrack()
    /// Keeps the outgoing profile on screen for the dismiss animation.
    @State private var shownTarget: SpatialProfileTarget?

    private var spatial: SpatialNavigationCoordinator { app.navigation.spatial }
    private var reduceTransparency: Bool {
        systemReduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        let presented = spatial.isProfileOpen
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let fullWidth = geometry.size.width + insets.leading + insets.trailing
            let width = SpatialSheetMetrics.sheetWidth(for: fullWidth)
            let progress = currentProgress(presented: presented, width: width)
            let visible = presented || progress > 0.001
            let travel = width + SpatialSheetMetrics.travelPadding

            ZStack(alignment: .topTrailing) {
                content
                    // Lightly blurred Home behind the sheet; opaque dim instead under Reduce Transparency.
                    .blur(radius: reduceTransparency || reduceMotion ? 0 : 3 * progress)
                    .accessibilityHidden(presented)

                if canOpenFromEdge {
                    // Right-edge strip below the top bar and above the bottom bar / accessory, so
                    // toolbar buttons and tabs keep their taps. The left edge stays the sidebar's
                    // (and the system Back gesture's).
                    Color.clear
                        .frame(width: SpatialSheetMetrics.edgeActivationWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .padding(.top, insets.top + 52)
                        .padding(.bottom, insets.bottom + 120)
                        .ignoresSafeArea()
                        .highPriorityGesture(edgeOpenGesture(width: width))
                        .accessibilityHidden(true)
                }

                if app.navigation.spatialEnabled, spatial.isDockOpen || spatial.liveDockDrag < 0 {
                    SpatialModulesDock(containerHeight: geometry.size.height + insets.top + insets.bottom,
                                       bottomInset: insets.bottom)
                        .ignoresSafeArea()
                        .zIndex(1)
                }

                if visible, let target = shownTarget ?? spatial.profileTarget ?? (openDrag != 0 ? .me : nil) {
                    scrim(progress: progress, width: width)
                        .zIndex(2)
                    sheet(target: target, width: width, insets: insets)
                        .offset(x: reduceMotion ? 0 : (1 - progress) * travel)
                        .opacity(reduceMotion ? progress : 1)
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .animation(reduceMotion ? SpatialSheetMetrics.reduceMotionFade : SpatialSheetMetrics.settleSpring, value: presented)
        .animation(reduceMotion ? SpatialSheetMetrics.reduceMotionFade : SpatialSheetMetrics.settleSpring, value: spatial.dockState)
        .onChange(of: spatial.profileTarget) { _, target in
            if let target { shownTarget = target } else { scheduleClear() }
        }
        .onAppear { shownTarget = spatial.profileTarget }
    }

    // MARK: Pieces

    private func scrim(progress: CGFloat, width: CGFloat) -> some View {
        let base: Double = reduceTransparency ? 0.5 : (scheme == .dark ? 0.42 : 0.26)
        return Color.black
            .opacity(base * progress)
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .highPriorityGesture(closeGesture(width: width))
            .simultaneousGesture(TapGesture().onEnded { close(haptic: true) })
            .accessibilityLabel("Close profile")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("spatial.profile.scrim")
            .accessibilityHidden(!spatial.isProfileOpen)
    }

    private func sheet(target: SpatialProfileTarget, width: CGFloat, insets: EdgeInsets) -> some View {
        @Bindable var spatial = self.spatial
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: SpatialSheetMetrics.cornerRadius,
            bottomLeadingRadius: SpatialSheetMetrics.cornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        return NavigationStack(path: $spatial.sheetPath) {
            ProfileView(userID: target.userID, section: target.section)
                .environment(\.spatialSheetContext, SpatialSheetContext(isRoot: true))
                .navigationDestination(for: AppRoute.self) { route in
                    RouteView(route: route)
                        .environment(\.spatialSheetContext, SpatialSheetContext(isRoot: false))
                }
        }
        .id(target)
        .environment(\.shellChromeMetrics, ShellChromeMetrics.resolve(policy: .policy(for: target.route, isTabRoot: true)))
        .fontDesign(app.appearance.fontDesign)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background { SpatialSheetBackground(shape: shape, opaque: reduceTransparency) }
        .clipShape(shape)
        .overlay(alignment: .leading) { grabber }
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.2), radius: 24, x: -6, y: 0)
        .ignoresSafeArea()
        // Root only: on a pushed screen a rightward swipe is the system Back gesture.
        .simultaneousGesture(closeGesture(width: width), including: spatial.sheetPath.isEmpty ? .all : .subviews)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("spatial.profile.sheet")
        .accessibilityAction(.escape) { close(haptic: true) }
        .accessibilityAction(named: "Close profile") { close(haptic: true) }
        .onKeyPress(.escape) {
            close(haptic: true)
            return .handled
        }
    }

    /// Small vertical handle on the exposed edge: reads as "this slides".
    private var grabber: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 4, height: 44)
            .padding(.leading, 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: State

    private var canOpenFromEdge: Bool {
        let navigation = app.navigation
        guard navigation.spatialEnabled, spatial.isHome, navigation.presented == nil,
              navigation.isAtTabRoot, app.appearance.edgePicker.side != .right else { return false }
        // Profile tab root already is the profile.
        return navigation.selectedTab != .profile
    }

    private func currentProgress(presented: Bool, width: CGFloat) -> CGFloat {
        if presented {
            guard closeDrag.axis == .horizontal else { return 1 }
            return SpatialNavigationCoordinator.progress(translation: closeDrag.translation, width: width,
                                                         startOpen: true, fromTrailing: true)
        }
        guard openDrag != 0 else { return 0 }
        return SpatialNavigationCoordinator.progress(translation: openDrag, width: width,
                                                     startOpen: false, fromTrailing: true)
    }

    private func scheduleClear() {
        // Leave the content in place until the slide-out has finished.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            if spatial.profileTarget == nil { shownTarget = nil }
        }
    }

    // MARK: Gestures

    private func edgeOpenGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($openDrag) { value, state, transaction in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                transaction.disablesAnimations = true
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                let progress = SpatialNavigationCoordinator.progress(translation: value.translation.width, width: width,
                                                                     startOpen: false, fromTrailing: true)
                let predicted = SpatialNavigationCoordinator.progress(translation: value.predictedEndTranslation.width,
                                                                      width: width, startOpen: false, fromTrailing: true)
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                guard horizontal, spatial.canBegin(from: .trailingEdge, at: value.startLocation,
                                                   isAtStackRoot: app.navigation.isAtTabRoot,
                                                   systemSheetPresented: app.navigation.presented != nil,
                                                   enabled: app.navigation.spatialEnabled),
                      SpatialNavigationCoordinator.settlesOpen(progress: progress, predicted: predicted) else {
                    return
                }
                withAnimation(settle) { spatial.openProfile(.me) }
                HapticEngine.shared.play(.contextOpen)
            }
    }

    private func closeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($closeDrag) { value, state, transaction in
                if state.axis == .undecided {
                    let dx = value.translation.width, dy = value.translation.height
                    guard max(abs(dx), abs(dy)) > 10 else { return }
                    let horizontal = abs(dx) > abs(dy) * 1.2 && dx > 0
                    state.axis = horizontal && !spatial.isExcluded(value.startLocation) && spatial.sheetPath.isEmpty
                        ? .horizontal : .rejected
                }
                guard state.axis == .horizontal else { return }
                transaction.disablesAnimations = true
                state.translation = max(0, value.translation.width)
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard dx > 0, abs(dx) > abs(dy) * 1.2, !spatial.isExcluded(value.startLocation),
                      spatial.sheetPath.isEmpty else { return }
                let progress = SpatialNavigationCoordinator.progress(translation: dx, width: width,
                                                                     startOpen: true, fromTrailing: true)
                let predicted = SpatialNavigationCoordinator.progress(translation: value.predictedEndTranslation.width,
                                                                      width: width, startOpen: true, fromTrailing: true)
                if !SpatialNavigationCoordinator.settlesOpen(progress: progress, predicted: predicted) {
                    close(haptic: true)
                }
            }
    }

    private var settle: Animation {
        reduceMotion ? SpatialSheetMetrics.reduceMotionFade : SpatialSheetMetrics.settleSpring
    }

    private func close(haptic: Bool) {
        withAnimation(settle) { spatial.close(.profile) }
        if haptic { HapticEngine.shared.play(.navigation) }
    }
}

/// Sheet surface: Liquid Glass chrome under the profile's own canvas, or an opaque canvas
/// under Reduce Transparency. Warm white / soft coral in light, charcoal / muted glass in dark
/// come from the palette the profile already uses.
struct SpatialSheetBackground<S: Shape>: View {
    let shape: S
    var opaque: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
        Group {
            if opaque {
                shape.fill(canvas)
            } else {
                shape.fill(canvas.opacity(0.94)).modulaGlass(in: shape, interactive: false)
            }
        }
        .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Gesture priority regions

/// Marks a horizontal gallery / module surface whose drags must win over spatial sheet
/// gestures when they start inside it.
private struct SpatialGesturePriorityModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var app: AppEnvironment?
    /// Only galleries inside a spatial sheet register (the hidden Profile tab copy must not).
    @Environment(\.spatialSheetContext) private var sheet
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                guard sheet != nil else { return }
                app?.navigation.spatial.setExclusion(id, frame: frame)
            }
            .onDisappear { app?.navigation.spatial.setExclusion(id, frame: nil) }
    }
}

extension View {
    /// Profile sheet over the shell (Gesture Navigation System).
    func modulaSpatialSurfaces() -> some View {
        SpatialSurfaceContainer { self }
    }

    /// Inner horizontal gestures here take precedence over spatial sheet swipes.
    func spatialGesturePriority() -> some View {
        modifier(SpatialGesturePriorityModifier())
    }
}
