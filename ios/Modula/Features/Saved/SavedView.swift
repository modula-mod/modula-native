import SwiftUI

struct SavedView: View {
    var section: SavedSection = .root
    @Environment(AppEnvironment.self) private var app
    @State private var videoCoordinator = FeedVideoCoordinator()

    var body: some View {
        Group {
            if app.saved.backendListOpen {
                ModulaEmptyState(
                    title: "Saved",
                    message: "Posts you save are kept, but showing them here isn’t available yet.",
                    symbol: "bookmark"
                )
            } else if (!app.saved.loaded || app.saved.loading) && app.saved.posts.isEmpty {
                // Skeleton instead of a bare spinner (and never an error flash while loading).
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 36, height: 36)
                                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)).frame(width: 120, height: 12)
                                }
                                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)).frame(height: 12)
                                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)).frame(width: 220, height: 12)
                                RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)).frame(height: 180)
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .redacted(reason: .placeholder)
                }
                .scrollDisabled(true)
                .accessibilityLabel("Loading saved posts")
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
                                },
                                // Same single-active-video policy as Home, so saved
                                // videos don't all autoplay at once.
                                videoCoordinator: videoCoordinator,
                                style: .immersive
                            )
                                .contextMenu {
                                    Button("Unsave", systemImage: "bookmark.slash", role: .destructive) {
                                        Task { await app.saved.unsave(postID: post.id, postActions: app.postActions) }
                                    }
                                }
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
