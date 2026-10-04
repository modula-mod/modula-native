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
    @State private var heartBurst = 0

    private var resolved: SocialPost {
        app.posts.resolved(post)
    }

    var body: some View {
        let post = resolved
        let canonical = ModulaPostMapper.map(post)
        let layout = ModulaPostLayoutPolicy.resolve(canonical)
        let media = post.media.first
        let ratio = media?.aspectRatio.map { Double($0) } ?? media.flatMap { item -> Double? in
            guard let width = item.width, let height = item.height, height > 0 else { return nil }
            return Double(width) / Double(height)
        }
        let usesRail = showsActionRail && layout.prefersActionRail && !dynamicTypeSize.isAccessibilitySize
            && ModulaPostLayoutPolicy.canOverlayActionRail(aspectRatio: ratio)
        VStack(alignment: .leading, spacing: 10 * app.appearance.density.spacingScale) {
            PostHeader(
                post: post,
                showsCompactAuthor: showsCompactAuthor,
                onOpenAuthor: onOpenAuthor,
                onMore: onMore,
                menuActions: onContextAction == nil ? [] : menuActions(for: post),
                onSelectAction: onContextAction
            )

            if !post.hasMedia { postBody(post) }

            PostCanonicalContent(
                source: post,
                videoCoordinator: videoCoordinator,
                onOpenAttachment: { attachment in
                    if let media = post.media.first(where: { $0.id == attachment.id }) {
                        onOpenMedia?(media)
                    }
                },
                onOpenModule: onOpenModule
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Settings → Gestures → "Double-tap to like". Simultaneous so single taps
            // (video play/pause, open media) are never delayed.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard ModulaPreferences.doubleTapToLike, post.hasMedia else { return }
                if !post.liked { onLike() }
                HapticEngine.shared.play(.lightImpact)
                heartBurst += 1
            })
            .overlay {
                DoubleTapHeartBurst(trigger: heartBurst)
            }
            .overlay(alignment: .trailing) {
                if usesRail {
                    PostActionRail(
                        post: post,
                        onLike: onLike,
                        onComment: onComment,
                        onSave: onSave,
                        onShare: { onShare?() ?? onRepost() },
                        onReactLongPress: onReactLongPress,
                        onContextAction: onContextAction
                    )
                    .padding(.trailing, 8)
                }
            }

            if post.hasMedia { postBody(post) }

            if !usesRail {
                PostActions(
                    post: post,
                    onLike: onLike,
                    onComment: onComment,
                    onRepost: onRepost,
                    onSave: onSave,
                    onReactLongPress: onReactLongPress
                )
            }

            if layout.prefersActionRail {
                PostCommentPrompt(post: post, onComment: onComment)
            }
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
        .accessibilityActions {
            // Expose every real menu action to VoiceOver instead of a single
            // "More Actions" entry that only played a haptic.
            if let onContextAction {
                ForEach(menuActions(for: post).filter(\.isInteractive)) { action in
                    Button(action.resolvedAccessibilityLabel) { onContextAction(action) }
                }
            }
        }
        .modulaContextMenu(
            actions: menuActions(for: post),
            onSelect: { onContextAction?($0) }
        )
        // Links in this post open in the Modula browser with the post in its bottom sheet.
        .environment(\.modulaLinkSource, linkSource(for: post))
        .environment(\.openURL, OpenURLAction { url in
            if let route = PostTextLinks.route(for: url) {
                app.navigation.push(route)
                return .handled
            }
            return ModulaLinkRouter.handle(url, source: linkSource(for: post))
        })
    }

    private func linkSource(for post: SocialPost) -> ModulaBrowserSource {
        ModulaBrowserSource(post: post, onLike: onLike, onComment: onComment, onRepost: onRepost, onSave: onSave, onShare: onShare)
    }

    private func menuActions(for post: SocialPost) -> [ModulaContextAction] {
        PostContextActions.menu(
            isOwn: isOwnPost,
            saved: post.saved,
            capabilities: app.postActions.capabilities
        )
    }

    /// The body is tappable to open the post, but is *not* wrapped in a
    /// Button so inline links and "Show more" keep their own hit testing.
    @ViewBuilder
    private func postBody(_ post: SocialPost) -> some View {
        if post.text?.isEmpty == false {
            PostBody(post: post)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenPost)
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: "Open Post", onOpenPost)
                .accessibilityHint("Opens the full post")
                .accessibilityIdentifier("post.open.\(post.id)")
        }
    }
}

