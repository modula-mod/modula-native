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
                            let resolved = app.posts.resolved(post)
                            PostCard(
                                post: resolved,
                                showsActionRail: resolved.hasMedia,
                                isOwnPost: resolved.author?.id == app.auth.account?.accountId,
                                onOpenPost: {
                                    app.postActions.ingest(resolved)
                                    app.navigation.open(.post(resolved.id, .root))
                                    HapticEngine.shared.play(.navigation)
                                },
                                onOpenAuthor: {
                                    guard let author = resolved.author else { return }
                                    app.navigation.push(.profile(author.routeID, .overview))
                                    HapticEngine.shared.play(.navigation)
                                },
                                onLike: {
                                    Task {
                                        app.postActions.ingest(resolved)
                                        await app.postActions.toggleLike(resolved)
                                    }
                                },
                                onComment: {
                                    app.navigation.open(.post(resolved.id, .comments))
                                    HapticEngine.shared.play(.navigation)
                                },
                                onRepost: {
                                    Task {
                                        app.postActions.ingest(resolved)
                                        await app.postActions.toggleRepost(resolved)
                                    }
                                },
                                onSave: {
                                    Task { await app.saved.unsave(postID: resolved.id, postActions: app.postActions) }
                                }
                            )
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
                .modulaSoftScrollEdge()
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
