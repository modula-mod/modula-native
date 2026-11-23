import SwiftUI

struct SavedView: View {
    var section: SavedSection = .root
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if showsPosts, app.saved.backendListOpen {
                ModulaEmptyState(
                    title: "Saved",
                    message: "Saved posts aren’t available from this account yet.",
                    symbol: "bookmark"
                )
            } else if showsPosts, (!app.saved.loaded || app.saved.loading) && app.saved.posts.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 92)
                        }
                    }
                    .padding(.horizontal, 16)
                    .redacted(reason: .placeholder)
                }
                .scrollDisabled(true)
                .accessibilityLabel("Loading saved posts")
            } else if showsPosts, let error = app.saved.error, app.saved.posts.isEmpty {
                ModulaErrorState(message: error) {
                    Task { await app.saved.load(force: true) }
                }
            } else {
                savedList
            }
        }
        .modulaCanvas()
        .navigationTitle(title)
        .accessibilityIdentifier("saved.root")
        .task { await app.saved.load() }
        .modulaRefreshable { await app.saved.load(force: true) }
    }

    private var showsPosts: Bool { section == .root || section == .posts }
    private var showsModules: Bool { section == .root || section == .modules }
    private var showsLinks: Bool { section == .root || section == .links }

    private var savedList: some View {
        List {
            Section {
                Text("Saved posts load from your account. Modules and links can’t be saved yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsPosts { postsSection }
            if showsModules { unavailableSection("Modules", "Saved modules aren’t available. There’s no saved-modules route.") }
            if showsLinks { unavailableSection("Links & Media", "Saved links aren’t available. There’s no saved-links route.") }
        }
        .listStyle(.insetGrouped)
        .modulaSoftScrollEdge()
    }

    private var postsSection: some View {
        Section {
            if app.saved.posts.isEmpty && app.saved.loaded {
                Text("Bookmark a post and it will show up here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.saved.posts) { post in
                    SavedPostRow(post: app.posts.resolved(post)) {
                        Task { await app.saved.unsave(postID: post.id, postActions: app.postActions) }
                    }
                }
                if app.saved.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await app.saved.loadMore() }
                }
            }
        } header: {
            HStack {
                Text("Posts")
                Spacer()
                Text(app.saved.posts.isEmpty ? "None yet" : "\(app.saved.posts.count) \(app.saved.posts.count == 1 ? "item" : "items")")
            }
        }
    }

    private func unavailableSection(_ title: String, _ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(.secondary)
        } header: {
            Text(title)
        }
    }

    private var title: String {
        switch section {
        case .root, .posts: "Saved"
        case .modules: "Saved Modules"
        case .links: "Saved Links"
        }
    }
}

private struct SavedPostRow: View {
    let post: SocialPost
    var onUnsave: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            app.postActions.ingest(post)
            app.navigation.open(.post(post.id, .root))
            HapticEngine.shared.play(.navigation)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let author = post.author {
                    ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(post.author?.displayName ?? "Post")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(ActivityRelativeTime.string(from: post.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color(hex: "#D66056"))
                            .accessibilityHidden(true)
                    }
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unsave", systemImage: "bookmark.slash", role: .destructive, action: onUnsave)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Unsave", role: .destructive, action: onUnsave)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the saved post")
    }

    private var excerpt: String {
        if let text = post.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        if !post.media.isEmpty { return "Photo or video" }
        return "Saved post"
    }
}
