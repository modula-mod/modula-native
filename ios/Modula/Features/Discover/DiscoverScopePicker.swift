import SwiftUI

struct DiscoverScopePicker: View {
    let selection: DiscoverRoute
    var onSelect: (DiscoverRoute) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8 * app.appearance.density.spacingScale) {
                ForEach(DiscoverRoute.allCases, id: \.self) { scope in
                    let selected = scope == selection
                    Button {
                        onSelect(scope)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Text(title(scope))
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? Color.white : .primary)
                            .background(
                                Capsule().fill(selected ? app.appearance.accent.color : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title(scope))
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("discover.scope.\(scope.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .animation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discover scope")
        .accessibilityIdentifier("discover.scope-picker")
    }

    private func title(_ route: DiscoverRoute) -> String {
        switch route {
        case .trending: "Trending"
        case .people: "People"
        case .topics: "Topics"
        case .posts: "Posts"
        case .modules: "Modules"
        }
    }
}
