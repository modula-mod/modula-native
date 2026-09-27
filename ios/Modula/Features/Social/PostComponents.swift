import SwiftUI

struct PostCard: View {
    let post: SocialPost
    var showsCompactAuthor: Bool = false
    var showsActionRail: Bool = false
    var isOwnPost: Bool = false
    var onOpenPost: () -> Void
    var onOpenAuthor: () -> Void
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    var onShare: (() -> Void)? = nil
    var onMore: (() -> Void)? = nil
    var onContextAction: ((ModulaContextAction) -> Void)? = nil
    var onOpenMedia: (@MainActor (SocialPostMedia) -> Void)? = nil
    var onOpenModule: (@MainActor (SocialPostModule) -> Void)? = nil
    var onReactLongPress: (() -> Void)? = nil
    var videoCoordinator: FeedVideoCoordinator? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.trailingInteractionInset) private var trailingInteractionInset

    private var resolved: SocialPost {
        app.posts.resolved(post)
    }

    var body: some View {
        let post = resolved
        VStack(alignment: .leading, spacing: 10 * app.appearance.density.spacingScale) {
            PostHeader(
                post: post,
                showsCompactAuthor: showsCompactAuthor,
                onOpenAuthor: onOpenAuthor,
                onMore: onMore
            )
            PostRendererRegistry.content(
                for: post,
                videoCoordinator: videoCoordinator,
                onOpenPost: onOpenPost,
                onOpenMedia: onOpenMedia,
                onOpenModule: onOpenModule
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            if showsActionRail && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    Spacer(minLength: 0)
                    PostActionRail(
                        post: post,
                        onLike: onLike,
                        onComment: onComment,
                        onSave: onSave,
                        onShare: { onShare?() ?? onRepost() },
                        onReactLongPress: onReactLongPress,
                        onContextAction: onContextAction
                    )
                }
                .padding(.trailing, max(0, TrailingInteractionSafeArea.postActionRail - 40))
            } else {
                PostActions(
                    post: post,
                    onLike: onLike,
                    onComment: onComment,
                    onRepost: onRepost,
                    onSave: onSave,
                    onReactLongPress: onReactLongPress
                )
            }

            PostMetadata(post: post)
        }
        .padding(.vertical, 12 * app.appearance.density.spacingScale)
        .padding(.trailing, trailingInteractionInset > 0 && showsActionRail ? 4 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(post.voiceOverSummary)
        .accessibilityIdentifier("home.post.\(post.id)")
        .accessibilityAction(named: "React", onLike)
        .accessibilityAction(named: "Comment", onComment)
        .accessibilityAction(named: "Save", onSave)
        .accessibilityAction(named: "Share") { onShare?() ?? onRepost() }
        .accessibilityAction(named: "Open Author", onOpenAuthor)
        .accessibilityAction(named: "More Actions") { onMore?() }
        .modulaContextMenu(
            actions: PostContextActions.menu(
                isOwn: isOwnPost,
                saved: post.saved,
                capabilities: app.postActions.capabilities
            ),
            onSelect: { onContextAction?($0) }
        )
    }
}

struct PostHeader: View {
    let post: SocialPost
    var showsCompactAuthor: Bool = false
    var onOpenAuthor: () -> Void
    var onMore: (() -> Void)? = nil

