import SwiftUI
import UIKit

/// Visual treatment for `PostCard`. `.immersive` is the Home feed's media-first card.
enum PostCardStyle: Sendable {
    case standard
    case immersive
}

// MARK: - Emoji reactions

/// One emoji in the reaction picker, mapped to the closest semantic value the backend accepts.
struct PostEmojiReaction: Identifiable, Hashable, Sendable {
    let emoji: String
    let title: String
    let reaction: SocialReaction
    var id: String { emoji }

    static let heart = PostEmojiReaction(emoji: "❤️", title: "Love", reaction: .like)

    /// Quick bar: heart, laugh, wow, sad, angry, fire (then "+").
    static let quick: [PostEmojiReaction] = [
        heart,
        .init(emoji: "😂", title: "Laugh", reaction: .laugh),
        .init(emoji: "😮", title: "Wow", reaction: .curious),
        .init(emoji: "😢", title: "Sad", reaction: .like),
        .init(emoji: "😡", title: "Angry", reaction: .like),
        .init(emoji: "🔥", title: "Fire", reaction: .fire),
    ]

    static let grid: [String] = [
        "❤️", "😂", "😮", "😢", "😡", "🔥", "😍", "🥰", "🤣", "😭",
        "🥲", "😎", "🤩", "🥳", "🎉", "👏", "🙌", "🙏", "🫶", "💯",
        "✨", "💡", "🤔", "🧐", "🤯", "😱", "😴", "🤤", "😈", "💀",
        "👀", "💪", "🌈", "⭐️", "🍿", "☕️", "🎶", "📸", "🌸", "🐐",
    ]

    /// Searchable "+" grid: emoji with names/keywords (first word is the VoiceOver name).
    static let catalog: [(String, String)] = [
        ("❤️", "heart love red like"), ("😂", "laugh joy tears funny lol"), ("😮", "wow surprised shock"),
        ("😢", "sad cry tear"), ("😡", "angry mad rage"), ("🔥", "fire hot lit flame"),
        ("😍", "love eyes heart crush"), ("🥰", "adore hearts smile love"), ("🤣", "rolling laugh lmao funny"),
        ("😭", "sob crying sad"), ("🥲", "smile tear bittersweet"), ("😎", "cool sunglasses"),
        ("🤩", "starstruck amazing wow"), ("🥳", "party celebrate birthday"), ("🎉", "tada celebrate party congrats"),
        ("👏", "clap applause bravo"), ("🙌", "raised hands praise celebrate"), ("🙏", "pray thanks please support"),
        ("🫶", "heart hands support love"), ("💯", "hundred perfect fire"), ("✨", "sparkles magic shine"),
        ("💡", "idea insightful bulb smart"), ("🤔", "thinking hmm curious"), ("🧐", "monocle curious inspect"),
        ("🤯", "mind blown wow"), ("😱", "scream shock scared"), ("😴", "sleep tired bored"),
        ("🤤", "drool yum want"), ("😈", "devil mischief"), ("💀", "skull dead lol"),
        ("👀", "eyes look curious watching"), ("💪", "strong muscle support flex"), ("🌈", "rainbow pride colour"),
        ("⭐️", "star favourite great"), ("🍿", "popcorn drama watching"), ("☕️", "coffee morning"),
        ("🎶", "music notes song"), ("📸", "camera photo picture"), ("🌸", "blossom flower spring"),
        ("🐐", "goat greatest best"), ("👍", "thumbs up like yes good"), ("👎", "thumbs down dislike no"),
        ("😆", "grin laugh happy"), ("😊", "blush smile happy"), ("😇", "angel innocent"),
        ("🤗", "hug support warm"), ("🤝", "handshake deal agree support"), ("✅", "check done yes correct"),
        ("❗️", "exclamation important"), ("❓", "question curious what"), ("🚀", "rocket launch ship fast"),
        ("🏆", "trophy win champion celebrate"), ("💎", "gem diamond valuable"), ("🧠", "brain smart insightful"),
        ("📈", "chart growth up"), ("🎯", "target bullseye insightful"), ("🫡", "salute respect"),
        ("😬", "grimace awkward yikes"), ("🙃", "upside down silly"), ("😤", "huff determined"),
        ("💔", "broken heart sad"), ("🌟", "glowing star shine"), ("🍀", "clover luck"),
    ]

    static func custom(_ emoji: String) -> PostEmojiReaction {
        if let quick = quick.first(where: { $0.emoji == emoji }) { return quick }
        let reaction: SocialReaction
        switch emoji {
        case "😍", "🥰", "😊", "😇", "💔": reaction = .love
        case "🥳", "🎉", "👏", "🙌", "🏆", "🚀", "🫡": reaction = .celebrate
        case "💡", "🧠", "🎯", "📈", "💎": reaction = .insightful
        case "🤔", "🧐", "👀", "🤯", "😱", "❓", "❗️", "😬": reaction = .curious
        case "🙏", "🫶", "💪", "🤗", "🤝": reaction = .support
        case "💯", "⭐️", "✨", "🌟", "😎", "🐐": reaction = .fire
        case "🤣", "😆", "💀", "🙃": reaction = .laugh
        default: reaction = .like
        }
        return PostEmojiReaction(emoji: emoji, title: emoji, reaction: reaction)
    }
}

/// Remembers which emoji the viewer picked per post (the server stores the semantic reaction).
@MainActor @Observable
final class PostEmojiReactionStore {
    static let shared = PostEmojiReactionStore()
    private(set) var emojis: [String: String] = [:]
    @ObservationIgnored private let key = "post.emojiReactions.v1"

