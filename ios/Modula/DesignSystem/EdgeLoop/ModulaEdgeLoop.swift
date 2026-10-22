import AudioToolbox
import SwiftUI

/// Picker-style tick for reel crossings. Respects Edge Picker / Appearance haptics.
@MainActor
enum EdgeLoopSound {
    static func tick(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1104)
    }
}

/// Configuration resolved from Appearance Edge Picker preferences (shell) or defaults (contained).
@MainActor
struct EdgeLoopConfiguration: Equatable, Sendable {
    var metrics: EdgeLoopMetrics
    var labelBehavior: EdgePickerLabelBehavior
    var glassIntensity: EdgePickerGlassIntensity
    var visibility: EdgePickerVisibility
    var motion: EdgePickerMotionPreference
    var haptics: EdgePickerHapticPreference
    var oled: Bool
    var globalMotion: AppearanceStore.MotionPersonality
    var globalHaptics: AppearanceStore.HapticIntensity

    static func shell(from appearance: AppearanceStore) -> EdgeLoopConfiguration {
        let prefs = appearance.edgePicker
        return EdgeLoopConfiguration(
            metrics: .resolve(
                size: prefs.size,
                textScale: CGFloat(appearance.textSize.scale),
                densityScale: CGFloat(appearance.density.spacingScale)
            ),
            labelBehavior: prefs.labelBehavior,
            glassIntensity: prefs.glassIntensity,
            visibility: prefs.visibility,
            motion: prefs.motion,
            haptics: prefs.haptics,
            oled: appearance.darkStyle == .oled && appearance.theme != .light,
            globalMotion: appearance.motion,
            globalHaptics: appearance.haptics
        )
    }

    static func contained(from appearance: AppearanceStore) -> EdgeLoopConfiguration {
        var config = shell(from: appearance)
        config.visibility = .always
        config.labelBehavior = .onChange
        return config
    }

    var hapticsEnabled: Bool {
        switch haptics {
        case .off: return false
        case .light, .standard: return true
        case .followAppearance: return globalHaptics != .off
        }
    }

    func playSelectionHaptic() {
        guard hapticsEnabled else { return }
        switch haptics {
        case .off: break
        case .light: HapticEngine.shared.play(.selection)
        case .standard, .followAppearance: HapticEngine.shared.play(.selection)
        }
    }

    func effectiveReduceMotion(system: Bool) -> Bool {
        if system { return true }
        switch motion {
        case .reduced: return true
        case .fluid: return false
        case .followAppearance: return false
        }
    }
}

