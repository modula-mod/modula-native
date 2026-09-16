import SwiftUI

/// Edge-docked reel selector.
///
/// Mechanics (deliberately matching the reference loop):
/// - The notch is one fixed size; the list scrolls through it. The selected item
///   is whatever settles in the middle.
/// - The selected pill grows along the rail to fit its word (46pt circle at rest,
///   up to 96pt revealed). Long words run vertically, bottom-to-top.
/// - Neighbour icons move with the pill so the gap stays 12pt whether the pill
///   is 46 or 96. Icons are 20pt.
/// - Looping reels wrap both ways; bounded reels rubber-band. Flicks coast with
///   momentum, capped so the reel never runs away.
struct ModulaEdgeLoop<Item: EdgeLoopItem>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    var behavior: EdgeLoopBehavior = .looping
    var position: EdgeLoopPosition = .trailing
    var placement: EdgeLoopPlacement = .shellEdge
    var disabled: Bool = false

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var engine: EdgeLoopEngine
    @State private var collapseTask: Task<Void, Never>?

    init(
        items: [Item],
        selection: Binding<Item.ID>,
        behavior: EdgeLoopBehavior = .looping,
        position: EdgeLoopPosition = .trailing,
        placement: EdgeLoopPlacement = .shellEdge,
        disabled: Bool = false
    ) {
        self.items = items
        self._selection = selection
        self.behavior = behavior
        self.position = position
        self.placement = placement
        self.disabled = disabled
        let index = items.firstIndex { $0.id == selection.wrappedValue } ?? 0
        _engine = State(initialValue: EdgeLoopEngine(itemCount: items.count, behavior: behavior, selectedIndex: index))
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }

    private var labelExpanded: Bool {
        engine.phase == .labelExpanded || engine.phase == .snapping
    }

    private var isDragging: Bool {
        engine.phase == .dragging
    }

    // MARK: - Pill sizing

    /// Measured pill length for a label plus whether it runs vertically.
    /// Short words ("All", "12") stay horizontal inside the resting circle;
    /// anything longer grows the pill along the rail with rotated text.
    private static func pillMetrics(for label: String) -> (length: CGFloat, vertical: Bool) {
        let pointSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        let font = UIFont.systemFont(ofSize: pointSize, weight: .bold)
        let width = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        if width <= 24 {
            return (EdgeLoopEngine.restingWidth, false)
        }
        return (min(max(width + 28, EdgeLoopEngine.restingWidth), EdgeLoopEngine.revealedWidth), true)
    }

    private var selectedMetrics: (length: CGFloat, vertical: Bool) {
        guard items.indices.contains(engine.selectedIndex) else {
            return (EdgeLoopEngine.restingWidth, false)
        }
        return Self.pillMetrics(for: items[engine.selectedIndex].label)
    }

    /// Current pill length: circle while resting or scrubbing, word-sized when revealed.
    private var pillLength: CGFloat {
        labelExpanded ? selectedMetrics.length : EdgeLoopEngine.restingWidth
    }

    // MARK: - Body

    var body: some View {
        let shape = placement == .contained
            ? AnyShape(ContainedLoopShape())
            : AnyShape(EdgeLoopShape(restingDepth: EdgeLoopEngine.restingWidth, position: position))
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        ZStack {
            loopBackdrop(shape: shape, opaque: opaque)
            reel
        }
        .frame(
            width: placement == .contained ? 52 : EdgeLoopEngine.restingWidth + 8,
            height: EdgeLoopEngine.railHeight
        )
        .mask(fadeMask)
        .contentShape(Rectangle().inset(by: placement == .contained ? 0 : -8))
        .gesture(reelGesture)
        .opacity(disabled ? 0.4 : 1)
        .allowsHitTesting(!disabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context selector")
        .accessibilityHint(behavior == .looping
            ? "Swipe up or down to move through modes. The list loops."
            : "Swipe up or down to move through options.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commitRelative(1)
            case .decrement: commitRelative(-1)
            @unknown default: break
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .onAppear(perform: syncEngineFromSelection)
        .onChange(of: selection) { _, _ in
            if engine.phase != .dragging {
                withAnimation(settleAnimation) { syncEngineFromSelection() }
            }
        }
        .onChange(of: items.count) { _, _ in
            engine = EdgeLoopEngine(itemCount: items.count, behavior: behavior, selectedIndex: selectedIndex)
        }
        .onDisappear { collapseTask?.cancel() }
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func loopBackdrop(shape: AnyShape, opaque: Bool) -> some View {
        if placement == .contained {
            Capsule()
                .fill(opaque ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.primary.opacity(opaque ? 0.18 : 0.08), lineWidth: 0.6))
                .frame(width: EdgeLoopEngine.restingWidth)
                .frame(maxWidth: .infinity, alignment: position == .trailing ? .trailing : .leading)
        } else {
            shape
                .fill(opaque ? AnyShapeStyle(Color.black.opacity(0.86)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(shape.stroke(Color.white.opacity(opaque ? 0.22 : 0.1), lineWidth: opaque ? 1 : 0.6))
                .shadow(color: .black.opacity(0.18), radius: 10, x: position == .trailing ? 4 : -4, y: 0)
        }
    }

    // MARK: - Reel

    private var reel: some View {
        GeometryReader { proxy in
            let centerX = railCenterX(in: proxy.size.width)
            let centerY = proxy.size.height / 2
            let metrics = selectedMetrics
            ZStack {
                // The pill lives in the notch centre. It is a fixed circle while
                // scrubbing — items scroll through it — and grows to the word on settle.
                pill(metrics: metrics)
                    .position(x: centerX, y: centerY)
                ForEach(engine.reelSlots(), id: \.slot) { entry in
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
            ? EdgeLoopEngine.restingWidth / 2
            : width - EdgeLoopEngine.restingWidth / 2
    }

    /// Vertical position for a reel slot. While dragging the reel is a uniform
    /// 32pt-stride list scrolling through the notch. At rest the neighbours are
    /// pushed out by the pill so the visible gap stays 12pt at any pill length.
    private func cellY(slot: Int, offset: CGFloat) -> CGFloat {
        if isDragging { return offset }
        let delta = slot - Int(engine.anchor.rounded())
        if delta == 0 { return offset }
        let firstNeighbour = pillLength / 2 + EdgeLoopEngine.itemGap + EdgeLoopEngine.iconSize / 2
        return CGFloat(delta.signum()) * (firstNeighbour + CGFloat(abs(delta) - 1) * EdgeLoopEngine.itemStride)
    }

    @ViewBuilder
    private func pill(metrics: (length: CGFloat, vertical: Bool)) -> some View {
        let expanded = labelExpanded
        let length = pillLength
        Capsule()
            .fill(app.appearance.accent.color)
            .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 1))
            .frame(width: EdgeLoopEngine.pillWidth, height: length)
            .overlay {
                if expanded, items.indices.contains(engine.selectedIndex) {
                    pillLabel(items[engine.selectedIndex].label, metrics: metrics)
                        .transition(.opacity)
                }
            }
            .animation(expansionAnimation, value: length)
            .animation(expansionAnimation, value: expanded)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pillLabel(_ label: String, metrics: (length: CGFloat, vertical: Bool)) -> some View {
        let text = Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        if metrics.vertical {
            text
                .frame(width: max(metrics.length - 22, 10))
                .rotationEffect(.degrees(-90))
        } else {
            text
        }
    }

    @ViewBuilder
    private func cell(_ item: Item, slot: Int, offset: CGFloat) -> some View {
        let y = cellY(slot: slot, offset: offset)
        let insidePill = abs(y) < pillLength / 2 + 2
        let isSelectedSlot = slot == Int(engine.anchor.rounded()) && !isDragging
        let distance = abs(y)
        Button {
            commit(item)
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: insidePill ? .semibold : .medium))
                .symbolVariant(insidePill ? .fill : .none)
                .frame(width: EdgeLoopEngine.iconSize, height: EdgeLoopEngine.iconSize)
                .foregroundStyle(insidePill ? Color.white : Color.primary.opacity(placement == .contained ? 0.7 : 0.62))
                .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(.plain)
        // The selected icon hands the pill over to the word while revealed.
        .opacity(isSelectedSlot && labelExpanded ? 0 : cellOpacity(distance: distance))
        .scaleEffect(insidePill ? 1 : max(0.82, 1 - distance / 480))
        .animation(expansionAnimation, value: labelExpanded)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(isSelectedSlot ? "Selected, \(positionLabel(for: item))" : positionLabel(for: item))
        .accessibilityAddTraits(isSelectedSlot ? .isSelected : [])
        .accessibilityIdentifier("rail.\(String(describing: item.id))")
    }

    private func cellOpacity(distance: CGFloat) -> CGFloat {
        distance < pillLength / 2 + 2 ? 1 : max(0.35, 0.8 - distance / 260)
    }

    private func positionLabel(for item: Item) -> String {
        guard let index = items.firstIndex(of: item) else { return "" }
        return "\(index + 1) of \(items.count)"
    }

    // MARK: - Gesture

    private var reelGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if engine.phase != .dragging {
                    withAnimation(scrubAnimation) { engine.beginDrag() }
                }
                let crossed = engine.updateDrag(translation: value.translation.height)
                if crossed {
                    HapticEngine.shared.play(.selection)
                }
            }
            .onEnded { value in
                let index: Int
                if reduceMotion {
                    index = withAnimation(settleAnimation) { engine.endDrag() }
                } else {
                    index = withAnimation(settleAnimation) {
                        engine.endDrag(projectedTranslation: value.predictedEndTranslation.height)
                    }
                }
                HapticEngine.shared.play(.lightImpact)
                commitIndex(index)
            }
    }

    // MARK: - Animation tokens

    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private var scrubAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.86)
    }

    private var expansionAnimation: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : ModulaMotion.animation(.railExpand, personality: app.appearance.motion, reduceMotion: reduceMotion)
    }

    // MARK: - Commit

    private func commit(_ item: Item) {
        guard let index = items.firstIndex(of: item) else { return }
        withAnimation(settleAnimation) { commitIndex(index) }
    }

    private func commitRelative(_ delta: Int) {
        withAnimation(settleAnimation) { commitIndex(engine.index(offsetBy: delta)) }
    }

    private func commitIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let alreadySelected = item.id == selection
        engine.setSelectedIndex(index, expandingLabel: true)
        if !alreadySelected {
            selection = item.id
            HapticEngine.shared.play(.selection)
        }
        scheduleCollapse()
    }

    private func syncEngineFromSelection() {
        engine.behavior = behavior
        engine.itemCount = items.count
        if engine.phase != .dragging {
            engine.setSelectedIndex(selectedIndex, expandingLabel: engine.phase == .labelExpanded)
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(EdgeLoopEngine.labelHoldDuration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(ModulaMotion.animation(.railCollapse, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                    engine.collapseLabel()
                }
            }
        }
    }
}

