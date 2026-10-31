import SwiftUI

struct DiscoverScopePicker: View {
    let selection: DiscoverRoute
    var compact: Bool = false
    var onSelect: (DiscoverRoute) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            scopeRow
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                   .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .animation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discover scope")
        .accessibilityIdentifier("discover.scope-picker")
    }

    @ViewBuilder
    private var scopeRow: some View {
        let row = HStack(spacing: 8 * app.appearance.density.spacingScale) {
            ForEach(DiscoverRoute.allCases, id: \.self) { scope in
                scopeButton(scope)
            }
        }
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { row }
        } else {
            row
        }
    }

    private func scopeButton(_ scope: DiscoverRoute) -> some View {
        let selected = scope == selection
        return Button {
            onSelect(scope)
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(scope))
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(title(scope))
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
                .padding(.horizontal, 14)
                .padding(.horizontal, compact ? -2 : 0)
                .frame(minHeight: compact ? 32 : 34)
                // Selected text sits on accent-tinted glass, so it must contrast with the tint
                // (it used to be accent-on-accent, which rendered the "Trending" chip blank).
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(DiscoverScopeGlass(selected: selected))
        .accessibilityLabel(title(scope))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("discover.scope.\(scope.rawValue)")
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

    private func symbol(_ route: DiscoverRoute) -> String {
        switch route {
        case .trending: "flame.fill"
        case .people: "person.fill"
        case .topics: "number"
        case .posts: "doc.text.fill"
        case .modules: "shippingbox.fill"
        }
    }
}

private struct DiscoverScopeGlass: ViewModifier {
    var selected: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        if #available(iOS 26.0, *), !opaque {
            if selected {
                content.glassEffect(.regular.tint(app.appearance.accent.color).interactive(), in: Capsule())
            } else {
                content.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            content
                .background(opaque ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: Capsule())
                .overlay(Capsule().stroke(selected ? app.appearance.accent.color.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: selected ? 1.25 : 0.75))
        }
    }
}