    var body: some View {
        if showsCompactAuthor {
            HStack {
                if post.isEdited {
                    Text("Edited")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Text(ActivityRelativeTime.string(from: post.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                moreButton
            }
            .accessibilityHidden(true)
        } else {
            HStack(spacing: 10) {
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
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(post.author.map { "\($0.displayName), @\($0.handle)" } ?? "Author")
                .accessibilityHint("Opens profile")
                .accessibilityIdentifier(post.author.map { "home.author.\($0.id)" } ?? "home.author.unknown")

                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ActivityRelativeTime.string(from: post.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if post.isEdited {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                moreButton
            }
        }
    }

    @ViewBuilder
    private var moreButton: some View {
        if let onMore {
            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
            .accessibilityIdentifier("post.more.\(post.id)")
        }
    }
}

struct PostBody: View {
    let post: SocialPost
    @State private var expanded = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let collapseThreshold = 280

    var body: some View {
        if let text = post.text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayedText(text))
                    .font(bodyFont)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(text)
                if text.count > collapseThreshold {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                            expanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .accessibilityLabel(expanded ? "Show less" : "Show more")
                }
            }
        }
    }

    private func displayedText(_ text: String) -> String {
        guard !expanded, text.count > collapseThreshold else { return text }
        let index = text.index(text.startIndex, offsetBy: collapseThreshold)
        return String(text[..<index]) + "…"
    }

    private var bodyFont: Font {
        .system(.body, design: app.appearance.fontDesign)
    }
}

struct PostModuleChip: View {
    let module: SocialPostModule
    var onOpen: (() -> Void)?
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.name ?? module.id)
                        .font(.caption.weight(.semibold))
                    if let publisher = module.publisher {
                        Text(publisher)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(app.appearance.accent.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(app.appearance.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Module \(module.name ?? module.id)")
        .accessibilityHint("Opens Product Hub")
    }
}

struct PostActions: View {
    let post: SocialPost
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    var onReactLongPress: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var showsReactionPicker = false

    var body: some View {
        HStack(spacing: 4) {
            likeControl
            actionButton(
                title: "Comment",
                symbol: "bubble.right",
                count: post.replyCount,
                active: false,
                filled: false,
                action: onComment
            )
            .accessibilityIdentifier("home.action.comment.\(post.id)")
            actionButton(
                title: "Repost",
                symbol: "arrow.2.squarepath",
                count: post.repostCount,
                active: post.reposted,
                filled: post.reposted,
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
        .overlay(alignment: .topLeading) {
            if showsReactionPicker {
                PostReactionPicker(
                    current: post.viewerReaction ?? (post.liked ? .like : nil),
                    multiEnabled: app.postActions.capabilities.multiReactions,
                    onSelect: { reaction in
                        showsReactionPicker = false
                        Task { await app.postActions.setReaction(post, reaction: reaction) }
                    },
                    onCancel: { showsReactionPicker = false }
                )
                .offset(y: -56)
                .zIndex(2)
            }
        }
    }

    private var likeControl: some View {
        actionButton(
            title: "Like",
            symbol: likeSymbol,
            count: post.likeCount,
            active: post.liked,
            filled: post.liked || post.viewerReaction != nil,
            action: onLike
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: PostGestureThresholds.longPressDuration)
                .onEnded { _ in
                    HapticEngine.shared.play(.contextOpen)
                    if let onReactLongPress {
                        onReactLongPress()
                    } else {
                        showsReactionPicker = true
                    }
                }
        )
        .accessibilityIdentifier("home.action.like.\(post.id)")
        .accessibilityAction(named: Text("React")) {
            showsReactionPicker = true
            HapticEngine.shared.play(.contextOpen)
        }
    }

    private var likeSymbol: String {
        if let reaction = post.viewerReaction {
            return reaction.systemImage
        }
        return post.liked ? "heart.fill" : "heart"
    }

    private func actionButton(
        title: String,
        symbol: String,
        count: Int,
        active: Bool,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolVariant(filled ? .fill : .none)
                if count > 0 {
                    Text(Self.formatCount(count))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? app.appearance.accent.color : .secondary)
            .opacity(differentiateWithoutColor && active ? 1 : 1)
            .frame(minWidth: 44, minHeight: 36)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if differentiateWithoutColor && active {
                    Capsule()
                        .fill(app.appearance.accent.color)
                        .frame(width: 16, height: 2)
                        .offset(y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(count > 0 ? ", \(count)" : "")\(active ? ", selected" : "")")
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
        HStack(spacing: 8) {
            if let feed = post.feed, !feed.isEmpty {
                Text(feed)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

enum PostRendererRegistry {
    @MainActor
    @ViewBuilder
    static func content(
        for post: SocialPost,
        presentation: PostPresentation = .feed,
        videoCoordinator: FeedVideoCoordinator? = nil,
        onOpenPost: (() -> Void)? = nil,
        onOpenMedia: (@MainActor (SocialPostMedia) -> Void)?,
        onOpenModule: (@MainActor (SocialPostModule) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onOpenPost {
                Button(action: onOpenPost) { PostBody(post: post) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHint("Opens the full post")
            } else {
                PostBody(post: post)
            }
            PostCanonicalContent(
                source: post,
                presentation: presentation,
                videoCoordinator: videoCoordinator,
                onOpenAttachment: { attachment in
                    if let media = post.media.first(where: { $0.id == attachment.id }) { onOpenMedia?(media) }
                },
                onOpenModule: onOpenModule
            )
        }
    }
}
