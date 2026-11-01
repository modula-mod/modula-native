import SwiftUI

extension DiscoverRoute {
    /// Scopes with something to customise. Trending and Topics have none, so no Customise entry is offered.
    var hasFilters: Bool {
        switch self {
        case .people, .posts, .modules: true
        case .trending, .topics: false
        }
    }
}

struct DiscoverFilterSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var scope: DiscoverRoute {
        if case .discover(let route) = app.navigation.currentRoute { return route }
        return .trending
    }

    var body: some View {
        ModulaGlassSheetScaffold(title: "Customise \(scope.filterTitle)", identifier: "discover.filter") {
            switch scope {
            case .people: peopleFilters
            case .posts: postFilters
            case .modules: moduleFilters
            case .topics, .trending:
                // Not reachable from the UI any more (Customise is hidden); kept as a graceful fallback.
                ModulaGlassSheetSection {
                    ModulaGlassActionRow(title: "Browse people", detail: "People have filters", symbol: "person.2") {
                        dismiss()
                        app.navigation.open(.discover(.people))
                    }
                }
            }
        }
    }

    @ViewBuilder private var peopleFilters: some View {
        let current = app.discover.people.filter
        ModulaGlassSheetSection(title: "Show") {
            ModulaGlassToggleRow(title: "Following", detail: "Only people you follow", symbol: "person.crop.circle.badge.checkmark", isOn: Binding(
                get: { current.followingOnly },
                set: { value in
                    var next = current
                    next.followingOnly = value
                    app.discover.setPeopleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            .accessibilityIdentifier("discover.filter.following")
            ModulaGlassRowDivider()
            ModulaGlassToggleRow(title: "Newest", detail: "Recently joined first", symbol: "clock", isOn: Binding(
                get: { current.newestFirst },
                set: { value in
                    var next = current
                    next.newestFirst = value
                    app.discover.setPeopleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            .accessibilityIdentifier("discover.filter.newest")
        }
    }

    @ViewBuilder private var postFilters: some View {
        let current = app.discover.posts.filter
        let accent = app.appearance.liveAccent
        ModulaGlassSheetSection(title: "Show") {
            ForEach(Array(PostFilters.Kind.allCases.enumerated()), id: \.element) { i, kind in
                if i > 0 { ModulaGlassRowDivider() }
                Button {
                    var next = current
                    next.kind = kind
                    app.discover.setPostFilter(next)
                    HapticEngine.shared.play(.selection)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ModulaGlassSheetIcon(symbol: "line.3.horizontal.decrease")
                        Text(kind.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                        Spacer()
                        if current.kind == kind { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(accent) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(current.kind == kind ? .isSelected : [])
                .accessibilityIdentifier("discover.filter.post.\(kind.rawValue)")
            }
        }
    }

    @ViewBuilder private var moduleFilters: some View {
        let current = app.discover.modules.filter
        ModulaGlassSheetSection(title: "Show") {
            ModulaGlassToggleRow(title: "Installed", detail: "Modules on this device", symbol: "checkmark.circle", isOn: Binding(
                get: { current.installedOnly },
                set: { value in
                    var next = current
                    next.installedOnly = value
                    app.discover.setModuleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            ModulaGlassRowDivider()
            ModulaGlassToggleRow(title: "From Modula", detail: "Made by the Modula team", symbol: "seal", isOn: Binding(
                get: { current.firstPartyOnly },
                set: { value in
                    var next = current
                    next.firstPartyOnly = value
                    app.discover.setModuleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            ModulaGlassRowDivider()
            ModulaGlassToggleRow(title: "Compatible", detail: "Runs on this version of Modula", symbol: "iphone", isOn: Binding(
                get: { current.compatibleOnly },
                set: { value in
                    var next = current
                    next.compatibleOnly = value
                    app.discover.setModuleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
        }
    }
}

private extension DiscoverRoute {
    var filterTitle: String {
        switch self {
        case .people: "People"
        case .posts: "Posts"
        case .modules: "Modules"
        case .trending: "Trending"
        case .topics: "Topics"
        }
    }
}