struct PostHeader: View {
    let post: SocialPost
    var showsCompactAuthor: Bool = false
    var onOpenAuthor: () -> Void
    var onMore: (() -> Void)? = nil
    /// When provided, the "…" control is a native Menu of these actions.
    var menuActions: [ModulaContextAction] = []
    var onSelectAction: ((ModulaContextAction) -> Void)? = nil

    var body: some View {
        if showsCompactAuthor {
            // Compact (profile) header: time on the leading edge, menu trailing. The
            // menu stays accessible (the whole row used to be hidden from VoiceOver).
            HStack(spacing: 6) {
                Text(ActivityRelativeTime.string(from: post.createdAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if post.isEdited {
                    Text("· Edited")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                moreButton
            }
        } else {
            HStack(spacing: 10) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: 10) {
                        if let author = post.author {
                            ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(author.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(headerContext(author: author))
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
                moreButton
            }
        }
    }

    private func headerContext(author: SocialAuthor) -> String {
        let origin = "@\(author.handle)"
        let time = ActivityRelativeTime.string(from: post.createdAt)
        return post.isEdited ? "\(origin) · \(time) · Edited" : "\(origin) · \(time)"
    }

    @ViewBuilder
    private var moreButton: some View {
        if let onSelectAction, !menuActions.isEmpty {
            Menu {
                ForEach(menuActions) { action in
                    Button(role: action.role == .destructive ? .destructive : nil) {
                        onSelectAction(action)
                    } label: {
                        if let symbol = action.systemImage {
                            Label(action.title, systemImage: symbol)
                        } else {
                            Text(action.title)
                        }
                    }
                    .disabled(!action.isInteractive)
                    .accessibilityLabel(action.resolvedAccessibilityLabel)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("post.more.\(post.id)")
        } else if let onMore {
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

private struct PostCommentPrompt: View {
    let post: SocialPost
    let onComment: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: onComment) {
            HStack(spacing: 9) {
                if let profile = app.profile.ownProfile {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 28)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                Text(post.replyCount > 0 ? "Join the conversation…" : "Add a comment…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a comment")
        .accessibilityHint("Opens comments")
        .accessibilityIdentifier("post.comment.prompt.\(post.id)")
    }
}

struct PostBody: View {
    let post: SocialPost
    var allowsCollapse = true
    @State private var expanded = false
    @Environment(\.modulaLinkSource) private var linkSource
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        if let text = post.text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(PostTextLinks.attributed(displayedText(text)))
                    .font(bodyFont)
                    .foregroundStyle(.primary)
                    .lineSpacing(captionSize.lineSpacing)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(text)
                    .tint(app.appearance.accent.color)
                    .environment(\.openURL, OpenURLAction { url in
                        if let route = PostTextLinks.route(for: url) {
                            app.navigation.push(route)
                            return .handled
                        }
                        return ModulaLinkRouter.handle(url, source: linkSource)
                    })
                // Rich preview for the first web link when the post has no structured link card.
                if post.link == nil, !post.hasMedia, let url = ModulaLinkDetector.firstWebURL(in: text) {
                    ModulaRichLinkCard(url: url)
                        .environment(\.openURL, OpenURLAction { ModulaLinkRouter.handle($0, source: linkSource) })
                }
                if allowsCollapse && text.count > collapseThreshold {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                            expanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .accessibilityLabel(expanded ? "Show less" : "Show more")
                }
                PostTranslationControl(text: text)
            }
        }
    }

    /// Settings → Personalisation → Captions.
    private var captionSize: ModulaPreferences.CaptionSize { ModulaPreferences.captionSize }
    private var collapseThreshold: Int {
        switch captionSize {
        case .compact: 180
        case .standard: 280
        case .comfortable: 420
        }
    }

    private func displayedText(_ text: String) -> String {
        guard allowsCollapse, !expanded, text.count > collapseThreshold else { return text }
        let index = text.index(text.startIndex, offsetBy: collapseThreshold)
        return String(text[..<index]) + "…"
    }

    private var bodyFont: Font {
        .system(captionSize == .compact ? .subheadline : .body, design: app.appearance.fontDesign)
    }
}

/// Interactive social text uses canonical Search/Profile routes, not a new feed.
enum PostTextLinks {
    static func attributed(_ text: String) -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_/@])(?:#[\p{L}\p{N}_]{1,64}|@[\p{L}\p{N}_]+(?:\.[\p{L}\p{N}_]+)*)"#) else {
            return AttributedString(text)
        }
        var result = AttributedString()
        var cursor = text.startIndex
        let whole = NSRange(text.startIndex..., in: text)
        // Web links (opened in the Modula browser) plus #hashtags and @mentions.
        var tokens: [(Range<String.Index>, URL?)] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: whole) {
                guard let range = Range(match.range, in: text), let url = match.url,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
                tokens.append((range, url))
            }
        }
        for match in regex.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text),
                  !tokens.contains(where: { $0.0.overlaps(range) }) else { continue }
            tokens.append((range, nil))
        }
        for (range, webURL) in tokens.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) {
            guard range.lowerBound >= cursor else { continue }
            result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            var token = AttributedString(String(text[range]))
            if let webURL {
                token.link = webURL
            } else {
                var url = URLComponents()
                url.scheme = "modula"
                url.host = text[range].first == "#" ? "hashtag" : "mention"
                url.queryItems = [URLQueryItem(name: "value", value: String(text[range].dropFirst()))]
                token.link = url.url
            }
            result.append(token)
            cursor = range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    static func route(for url: URL) -> AppRoute? {
        guard url.scheme == "modula",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "value" })?.value,
              !value.isEmpty else { return nil }
        switch url.host {
        case "hashtag": return .search(.section(.posts, "#\(value)"))
        case "mention": return .profile(value, .overview)
        default: return nil
        }
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
            .background(app.appearance.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: ModulaRadius.small, style: .continuous))
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
    var onShare: (() -> Void)? = nil
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.saved ? "Unsave" : "Save")
            .accessibilityIdentifier("home.action.save.\(post.id)")
            if let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share post")
            }
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
            title: post.viewerReaction?.accessibilityName ?? "Like",
            symbol: likeSymbol,
            count: max(post.reactionCount, post.likeCount),
            active: post.liked || post.viewerReaction != nil,
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
                    .font(.system(size: 18, weight: .medium))
                    .symbolVariant(filled ? .fill : .none)
                if count > 0 {
                    Text(Self.formatCount(count))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? app.appearance.accent.color : .secondary)
            .opacity(differentiateWithoutColor && active ? 1 : 1)
            .frame(minWidth: 44, minHeight: 44)
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
                PostBody(post: post, allowsCollapse: presentation != .detail)
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

/// Heart that pops over media after a double-tap like. Reduce Motion (system or
/// Settings → Battery & Data → Extra motion reduction) swaps the pop for a fade.
struct DoubleTapHeartBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 88, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
            .scaleEffect(visible ? 1 : (calm ? 1 : 0.4))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in
                withAnimation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.55)) { visible = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(.easeOut(duration: 0.25)) { visible = false }
                }
            }
    }

    private var calm: Bool { reduceMotion || ModulaPreferences.extraMotionReduction }
}

extension ModulaPreferences.CaptionSize {
    var lineSpacing: CGFloat {
        switch self {
        case .compact: 2
        case .standard: 4
        case .comfortable: 7
        }
    }
}
