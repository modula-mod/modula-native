import SwiftUI

struct DiscoverFilterSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let scope: DiscoverRoute = {
            if case .discover(let route) = app.navigation.currentRoute { return route }
            return .trending
        }()
        List {
            switch scope {
            case .people:
                peopleFilters
            case .posts:
                postFilters
            case .modules:
                moduleFilters
            case .topics, .trending:
                Section {
                    Text("This scope has no extra filters.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Customise")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("discover.filter")
    }

    @ViewBuilder private var peopleFilters: some View {
        let current = app.discover.people.filter
        Section("People") {
            Toggle("Following", isOn: Binding(
                get: { current.followingOnly },
                set: { value in
                    var next = current
                    next.followingOnly = value
                    app.discover.setPeopleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            .accessibilityIdentifier("discover.filter.following")
            Toggle("Newest", isOn: Binding(
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
        Section("Posts") {
            ForEach(PostFilters.Kind.allCases) { kind in
                Button {
                    var next = current
                    next.kind = kind
                    app.discover.setPostFilter(next)
                    HapticEngine.shared.play(.selection)
                    dismiss()
                } label: {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        if current.kind == kind { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityIdentifier("discover.filter.post.\(kind.rawValue)")
            }
        }
    }

    @ViewBuilder private var moduleFilters: some View {
        let current = app.discover.modules.filter
        Section("Modules") {
            Toggle("Installed", isOn: Binding(
                get: { current.installedOnly },
                set: { value in
                    var next = current
                    next.installedOnly = value
                    app.discover.setModuleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            Toggle("From Modula", isOn: Binding(
                get: { current.firstPartyOnly },
                set: { value in
                    var next = current
                    next.firstPartyOnly = value
                    app.discover.setModuleFilter(next)
                    HapticEngine.shared.play(.selection)
                }
            ))
            Toggle("Compatible", isOn: Binding(
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
