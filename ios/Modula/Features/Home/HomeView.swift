import SwiftUI

struct HomeView: View {
    let mode: HomeMode
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ModulaTopBar(title: "Modula") { app.navigation.open(.settings(.root)) }
                ModulaHero(title: title, subtitle: subtitle) {
                    LinearGradient(colors: [app.appearance.accent.color.opacity(0.82), Color.indigo.opacity(0.5), Color.black.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(alignment: .topTrailing) { Image(systemName: symbol).font(.system(size: 76, weight: .ultraLight)).foregroundStyle(.white.opacity(0.6)).padding(28) }
                }
                ModulaSection(title: "Foundation feed") {
                    ModulaCard { VStack(alignment: .leading, spacing: 10) { ModulaBadge(title: "N2 native", symbol: "swift"); ModulaText(text: "The native shell owns this route, its chrome, and its appearance.", role: .headline); Text("Feed data arrives in N3. This sample proves scroll behavior and keeps the product state honest.").foregroundStyle(.secondary) } }
                }
                ModulaSection(title: "Quick access") {
                    ModulaCard { VStack { ModulaListRow(title: "Product Hub", subtitle: "Browse native module pages", symbol: "shippingbox") { app.navigation.open(.productHub(.featured)) }; ModulaListRow(title: "Profile", symbol: "person.crop.circle") { app.navigation.open(.me(.overview)) }; ModulaListRow(title: "Settings", symbol: "gearshape") { app.navigation.open(.settings(.root)) } } }
                }
            }.padding(.horizontal, ModulaLayout.contentInset).padding(.bottom, 24)
        }
        .navigationTitle("Modula").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("native.home").accessibilityValue(RouteSerializer.serialize(.home(mode)))
    }
    private var title: String { switch mode { case .following: "Your people, in focus."; case .forYou: "Fresh perspectives."; case .modules: "Tools in your flow." } }
    private var subtitle: String { switch mode { case .following: "Following"; case .forYou: "For You"; case .modules: "Modules" } }
    private var symbol: String { switch mode { case .following: "person.2.fill"; case .forYou: "sparkles"; case .modules: "shippingbox.fill" } }
}

struct DiscoverView: View {
    let section: DiscoverRoute
    @State private var query = ""
    var body: some View { ScrollView { VStack(spacing: 18) { ModulaTopBar(title: "Discover"); ModulaSearchField(text: $query, prompt: "People, posts, topics, modules"); ModulaCard { VStack(alignment: .leading, spacing: 8) { ModulaBadge(title: section.rawValue.capitalized, symbol: "safari"); ModulaText(text: "Explore Modula", role: .title); Text("Discovery data will connect in a later product phase.").foregroundStyle(.secondary) } } }.padding(.horizontal, 18) }.navigationBarHidden(true) }
}

struct ActivityView: View {
    let mode: ActivityMode
    var body: some View { ScrollView { VStack(spacing: 18) { ModulaTopBar(title: "Activity"); ModulaEmptyState(title: mode.rawValue.capitalized, message: "You’re all caught up. Activity data connects in a later phase.", symbol: mode == .mentions ? "at" : "bell") }.padding(.horizontal, 18) }.navigationBarHidden(true).accessibilityIdentifier("activity.\(mode.rawValue)") }
}