    private init() {
        emojis = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func emoji(for postID: SocialPostID) -> String? { emojis[postID] }

    func set(_ emoji: String?, for postID: SocialPostID) {
        emojis[postID] = emoji
        if emojis.count > 600 {
            emojis = Dictionary(uniqueKeysWithValues: emojis.prefix(400).map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(emojis, forKey: key)
    }
}

private struct ImmersiveViewerItem: Identifiable {
    let attachment: ModulaAttachment
    let gallery: [ModulaAttachment]
    var id: String { attachment.id }
}

// MARK: - Card

/// Media-first Home card: full-bleed media in a 24pt glass card, overlaid header, caption and a
/// vertical Liquid Glass action rail; text posts get an elevated glass card in the same language.
struct ImmersivePostCard: View {
    let post: SocialPost
    var isOwnPost = false
    var onOpenPost: () -> Void
    var onOpenAuthor: () -> Void
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    var onShare: (() -> Void)? = nil
    var onContextAction: ((ModulaContextAction) -> Void)? = nil
    var onOpenMedia: (@MainActor (SocialPostMedia) -> Void)? = nil
    var onOpenModule: (@MainActor (SocialPostModule) -> Void)? = nil
    var videoCoordinator: FeedVideoCoordinator? = nil
    /// Post detail shows comments inline below, so the card drops its comment button and
    /// "Add a comment…" strip there (comment intents focus the inline composer instead).
    var showsCommentAffordances: Bool = true
    /// `.detail` renders the same shell flush and full-width (no card radius, stroke, fill or
    /// shadow) and drops the in-card "…" because the detail nav bar owns the post menu.
    var style: Style = .feed
    enum Style: Sendable { case feed, detail }
    private var isDetail: Bool { style == .detail }

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.trailingInteractionInset) private var trailingInteractionInset
    @Environment(\.openURL) private var openURL
    /// The app's real scheme. Media stages force `.dark` for legibility over photos, but the
    /// post menu must present in the app scheme so it reads like the accessory Options menu.
    @Environment(\.colorScheme) private var appScheme

    @State private var heartBurst = 0
    @State private var page: Int? = 0
    @State private var showsReactions = false
    @State private var hoveredReaction: String?
    @State private var showsReactionGrid = false
    @State private var moreFrame: CGRect = .zero
    @State private var viewer: ImmersiveViewerItem?
    @State private var reactionFrames: [String: CGRect] = [:]
    @State private var heartFrame: CGRect = .zero
    @State private var suppressHeartTap = false
    @State private var captionExpanded = false
    @State private var pinchScale: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var saveBounce = 0
    @State private var railPressed: String?
    @State private var showsTranslation = false
    /// Finger position (card space) while the reaction picker is open — drives dock magnification.
    @State private var fingerPoint: CGPoint?
    @State private var pickerStagger = false
    @State private var barSize: CGSize = .zero
    @State private var bursts: [ReactionBurst] = []

    private var radius: CGFloat { isDetail ? 0 : 24 }
    private var space: String { "immersive.\(post.id)" }
    private var calm: Bool { reduceMotion || ModulaPreferences.extraMotionReduction }

    var body: some View {
        let canonical = ModulaPostMapper.map(post)
        let pages = Self.mediaPages(canonical)
        Group {
            if pages.isEmpty {
                textCard(canonical)
            } else {
                mediaCard(canonical, pages: pages)
            }
        }
        .coordinateSpace(.named(space))
        .overlay { pickerLayer }
        .overlay {
            ZStack {
                ForEach(bursts) { burst in ReactionBurstView(burst: burst) }
            }
            .allowsHitTesting(false)
        }
        .zIndex(showsReactions || !bursts.isEmpty ? 5 : 0)
        .padding(.vertical, 6)
        // Gate post share/save pans while the dock or full emoji grid is up.
        .postReactionPickerPresented(showsReactions || showsReactionGrid)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(post.voiceOverSummary)
        .accessibilityIdentifier("home.post.\(post.id)")
        .accessibilityAction(named: "React", onLike)
        .accessibilityAction(named: "Choose reaction") { showsReactions = true }
        .accessibilityAction(named: "Comment", onComment)
        .accessibilityAction(named: "Save", onSave)
        .accessibilityAction(named: "Share") { share() }
        .accessibilityAction(named: "Open Author", onOpenAuthor)
        .accessibilityAction(named: "More actions") { }
        .accessibilityAction(named: "Who reacted") { openReactors() }
        .sheet(isPresented: $showsReactionGrid) {
            ReactionGridSheet { emoji in
                showsReactionGrid = false
                apply(.custom(emoji))
            }
            .presentationDetents([.medium])
            .presentationBackground(.thinMaterial)
        }
        .fullScreenCover(item: $viewer) { item in
            AttachmentViewerRouter(attachment: item.attachment, imageGallery: item.gallery) { viewer = nil }
                .environment(app)
        }
        .environment(\.modulaLinkSource, linkSource)
        .environment(\.openURL, OpenURLAction { url in
            if let route = PostTextLinks.route(for: url) {
                app.navigation.push(route)
                return .handled
            }
            return ModulaLinkRouter.handle(url, source: linkSource)
        })
    }

    private var linkSource: ModulaBrowserSource {
        ModulaBrowserSource(post: post, onLike: onLike, onComment: onComment, onRepost: onRepost, onSave: onSave, onShare: onShare, originFrame: .zero)
    }

    // MARK: Media pages

    static func mediaPages(_ post: ModulaPost) -> [ModulaAttachment] {
        guard post.content.first?.isMediaFirst == true else { return [] }
        var pages: [ModulaAttachment] = []
        for block in post.content {
            switch block {
            case .image(let value): pages.append(value.attachment)
            case .video(let value): pages.append(value.attachment)
            case .imageGallery(let value): pages.append(contentsOf: value.attachments)
            default: break
            }
        }
        return Array(pages.prefix(10))
    }

    /// Native aspect, clamped so photos fill the card: 4:5 tallest, 1.2:1 widest (rail always fits).
    private func stageRatio(_ attachment: ModulaAttachment?) -> CGFloat {
        guard let size = attachment?.dimensions, size.width > 0, size.height > 0 else { return 0.86 }
        return min(max(size.width / size.height, 0.8), 1.2)
    }

    private var font: Font.Design { app.appearance.fontDesign }

    // MARK: Media card

    @ViewBuilder
    private func mediaCard(_ canonical: ModulaPost, pages: [ModulaAttachment]) -> some View {
        let current = min(max(page ?? 0, 0), pages.count - 1)
        let isVideo = pages[current].kind == .video
        VStack(alignment: .leading, spacing: 10) {
            mediaStage(canonical, pages: pages, current: current, isVideo: isVideo)
            extraBlocks(canonical)
            translationBlock
        }
    }

    @ViewBuilder
    private var translationBlock: some View {
        if showsTranslation, let text = post.text, !text.isEmpty {
            PostTranslationControl(text: text, autoStart: true)
                .padding(.horizontal, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func mediaStage(_ canonical: ModulaPost, pages: [ModulaAttachment], current: Int, isVideo: Bool) -> some View {
        let expandable: ModulaAttachment? = isVideo ? pages[current] : nil
        // Rail is a ZStack sibling, not an overlay on the preview `contextMenu`.
        // Long-press on Like must open the reaction picker, never the post preview.
        return ZStack(alignment: .bottomTrailing) {
            mediaStageBase(pages: pages)
                .environment(\.colorScheme, .dark)
                .overlay(alignment: .top) { mediaHeader(canonical, pages: pages, current: current) }
                .overlay(alignment: .bottomLeading) { captionBlock(canonical, pages: pages, current: current, isVideo: isVideo) }
                .postMenuLongPress(enabled: !showsReactions && !suppressHeartTap) { menuRequest(anchor: $0) }
                .environment(\.colorScheme, appScheme)
                .overlay(alignment: .bottom) {
                    if showsCommentAffordances { mediaCommentStrip(isVideo: isVideo) }
                }
            rail(expandable: expandable, gallery: pages)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay { if !isDetail { mediaCardStroke } }
        .shadow(color: glow.opacity(isDetail ? 0 : 0.28), radius: 18, y: 8)
        .shadow(color: .black.opacity(isDetail ? 0 : 0.12), radius: 4, y: 2)
        .environment(\.colorScheme, .dark)
    }

    private func mediaStageBase(pages: [ModulaAttachment]) -> some View {
        Color.black
            .aspectRatio(stageRatio(pages.first), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { mediaPager(pages) }
            .overlay(alignment: .top) { mediaTopFade }
            .overlay(alignment: .bottom) { mediaBottomFade }
            .overlay { DoubleTapHeartBurst(trigger: heartBurst) }
    }

    private var mediaTopFade: some View {
        LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 120)
            .allowsHitTesting(false)
    }

    private var mediaBottomFade: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            .frame(height: 210)
            .allowsHitTesting(false)
    }

    private var mediaCardStroke: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8
            )
            .allowsHitTesting(false)
    }

    private var glow: Color {
        if let hex = post.glowColour, let color = Color(immersiveHex: hex) { return color }
        return app.appearance.accent.color
    }

    @ViewBuilder
    private func mediaPager(_ pages: [ModulaAttachment]) -> some View {
        if pages.count == 1 {
            mediaPage(pages[0], gallery: pages)
        } else {
            // Horizontal paging owns only horizontal drags; the feed keeps vertical scrolling.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, attachment in
                        mediaPage(attachment, gallery: pages)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(index)
                            .accessibilityLabel("\(attachment.accessibilityLabel), \(index + 1) of \(pages.count)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)
            .onChange(of: page) { _, _ in HapticEngine.shared.play(.selection) }
        }
    }

    @ViewBuilder
    private func mediaPage(_ attachment: ModulaAttachment, gallery: [ModulaAttachment]) -> some View {
        Group {
            if attachment.resolvedRemoteState != .ready {
                ZStack {
                    Color(white: 0.12)
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Processing").font(.system(.caption, design: font, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
            } else if attachment.kind == .video {
                ModulaVideoSurface(
                    attachment: attachment,
                    coordinator: videoCoordinator,
                    onExpand: { viewer = ImmersiveViewerItem(attachment: attachment, gallery: gallery) },
                    height: nil,
                    cornerRadius: 0,
                    immersive: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SmartCropImage(attachment: attachment)
                    .scaleEffect(pinchScale)
                    .animation(calm ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.82), value: pinchScale)
                    .contentShape(Rectangle())
                    .onTapGesture { if pinchScale <= 1.05 { openMedia(attachment) } }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard !calm else { return }
                                pinchScale = min(max(pinchBase * value, 1), 3.2)
                            }
                            .onEnded { _ in
                                pinchBase = 1
                                withAnimation(calm ? nil : .spring(response: 0.32, dampingFraction: 0.78)) { pinchScale = 1 }
                                HapticEngine.shared.play(.selection)
                            }
                    )
                    .accessibilityLabel(attachment.accessibilityLabel)
                    .accessibilityHint("Opens the post. Pinch to zoom.")
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard ModulaPreferences.doubleTapToLike else { return }
            if !post.liked && post.viewerReaction == nil { onLike() }
            HapticEngine.shared.play(.lightImpact)
            heartBurst += 1
        })
    }

    private func openMedia(_ attachment: ModulaAttachment) {
        if let media = post.media.first(where: { $0.id == attachment.id }) {
            onOpenMedia?(media)
        } else {
            onOpenPost()
        }
    }

    // MARK: Header

    private func mediaHeader(_ canonical: ModulaPost, pages: [ModulaAttachment], current: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            authorButton(canonical, onMedia: true)
            Spacer(minLength: 6)
            if pages.count > 1 {
                Text("\(current + 1)/\(pages.count)")
                    .font(.system(.caption2, design: font, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .accessibilityLabel("Item \(current + 1) of \(pages.count)")
            }
            if !isDetail { moreButton(onMedia: true) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func authorButton(_ canonical: ModulaPost, onMedia: Bool) -> some View {
        Button(action: onOpenAuthor) {
            HStack(spacing: 10) {
                RingedAvatar(author: post.author, size: onMedia ? 38 : 34)
                authorMeta(canonical, onMedia: onMedia)
            }
            .foregroundStyle(onMedia ? Color.white : Color.primary)
            .shadow(color: onMedia ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(post.author.map { "\($0.displayName), @\($0.handle)" } ?? "Author")
        .accessibilityHint("Opens profile")
        .accessibilityIdentifier(post.author.map { "home.author.\($0.id)" } ?? "home.author.unknown")
    }

    @ViewBuilder
    private func authorMeta(_ canonical: ModulaPost, onMedia: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            authorNameRow(onMedia: onMedia)
            authorSubtitle(canonical, onMedia: onMedia)
        }
    }

    private func authorNameRow(onMedia: Bool) -> some View {
        HStack(spacing: 4) {
            Text(post.author?.displayName ?? "Modula")
                .font(.system(.subheadline, design: font, weight: .semibold))
                .lineLimit(1)
            if post.author?.isVerified == true {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.blue)
                    .accessibilityLabel("Verified")
            }
            Text("· \(ActivityRelativeTime.string(from: post.createdAt))")
                .font(.system(.caption, design: font))
                .foregroundStyle(onMedia ? Color.white.opacity(0.75) : Color.secondary.opacity(0.7))
                .lineLimit(1)
                .layoutPriority(-1)
        }
    }

    @ViewBuilder
    private func authorSubtitle(_ canonical: ModulaPost, onMedia: Bool) -> some View {
        if let location = canonical.context.location {
            Label(location, systemImage: "mappin.and.ellipse")
                .font(.system(.caption2, design: font, weight: .medium))
                .foregroundStyle(onMedia ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
                .labelStyle(TightLabelStyle())
        } else if let handle = post.author?.handle, !onMedia {
            Text("@\(handle)")
                .font(.system(.caption2, design: font))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineLimit(1)
        }
    }

    /// "…" opens the native Options-style menu. The glass disc is a sibling *behind* a plain
    /// Menu label (not the label itself), and the Menu gets the app's colour scheme: the menu
    /// then presents above the Tools accessory / tab bar instead of morphing out of a glass
    /// element inside the clipped, forced-dark media card.
    private func moreButton(onMedia: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: 36, height: 36)
                .modulaGlass(in: Circle(), interactive: false, specular: true)
                .accessibilityHidden(true)
            PostMenuButton(makeRequest: { menuRequest(anchor: $0) }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(onMedia ? Color.white : Color.primary)
                    .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
                    .contentShape(Circle())
            }
            .environment(\.colorScheme, appScheme)
        }
        .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { moreFrame = $0 }
        .accessibilityIdentifier("post.more.\(post.id)")
    }

    private func menuRequest(anchor: CGRect) -> PostMenuRequest {
        let translatable = post.text.flatMap { PostTranslationPolicy.decision(for: $0) } != nil
        return PostMenuRequest(
            post: post,
            isOwn: isOwnPost,
            anchor: anchor,
            hooks: PostMenuHooks(
                onSave: {
                    saveBounce += 1
                    onSave()
                },
                onShare: share,
                onTranslate: translatable && !showsTranslation ? {
                    withAnimation(calm ? nil : .snappy) { showsTranslation = true }
                } : nil,
                onContextAction: onContextAction
            )
        )
    }

    // MARK: Caption

    private func captionBlock(_ canonical: ModulaPost, pages: [ModulaAttachment], current: Int, isVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            reactionSummaryChip(onMedia: true)
            if let text = post.text, !text.isEmpty {
                Text(PostTextLinks.attributed(text))
                    .font(.system(.subheadline, design: font))
                    .foregroundStyle(.white)
                    .tint(app.appearance.accent.color.mix(with: .white, by: 0.55))
                    .lineLimit(captionExpanded ? 8 : 2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if text.count < 90 {
                            onOpenPost()
                        } else if captionExpanded {
                            withAnimation(calm ? nil : .snappy) { captionExpanded = false }
                        } else {
                            withAnimation(calm ? nil : .snappy) { captionExpanded = true }
                        }
                    }
                    .accessibilityLabel(text)
                    .accessibilityHint("Opens the full post")
                    .accessibilityIdentifier("post.open.\(post.id)")
            }
            let chips: [(String, String)] = [
                canonical.context.audioTitle.map { ("music.note", $0) },
                canonical.context.location.map { ("mappin.and.ellipse", $0) },
                canonical.context.module.map { ("shippingbox.fill", $0.name ?? $0.id) },
            ].compactMap { $0 }
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                        Button {
                            if chip.0 == "shippingbox.fill", let module = canonical.context.module {
                                onOpenModule?(module)
                            } else if chip.0 == "mappin.and.ellipse" {
                                app.navigation.push(.search(.section(.posts, chip.1)))
                            }
                        } label: {
                            Label(chip.1, systemImage: chip.0)
                                .font(.system(.caption2, design: font, weight: .semibold))
                                .lineLimit(1)
                                .labelStyle(TightLabelStyle())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .modulaGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if pages.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Button {
                            withAnimation(calm ? nil : .snappy) { page = index }
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Capsule()
                                .fill(.white.opacity(index == current ? 0.95 : 0.4))
                                .frame(width: index == current ? 18 : 7, height: 7)
                                .frame(minWidth: 18, minHeight: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to item \(index + 1)")
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(calm ? nil : .snappy, value: current)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 70)
        // Leave room for the slim comment strip overlay.
        .padding(.bottom, isVideo ? 64 : 48)
    }

    // MARK: Rail

    private var reacted: Bool { post.liked || post.viewerReaction != nil }
    private var reactionCount: Int { max(post.reactionCount, post.likeCount) }

    private func rail(expandable: ModulaAttachment?, gallery: [ModulaAttachment]) -> some View {
        VStack(spacing: 0) {
            heartControl(vertical: true)
            if showsCommentAffordances {
                railButton("Comment", symbol: "bubble.right.fill", count: post.replyCount, active: false) {
                    HapticEngine.shared.play(.contextOpen)
                    onComment()
                }
                .accessibilityIdentifier("home.action.comment.\(post.id)")
            }
            railButton(post.saved ? "Unsave" : "Save", symbol: post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, tint: .yellow) {
                saveBounce += 1
                HapticEngine.shared.play(.confirmation)
                onSave()
            }
                .accessibilityIdentifier("home.action.save.\(post.id)")
            railButton("Share", symbol: "paperplane.fill", count: post.repostCount, active: false) {
                HapticEngine.shared.play(.contextOpen)
                share()
            }
            if let expandable {
                railButton("Open full-screen player", symbol: "arrow.up.left.and.arrow.down.right", count: 0, active: false) {
                    viewer = ImmersiveViewerItem(attachment: expandable, gallery: gallery)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .modulaGlass(in: Capsule(), interactive: false, specular: true)
        .overlay {
            if !calm {
                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: [glow.opacity(0.55), .white.opacity(0.15), glow.opacity(0.35), .clear, glow.opacity(0.55)], center: .center),
                        lineWidth: 1
                    )
                    .opacity(0.85)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: glow.opacity(calm ? 0 : 0.35), radius: 10, y: 0)
        // Keep clear of the Edge Loop "For You" tab.
        .padding(.trailing, max(10, trailingInteractionInset * 0.35 + 6))
        .padding(.bottom, 36)
        // Swipe down on the rail: the menu grows out of where the finger is; keep sliding to pick.

        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post actions")
        .accessibilityIdentifier("post.action.rail.\(post.id)")
    }

    private func railButton(_ title: String, symbol: String, count: Int, active: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(active ? (tint ?? app.appearance.accent.color) : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: symbol.contains("bookmark") ? saveBounce : 0)
                    .scaleEffect(railPressed == title ? 0.82 : 1)
                if let text = ModulaCountFormat.compact(count) {
                    Text(text)
                        .font(.system(size: 10, weight: .semibold, design: font).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .animation(calm ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: railPressed == title)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if railPressed != title { railPressed = title } }
                .onEnded { _ in railPressed = nil }
        )
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }

    /// Heart: tap toggles, long-press opens the picker; keep holding and slide to preview, release to apply.
    private func heartControl(vertical: Bool) -> some View {
        let emoji = reacted ? PostEmojiReactionStore.shared.emoji(for: post.id) : nil
        let symbol = post.viewerReaction.flatMap { $0 == .like ? nil : $0.systemImage } ?? (reacted ? "heart.fill" : "heart")
        let likeName = reacted ? (emoji.map { "Reacted \($0)" } ?? post.viewerReaction?.accessibilityName ?? "Liked") : "Like"
        return heartGlyphs(vertical: vertical, emoji: emoji, symbol: symbol)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { heartFrame = $0 }
            .onTapGesture(perform: tapHeart)
            .exclusiveReactionLongPress(perform: openReactionPicker)
            .simultaneousGesture(reactionScrub)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(likeName)
            .accessibilityValue(reactionCount > 0 ? "\(reactionCount)" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onLike() }
            .accessibilityHint("Tap to like. Touch and hold for more reactions.")
            .accessibilityIdentifier("home.action.like.\(post.id)")
    }

    @ViewBuilder
    private func heartGlyphs(vertical: Bool, emoji: String?, symbol: String) -> some View {
        if vertical {
            VStack(spacing: 1) { heartGlyph(emoji: emoji, symbol: symbol, size: 21, onMedia: true); heartCount(onMedia: true) }
                .frame(width: 44, height: 46)
        } else {
            HStack(spacing: 5) { heartGlyph(emoji: emoji, symbol: symbol, size: 19, onMedia: false); heartCount(onMedia: false) }
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 4)
        }
    }

    private func tapHeart() {
        guard !suppressHeartTap else { return }
        if showsReactions { closePicker(); return }
        onLike()
        if !reacted {
            heartBurst += 1
            HapticEngine.shared.play(.confirmation)
        } else {
            HapticEngine.shared.play(.selection)
        }
    }

    private func openReactionPicker() {
        guard !showsReactions else { return }
        suppressHeartTap = true
        HapticEngine.shared.play(.contextOpen)
        withAnimation(calm ? nil : .spring(response: 0.3, dampingFraction: 0.72)) { showsReactions = true }
    }

    private var reactionScrub: some Gesture {
        LongPressGesture(minimumDuration: PostGestureThresholds.reactionLongPressDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if !showsReactions { openReactionPicker() }
                    if let drag { hover(at: drag.location) }
                default:
                    break
                }
            }
            .onEnded { value in
                var velocity = CGSize.zero
                if case .second(true, let drag?) = value { velocity = drag.velocity }
                let flung = velocity.height < -650
                let target = hoveredReaction ?? (flung ? nearestReaction() : nil)
                if let target {
                    if target == "+" { openGrid() } else { apply(.custom(target), fling: flung) }
                }
                hoveredReaction = nil
                fingerPoint = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    suppressHeartTap = false
                }
            }
    }

    @ViewBuilder
    private func heartGlyph(emoji: String?, symbol: String, size: CGFloat, onMedia: Bool) -> some View {
        if let emoji {
            Text(emoji).font(.system(size: size))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(reacted ? Color(red: 1, green: 0.27, blue: 0.4) : (onMedia ? Color.white : Color.secondary))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reacted)
        }
    }

    @ViewBuilder
    private func heartCount(onMedia: Bool) -> some View {
        if let text = ModulaCountFormat.compact(reactionCount) {
            Text(text)
                .font(.system(size: onMedia ? 10 : 12, weight: .semibold, design: font).monospacedDigit())
                .foregroundStyle(onMedia ? .white.opacity(0.9) : .secondary)
        }
    }

    /// Band around the bar where the finger magnifies emoji; outside it, releasing cancels.
    private var reactionBand: CGRect? {
        let frames = reactionFrames.values
        guard let first = frames.first else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return union.insetBy(dx: -24, dy: -60)
    }

    private func nearestReaction(to point: CGPoint? = nil) -> String? {
        guard let x = (point ?? fingerPoint)?.x else { return nil }
        return reactionFrames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    private func hover(at point: CGPoint) {
        fingerPoint = point
        let hit = (reactionBand?.contains(point) ?? false) ? nearestReaction(to: point) : nil
        if hit != hoveredReaction {
            hoveredReaction = hit
            if hit != nil { HapticEngine.shared.play(.selection) }
        }
    }

    private func apply(_ option: PostEmojiReaction, fling: Bool = false) {
        HapticEngine.shared.play(fling ? .success : .confirmation)
        let origin = reactionFrames[option.emoji].map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: heartFrame.midX, y: heartFrame.midY)
        PostEmojiReactionStore.shared.set(option.emoji == PostEmojiReaction.heart.emoji ? nil : option.emoji, for: post.id)
        closePicker()
        heartBurst += option.emoji == PostEmojiReaction.heart.emoji && !fling ? 1 : 0
        if !calm {
            let burst = ReactionBurst(emoji: option.emoji, origin: origin, fling: fling)
            bursts.append(burst)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                bursts.removeAll { $0.id == burst.id }
            }
        }
        Task { await app.postActions.setReaction(post, reaction: option.reaction) }
    }

    // MARK: Reaction summary

    /// Top three emoji on this post: server breakdown first, then the viewer's own pick.
    private var topReactionEmojis: [String] {
        var list: [String] = []
        if let summary = post.engagement.reactionSummary {
            for (kind, count) in summary.breakdown.sorted(by: { $0.value > $1.value }) where count > 0 {
                list.append(kind.emoji)
            }
        }
        if reacted {
            let mine = PostEmojiReactionStore.shared.emoji(for: post.id) ?? post.viewerReaction?.emoji ?? "❤️"
            if !list.contains(mine) { list.insert(mine, at: 0) }
        }
        if list.isEmpty && reactionCount > 0 { list = ["❤️"] }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    @ViewBuilder
    private func reactionSummaryChip(onMedia: Bool) -> some View {
        let emojis = topReactionEmojis
        if reactionCount > 0, !emojis.isEmpty {
            Button(action: openReactors) {
                HStack(spacing: 5) {
                    HStack(spacing: -5) {
                        ForEach(Array(emojis.enumerated()), id: \.element) { index, emoji in
                            Text(emoji)
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(onMedia ? Color.black.opacity(0.45) : Color(uiColor: .secondarySystemBackground)))
                                .overlay(Circle().strokeBorder(onMedia ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 0.5))
                                .zIndex(Double(3 - index))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text(ModulaCountFormat.compact(reactionCount) ?? "\(reactionCount)")
                        .font(.system(size: 11, weight: .semibold, design: font).monospacedDigit())
                        .foregroundStyle(onMedia ? Color.white.opacity(0.92) : Color.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.leading, 4)
                .padding(.trailing, 9)
                .padding(.vertical, 3)
                .modulaGlass(in: Capsule(), interactive: true)
                .animation(calm ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: emojis)
            }
            .buttonStyle(.modulaPress)
            .accessibilityLabel("\(reactionCount) reactions: \(emojis.joined(separator: " "))")
            .accessibilityHint("Shows who reacted")
            .accessibilityIdentifier("post.reaction.summary.\(post.id)")
        }
    }

    private func openReactors() {
        if app.postActions.capabilities.reactionsList {
            app.navigation.push(.post(post.id, .reactions))
            HapticEngine.shared.play(.navigation)
        } else {
            app.navigation.flash("Who reacted is coming soon", symbol: "face.smiling")
        }
    }

    private func openGrid() {
        closePicker()
        HapticEngine.shared.play(.contextOpen)
        showsReactionGrid = true
    }

    private func closePicker() {
        withAnimation(calm ? nil : .snappy(duration: 0.2)) { showsReactions = false }
        hoveredReaction = nil
        fingerPoint = nil
    }

    // MARK: Reaction picker layer

    @ViewBuilder
    private var pickerLayer: some View {
        if showsReactions {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { closePicker() }
                    let barCenter = CGPoint(x: geo.size.width / 2, y: max(34, heartFrame.minY - 36))
                    reactionBar
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { barSize = $0 }
                        .position(barCenter)
                        // Grows out of the heart.
                        .transition(calm ? .opacity : .scale(scale: 0.12, anchor: heartAnchor(barCenter: barCenter)).combined(with: .opacity))
                }
            }
            .transition(.opacity)
        }
    }

    private func heartAnchor(barCenter: CGPoint) -> UnitPoint {
        let size = barSize == .zero ? CGSize(width: 330, height: 52) : barSize
        return UnitPoint(
            x: (heartFrame.midX - (barCenter.x - size.width / 2)) / size.width,
            y: (heartFrame.midY - (barCenter.y - size.height / 2)) / size.height
        )
    }

    private var reactionBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(PostEmojiReaction.quick.enumerated()), id: \.element.id) { index, option in
                reactionItem(id: option.emoji, index: index, title: option.title) {
                    Text(option.emoji).font(.system(size: 27))
                }
                .accessibilityLabel(option.title)
                .onTapGesture { apply(option) }
            }
            reactionItem(id: "+", index: PostEmojiReaction.quick.count, title: "More") {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("More reactions")
            .onTapGesture { openGrid() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .modulaGlass(in: Capsule(), specular: true)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .onAppear { withAnimation { pickerStagger = true } }
        .onDisappear { pickerStagger = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post.reaction.picker")
    }

    /// Dock-style magnification: emoji near the finger swell, the one under it lifts and shows its name.
    private func magnification(for id: String) -> CGFloat {
        guard !calm else { return hoveredReaction == id ? 1.3 : 1 }
        guard let finger = fingerPoint, let frame = reactionFrames[id], reactionBand?.contains(finger) == true else { return 1 }
        let distance = abs(finger.x - frame.midX)
        return 1 + 0.75 * max(0, 1 - distance / 70)
    }

    private func reactionItem<Content: View>(id: String, index: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        let hovered = hoveredReaction == id
        let scale = magnification(for: id)
        // Fixed slot is measured (not the scaled glyph) so hit-testing stays stable while magnifying.
        return Color.clear
            .frame(width: 42, height: 42)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { reactionFrames[id] = $0 }
            .overlay {
                content()
                    .scaleEffect(scale, anchor: .bottom)
                    .offset(y: hovered && !calm ? -12 : 0)
                    .scaleEffect(pickerStagger || calm ? 1 : 0.3)
                    .opacity(pickerStagger || calm ? 1 : 0)
                    .animation(calm ? nil : .spring(response: 0.34, dampingFraction: 0.62).delay(Double(index) * 0.03), value: pickerStagger)
                    .animation(calm ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.62), value: scale)
            }
            .overlay(alignment: .top) {
                if hovered {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .modulaGlass(in: Capsule(), interactive: false)
                        .offset(y: calm ? -30 : -62)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(calm ? nil : .snappy(duration: 0.18), value: hovered)
            .zIndex(hovered ? 2 : 0)
            .contentShape(Rectangle())
    }

    private func perform(_ action: ModulaContextAction) {
        if let onContextAction { onContextAction(action); return }
        switch action.id {
        case "share": share()
        case "copy-link": UIPasteboard.general.string = post.shareURL.absoluteString
        case "save": onSave()
        case "save-collection": app.navigation.presented = .collectionPicker(postID: post.id)
        default: break
        }
    }

    private func share() {
        if let onShare { onShare() } else { onRepost() }
    }

    // MARK: Comment strip (blended — no nested glass pill)

    /// Slim affordance on media cards, drawn over the bottom gradient (left of the rail).
    private func mediaCommentStrip(isVideo: Bool) -> some View {
        Button(action: onComment) {
            HStack(spacing: 8) {
                if let profile = app.profile.ownProfile {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 22)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 22, height: 22)
                }
                Text(post.replyCount > 0 ? "View comments" : "Add a comment…")
                    .font(.system(.caption, design: font, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.trailing, 62 + max(0, trailingInteractionInset * 0.25))
        .padding(.bottom, isVideo ? 28 : 10)
        .gesture(
            DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
                .onEnded { value in
                    if value.translation.height < -PostGestureThresholds.commentSheetThreshold {
                        HapticEngine.shared.play(.contextOpen)
                        onComment()
                    }
                }
        )
        .accessibilityLabel("Add a comment")
        .accessibilityHint("Opens comments. Swipe up to open.")
        .accessibilityIdentifier("post.comment.prompt.\(post.id)")
    }

    /// Slim strip for text/link/audio/doc cards — same capsule as the media strip,
    /// tinted for the card surface instead of the media gradient.
    private var commentBar: some View {
        Button(action: onComment) {
            HStack(spacing: 8) {
                if let profile = app.profile.ownProfile {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 22)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 22)
                }
                Text("Add a comment…")
                    .font(.system(.caption, design: font, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
                .onEnded { value in
                    if value.translation.height < -PostGestureThresholds.commentSheetThreshold {
                        HapticEngine.shared.play(.contextOpen)
                        onComment()
                    }
                }
        )
        .accessibilityLabel("Add a comment")
        .accessibilityHint("Opens comments. Swipe up to open.")
        .accessibilityIdentifier("post.comment.prompt.\(post.id)")
    }

    @ViewBuilder
    private func extraBlocks(_ canonical: ModulaPost) -> some View {
        ForEach(canonical.content.filter { !$0.isMediaFirst }) { block in
            if case .link(let value) = block {
                ModulaLinkPreview(content: value, onOpen: { openURL($0) }, embedded: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Text card

    @ViewBuilder
    private func textCard(_ canonical: ModulaPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    authorButton(canonical, onMedia: false)
                    Spacer(minLength: 6)
                    if !isDetail { moreButton(onMedia: false) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if post.text?.isEmpty == false {
                    PostBody(post: post)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onOpenPost)
                        .accessibilityAction(named: "Open Post", onOpenPost)
                        .accessibilityIdentifier("post.open.\(post.id)")
                }
                translationBlock
                    .padding(.horizontal, 4)
                    .padding(.bottom, showsTranslation ? 8 : 0)

                Group {
                    if case .audio(let value)? = canonical.content.first {
                        ImmersiveMusicPlayer(attachment: value.attachment, onExpand: {
                            viewer = ImmersiveViewerItem(attachment: value.attachment, gallery: [])
                        }, embedded: true)
                    } else if !canonical.content.isEmpty || canonical.context.module != nil {
                        PostCanonicalContent(
                            source: post,
                            videoCoordinator: videoCoordinator,
                            onOpenAttachment: { attachment in
                                if let media = post.media.first(where: { $0.id == attachment.id }) { onOpenMedia?(media) }
                            },
                            onOpenModule: onOpenModule,
                            embeddedAttachments: true
                        )
                    }
                }
                .padding(.horizontal, 0)
                .padding(.bottom, 6)
            }
            .postMenuLongPress(enabled: !showsReactions && !suppressHeartTap) { menuRequest(anchor: $0) }

            // Soft fade into the action band (one system — horizontal only).
            textActions
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 2)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Color.primary.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .allowsHitTesting(false)
                }

            if showsCommentAffordances {
                commentBar
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .background {
            if !isDetail {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
            }
        }
        .background {
            if !isDetail {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [glow.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay {
            if !isDetail {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), Color.primary.opacity(0.05), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
            }
        }
        .shadow(color: glow.opacity(isDetail ? 0 : 0.16), radius: 16, y: 6)
        .shadow(color: .black.opacity(isDetail ? 0 : 0.06), radius: 3, y: 1)
    }

    private var textActions: some View {
        HStack(spacing: isDetail ? 10 : 2) {
            heartControl(vertical: false)
                .foregroundStyle(.secondary)
            reactionSummaryChip(onMedia: false)
            if showsCommentAffordances {
                pillButton("Comment", symbol: "bubble.right", count: post.replyCount, active: false, action: onComment)
                    .accessibilityIdentifier("home.action.comment.\(post.id)")
            }
            pillButton("Repost", symbol: "arrow.2.squarepath", count: post.repostCount, active: post.reposted, action: onRepost)
                .accessibilityIdentifier("home.action.repost.\(post.id)")
            Spacer(minLength: 0)
            pillButton(post.saved ? "Unsave" : "Save", symbol: post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, action: onSave)
                .accessibilityIdentifier("home.action.save.\(post.id)")
            pillButton("Share", symbol: "paperplane", count: 0, active: false, action: share)
        }
        .frame(minHeight: 40)
    }

    private func pillButton(_ title: String, symbol: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: active)
                if let text = ModulaCountFormat.compact(count) {
                    Text(text).font(.system(size: 12, weight: .semibold, design: font).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(active ? app.appearance.accent.color : .secondary)
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .scaleEffect(railPressed == title ? 0.9 : 1)
            .animation(calm ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: railPressed == title)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in railPressed = title }
                .onEnded { _ in railPressed = nil }
        )
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }
}

// MARK: - Pieces

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// Avatar with a gradient story-style ring.
struct RingedAvatar: View {
    let author: SocialAuthor?
    var size: CGFloat = 38
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let accent = app.appearance.accent.color
        ModulaAvatar(initials: author?.initials ?? "M", url: author?.avatarURL, size: size - 6, name: author?.displayName)
            .padding(3)
            .overlay {
                Circle().strokeBorder(
                    AngularGradient(colors: [accent, .pink, .orange, .yellow, .purple, accent], center: .center),
                    lineWidth: 2
                )
            }
            .frame(width: size, height: size)
    }
}

/// Aspect-fill photo with a "smart" crop: portrait frames keep the upper-middle (where faces are).
struct SmartCropImage: View {
    let attachment: ModulaAttachment
    @State private var retryID = 0

    var body: some View {
        GeometryReader { geo in
            ModulaRemoteImage(
                url: attachment.bestPreviewURL ?? attachment.playableURL,
                cacheKey: "attachment:\(attachment.id):feed-image",
                maximumPixelSize: 2_000,
                retryID: retryID
            ) { phase in
                switch phase {
                case .success(let image):
                    cropped(image, in: geo.size)
                case .failure:
                    ZStack {
                        Color(white: 0.14)
                        VStack(spacing: 8) {
                            Label("Couldn’t load photo", systemImage: "photo.badge.exclamationmark")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            Button("Retry", systemImage: "arrow.clockwise") { retryID += 1 }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                case .loading:
                    Color(white: 0.14).modulaShimmer()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        .accessibilityIdentifier("post.attachment.\(attachment.id)")
    }

    private func cropped(_ image: UIImage, in box: CGSize) -> some View {
        let size = image.size
        let scale = max(box.width / max(size.width, 1), box.height / max(size.height, 1))
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        // Horizontal crops stay centred; vertical crops favour the upper third.
        let x = (box.width - drawn.width) / 2
        let y = (box.height - drawn.height) * 0.38
        return Image(uiImage: image)
            .resizable()
            .frame(width: drawn.width, height: drawn.height)
            .offset(x: x, y: y)
            .frame(width: box.width, height: box.height, alignment: .topLeading)
    }
}

/// Glass context menu revealed by swiping down on the action rail (or the "…" button).
struct ImmersivePostContextPanel: View {
    let post: SocialPost
    var isOwnPost: Bool
    var capabilities: PostBackendCapabilities
    var onSelect: (ModulaContextAction) -> Void
    var onClose: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let actions = PostContextActions.immersivePanel(isOwn: isOwnPost, saved: post.saved, capabilities: capabilities)
        let author = isOwnPost ? [] : PostContextActions.authorActions(capabilities: capabilities)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Post")
                    .font(.system(.footnote, design: app.appearance.fontDesign, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.leading, 14)
            ForEach(actions) { action in
                row(action)
            }
            if let handle = post.author?.handle, !author.isEmpty {
                Divider().padding(.vertical, 4)
                Text("@\(handle)")
                    .font(.system(.footnote, design: app.appearance.fontDesign, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(author) { action in
                        Button { onSelect(action) } label: {
                            Label(action.title, systemImage: action.systemImage ?? "person")
                                .font(.system(.caption, design: app.appearance.fontDesign, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(action.role == .destructive ? Color.red : Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.resolvedAccessibilityLabel)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 262)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, specular: true)
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post actions")
    }

    private func row(_ action: ModulaContextAction) -> some View {
        Button { onSelect(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage ?? "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(action.title)
                    .font(.system(.subheadline, design: app.appearance.fontDesign, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(action.role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.resolvedAccessibilityLabel)
    }
}

/// "+" grid: every emoji maps onto one of the server's 8 reaction types. Searchable by name.
private struct ReactionGridSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [(String, String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return PostEmojiReaction.catalog }
        return PostEmojiReaction.catalog.filter { $0.0 == q || $0.1.contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ModulaGlassSearchField(prompt: "Search reactions", text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ScrollView {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
                            ForEach(results, id: \.0) { item in
                                Button {
                                    HapticEngine.shared.play(.reactionSelect)
                                    onPick(item.0)
                                } label: {
                                    Text(item.0)
                                        .font(.system(size: 32))
                                        .frame(width: 52, height: 52)
                                }
                                .buttonStyle(EmojiPressStyle())
                                .accessibilityLabel(item.1.split(separator: " ").first.map(String.init) ?? item.0)
                            }
                        }
                        .padding(16)
                        .animation(.snappy, value: query)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

/// One release / fling of an emoji reaction: particles burst from the picked emoji.
struct ReactionBurst: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let origin: CGPoint
    var fling = false
}

private struct ReactionBurstView: View {
    let burst: ReactionBurst
    @State private var go = false

    var body: some View {
        ZStack {
            if burst.fling {
                Text(burst.emoji)
                    .font(.system(size: 40))
                    .scaleEffect(go ? 1.9 : 1)
                    .rotationEffect(.degrees(go ? -16 : 0))
                    .offset(y: go ? -230 : 0)
                    .opacity(go ? 0 : 1)
            }
            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) / 12 * .pi * 2 + 0.3
                let radius: CGFloat = go ? CGFloat(52 + (index % 3) * 16) : 4
                Group {
                    if index.isMultiple(of: 2) {
                        Text(burst.emoji).font(.system(size: 13 + CGFloat(index % 3) * 4))
                    } else {
                        Circle()
                            .fill(index % 3 == 0 ? Color.yellow : Color(red: 1, green: 0.42, blue: 0.55))
                            .frame(width: 5, height: 5)
                    }
                }
                .offset(x: cos(angle) * radius, y: sin(angle) * radius - (go ? 18 : 0))
                .scaleEffect(go ? 0.55 : 1)
                .opacity(go ? 0 : 1)
            }
        }
        .position(burst.origin)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: burst.fling ? 0.75 : 0.62)) { go = true } }
    }
}

extension ReactionKind {
    var emoji: String {
        switch self {
        case .like: "❤️"
        case .love: "😍"
        case .laugh: "😂"
        case .wow: "😮"
        case .support: "🙏"
        case .sad: "😢"
        case .angry: "😡"
        }
    }
}

extension SocialReaction {
    var emoji: String {
        switch self {
        case .like: "❤️"
        case .love: "😍"
        case .laugh: "😂"
        case .fire: "🔥"
        case .celebrate: "🎉"
        case .insightful: "💡"
        case .support: "🙏"
        case .curious: "😮"
        }
    }
}

private struct EmojiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.5 : 1)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0)))
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Music / audio post: artwork, now-playing chip and an expand button for the full player.
struct ImmersiveMusicPlayer: View {
    let attachment: ModulaAttachment
    var onExpand: () -> Void
    var embedded = false
    @State private var audio = ModulaAudioPlayerState()
    @State private var download = AttachmentDownloadModel()
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = app.appearance.accent.color
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [accent, accent.mix(with: .purple, by: 0.5), .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = attachment.bestPreviewURL {
                    ModulaRemoteImage(url: url, cacheKey: "attachment:\(attachment.id):artwork", maximumPixelSize: 400) { phase in
                        if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.title).foregroundStyle(.white) }
                    }
                } else {
                    Image(systemName: "music.note").font(.title).foregroundStyle(.white)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: accent.opacity(0.35), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                if audio.isPlaying {
                    HStack(spacing: 5) {
                        NowPlayingBars(animated: !reduceMotion)
                        Text("Now playing")
                            .font(.system(size: 10, weight: .bold, design: app.appearance.fontDesign))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .modulaGlass(in: Capsule(), interactive: false, tint: accent)
                }
                Text(attachment.metadata.title ?? attachment.displayName)
                    .font(.system(.subheadline, design: app.appearance.fontDesign, weight: .semibold))
                    .lineLimit(1)
                Text(attachment.metadata.creator ?? "Audio")
                    .font(.system(.caption, design: app.appearance.fontDesign))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    Capsule().fill(Color.primary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(accent).frame(width: max(4, geo.size.width * audio.progress))
                        }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Button {
                if let url = playableURL { audio.attach(url: url); audio.toggle() }
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle(), tint: accent, prominent: true)
            .disabled(playableURL == nil)
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full player")
        }
        .padding(embedded ? 8 : 10)
        .background(
            Color.primary.opacity(embedded ? 0.04 : 0.045),
            in: RoundedRectangle(cornerRadius: embedded ? 12 : 18, style: .continuous)
        )
        .onDisappear { audio.release() }
        .task(id: attachment.id) {
            download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.accessibilityLabel)
    }

    private var playableURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return attachment.localFileURL
    }
}

private struct NowPlayingBars: View {
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .frame(width: 2.5, height: animated ? 4 + 6 * abs(sin(t * 5 + Double(index) * 1.3)) : 8)
                }
            }
            .frame(height: 10, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// "#RRGGBB" / "RRGGBB" glow colours from the API.
    init?(immersiveHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// Thin progress bar + elapsed/total time for immersive video (sits left of the action rail).
/// Drag to scrub; long-press the time label to cycle 1× / 1.5× / 2×.
struct ImmersiveVideoProgress: View {
    let controller: ModulaVideoPlaybackController
    @State private var scrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var rateFlash: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Text(rateFlash ?? label)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize()
                .contentTransition(.opacity)
                .onLongPressGesture(minimumDuration: 0.35) {
                    PostMenuCenter.shared.suppressLongPressUntil = Date().addingTimeInterval(1)
                    let rate = controller.cycleRate()
                    let label = rate == 1 ? "1×" : (rate == 1.5 ? "1.5×" : "2×")
                    rateFlash = label
                    HapticEngine.shared.play(.confirmation)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(900))
                        if rateFlash == label { rateFlash = nil }
                    }
                }
                .accessibilityLabel("Playback speed \(controller.rate == 1 ? "1x" : controller.rate == 1.5 ? "1.5x" : "2x"). Long-press to change.")
            GeometryReader { geo in
                let shown = scrubbing ? scrubProgress : controller.progress
                Capsule().fill(.white.opacity(0.28))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: max(2, geo.size.width * shown))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                PostMenuCenter.shared.suppressLongPressUntil = Date().addingTimeInterval(0.8)
                                if !scrubbing {
                                    scrubbing = true
                                    HapticEngine.shared.play(.selection)
                                }
                                scrubProgress = fraction
                            }
                            .onEnded { value in
                                let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                controller.seek(to: fraction)
                                scrubbing = false
                                HapticEngine.shared.play(.lightImpact)
                            }
                    )
            }
            .frame(height: scrubbing ? 8 : 3)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: scrubbing)
            .accessibilityElement()
            .accessibilityLabel("Video progress")
            .accessibilityValue("\(Int((scrubbing ? scrubProgress : controller.progress) * 100)) percent")
            .accessibilityAdjustableAction { direction in
                let step = 0.05
                let next = controller.progress + (direction == .increment ? step : -step)
                controller.seek(to: next)
            }
            Button {
                controller.toggleMute()
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isMuted ? "Unmute video" : "Mute video")
        }
        .padding(.leading, 14)
        .padding(.trailing, 66)
        .padding(.bottom, 2)
    }

    private var label: String {
        let total = controller.duration
        let elapsed = total * (scrubbing ? scrubProgress : controller.progress)
        return "\(Self.clock(elapsed)) / \(Self.clock(total))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
