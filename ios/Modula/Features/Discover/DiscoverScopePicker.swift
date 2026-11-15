import SwiftUI

struct DiscoverScopePicker: View {
    let selection: DiscoverRoute
    var compact: Bool = false
    var onSelect: (DiscoverRoute) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Shared segmented control (5 scopes fit; scrolls automatically if more are added).
        ModulaSegmentedControl("Discover scope", selection: Binding(get: { selection }, set: { onSelect($0) }),
                               options: DiscoverRoute.allCases, compact: compact, symbol: { symbol($0) },
                               identifier: { "discover.scope.\($0.rawValue)" }) { title($0) }
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
