import SwiftUI

private struct HomeSignalArtwork: View {
    let mode: HomeMode
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: "#071C20")
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.2))
                    .frame(width: proxy.size.width * 0.82)
                    .offset(x: proxy.size.width * 0.32, y: -proxy.size.height * 0.27)
                Circle()
                    .stroke(app.appearance.accent.color.opacity(0.48), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.56)
                    .offset(x: proxy.size.width * 0.32, y: -proxy.size.height * 0.27)
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(index == modeIndex ? 0.72 : 0.18))
                            .frame(width: CGFloat(34 + index * 23), height: 7)
                    }
                }
                .rotationEffect(.degrees(-18))
                .offset(x: proxy.size.width * 0.27, y: proxy.size.height * 0.17)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.5)
                    .rotationEffect(.degrees(12))
                    .offset(x: -proxy.size.width * 0.31, y: -proxy.size.height * 0.26)
            }
        }
        .accessibilityHidden(true)
    }

    private var modeIndex: Int {
        switch mode { case .following: 0; case .forYou: 1; case .modules: 2 }
    }
}

private struct HomeHero: View {
    let mode: HomeMode
    let title: String
    let subtitle: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HomeSignalArtwork(mode: mode)
            VStack(alignment: .leading, spacing: 7) {
                Text(subtitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.62))
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct HomeView: View {
    let mode: HomeMode
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HomeHero(mode: mode, title: title, subtitle: subtitle)
                ModulaSection(title: "Today") {
                    ModulaCard {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                ModulaBadge(title: "Native foundation", symbol: "swift")
                                Spacer()
                                Text("N2").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            }
                            ModulaText(text: "Your shell is ready for what comes next.", role: .headline)
                            Text("Feed data arrives in N3. Routing, appearance, secure module hosting, and independent destination state are already native.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ModulaSection(title: "Quick access") {
                    ModulaCard {
                        VStack(spacing: 0) {
                            ModulaListRow(title: "Product Hub", subtitle: "Browse native module pages", symbol: "shippingbox") {
                                app.navigation.open(.productHub(.featured))
                            }
                            Divider().padding(.leading, 42)
                            ModulaListRow(title: "Appearance", subtitle: "Make Modula feel like yours", symbol: "paintpalette") {
                                app.navigation.open(.settings(.appearance(.root)))
                            }
                            Divider().padding(.leading, 42)
                            ModulaListRow(title: "Settings", symbol: "gearshape") {
                                app.navigation.open(.settings(.root))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 26)
        }
        .modulaCanvas()
        .navigationTitle("Modula")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.navigation.open(.settings(.root)) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .accessibilityIdentifier("native.home")
        .accessibilityValue(RouteSerializer.serialize(.home(mode)))
    }

    private var title: String {
        switch mode {
        case .following: "Your people, in focus."
        case .forYou: "Fresh perspectives."
        case .modules: "Tools in your flow."
        }
    }

    private var subtitle: String {
        switch mode {
        case .following: "Following"
        case .forYou: "For You"
        case .modules: "Modules"
        }
    }
}

struct DiscoverView: View {
    let section: DiscoverRoute
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModulaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ModulaBadge(title: section.rawValue.capitalized, symbol: "safari")
                        ModulaText(text: "Explore Modula", role: .title)
                        Text("Discovery data connects in a later product phase. This foundation preserves the native route without inventing content.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 12)
        }
        .modulaCanvas()
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "People, posts, topics, modules")
        .modulaMinimizedSearchToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(DiscoverRoute.allCases, id: \.self) { destination in
                        Button(display(destination.rawValue), systemImage: discoverSymbol(destination)) {
                            appNavigation(destination)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Discover sections")
            }
        }
    }

    @Environment(AppEnvironment.self) private var app

    private func appNavigation(_ destination: DiscoverRoute) {
        app.navigation.replaceContext(with: .discover(destination))
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func discoverSymbol(_ route: DiscoverRoute) -> String {
        switch route {
        case .trending: "chart.line.uptrend.xyaxis"
        case .people: "person.2"
        case .topics: "number"
        case .posts: "text.bubble"
        case .modules: "shippingbox"
        }
    }
}