/// Edge-docked reel selector — Modula Edge Picker.
///
/// Fixed selection aperture; items reel through it. Labels reveal vertically
/// along the rail (whole-phrase rotation). Liquid Glass body on one continuous
/// carved silhouette. Outer cutout stays stable when the label expands.
struct ModulaEdgeLoop<Item: EdgeLoopItem>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    var behavior: EdgeLoopBehavior = .looping
    var position: EdgeLoopPosition = .trailing
    var placement: EdgeLoopPlacement = .shellEdge
    var configuration: EdgeLoopConfiguration
    var disabled: Bool = false
    /// Semantic vertical anchor (shell only). Contained ignores this.
    var verticalAnchor: EdgePickerPosition = .middle
    /// Developer-only geometry diagnostics (never in production UI).
    var showsShapeDiagnostics: Bool = false

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var engine: EdgeLoopEngine
    @State private var collapseTask: Task<Void, Never>?
    @State private var autoHideTask: Task<Void, Never>?
    @State private var quiet: Bool = false
    @State private var awake: Bool = false
    @State private var generation: UInt64 = 0

    init(
        items: [Item],
        selection: Binding<Item.ID>,
        behavior: EdgeLoopBehavior = .looping,
        position: EdgeLoopPosition = .trailing,
        placement: EdgeLoopPlacement = .shellEdge,
        configuration: EdgeLoopConfiguration,
        disabled: Bool = false,
        verticalAnchor: EdgePickerPosition = .middle,
        showsShapeDiagnostics: Bool = false
    ) {
        self.items = items
        self._selection = selection
        self.behavior = behavior
        self.position = position
        self.placement = placement
        self.configuration = configuration
        self.disabled = disabled
        self.verticalAnchor = verticalAnchor
        self.showsShapeDiagnostics = showsShapeDiagnostics
        let index = items.firstIndex { $0.id == selection.wrappedValue } ?? 0
        _engine = State(initialValue: EdgeLoopEngine(
            itemCount: items.count,
            behavior: behavior,
            selectedIndex: index,
            stride: configuration.metrics.itemStride
        ))
    }

    private var metrics: EdgeLoopMetrics { configuration.metrics }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }

    private var wantsLabel: Bool {
        switch configuration.labelBehavior {
        case .always: return true
        case .iconsOnly: return false
        case .onChange: return engine.phase == .labelExpanded || engine.phase == .snapping
        }
    }

    private var isDragging: Bool { engine.phase == .dragging }

    private var showLabel: Bool {
        wantsLabel && !isDragging && configuration.labelBehavior != .iconsOnly
    }

    private var reduceMotion: Bool {
        configuration.effectiveReduceMotion(system: systemReduceMotion)
    }

    private var opaque: Bool {
        reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
    }

    private var higherContrast: Bool {
        app.appearance.contrastTransparency == .higherContrast
    }

    private var selectedLabel: String {
        guard items.indices.contains(engine.selectedIndex) else { return "" }
        return items[engine.selectedIndex].label
    }

    /// Selection aperture height only — never feeds the outer carved silhouette.
    private var apertureHeight: CGFloat {
        showLabel ? metrics.revealLength(for: selectedLabel) : metrics.selectionCollapsedHeight
    }

    private var bodyDepth: CGFloat {
        if quiet && configuration.visibility == .autoHide && !voiceOverEnabled {
            return max(metrics.channelDepth * 0.62, 24)
        }
        return metrics.channelDepth
    }

    /// Hit testing may extend inward past the visual channel for one-handed Compact use.
    private var hitDepth: CGFloat {
        max(bodyDepth + 12, min(metrics.hitSlop, bodyDepth + 20))
    }

    private var labelRotation: Angle {
        // Trailing: bottom-to-top along the edge. Leading: readable from the interior.
        // Never negative-scale text — glyphs must not become backwards.
        .degrees(position == .trailing ? -90 : 90)
    }

    var body: some View {
        // Spacers position the rail; they must not accept gestures.
        VStack(spacing: 0) {
            if verticalAnchor != .up {
                Spacer(minLength: 0).allowsHitTesting(false)
            }
            railControl
            if verticalAnchor != .down {
                Spacer(minLength: 0).allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .opacity(disabled ? 0.4 : (quiet ? 0.7 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectedAccessibilityLabel)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(behavior == .looping
            ? "Swipe up or down with one finger to change mode. The list loops."
            : "Swipe up or down with one finger to change option.")
        // Adjustable (from accessibilityAdjustableAction), not a button: the
        // picker is scrub-only, so "double-tap to activate" would be misleading.
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            touchActivity()
            switch direction {
            case .increment: commitRelative(1)
            case .decrement: commitRelative(-1)
            @unknown default: break
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onAppear {
            syncEngineFromSelection()
            scheduleAutoHide()
        }
        .onChange(of: selection) { _, _ in
            if engine.phase != .dragging { syncEngineFromSelection() }
        }
        .onChange(of: items.count) { _, _ in
            engine = EdgeLoopEngine(itemCount: items.count, behavior: behavior, selectedIndex: selectedIndex, stride: metrics.itemStride)
        }
        .onChange(of: metrics.itemStride) { _, stride in
            engine.stride = stride
        }
        .onChange(of: configuration.labelBehavior) { _, _ in
            if configuration.labelBehavior == .always {
                engine.phase = .labelExpanded
            } else if configuration.labelBehavior == .iconsOnly {
                engine.collapseLabel()
            }
        }
        .onDisappear {
            collapseTask?.cancel()
            autoHideTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if configuration.labelBehavior != .always {
                engine.collapseLabel()
            }
            quiet = false
            awake = false
        }
    }

    /// Visible silhouette only — gestures and hit testing stay on this control.
    private var railControl: some View {
        let visualShape = EdgeLoopShape(depth: bodyDepth, position: position, metrics: metrics)
        let hitShape = EdgeLoopShape(depth: hitDepth, position: position, metrics: metrics)
        return ZStack(alignment: position == .trailing ? .trailing : .leading) {
            loopBackdrop(shellShape: visualShape)
            reel.mask {
                if placement == .contained {
                    Capsule().frame(width: metrics.channelDepth)
                } else {
                    visualShape
                }
            }
            #if DEBUG
            if showsShapeDiagnostics {
                shapeDiagnosticsOverlay
            }
            #endif
        }
        .frame(
            width: placement == .contained ? metrics.channelDepth + 8 : hitDepth + 6,
            height: metrics.railHeight
        )
        .contentShape(placement == .contained ? AnyShape(Capsule()) : AnyShape(hitShape))
        // Publish the live bulge so feed rows can flow around it (shell placement only).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShellChromeFreeze.cardSpace)) } action: { frame in
            guard placement == .shellEdge, showsShapeDiagnostics == false else { return }
            EdgePickerBulge.shared.publish(frame: frame, depth: disabled ? 0 : bodyDepth, trailing: position == .trailing, metrics: metrics)
        }
        .onChange(of: bodyDepth) { _, depth in
            guard placement == .shellEdge else { return }
            guard !EdgePickerBulge.shared.isLocked else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { EdgePickerBulge.shared.depth = disabled ? 0 : depth }
        }
        .onDisappear { if placement == .shellEdge { EdgePickerBulge.shared.hide() } }
        .highPriorityGesture(reelGesture)
        .allowsHitTesting(!disabled)
    }

    private var selectedAccessibilityLabel: String {
        guard items.indices.contains(selectedIndex) else { return "Context selector" }
        return items[selectedIndex].accessibilityLabel
    }

    private var accessibilityValueText: String {
        guard !items.isEmpty else { return "" }
        return "Selected, \(selectedIndex + 1) of \(items.count)"
    }

    // MARK: - Backdrop

    @ViewBuilder
    private func loopBackdrop(shellShape: EdgeLoopShape) -> some View {
        if placement == .contained {
            Capsule()
                .fill(Color.clear)
                .frame(width: metrics.channelDepth)
                .modulaChrome(in: Capsule(), opaque: opaque)
                .overlay(Capsule().stroke(Color.primary.opacity(opaque ? 0.18 : 0.08), lineWidth: 0.6))
        } else if opaque {
            let bodyFill = ModulaMaterial.edgeLoopBody(
                intensity: configuration.glassIntensity,
                opaque: true,
                scheme: colorScheme,
                oled: configuration.oled
            )
            shellShape
                .fill(bodyFill)
                .overlay(shellShape.fill(app.appearance.accent.color.opacity(0.18)))
                .overlay(
                    shellShape.stroke(
                        Color.primary.opacity(higherContrast ? 0.28 : 0.12),
                        lineWidth: higherContrast ? 1.2 : 1.0
                    )
                )
                .animation(expansionAnimation, value: bodyDepth)
        } else {
            // Carved channel = Liquid Glass + quiet accent tint (not a flat black rail).
            let sink = bodySinkOpacity
            let edgeBoost = awake ? 1.15 : (quiet ? 0.75 : 1.0)
            let bodyAccent = quiet ? 0.06 : (awake ? 0.14 : 0.1)
            shellShape
                .fill(Color.clear)
                .modulaChrome(in: shellShape, opaque: false)
                .overlay(shellShape.fill(Color.black.opacity(sink)))
                .overlay(shellShape.fill(app.appearance.accent.color.opacity(bodyAccent)))
                .overlay(
                    shellShape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((colorScheme == .dark ? 0.16 : 0.24) * edgeBoost),
                                app.appearance.accent.color.opacity(0.12 * edgeBoost),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: position == .trailing ? .leading : .trailing,
                            endPoint: position == .trailing ? .trailing : .leading
                        ),
                        lineWidth: higherContrast ? 1.15 : 0.7
                    )
                )
                .shadow(color: .black.opacity(quiet ? 0.03 : 0.06), radius: 4, x: position == .trailing ? 2 : -2, y: 0)
                .animation(expansionAnimation, value: bodyDepth)
                .animation(expansionAnimation, value: awake)
        }
    }

    private var bodySinkOpacity: Double {
        let base: Double = switch configuration.glassIntensity {
        case .subtle: colorScheme == .dark ? (configuration.oled ? 0.14 : 0.04) : 0.02
        case .standard: colorScheme == .dark ? (configuration.oled ? 0.22 : 0.08) : 0.0
        case .strong: colorScheme == .dark ? (configuration.oled ? 0.3 : 0.14) : 0.04
        }
        if awake { return min(base + 0.04, 0.36) }
        if quiet { return base * 0.7 }
        return base
    }

    // MARK: - Selection aperture (inside channel)

    /// Vertical liquid-glass pill with accent tint — matches the orange reference.
    /// Collapsed is taller than wide (never a circle); expands for vertical labels.
    private var selectionAperture: some View {
        let height = max(apertureHeight, metrics.selectionWidth * 1.4)
        let width = metrics.selectionWidth
        let accent = app.appearance.accent.color
        // Accent-led glass pill (reference reads as tinted liquid glass, not a grey circle).
        let accentFill = opaque ? 0.55 : (awake ? 0.48 : 0.42)
        return Capsule()
            .fill(Color.clear)
            .frame(width: width, height: height)
            .modulaChrome(in: Capsule(), opaque: opaque)
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(min(accentFill + 0.1, 0.72)),
                                accent.opacity(accentFill),
                                accent.opacity(max(accentFill - 0.08, 0.28))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(opaque ? 0.22 : 0.35),
                                accent.opacity(higherContrast ? 0.85 : 0.55),
                                accent.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: higherContrast ? 1.35 : 1.05
                    )
            )
            .overlay {
                ZStack {
                    if showLabel {
                        Text(selectedLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize()
                            .rotationEffect(labelRotation)
                            .transition(.opacity)
                    }
                }
            }
            .shadow(color: accent.opacity(showLabel ? 0.35 : 0.28), radius: showLabel ? 10 : 7, y: 1)
            .animation(expansionAnimation, value: height)
            .animation(expansionAnimation, value: showLabel)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    // MARK: - Reel

    private var reel: some View {
        GeometryReader { proxy in
            let centerX = railCenterX(in: proxy.size.width)
            let centerY = proxy.size.height / 2
            ZStack {
                selectionAperture
                    .position(x: centerX, y: centerY)
                ForEach(engine.reelSlots(radius: EdgeLoopEngine.visibleRadius), id: \.slot) { entry in
                    if items.indices.contains(entry.index) {
                        cell(items[entry.index], slot: entry.slot, offset: entry.offset)
                            .position(x: centerX, y: centerY + cellY(slot: entry.slot, offset: entry.offset))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func railCenterX(in width: CGFloat) -> CGFloat {
        position == .leading
            ? bodyDepth / 2
            : width - bodyDepth / 2
    }

    private func cellY(slot: Int, offset: CGFloat) -> CGFloat {
        if isDragging { return offset }
        let delta = slot - Int(engine.anchor.rounded())
        if delta == 0 { return offset }
        // Neighbours sit outside the (possibly expanded) aperture, inside the stable channel.
        let first = apertureHeight / 2 + metrics.itemSpacing + metrics.iconSize / 2
        return CGFloat(delta.signum()) * (first + CGFloat(abs(delta) - 1) * metrics.itemStride)
    }

    @ViewBuilder
    private func cell(_ item: Item, slot: Int, offset: CGFloat) -> some View {
        let y = cellY(slot: slot, offset: offset)
        let insideAperture = abs(y) < apertureHeight / 2 + 2
        let isSelectedSlot = slot == Int(engine.anchor.rounded()) && !isDragging
        let distance = abs(y)
        let visibility = cellOpacity(slot: slot, distance: distance)
        let scale: CGFloat = {
            if isSelectedSlot { return metrics.selectedIconScale }
            let delta = abs(slot - Int(engine.anchor.rounded()))
            return delta <= 1 ? metrics.neighbourScale : metrics.farScale
        }()
        let iconWeight: Font.Weight = (isSelectedSlot || insideAperture) ? .semibold : .medium
        let iconOpacity: Double = {
            if isSelectedSlot && showLabel { return 0 }
            let boosted = awake ? min(visibility + 0.08, 1) : visibility
            return quiet ? boosted * 0.85 : boosted
        }()

        // Icons are visual only — selection is scrub/drag (or VoiceOver adjust).
        Image(systemName: item.icon)
            .font(.system(size: metrics.iconSize * 0.75, weight: iconWeight))
            .symbolVariant((isSelectedSlot || insideAperture) ? .fill : .none)
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .foregroundStyle((isSelectedSlot || insideAperture)
                ? AnyShapeStyle(Color.white)
                : AnyShapeStyle(Color.primary.opacity(placement == .contained ? 0.7 : (higherContrast ? 0.78 : 0.58))))
            .opacity(iconOpacity)
            .scaleEffect(scale)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func cellOpacity(slot: Int, distance: CGFloat) -> CGFloat {
        if isDragging {
            if distance < apertureHeight / 2 + 2 { return 1 }
            // Fade into the carved upper/lower transitions.
            let fadeStart = metrics.itemStride * 0.45
            let fadeEnd = metrics.itemStride * 1.25
            if distance <= fadeStart { return 1 }
            return max(0, 1 - (distance - fadeStart) / (fadeEnd - fadeStart))
        }
        switch abs(slot - Int(engine.anchor.rounded())) {
        case 0: return 1
        case 1: return metrics.neighbourOpacity
        default: return metrics.farOpacity
        }
    }

    // MARK: - Gesture

    private var reelGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                touchActivity()
                if engine.phase != .dragging {
                    withAnimation(scrubAnimation) {
                        engine.beginDrag()
                        if configuration.labelBehavior == .onChange {
                            engine.collapseLabel()
                        }
                    }
                }
                let travel = value.translation.height * EdgeLoopMetrics.dragSensitivity
                if placement == .shellEdge { EdgePickerBulge.shared.drag = max(-1, min(1, value.translation.height / 140)) }
                let crossed = engine.updateDrag(translation: travel)
                if crossed {
                    configuration.playSelectionHaptic()
                    EdgeLoopSound.tick(enabled: configuration.hapticsEnabled)
                }
            }
            .onEnded { value in
                touchActivity()
                if placement == .shellEdge { withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { EdgePickerBulge.shared.drag = 0 } }
                let actual = value.translation.height * EdgeLoopMetrics.dragSensitivity
                let projected = value.predictedEndTranslation.height * EdgeLoopMetrics.dragSensitivity
                let index: Int
                // Short press / tiny scrub must not change the selection.
                if abs(actual) < metrics.itemStride * EdgeLoopMetrics.commitThreshold {
                    index = withAnimation(settleAnimation) { engine.cancelDrag() }
                } else if reduceMotion {
                    index = withAnimation(settleAnimation) { engine.endDrag() }
                } else {
                    let startSlot = engine.dragBaseSlot
                    let targetSlot = engine.previewSettleAnchor(projectedTranslation: projected)
                    let distance = abs(targetSlot - engine.anchor) * metrics.itemStride
                    let velocity = abs(value.velocity.height) * EdgeLoopMetrics.dragSensitivity
                    let settle: Animation = .interpolatingSpring(
                        stiffness: 280,
                        damping: 30,
                        initialVelocity: distance > 1 ? min(velocity / distance, 16) : 0
                    )
                    index = withAnimation(settle) {
                        engine.endDrag(projectedTranslation: projected)
                    }
                    playCoastTicks(Int(abs(targetSlot - startSlot)))
                }
                commitIndex(index, fromDrag: true)
            }
    }

    private func playCoastTicks(_ count: Int) {
        guard count > 0, configuration.hapticsEnabled else { return }
        Task {
            for step in 0..<count {
                EdgeLoopSound.tick(enabled: true)
                configuration.playSelectionHaptic()
                try? await Task.sleep(for: .milliseconds(50 + step * 22))
            }
        }
    }

    // MARK: - Animation

    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88)
    }

    private var scrubAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.9)
    }

    private var expansionAnimation: Animation? {
        if reduceMotion { return .easeOut(duration: 0.12) }
        switch configuration.motion {
        case .fluid:
            return .spring(response: 0.36, dampingFraction: 0.82)
        case .reduced:
            return .easeOut(duration: 0.12)
        case .followAppearance:
            return ModulaMotion.animation(.railExpand, personality: configuration.globalMotion, reduceMotion: false)
        }
    }

    // MARK: - Commit

    private func commitRelative(_ delta: Int) {
        commitIndex(engine.index(offsetBy: delta), fromDrag: false)
    }

    private func commitIndex(_ index: Int, fromDrag: Bool) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let alreadySelected = item.id == selection
        let expand = configuration.labelBehavior != .iconsOnly
        engine.setSelectedIndex(index, expandingLabel: expand && configuration.labelBehavior != .always ? true : expand)
        if configuration.labelBehavior == .always {
            engine.phase = .labelExpanded
        }
        if !alreadySelected {
            selection = item.id
            if !fromDrag {
                configuration.playSelectionHaptic()
            }
        }
        if configuration.labelBehavior == .onChange {
            scheduleCollapse()
        }
        scheduleAutoHide()
    }

    private func syncEngineFromSelection() {
        engine.behavior = behavior
        engine.itemCount = items.count
        engine.stride = metrics.itemStride
        if engine.phase != .dragging {
            let expand = configuration.labelBehavior == .always || engine.phase == .labelExpanded
            engine.setSelectedIndex(selectedIndex, expandingLabel: expand)
            if configuration.labelBehavior == .always {
                engine.phase = .labelExpanded
            }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        generation &+= 1
        let token = generation
        collapseTask = Task {
            try? await Task.sleep(for: metrics.revealHold)
            guard !Task.isCancelled, token == generation else { return }
            await MainActor.run {
                withAnimation(expansionAnimation) {
                    engine.collapseLabel()
                }
            }
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard configuration.visibility == .autoHide, !voiceOverEnabled else {
            quiet = false
            return
        }
        quiet = false
        autoHideTask = Task {
            try? await Task.sleep(for: metrics.autoHideDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(expansionAnimation) {
                    quiet = true
                    awake = false
                    if configuration.labelBehavior == .onChange {
                        engine.collapseLabel()
                    }
                }
            }
        }
    }

    private func touchActivity() {
        if quiet || !awake {
            withAnimation(expansionAnimation) {
                quiet = false
                awake = true
            }
        }
        scheduleAutoHide()
    }

    #if DEBUG
    private var shapeDiagnosticsOverlay: some View {
        GeometryReader { proxy in
            let marks = EdgeLoopShape.landmarks(
                in: proxy.frame(in: .local),
                curveStartFraction: metrics.curveStartFraction,
                channelStartFraction: metrics.channelStartFraction,
                channelEndFraction: metrics.channelEndFraction,
                curveEndFraction: metrics.curveEndFraction
            )
            let x = position == .trailing ? proxy.size.width - 2 : 2
            ZStack(alignment: .leading) {
                diagnosticRule(y: marks.curveStart, color: .orange, in: proxy.size, x: x)
                diagnosticRule(y: marks.channelTop, color: .yellow, in: proxy.size, x: x)
                diagnosticRule(y: marks.selectionCentre, color: .green, in: proxy.size, x: x)
                diagnosticRule(y: marks.channelBottom, color: .yellow, in: proxy.size, x: x)
                diagnosticRule(y: marks.curveEnd, color: .orange, in: proxy.size, x: x)
            }
            .allowsHitTesting(false)
        }
    }

    private func diagnosticRule(y: CGFloat, color: Color, in size: CGSize, x: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
        .overlay(alignment: .leading) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .position(x: x, y: y)
        }
    }
    #endif
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Contained reel used inside Typography preview. Same engine; shell prefs for Position/Side/Auto-hide do not apply.
/// Does not use the shell carved-edge silhouette.
struct ContainedLoopPicker<Item: EdgeLoopItem>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    var behavior: EdgeLoopBehavior = .bounded
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let config = EdgeLoopConfiguration.contained(from: app.appearance)
        ModulaEdgeLoop(
            items: items,
            selection: $selection,
            behavior: behavior,
            position: .trailing,
            placement: .contained,
            configuration: config
        )
        .frame(width: config.metrics.channelDepth + 8, height: min(config.metrics.railHeight, CGFloat(max(items.count, 3)) * 40 + 32))
        .accessibilityIdentifier("edge-loop.contained")
    }
}

