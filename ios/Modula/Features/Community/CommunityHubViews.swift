import SwiftUI

struct CommunityRootView: View {
    let route: CommunityRoute

    var body: some View {
        Group {
            if CommunityFeatureFlags.isEnabled {
                switch route {
                case .modulaBuilders: CommunityBuildersView()
                case .settings: CommunitySettingsView()
                case .poll: CommunityPollView()
                case .event: CommunityEventView()
                default: CommunityHubView(route: route)
                }
            } else {
                CommunityUnavailableView()
            }
        }
        .modulaCanvas()
        .navigationTitle(CommunityFeatureFlags.isEnabled ? route.navigationTitle : CommunityCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(accessibilityID)
    }

    private var accessibilityID: String {
        switch route {
        case .modulaBuilders: "community.builders"
        case .settings: "community.settings"
        case .poll: "community.poll"
        case .event: "community.event"
        default: "community.hub"
        }
    }
}

struct CommunityUnavailableView: View {
    var body: some View {
        ModulaEmptyState(
            title: CommunityCopy.title,
            message: "\(CommunityCopy.comingSoon). \(CommunityCopy.noRoutes)",
            symbol: "person.3"
        )
    }
}

struct CommunityHubView: View {
    let route: CommunityRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""

    private var scope: CommunityHubScope { route.hubScope ?? .forYou }
    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                search
                scopes
                scopeBody
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .toolbar { hubToolbar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaWordmark(height: 22)
            Text(CommunityCopy.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(CommunityCopy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(CommunityCopy.preview)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(CommunityCopy.searchPrompt, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { openSearch() }
                Button(action: openSearch) {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }
            .padding(.leading, 14)
            .modulaGlass(in: Capsule(), interactive: true, specular: true)
            Text(CommunityCopy.searchFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(CommunityHubScope.allCases) { item in
                        let selected = item == scope
                        Button {
                            guard item != scope else { return }
                            HapticEngine.shared.play(.selection)
                            app.navigation.replaceTop(with: .community(item.route))
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("community.scope.\(item.rawValue)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scopeBody: some View {
        switch scope {
        case .forYou:
            CommunityPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Featured")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Share your space")
                        .font(.title2.bold())
                    Text(CommunityCopy.noRoutes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    CommunityComingSoonButton(title: "Join the conversation")
                }
            }
            section("Trending", message: "Topics will show up here when communities exist.")
            buildersLink
            section("Posts", message: CommunityCopy.postsEmpty)
            pollLink
        case .following:
            section("Following", message: "People you follow already appear on Home. There is no community following feed.")
            eventLink
        case .communities:
            section("Communities", message: "No communities to join yet.")
            buildersLink
        case .topics:
            section("Topics", message: "No topics yet. Hashtags in posts stay on Search.")
        case .creators:
            section("Creators", message: "No creator directory yet.")
        case .builders:
            buildersLink
            section("Projects", message: "Builder projects aren’t a catalogue yet.")
        case .events:
            eventLink
            section("Events", message: CommunityCopy.eventFootnote)
        }
    }

    private var buildersLink: some View {
        Button {
            app.navigation.push(.community(.modulaBuilders))
        } label: {
            CommunityPanel {
                HStack(spacing: 12) {
                    CommunityMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CommunityCopy.buildersTitle)
                            .font(.headline)
                        Text(CommunityCopy.buildersStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CommunityCopy.buildersTitle)
        .accessibilityIdentifier("community.open.builders")
    }

    private var eventLink: some View {
        Button {
            app.navigation.push(.community(.event))
        } label: {
            CommunityPanel {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Community events")
                            .font(.headline)
                        Text(CommunityCopy.comingSoon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("community.open.event")
    }

    private var pollLink: some View {
        Button {
            app.navigation.push(.community(.poll))
        } label: {
            CommunityPanel {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Polls")
                            .font(.headline)
                        Text("Look up a comment poll on a post.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("community.open.poll")
    }

    private func section(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModulaSectionHeader(title: title)
            CommunityPanel {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var hubToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                app.navigation.push(.community(.settings))
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Community Settings")
            .accessibilityIdentifier("community.open.settings")
        }
    }

    private func openSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        app.navigation.open(.search(.root(trimmed.isEmpty ? nil : trimmed)))
    }
}

struct CommunityBuildersView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var tab: CommunityBuildersTab = .feed
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                identity
                tabs
                tabBody
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .toolbar { buildersToolbar }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.opacity(0.55), Color.orange.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 168)
            VStack(alignment: .leading, spacing: 6) {
                Text("MODULA BUILDERS")
                    .font(.caption.weight(.bold))
                Text("Build together when this community exists.")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            CommunityMark()
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.shownName)
                    .font(.title3.bold())
                Text(CommunityCopy.buildersStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(CommunityBuildersTab.allCases) { item in
                        let selected = item == tab
                        Button {
                            tab = item
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("community.builders.tab.\(item.rawValue)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .feed:
            CommunityPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CommunityCopy.postsEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CommunityCopy.noRoutes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .projects:
            CommunityPanel {
                Text("Projects aren’t listed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .events:
            Button {
                app.navigation.push(.community(.event))
            } label: {
                CommunityPanel {
                    Label("Community events", systemImage: "calendar")
                        .font(.headline)
                    Text(CommunityCopy.comingSoon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        case .members:
            CommunityPanel {
                Text(CommunityCopy.membersEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .about:
            CommunityPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CommunityCopy.buildersTitle)
                        .font(.headline)
                    Text("A place for people building on Modula, once communities exist on the server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CommunityCopy.noRoutes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        CommunityComingSoonButton(title: "Join")
            .accessibilityIdentifier("community.builders.join")
    }

    @ToolbarContentBuilder
    private var buildersToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    app.navigation.push(.community(.poll))
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Community poll")
                Button {
                    app.navigation.push(.community(.settings))
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Community Settings")
            }
        }
    }
}

struct CommunityMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.09, green: 0.11, blue: 0.14))
            ModulaUnitMark(style: .solid(.white))
                .padding(10)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

struct CommunityPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
    }
}

struct CommunityComingSoonButton: View {
    var title: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            app.navigation.flash(CommunityCopy.comingSoon, symbol: "clock")
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .modulaAccentCTA()
        .accessibilityHint(CommunityCopy.comingSoon)
    }
}

#if DEBUG
struct CommunityDeveloperEntry: View {
    @Environment(AppEnvironment.self) private var app
    @State private var enabled = CommunityFeatureFlags.isEnabled

    var body: some View {
        Toggle("Community shell", isOn: $enabled)
            .onChange(of: enabled) { _, value in
                CommunityFeatureFlags.setEnabled(value)
            }
            .accessibilityIdentifier("developer.community.toggle")
        if enabled {
            Button("Open Community") {
                app.navigation.open(.community(.hub))
            }
            .accessibilityIdentifier("developer.community.open")
        }
    }
}
#endif
