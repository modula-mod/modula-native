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
        .navigationTitle("Tools")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("home.tools")
    }
}
