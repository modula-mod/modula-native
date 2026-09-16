import SwiftUI

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
                syncEngineFromSelection()
            }
        }
        .onChange(of: items.count) { _, _ in
            engine = EdgeLoopEngine(itemCount: items.count, behavior: behavior, selectedIndex: selectedIndex)
        }
        .onDisappear { collapseTask?.cancel() }
    }

    @ViewBuilder
    private func loopBackdrop(shape: AnyShape, opaque: Bool) -> some View {
        if placement == .contained {
            Capsule()
                .fill(opaque ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.primary.opacity(opaque ? 0.18 : 0.08), lineWidth: 0.6))
                .frame(width: 46)
                .frame(maxWidth: .infinity, alignment: position == .trailing ? .trailing : .leading)
        } else {
            shape
                .fill(opaque ? AnyShapeStyle(Color.black.opacity(0.86)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(shape.stroke(Color.white.opacity(opaque ? 0.22 : 0.1), lineWidth: opaque ? 1 : 0.6))
                .shadow(color: .black.opacity(0.18), radius: 10, x: position == .trailing ? 4 : -4, y: 0)
        }
    }

    private var reel: some View {
        GeometryReader { proxy in
            let centerY = proxy.size.height / 2
            ZStack {
                ForEach(engine.visibleSlots(), id: \.slot) { slot in
                    if items.indices.contains(slot.index) {
                        cell(items[slot.index], selected: slot.index == engine.proposedIndex)
                            .position(
                                x: cellX(in: proxy.size.width),
                                y: centerY + engine.visualOffset(forSlot: slot.slot)
                            )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func cellX(in width: CGFloat) -> CGFloat {
        if position == .leading {
            return labelExpanded ? min(width * 0.52, EdgeLoopEngine.revealedWidth / 2) : EdgeLoopEngine.restingWidth / 2
        }
        let resting = width - (EdgeLoopEngine.restingWidth / 2)
        if labelExpanded {
            return width - (min(estimatedSelectedWidth, EdgeLoopEngine.revealedWidth) / 2)
        }
        return resting
    }

    private var estimatedSelectedWidth: CGFloat {
        labelExpanded ? EdgeLoopEngine.revealedWidth - 4 : EdgeLoopEngine.restingWidth
    }

    @ViewBuilder
    private func cell(_ item: Item, selected: Bool) -> some View {
        let expanded = selected && labelExpanded
        Button {
            commit(item)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: selected ? 17 : 15, weight: selected ? .semibold : .medium))
                    .symbolVariant(selected ? .fill : .none)
                if expanded {
                    Text(item.label)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(placement == .contained ? 0.7 : 0.62))
            .padding(.horizontal, expanded ? 12 : 0)
            .frame(minWidth: 34, minHeight: 34)
            .frame(width: expanded ? nil : 34, height: selected ? EdgeLoopEngine.apertureHeight : 34)
            .background {
                if selected {
                    Capsule()
                        .fill(app.appearance.accent.color)
                        .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: EdgeLoopEngine.hitSlop, minHeight: EdgeLoopEngine.hitSlop)
        .scaleEffect(selected ? 1 : 0.88)
        .opacity(selected ? 1 : 0.72)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion),
            value: selected
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : ModulaMotion.animation(.railExpand, personality: app.appearance.motion, reduceMotion: reduceMotion),
            value: expanded
        )
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(selected ? "Selected, \(positionLabel(for: item))" : positionLabel(for: item))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("rail.\(String(describing: item.id))")
    }

    private func positionLabel(for item: Item) -> String {
        guard let index = items.firstIndex(of: item) else { return "" }
        return "\(index + 1) of \(items.count)"
    }

    private var reelGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if engine.phase != .dragging {
                    engine.beginDrag()
                }
                let crossed = engine.updateDrag(translation: value.translation.height)
                if crossed {
                    HapticEngine.shared.play(.selection)
                }
            }
            .onEnded { _ in
                let index = engine.endDrag()
                commitIndex(index)
            }
    }

    private func commit(_ item: Item) {
        guard let index = items.firstIndex(of: item) else { return }
        commitIndex(index)
    }

    private func commitRelative(_ delta: Int) {
        commitIndex(engine.index(offsetBy: delta))
    }

    private func commitIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let alreadySelected = item.id == selection
        engine.setSelectedIndex(index, expandingLabel: true)
        if !alreadySelected {
            selection = item.id
        }
        HapticEngine.shared.play(.selection)
        scheduleCollapse()
        if engine.phase == .snapping {
            engine.completeSnap(expandingLabel: true)
        }
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
        .frame(width: 52, height: min(EdgeLoopEngine.railHeight, CGFloat(max(items.count, 3)) * EdgeLoopEngine.itemStride + 24))
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
