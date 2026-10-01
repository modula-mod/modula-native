import SwiftUI

struct HomeSummarySheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mode: HomeMode = {
            if case .home(let mode) = app.navigation.currentRoute { return mode }
            return .following
        }()
        let summary = app.home.summary(for: mode)
        List {
            Section("Overview") {
                LabeledContent("Posts", value: "\(summary.postCount)")
                LabeledContent("Likes", value: "\(summary.likeCount)")
                LabeledContent("Replies", value: "\(summary.replyCount)")
                LabeledContent("With media", value: "\(summary.mediaCount)")
                if summary.moduleCount > 0 {
                    LabeledContent("Module updates", value: "\(summary.moduleCount)")
                }
            }
            if !summary.authorNames.isEmpty {
                Section("Most present") {
                    Text(summary.authorNames.joined(separator: ", "))
                }
            }
            if !summary.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(summary.highlights, id: \.self) { Text($0) }
                }
            }
            if let ranking = summary.rankingVersion {
                Section("Ranking") {
                    Text(ranking).font(.footnote.monospaced())
                }
            }
            Section {
                Text("From your loaded feed. Deterministic aggregate — not an AI summary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Home Summary")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("home.summary")
    }
}

struct HomeFeedToolsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mode: HomeMode = {
            if case .home(let mode) = app.navigation.currentRoute { return mode }
            return .following
        }()
        List {
            Section("Feed") {
                Button {
                    Task {
                        await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                        HapticEngine.shared.play(.confirmation)
                        dismiss()
                    }
                } label: {
                    Label("Refresh \(mode.heroSubtitle)", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("home.tools.refresh")
            }
            Section("Following") {
                Button {
                    dismiss()
                    app.navigation.open(.discover(.people))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Label("Manage Following", systemImage: "person.2")
                }
                .accessibilityIdentifier("home.tools.following")
                Text("Opens Discover people so you can follow or unfollow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Tools")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("home.tools")
    }
}

struct HomeFeedsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var mode: HomeMode {
        if case .home(let mode) = app.navigation.currentRoute { return mode }
        return .following
    }

    var body: some View {
        let options = app.home.displayOptions(for: mode)
        List {
            Section("Your feeds") {
                ForEach(HomeMode.allCases, id: \.self) { feed in
                    Button {
                        app.navigation.replaceContext(with: .home(feed))
                        HapticEngine.shared.play(.navigation)
                        dismiss()
                    } label: {
                        HStack {
                            Label(feed.heroSubtitle, systemImage: symbol(for: feed))
                            Spacer()
                            if feed == mode { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("home.feeds.\(feed.rawValue)")
                }
            }
            Section("Customise \(mode.heroSubtitle)") {
                Toggle("Media only", isOn: Binding(
                    get: { options.mediaOnly },
                    set: { value in
                        var next = options
                        next.mediaOnly = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.media-only")
                Toggle("Hide module posts", isOn: Binding(
                    get: { options.hideModules },
                    set: { value in
                        var next = options
                        next.hideModules = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.hide-modules")
                Text("Applies to posts already loaded in this feed. It doesn’t change what Modula recommends.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("More") {
                Button {
                    dismiss()
                    app.navigation.open(.discover(.people))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Label("Manage following", systemImage: "person.2")
                }
                .accessibilityIdentifier("home.feeds.following")
                Button {
                    Task {
                        await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                        HapticEngine.shared.play(.confirmation)
                        dismiss()
                    }
                } label: {
                    Label("Refresh \(mode.heroSubtitle)", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("home.feeds.refresh")
            }
            Section {
                Text("Following, For You, and Modules are the live home feeds. Custom lists are not on the API yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("home.feeds")
    }

    private func symbol(for feed: HomeMode) -> String {
        switch feed {
        case .following: "person.2"
        case .forYou: "sparkles"
        case .modules: "shippingbox"
        }
    }
}
