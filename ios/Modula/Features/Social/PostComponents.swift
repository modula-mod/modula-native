import SwiftUI

struct PostCard: View {
    let post: SocialPost
    var showsCompactAuthor: Bool = false
    var onOpenPost: () -> Void
    var onOpenAuthor: () -> Void
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostHeader(post: post, showsCompactAuthor: showsCompactAuthor, onOpenAuthor: onOpenAuthor)
            Button(action: onOpenPost) {
                VStack(alignment: .leading, spacing: 10) {
                    PostBody(post: post)
                    if post.hasMedia {
                        PostMedia(media: post.media)
                    }
                    if let link = post.link {
                        PostLinkPreview(link: link)
                    }
                    if let module = post.module {
                        PostModuleChip(module: module)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            PostActions(
                post: post,
                onLike: onLike,
                onComment: onComment,
                onRepost: onRepost,
                onSave: onSave
            )
            PostMetadata(post: post)
        }
        .padding(.vertical, 12 * app.appearance.density.spacingScale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.post.\(post.id)")
    }
}

struct PostHeader: View {
    let post: SocialPost
    var showsCompactAuthor: Bool = false
    var onOpenAuthor: () -> Void

    var body: some View {
        if showsCompactAuthor {
            HStack {
                Spacer(minLength: 0)
                Text(ActivityRelativeTime.string(from: post.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
        } else {
            Button(action: onOpenAuthor) {
                HStack(spacing: 10) {
                    if let author = post.author {
                        ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(author.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("@\(author.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Modula")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    Text(ActivityRelativeTime.string(from: post.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.author.map { "\($0.displayName), @\($0.handle)" } ?? "Author")
            .accessibilityHint("Opens profile")
            .accessibilityIdentifier(post.author.map { "home.author.\($0.id)" } ?? "home.author.unknown")
        }
    }
}

struct PostBody: View {
    let post: SocialPost

    var body: some View {
        if let text = post.text, !text.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(text)
        }
    }
}

struct PostMedia: View {
    let media: [SocialPostMedia]

    var body: some View {
        let images = media.filter(\.isImage)
        if images.count == 1, let first = images.first {
            mediaImage(first, height: 200)
        } else if images.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images) { item in
                        mediaImage(item, height: 160)
                            .frame(width: 220)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(images.count) images")
        }
    }

    private func mediaImage(_ item: SocialPostMedia, height: CGFloat) -> some View {
        Group {
            if let url = item.url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(item.altText ?? "Image")
    }
}

struct PostLinkPreview: View {
    let link: SocialPostLink
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = link.title {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if let description = link.description {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let domain = link.domain ?? link.url?.host {
                Text(domain).font(.caption2.weight(.semibold)).foregroundStyle(app.appearance.accent.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(link.title ?? link.domain ?? "Link")
    }
}

struct PostModuleChip: View {
    let module: SocialPostModule
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Label(module.name ?? module.id, systemImage: "shippingbox")
            .font(.caption.weight(.semibold))
            .foregroundStyle(app.appearance.accent.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(app.appearance.accent.color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Module \(module.name ?? module.id)")
    }
}

struct PostActions: View {
    let post: SocialPost
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            actionButton(
                title: "Like",
                symbol: post.liked ? "heart.fill" : "heart",
                count: post.likeCount,
                active: post.liked,
                action: onLike
            )
            .accessibilityIdentifier("home.action.like.\(post.id)")
            actionButton(
                title: "Comment",
                symbol: "bubble.right",
                count: post.replyCount,
                active: false,
                action: onComment
            )
            .accessibilityIdentifier("home.action.comment.\(post.id)")
            actionButton(
                title: "Repost",
                symbol: post.reposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                count: post.repostCount,
                active: post.reposted,
                action: onRepost
            )
            .accessibilityIdentifier("home.action.repost.\(post.id)")
            Spacer(minLength: 0)
            Button(action: onSave) {
                Image(systemName: post.saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(post.saved ? app.appearance.accent.color : .secondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.saved ? "Unsave" : "Save")
            .accessibilityIdentifier("home.action.save.\(post.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post actions")
    }

    private func actionButton(
        title: String,
        symbol: String,
        count: Int,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                if count > 0 {
                    Text(Self.formatCount(count))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? app.appearance.accent.color : .secondary)
            .frame(minWidth: 44, minHeight: 36)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(count > 0 ? ", \(count)" : "")")
    }

    static func formatCount(_ value: Int) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        if value >= 10_000 {
            return String(format: "%.1fK", locale: posix, Double(value) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        }
        if value >= 1_000 {
            return String(format: "%.1fK", locale: posix, Double(value) / 1_000)
        }
        return "\(value)"
    }
}

struct PostMetadata: View {
    let post: SocialPost

    var body: some View {
        if let feed = post.feed, !feed.isEmpty {
            Text(feed)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