struct ShellEdgeLoopItem: EdgeLoopItem {
    let id: String
    let icon: String
    let label: String
    let route: AppRoute
}

/// Route-backed shell adapter. Reads Edge Picker preferences from Appearance.
struct ShellEdgeLoop: View {
    let route: AppRoute
    var interaction: ModulaContextRail.Interaction = .idle
    /// When true, renders without binding to live navigation (Appearance live preview).
    var previewSelection: Binding<String>? = nil
    @Environment(AppEnvironment.self) private var app

    private var items: [ShellEdgeLoopItem] {
        switch route {
        case .home:
            return [
                ShellEdgeLoopItem(id: "following", icon: "person.2", label: "Following", route: .home(.following)),
                ShellEdgeLoopItem(id: "for-you", icon: "safari", label: "For You", route: .home(.forYou)),
                ShellEdgeLoopItem(id: "modules", icon: "shippingbox", label: "Modules", route: .home(.modules))
            ]
        case .activity:
            return [
                ShellEdgeLoopItem(id: "all", icon: "bell", label: "All", route: .activity(.all)),
                ShellEdgeLoopItem(id: "mentions", icon: "at", label: "Mentions", route: .activity(.mentions)),
                ShellEdgeLoopItem(id: "requests", icon: "person.badge.plus", label: "Requests", route: .activity(.requests))
            ]
        case .profile(let id, _):
            return [
                ShellEdgeLoopItem(id: "overview", icon: "person", label: "Overview", route: .profile(id, .overview)),
                ShellEdgeLoopItem(id: "posts", icon: "list.bullet", label: "Posts", route: .profile(id, .posts)),
                ShellEdgeLoopItem(id: "modules", icon: "shippingbox", label: "Modules", route: .profile(id, .modules))
            ]
        case .me:
            return [
                ShellEdgeLoopItem(id: "overview", icon: "person", label: "Overview", route: .me(.overview)),
                ShellEdgeLoopItem(id: "posts", icon: "list.bullet", label: "Posts", route: .me(.posts)),
                ShellEdgeLoopItem(id: "modules", icon: "shippingbox", label: "Modules", route: .me(.modules))
            ]
        default:
            return [
                ShellEdgeLoopItem(id: "following", icon: "person.2", label: "Following", route: .home(.following)),
                ShellEdgeLoopItem(id: "for-you", icon: "safari", label: "For You", route: .home(.forYou)),
                ShellEdgeLoopItem(id: "modules", icon: "shippingbox", label: "Modules", route: .home(.modules))
            ]
        }
    }