/// Contained reel used inside Typography preview. Same engine, not docked to the screen edge.
struct ContainedLoopPicker<Item: EdgeLoopItem>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    var behavior: EdgeLoopBehavior = .bounded

    var body: some View {
        ModulaEdgeLoop(
            items: items,
            selection: $selection,
            behavior: behavior,
            position: .trailing,
            placement: .contained
        )
        .frame(width: 52, height: min(EdgeLoopEngine.railHeight, CGFloat(max(items.count, 3)) * 40 + 32))
        .accessibilityIdentifier("edge-loop.contained")
    }
}

struct ShellEdgeLoopItem: EdgeLoopItem {
    let id: String
    let icon: String
    let label: String
    let route: AppRoute
}

/// Route-backed shell adapter. Navigation meaning stays with the caller / coordinator.
struct ShellEdgeLoop: View {
    let route: AppRoute
    var interaction: ModulaContextRail.Interaction = .idle
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
            return []
        }
    }

    private var selectedID: String {
        switch route {
        case .home(let value): value.rawValue
        case .activity(let value): value.rawValue
        case .profile(_, let value), .me(let value): value.rawValue
        default: ""
        }
    }

    private var behavior: EdgeLoopBehavior {
        switch route {
        case .home, .activity: .looping
        case .profile, .me: .looping
        default: .bounded
        }
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ModulaEdgeLoop(
                items: items,
                selection: Binding(
                    get: { selectedID },
                    set: { newID in
                        guard let item = items.first(where: { $0.id == newID }) else { return }
                        app.navigation.replaceContextOrTop(with: item.route)
                    }
                ),
                behavior: behavior,
                position: .trailing,
                placement: .shellEdge
            )
            .padding(.trailing, -2)
            .opacity(interaction.keyboardVisible || interaction.immersive ? 0 : interaction.isScrolling ? 0.72 : 1)
            .offset(x: interaction.keyboardVisible || interaction.immersive ? 24 : 0)
            .accessibilityIdentifier("shell.edge-loop")
        }
    }
}
