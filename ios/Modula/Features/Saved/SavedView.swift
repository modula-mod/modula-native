import SwiftUI

struct SavedView: View {
    var section: SavedSection = .root
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if app.saved.backendListOpen {
                ModulaEmptyState(
                    title: "Saved",
                    message: "Saving posts works. Listing saved posts waits on a Greenfield contract.",
                    symbol: "bookmark"
                )
            } else if let error = app.saved.error, app.saved.posts.isEmpty {
                ModulaErrorState(message: error) {
                    Task { await app.saved.load(force: true) }
                }
            } else if app.saved.posts.isEmpty && app.saved.loaded {
                ModulaEmptyState(
                    title: "No saved posts",
                    message: "Bookmark posts to find them here later.",
                    symbol: "bookmark"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: app.appearance.density == .compact ? 10 : 14) {
                        ForEach(app.saved.posts) { post in
                            PostCard(post: post)
                                .contextMenu {
                                    Button("Unsave", systemImage: "bookmark.slash", role: .destructive) {
                                        Task { await app.saved.unsave(postID: post.id, postActions: app.postActions) }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                        }
                        if app.saved.hasMore {
                            ProgressView()
                                .task { await app.saved.loadMore() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .modulaCanvas()
        .navigationTitle(title)
        .accessibilityIdentifier("saved.root")
        .task { await app.saved.load() }
        .refreshable { await app.saved.load(force: true) }
    }

    private var title: String {
        switch section {
        case .root, .posts: "Saved"
        case .modules: "Saved Modules"
        case .links: "Saved Links"
        }
    }
}