    private var selectedID: String {
        if let previewSelection { return previewSelection.wrappedValue }
        switch route {
        case .home(let value): return value.rawValue
        case .activity(let value): return value.rawValue
        case .profile(_, let value), .me(let value): return value.rawValue
        default: return items.first?.id ?? ""
        }
    }

    private var behavior: EdgeLoopBehavior {
        switch route {
        case .home, .activity, .profile, .me: .looping
        default: .looping
        }
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let prefs = app.appearance.edgePicker
            let config = EdgeLoopConfiguration.shell(from: app.appearance)
            ModulaEdgeLoop(
                items: items,
                selection: Binding(
                    get: { selectedID },
                    set: { newID in
                        if let previewSelection {
                            previewSelection.wrappedValue = newID
                            return
                        }
                        guard let item = items.first(where: { $0.id == newID }) else { return }
                        app.navigation.replaceContextOrTop(with: item.route)
                    }
                ),
                behavior: behavior,
                position: prefs.side.loopPosition,
                placement: .shellEdge,
                configuration: config,
                verticalAnchor: prefs.position
            )
            .padding(prefs.side == .right ? .trailing : .leading, -2)
            .opacity(interaction.keyboardVisible || interaction.immersive ? 0 : interaction.isScrolling ? 0.72 : 1)
            .offset(x: interaction.keyboardVisible || interaction.immersive
                ? (prefs.side == .right ? 24 : -24)
                : 0)
            .accessibilityIdentifier("shell.edge-loop")
        }
    }
}
