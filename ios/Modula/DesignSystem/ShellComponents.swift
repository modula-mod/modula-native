import SwiftUI

struct ModulaTabBar: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        @Bindable var navigation = app.navigation
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    navigation.select(tab); HapticEngine.shared.play(.navigation)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: navigation.selectedTab == tab ? tab.selectedIcon : tab.icon).font(.system(size: 19, weight: .medium))
                        Text(tab.title).font(.caption2.weight(navigation.selectedTab == tab ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(navigation.selectedTab == tab ? app.appearance.accent.color : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(navigation.selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
        .background((reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency) ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

struct ModulaContextRail: View {
    struct Interaction: Equatable { var isScrolling = false; var keyboardVisible = false; var immersive = false; static let idle = Self() }
    struct Item: Identifiable { let id: String; let title: String; let symbol: String; let route: AppRoute }
    let route: AppRoute
    var interaction: Interaction = .idle
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var revealedID: String?
    @State private var collapseTask: Task<Void, Never>?
    private var items: [Item] {
        switch route {
        case .home:
            return [Item(id: "following", title: "Following", symbol: "person.2", route: .home(.following)), Item(id: "for-you", title: "For You", symbol: "safari", route: .home(.forYou)), Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .home(.modules))]
        case .activity:
            return [Item(id: "all", title: "All", symbol: "bell", route: .activity(.all)), Item(id: "mentions", title: "Mentions", symbol: "at", route: .activity(.mentions)), Item(id: "requests", title: "Requests", symbol: "person.badge.plus", route: .activity(.requests))]
        case .profile(let id, _):
            return [Item(id: "overview", title: "Overview", symbol: "person", route: .profile(id, .overview)), Item(id: "posts", title: "Posts", symbol: "list.bullet", route: .profile(id, .posts)), Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .profile(id, .modules))]
        case .me:
            return [Item(id: "overview", title: "Overview", symbol: "person", route: .me(.overview)), Item(id: "posts", title: "Posts", symbol: "list.bullet", route: .me(.posts)), Item(id: "modules", title: "Modules", symbol: "shippingbox", route: .me(.modules))]
        default: return []
        }
    }
    private var selectedID: String {
        switch route { case .home(let r): r.rawValue; case .activity(let r): r.rawValue; case .profile(_, let r), .me(let r): r.rawValue; default: "" }
    }
    var body: some View {
        VStack(spacing: 5) {
            ForEach(items) { item in
                Button { select(item) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol).frame(width: 24)
                        if revealedID == item.id { Text(item.title).font(.caption.weight(.semibold)).lineLimit(1).transition(.opacity.combined(with: .move(edge: .trailing))) }
                    }
                    .foregroundStyle(selectedID == item.id ? Color.white : Color.primary)
                    .frame(width: revealedID == item.id ? 90 : 44, height: 46)
                    .background(selectedID == item.id ? app.appearance.accent.color.gradient : Color.clear.gradient, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                .accessibilityIdentifier("rail.\(item.id)")
            }
        }
        .padding(.vertical, 8).padding(.leading, 6).padding(.trailing, 12)
        .background((reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency) ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial), in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 28, bottomTrailingRadius: 0, topTrailingRadius: 0))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 28, bottomTrailingRadius: 0, topTrailingRadius: 0).stroke(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 18, x: -5, y: 7)
        .opacity(interaction.keyboardVisible || interaction.immersive ? 0 : interaction.isScrolling ? 0.72 : 1)
        .offset(x: interaction.keyboardVisible || interaction.immersive ? 24 : 0)
        .animation(ModulaMotion.animation(.railExpand, personality: app.appearance.motion, reduceMotion: reduceMotion), value: revealedID)
    }
    private func select(_ item: Item) {
        collapseTask?.cancel(); revealedID = item.id; app.navigation.replaceContext(with: item.route); HapticEngine.shared.play(.selection)
        collapseTask = Task { try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; await MainActor.run { revealedID = nil } }
    }
}
