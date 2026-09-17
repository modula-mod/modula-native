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
/// along the rail (rotated readable text). Liquid Glass body. Preferences
/// arrive via `EdgeLoopConfiguration`.
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

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var engine: EdgeLoopEngine
    @State private var collapseTask: Task<Void, Never>?
    @State private var autoHideTask: Task<Void, Never>?
    @State private var quiet: Bool = false
    @State private var generation: UInt64 = 0

    init(
        items: [Item],
        selection: Binding<Item.ID>,
        behavior: EdgeLoopBehavior = .looping,
        position: EdgeLoopPosition = .trailing,
        placement: EdgeLoopPlacement = .shellEdge,
        configuration: EdgeLoopConfiguration,
        disabled: Bool = false,
        verticalAnchor: EdgePickerPosition = .middle
    ) {
        self.items = items
        self._selection = selection
        self.behavior = behavior
        self.position = position
        self.placement = placement
        self.configuration = configuration
        self.disabled = disabled
        self.verticalAnchor = verticalAnchor
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

    private var selectedLabel: String {
        guard items.indices.contains(engine.selectedIndex) else { return "" }
        return items[engine.selectedIndex].label
    }

    private var pillLength: CGFloat {
        showLabel ? metrics.revealLength(for: selectedLabel) : metrics.apertureHeight
    }

    private var bodyDepth: CGFloat {
        if quiet && configuration.visibility == .autoHide && !voiceOverEnabled {
            return max(metrics.restingDepth * 0.55, 22)
        }
        return metrics.restingDepth
    }

    var body: some View {
        let shape = placement == .contained
            ? AnyShape(ContainedLoopShape())
            : AnyShape(EdgeLoopShape(
                depth: bodyDepth,
                position: position,
                waistHalf: max(pillLength / 2 + metrics.waistExtra, metrics.apertureHeight / 2 + metrics.waistExtra)
            ))
        ZStack(alignment: position == .trailing ? .trailing : .leading) {
            loopBackdrop(shape: shape)
            reel.mask { reelClip }
        }
        .frame(
            width: placement == .contained ? metrics.restingDepth + 8 : bodyDepth + 14,
            height: metrics.railHeight
        )
        .frame(maxHeight: .infinity, alignment: verticalAlignment)
        .contentShape(Rectangle().inset(by: placement == .contained ? 0 : -18))
        .highPriorityGesture(reelGesture)
        .opacity(disabled ? 0.4 : (quiet ? 0.72 : 1))
        .allowsHitTesting(!disabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectedAccessibilityLabel)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(behavior == .looping
            ? "Swipe up or down to move through modes. The list loops."
            : "Swipe up or down to move through options.")
        .accessibilityAddTraits(.isButton)
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
        }
    }

    private var verticalAlignment: Alignment {
        switch verticalAnchor {
        case .up: .top
        case .middle: .center
        case .down: .bottom
        }
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
    private func loopBackdrop(shape: AnyShape) -> some View {
        if placement == .contained {
            Capsule()
                .fill(ModulaMaterial.edgeLoopBody.style(opaque: opaque, scheme: colorScheme))
                .overlay(Capsule().stroke(Color.primary.opacity(opaque ? 0.18 : 0.08), lineWidth: 0.6))
                .frame(width: metrics.restingDepth)
        } else {
            let bodyFill = ModulaMaterial.edgeLoopBody(
                intensity: configuration.glassIntensity,
                opaque: opaque,
                scheme: colorScheme,
                oled: configuration.oled
            )
            shape
                .fill(bodyFill)
                .overlay(
                    shape.fill(Color.black.opacity(!opaque && colorScheme == .dark ? (configuration.oled ? 0.22 : 0.12) : 0))
                )
                .overlay(
                    // Restrained inward edge highlight — glass edge catchlight.
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(opaque ? 0.18 : (colorScheme == .dark ? 0.14 : 0.22)),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: position == .trailing ? .leading : .trailing,
                            endPoint: position == .trailing ? .trailing : .leading
                        ),
                        lineWidth: opaque || app.appearance.contrastTransparency == .higherContrast ? 1.1 : 0.7
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 4, x: position == .trailing ? 2 : -2, y: 0)
                .animation(expansionAnimation, value: bodyDepth)
        }
    }

    @ViewBuilder
    private var reelClip: some View {
        if placement == .contained {
            Capsule().frame(width: metrics.restingDepth)
        } else {
            EdgeLoopShape(
                depth: bodyDepth,
                position: position,
                waistHalf: max(pillLength / 2 + metrics.waistExtra, metrics.apertureHeight / 2 + metrics.waistExtra)
            )
        }
    }

    // MARK: - Vertical reveal (label along the rail)

    private var selectionPill: some View {
        let length = pillLength
        return Capsule()
            .fill(ModulaMaterial.edgeLoopReveal.style(opaque: opaque, scheme: colorScheme))
            .overlay(Capsule().fill(app.appearance.accent.color.opacity(opaque ? 0.28 : 0.2)))
            .overlay(Capsule().stroke(app.appearance.accent.color.opacity(0.5), lineWidth: 1))
            .frame(width: metrics.pillWidth, height: length)
            .overlay {
                if showLabel {
                    Text(selectedLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: max(length - 20, 10))
                        .rotationEffect(.degrees(-90))
                        .transition(.opacity)
                }
            }
            .shadow(color: app.appearance.accent.color.opacity(0.2), radius: 6, y: 0)
            .animation(expansionAnimation, value: length)
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
                selectionPill
                    .position(x: centerX, y: centerY)
                ForEach(engine.reelSlots(radius: 2), id: \.slot) { entry in
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
            ? metrics.restingDepth / 2
            : width - metrics.restingDepth / 2
    }

    private func cellY(slot: Int, offset: CGFloat) -> CGFloat {
        if isDragging { return offset }
        let delta = slot - Int(engine.anchor.rounded())
        if delta == 0 { return offset }
        let first = pillLength / 2 + metrics.itemSpacing + metrics.iconSize / 2
        return CGFloat(delta.signum()) * (first + CGFloat(abs(delta) - 1) * metrics.itemStride)
    }

    @ViewBuilder
    private func cell(_ item: Item, slot: Int, offset: CGFloat) -> some View {
        let y = cellY(slot: slot, offset: offset)
        let insidePill = abs(y) < pillLength / 2 + 2
        let isSelectedSlot = slot == Int(engine.anchor.rounded()) && !isDragging
        let distance = abs(y)
        let visibility = cellOpacity(slot: slot, distance: distance)
        let interactive = isSelectedSlot || visibility >= 0.5
        let scale: CGFloat = {
            if isSelectedSlot { return metrics.selectedIconScale }
            let delta = abs(slot - Int(engine.anchor.rounded()))
            return delta <= 1 ? metrics.neighbourScale : metrics.farScale
        }()
        let icon = Image(systemName: item.icon)
            .font(.system(size: metrics.iconSize * 0.75, weight: (isSelectedSlot || insidePill) ? .semibold : .medium))
            .symbolVariant((isSelectedSlot || insidePill) ? .fill : .none)
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .foregroundStyle((isSelectedSlot || insidePill)
                ? AnyShapeStyle(Color.white)
                : AnyShapeStyle(Color.primary.opacity(placement == .contained ? 0.7 : 0.62)))

        if interactive {
            Button {
                touchActivity()
                commit(item)
            } label: {
                icon.contentShape(Rectangle().inset(by: -12))
            }
            .buttonStyle(.plain)
            .opacity(isSelectedSlot && showLabel ? 0 : visibility)
            .scaleEffect(scale)
            .frame(minWidth: metrics.hitSlop, minHeight: metrics.hitSlop)
            .accessibilityHidden(true)
        } else {
            icon
                .opacity(visibility)
                .scaleEffect(scale)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func cellOpacity(slot: Int, distance: CGFloat) -> CGFloat {
        if isDragging {
            if distance < pillLength / 2 + 2 { return 1 }
            let fadeStart = metrics.itemStride * 0.7
            let fadeEnd = metrics.itemStride * 2.2
            if distance <= fadeStart { return 1 }
            return max(0, 1 - (distance - fadeStart) / (fadeEnd - fadeStart))
        }
        switch abs(slot - Int(engine.anchor.rounded())) {
        case 0: return 1
        case 1: return metrics.neighbourOpacity
        case 2: return metrics.farOpacity
        default: return 0
        }
    }

    // MARK: - Gesture

    private var reelGesture: some Gesture {
        // Low activation + amplified travel so a short edge flick crosses an item
        // on the first try (ScrollView no longer steals via highPriorityGesture).
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
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
                let crossed = engine.updateDrag(translation: travel)
                if crossed {
                    configuration.playSelectionHaptic()
                    EdgeLoopSound.tick(enabled: configuration.hapticsEnabled)
                }
            }
            .onEnded { value in
                touchActivity()
                let actual = value.translation.height * EdgeLoopMetrics.dragSensitivity
                let projected = value.predictedEndTranslation.height * EdgeLoopMetrics.dragSensitivity
                let index: Int
                // Even a short nudge should settle to the nearest crossed candidate.
                if reduceMotion || abs(actual) < metrics.itemStride * 0.28 {
                    index = withAnimation(settleAnimation) { engine.endDrag() }
                } else {
                    let startSlot = engine.anchor.rounded()
                    let targetSlot = engine.previewSettleAnchor(projectedTranslation: projected)
                    let distance = abs(targetSlot - engine.anchor) * metrics.itemStride
                    let velocity = abs(value.velocity.height) * EdgeLoopMetrics.dragSensitivity
                    let settle: Animation = .interpolatingSpring(
                        stiffness: 280,
                        damping: 26,
                        initialVelocity: distance > 1 ? min(velocity / distance, 28) : 0
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
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private var scrubAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.86)
    }

    private var expansionAnimation: Animation? {
        if reduceMotion { return .easeOut(duration: 0.12) }
        switch configuration.motion {
        case .fluid:
            return .spring(response: 0.38, dampingFraction: 0.78)
        case .reduced:
            return .easeOut(duration: 0.12)
        case .followAppearance:
            return ModulaMotion.animation(.railExpand, personality: configuration.globalMotion, reduceMotion: false)
        }
    }

    // MARK: - Commit

    private func commit(_ item: Item) {
        guard let index = items.firstIndex(of: item) else { return }
        commitIndex(index, fromDrag: false)
    }

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
                    if configuration.labelBehavior == .onChange {
                        engine.collapseLabel()
                    }
                }
            }
        }
    }

    private func touchActivity() {
        if quiet {
            withAnimation(expansionAnimation) { quiet = false }
        }
        scheduleAutoHide()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Contained reel used inside Typography preview. Same engine; shell prefs for Position/Side/Auto-hide do not apply.
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
        .frame(width: config.metrics.restingDepth + 8, height: min(config.metrics.railHeight, CGFloat(max(items.count, 3)) * 40 + 32))
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
