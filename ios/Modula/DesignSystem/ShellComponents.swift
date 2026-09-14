import SwiftUI

/// Shell-owned bottom chrome. The accessory contains contextual navigation and
/// actions; the five destinations remain the only tab-bar items.
struct ModulaBottomChrome: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 6) {
            ModulaTabAccessory(route: route)
            ModulaTabBar()
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 5)
    }
}

struct ModulaTabBar: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var navigation = app.navigation
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = navigation.selectedTab == tab
                Button {
                    navigation.select(tab)
                    HapticEngine.shared.play(.navigation)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 17, weight: selected ? .semibold : .medium))
                            .symbolEffect(.bounce, value: selected)
                        Text(tab.title)
                            .font(.caption2.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if selected {
                            Capsule()
                                .fill(app.appearance.accent.color.opacity(0.11))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: 560)
        .modulaChrome(in: Capsule(), opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency)
        .shadow(color: .black.opacity(0.11), radius: 16, y: 8)
        // System tab bars keep compact labels at accessibility sizes; the full
        // names remain available to VoiceOver through each button label.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global navigation")
    }
}

/// A small attached accessory for truthful shell actions. It deliberately does
/// not expose contextual modes: the edge rail remains their only selector.
struct ModulaTabAccessory: View {
    let route: AppRoute
    var nativeHosted = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: context.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(app.appearance.accent.color)
                .frame(width: 26, height: 26)
                .background(app.appearance.accent.color.opacity(0.12), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(context.eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(context.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                app.navigation.open(.search(.root(nil)))
                HapticEngine.shared.play(.navigation)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search Modula")
            .accessibilityIdentifier("accessory.search")
            Menu {
                Section("Quick Access") {
                    Button("Settings", systemImage: "gearshape") { app.navigation.open(.settings(.root)) }
                    Button("Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
                    Button("Account", systemImage: "person.crop.circle") {
                        app.navigation.open(app.auth.account == nil ? .auth(.login) : .settings(.account(.root)))
                    }
                }
                Section("Modules") {
                    Button("Product Hub", systemImage: "shippingbox") { app.navigation.open(.productHub(.featured)) }
                    Button("Installed Modules", systemImage: "checkmark.circle") {
                        app.navigation.open(.productHub(.collection(.installed)))
                    }
                    Button("Updates", systemImage: "arrow.triangle.2.circlepath") {
                        app.navigation.open(.productHub(.collection(.updates)))
                    }
                }
                Section("Privacy & Information") {
                    Button("Privacy & Security", systemImage: "lock.shield") { app.navigation.open(.settings(.privacy(.root))) }
                    Button("About Modula", systemImage: "info.circle") { app.navigation.open(.settings(.about(.root))) }
                    Button("Share Modula", systemImage: "square.and.arrow.up") {
                        PresentationCoordinator.present(.share(route), in: app.navigation)
                    }
                }
                #if DEBUG
                Divider()
                Button("Component Catalog", systemImage: "square.grid.3x3") { app.navigation.open(.developer(.components)) }
                #endif
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("accessory.more")
        }
        .padding(.leading, nativeHosted ? 2 : 7)
        .padding(.trailing, nativeHosted ? 2 : 4)
        .frame(maxWidth: nativeHosted ? .infinity : 310, minHeight: 38)
        .modulaAccessorySurface(
            nativeHosted: nativeHosted,
            opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        )
        .dynamicTypeSize(...DynamicTypeSize.large)
        .contentTransition(.interpolate)
        .animation(.snappy(duration: 0.28), value: context.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tab.accessory")
    }

    private var context: (eyebrow: String, title: String, symbol: String) {
        switch route {
        case .home(let mode): return ("HOME", display(mode.rawValue), "sparkles")
        case .discover: return ("DISCOVER", "Explore Modula", "safari")
        case .search: return ("DISCOVER", "Search", "magnifyingglass")
        case .productHub: return ("MODULES", "Product Hub", "shippingbox")
        case .activity(let mode): return ("ACTIVITY", display(mode.rawValue), "bell")
        case .profile(_, let section), .me(let section): return ("PROFILE", display(section.rawValue), "person.crop.circle")
        default: return ("MODULA", "Quick Access", "m.circle")
        }
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

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
        let shoulder = 22 + (p * 8)
        let waist = 8 - (p * 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder - 24),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - shoulder),
            control2: CGPoint(x: rect.minX + waist, y: rect.maxY - shoulder + 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + waist, y: rect.minY + shoulder + 24),
            control1: CGPoint(x: rect.minX, y: rect.midY + 40 + (p * 20)),
            control2: CGPoint(x: rect.minX, y: rect.midY - 40 - (p * 20))
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

    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let route: AppRoute
    }

    let route: AppRoute
    var interaction: Interaction = .idle
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedID: String?
    @State private var collapseTask: Task<Void, Never>?
    @GestureState private var dragOffset: CGFloat = 0
    @Namespace private var selectionMorph

    private var items: [Item] {
        switch route {
        case .home:
            return [
                Item(id: "following", title: "Following", symbol: "person.2", route: .home(.following)),
                Item(id: "for-you", title: "For You", symbol: "safari", route: .home(.forYou)),
                Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .home(.modules))
            ]
        case .activity:
            return [
                Item(id: "all", title: "All", symbol: "bell", route: .activity(.all)),
                Item(id: "mentions", title: "Mentions", symbol: "at", route: .activity(.mentions)),
                Item(id: "requests", title: "Requests", symbol: "person.badge.plus", route: .activity(.requests))
            ]
        case .profile(let id, _):
            return [
                Item(id: "overview", title: "Overview", symbol: "person", route: .profile(id, .overview)),
                Item(id: "posts", title: "Posts", symbol: "list.bullet", route: .profile(id, .posts)),
                Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .profile(id, .modules))
            ]
        case .me:
            return [
                Item(id: "overview", title: "Overview", symbol: "person", route: .me(.overview)),
                Item(id: "posts", title: "Posts", symbol: "list.bullet", route: .me(.posts)),
                Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .me(.modules))
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

    private var selectedIndex: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    private var orderedItems: [Item] {
        guard !items.isEmpty else { return [] }
        let count = items.count
        return [items[(selectedIndex - 1 + count) % count], items[selectedIndex], items[(selectedIndex + 1) % count]]
    }
    private var isRevealed: Bool { revealedID == selectedID }
    private var selectedHeight: CGFloat { isRevealed ? 96 : 46 }
    private var railHeight: CGFloat { (46 * 2) + selectedHeight + (12 * 2) + 20 }
    var body: some View {
        let shape = ModulaRailShape(revealProgress: isRevealed ? 1 : 0)
        VStack(spacing: 12) {
            ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                railButton(item, selected: index == 1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(width: 54, height: railHeight)
        .offset(x: 2)
        .offset(y: dragOffset * 0.28)
        .background(Color.black.opacity(0.93), in: shape)
        .contentShape(Rectangle().inset(by: -12))
        .gesture(reelGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context selector")
        .accessibilityHint("Swipe up or down to move through modes. The list loops.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectRelative(1)
            case .decrement: selectRelative(-1)
            @unknown default: break
            }
        }
        .opacity(interaction.keyboardVisible || interaction.immersive ? 0 : interaction.isScrolling ? 0.72 : 1)
        .offset(x: interaction.keyboardVisible || interaction.immersive ? 24 : 0)
        .animation(ModulaMotion.animation(.railExpand, personality: app.appearance.motion, reduceMotion: reduceMotion), value: revealedID)
        .animation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion), value: selectedID)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .onDisappear { collapseTask?.cancel() }
    }

    @ViewBuilder
    private func railButton(_ item: Item, selected: Bool) -> some View {
        Button { select(item) } label: {
            Group {
                if selected && isRevealed {
                    Text(item.title)
                        .font(.caption2.weight(.bold))
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: selected ? .semibold : .medium))
                        .symbolVariant(selected ? .fill : .none)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.68))
            .frame(width: 46, height: selected ? selectedHeight : 46)
            .background {
                if selected {
                    Capsule()
                        .fill(app.appearance.accent.color)
                        .matchedGeometryEffect(id: "rail.selection", in: selectionMorph)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(selected ? 1 : 0.72)
        .scaleEffect(selected ? 1 : 0.9)
        .accessibilityLabel(item.title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("rail.\(item.id)")
    }

    private var reelGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = min(max(value.translation.height, -60), 60)
            }
            .onEnded { value in
                guard abs(value.predictedEndTranslation.height) > 24 else { return }
                selectRelative(value.predictedEndTranslation.height < 0 ? 1 : -1)
            }
    }

    private func selectRelative(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = (selectedIndex + delta + items.count) % items.count
        select(items[next])
    }

    private func select(_ item: Item) {
        collapseTask?.cancel()
        revealedID = item.id
        app.navigation.replaceContext(with: item.route)
        HapticEngine.shared.play(.selection)
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { revealedID = nil }
        }
    }
}

private extension View {
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
