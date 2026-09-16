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
    private var selectedHeight: CGFloat { isRevealed ? 72 : 38 }
    private var railHeight: CGFloat { (38 * 2) + selectedHeight + (8 * 2) + 14 }

    var body: some View {
        let shape = ModulaRailShape(revealProgress: isRevealed ? 1 : 0)
        VStack(spacing: 8) {
            ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                railButton(item, selected: index == 1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
        .frame(width: 44, height: railHeight)
        .offset(x: 0)
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
                        .font(.system(size: 17, weight: selected ? .semibold : .medium))
                        .symbolVariant(selected ? .fill : .none)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.68))
            .frame(width: 38, height: selected ? selectedHeight : 38)
            .background {
                if selected {
                    Capsule()
                        .fill(app.appearance.accent.color.opacity(isRevealed ? 1 : 0.92))
                        .matchedGeometryEffect(id: "rail.selection", in: selectionMorph)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .opacity(selected ? 1 : 0.72)
        .scaleEffect(selected ? 1 : 0.88)
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
        app.navigation.replaceContextOrTop(with: item.route)
        HapticEngine.shared.play(.selection)
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { revealedID = nil }
        }
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
