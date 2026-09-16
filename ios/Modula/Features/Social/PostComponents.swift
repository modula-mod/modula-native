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
    var onOpenMedia: ((SocialPostMedia) -> Void)? = nil
    var onOpenModule: ((SocialPostModule) -> Void)? = nil
    var onReactLongPress: (() -> Void)? = nil

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
            Button(action: onOpenPost) {
                PostRendererRegistry.content(
                    for: post,
                    onOpenMedia: onOpenMedia,
                    onOpenModule: onOpenModule
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .contextMenu {
            let actions = PostContextActions.menu(
                isOwn: isOwnPost,
                saved: post.saved,
                capabilities: app.postActions.capabilities
            )
            ForEach(actions) { action in
                Button(role: action.role == .destructive ? .destructive : nil) {
                    onContextAction?(action)
                } label: {
                    if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
                .disabled(!action.isInteractive)
            }
        }
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

struct PostMediaView: View {
    let media: [SocialPostMedia]
    var onOpen: ((SocialPostMedia) -> Void)?

    var body: some View {
        let images = media.filter(\.isImage)
        if images.count == 1, let first = images.first {
            mediaImage(first, immersive: true)
        } else if images.count > 1 {
            PostCarouselMedia(images: images, onOpen: onOpen)
        }
    }

    private func mediaImage(_ item: SocialPostMedia, immersive: Bool) -> some View {
        Button {
            onOpen?(item)
        } label: {
            Group {
                if let url = item.url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        default:
                            placeholder.overlay(ProgressView().controlSize(.small))
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: immersive ? mediaHeight(for: item) : 160)
            .clipShape(RoundedRectangle(cornerRadius: immersive ? 4 : 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.altText ?? "Photo attached")
        .accessibilityHint("Opens media viewer")
        .accessibilityIdentifier("post.media.\(item.id)")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
    }

    private func mediaHeight(for item: SocialPostMedia) -> CGFloat {
        guard let ratio = item.aspectRatio, ratio > 0 else { return 220 }
        let clamped = min(max(ratio, 0.6), 1.8)
        return min(320, max(160, 280 / clamped))
    }
}

struct PostCarouselMedia: View {
    let images: [SocialPostMedia]
    var onOpen: ((SocialPostMedia) -> Void)?
    @State private var page = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onOpen?(item)
                    } label: {
                        Group {
                            if let url = item.url {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        Color.primary.opacity(0.08)
                                    }
                                }
                            } else {
                                Color.primary.opacity(0.08)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                    .accessibilityLabel(item.altText ?? "Image \(index + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 220)
            .accessibilityLabel("\(images.count) images")
            .accessibilityValue("Page \(page + 1) of \(images.count)")
        }
    }
}

struct PostLinkPreview: View {
    let link: SocialPostLink
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openSafely()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let imageURL = link.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.primary.opacity(0.06)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
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
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(link.title ?? link.domain ?? "Link")
        .accessibilityHint("Opens link")
    }

    private func openSafely() {
        guard let url = link.url else { return }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        openURL(url)
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
                        if let reaction {
                            Task { await app.postActions.setReaction(post, reaction: reaction) }
                        }
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
    @ViewBuilder
    static func content(
        for post: SocialPost,
        onOpenMedia: ((SocialPostMedia) -> Void)?,
        onOpenModule: ((SocialPostModule) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PostBody(post: post)
            switch post.kind {
            case .media, .carousel, .text where post.hasMedia:
                if post.hasMedia {
                    PostMediaView(media: post.media, onOpen: onOpenMedia)
                }
            case .link:
                if post.hasMedia {
                    PostMediaView(media: post.media, onOpen: onOpenMedia)
                }
                if let link = post.link {
                    PostLinkPreview(link: link)
                }
            case .module:
                if let module = post.module {
                    PostModuleChip(module: module) {
                        onOpenModule?(module)
                    }
                }
                if post.hasMedia {
                    PostMediaView(media: post.media, onOpen: onOpenMedia)
                }
            case .video, .poll, .audio, .movie:
                // Reserved — never fake playback / poll UI without backend truth.
                if post.hasMedia {
                    PostMediaView(media: post.media, onOpen: onOpenMedia)
                }
                if let link = post.link {
                    PostLinkPreview(link: link)
                }
            case .text, .unknown:
                if let link = post.link {
                    PostLinkPreview(link: link)
                }
                if let module = post.module {
                    PostModuleChip(module: module) {
                        onOpenModule?(module)
                    }
                }
            }
            if post.kind != .link, let link = post.link, post.kind == .media {
                PostLinkPreview(link: link)
            }
        }
    }
}
