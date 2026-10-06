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

    static func custom(_ emoji: String) -> PostEmojiReaction {
        if let quick = quick.first(where: { $0.emoji == emoji }) { return quick }
        let reaction: SocialReaction
        switch emoji {
        case "😍", "🥰": reaction = .love
        case "🥳", "🎉", "👏", "🙌": reaction = .celebrate
        case "💡": reaction = .insightful
        case "🤔", "🧐", "👀", "🤯", "😱": reaction = .curious
        case "🙏", "🫶", "💪": reaction = .support
        case "💯", "⭐️", "✨": reaction = .fire
        case "🤣": reaction = .laugh
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

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL

    @State private var heartBurst = 0
    @State private var page: Int? = 0
    @State private var showsReactions = false
    @State private var hoveredReaction: String?
    @State private var showsReactionGrid = false
    @State private var showsPanel = false
    @State private var viewer: ImmersiveViewerItem?
    @State private var reactionFrames: [String: CGRect] = [:]
    @State private var heartFrame: CGRect = .zero
    @State private var suppressHeartTap = false
    @State private var captionExpanded = false

    private let radius: CGFloat = 24
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
        .overlay(alignment: .topTrailing) { panelLayer }
        .zIndex(showsPanel || showsReactions ? 5 : 0)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(post.voiceOverSummary)
        .accessibilityIdentifier("home.post.\(post.id)")
        .accessibilityAction(named: "React", onLike)
        .accessibilityAction(named: "Choose reaction") { showsReactions = true }
        .accessibilityAction(named: "Comment", onComment)
        .accessibilityAction(named: "Save", onSave)
        .accessibilityAction(named: "Share") { share() }
        .accessibilityAction(named: "Open Author", onOpenAuthor)
        .accessibilityAction(named: "More actions") { openPanel() }
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
        let ratio = stageRatio(pages.first)
        let current = min(max(page ?? 0, 0), pages.count - 1)
        let isVideo = pages[current].kind == .video
        VStack(alignment: .leading, spacing: 10) {
            Color.black
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { mediaPager(pages) }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 210)
                        .allowsHitTesting(false)
                }
                .overlay { DoubleTapHeartBurst(trigger: heartBurst) }
                .overlay(alignment: .top) { mediaHeader(canonical, pages: pages, current: current) }
                .overlay(alignment: .bottomLeading) { captionBlock(canonical, pages: pages, current: current, isVideo: isVideo) }
                .overlay(alignment: .bottomTrailing) { rail(expandable: isVideo ? pages[current] : nil, gallery: pages) }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.8
                        )
                        .allowsHitTesting(false)
                }
                .shadow(color: glow.opacity(0.28), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .environment(\.colorScheme, .dark)

            commentBar
            extraBlocks(canonical)
        }
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
                LazyHStack(spacing: 0) {
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
                    .contentShape(Rectangle())
                    .onTapGesture { openMedia(attachment) }
                    .accessibilityLabel(attachment.accessibilityLabel)
                    .accessibilityHint("Opens the post")
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
            moreButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func authorButton(_ canonical: ModulaPost, onMedia: Bool) -> some View {
        Button(action: onOpenAuthor) {
            HStack(spacing: 10) {
                RingedAvatar(author: post.author, size: 38)
                VStack(alignment: .leading, spacing: 2) {
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
                            .foregroundStyle(onMedia ? .white.opacity(0.75) : .secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    if let location = canonical.context.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(.caption2, design: font, weight: .medium))
                            .foregroundStyle(onMedia ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
                            .labelStyle(TightLabelStyle())
                    } else if let handle = post.author?.handle, !onMedia {
                        Text("@\(handle)")
                            .font(.system(.caption, design: font))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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

    private var moreButton: some View {
        Button(action: openPanel) {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), specular: true)
        .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
        .contentShape(Rectangle())
        .accessibilityLabel("More actions")
        .accessibilityIdentifier("post.more.\(post.id)")
    }

    // MARK: Caption

    private func captionBlock(_ canonical: ModulaPost, pages: [ModulaAttachment], current: Int, isVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        if captionExpanded || text.count < 90 { onOpenPost() } else {
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
                        Capsule()
                            .fill(.white.opacity(index == current ? 0.95 : 0.4))
                            .frame(width: index == current ? 16 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(calm ? nil : .snappy, value: current)
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 70)
        .padding(.bottom, isVideo ? 30 : 14)
    }

    // MARK: Rail

    private var reacted: Bool { post.liked || post.viewerReaction != nil }
    private var reactionCount: Int { max(post.reactionCount, post.likeCount) }

    private func rail(expandable: ModulaAttachment?, gallery: [ModulaAttachment]) -> some View {
        VStack(spacing: 0) {
            heartControl(vertical: true)
            railButton("Comment", symbol: "bubble.right.fill", count: post.replyCount, active: false, action: onComment)
                .accessibilityIdentifier("home.action.comment.\(post.id)")
            railButton(post.saved ? "Unsave" : "Save", symbol: post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, tint: .yellow, action: onSave)
                .accessibilityIdentifier("home.action.save.\(post.id)")
            railButton("Share", symbol: "paperplane.fill", count: post.repostCount, active: false, action: share)
            if let expandable {
                railButton("Open full-screen player", symbol: "arrow.up.left.and.arrow.down.right", count: 0, active: false) {
                    viewer = ImmersiveViewerItem(attachment: expandable, gallery: gallery)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .modulaGlass(in: Capsule(), interactive: false, specular: true)
        .padding(.trailing, 10)
        .padding(.bottom, 12)
        .gesture(
            DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
                .onEnded { value in
                    let vertical = value.translation.height
                    guard vertical > PostGestureThresholds.railMorphThreshold,
                          vertical > abs(value.translation.width) * PostGestureThresholds.verticalDominanceRatio else { return }
                    openPanel()
                }
        )
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
                if let text = ModulaCountFormat.compact(count) {
                    Text(text)
                        .font(.system(size: 10, weight: .semibold, design: font).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }

    /// Heart: tap toggles, long-press opens the picker; keep holding and slide to preview, release to apply.
    private func heartControl(vertical: Bool) -> some View {
        let emoji = reacted ? PostEmojiReactionStore.shared.emoji(for: post.id) : nil
        let symbol = post.viewerReaction.flatMap { $0 == .like ? nil : $0.systemImage } ?? (reacted ? "heart.fill" : "heart")
        return Group {
            if vertical {
                VStack(spacing: 1) { heartGlyph(emoji: emoji, symbol: symbol, size: 21, onMedia: true); heartCount(onMedia: true) }
                    .frame(width: 44, height: 46)
            } else {
                HStack(spacing: 5) { heartGlyph(emoji: emoji, symbol: symbol, size: 19, onMedia: false); heartCount(onMedia: false) }
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { heartFrame = $0 }
        .onTapGesture {
            guard !suppressHeartTap else { return }
            if showsReactions { closePicker(); return }
            onLike()
            if !reacted { HapticEngine.shared.play(.lightImpact) }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: PostGestureThresholds.longPressDuration)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if !showsReactions {
                            suppressHeartTap = true
                            HapticEngine.shared.play(.contextOpen)
                            withAnimation(calm ? nil : .spring(response: 0.3, dampingFraction: 0.72)) { showsReactions = true }
                        }
                        if let drag { hover(at: drag.location) }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    if let hovered = hoveredReaction {
                        if hovered == "+" { openGrid() } else { apply(.custom(hovered)) }
                    }
                    hoveredReaction = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        suppressHeartTap = false
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reacted ? (emoji.map { "Reacted \($0)" } ?? post.viewerReaction?.accessibilityName ?? "Liked") : "Like")
        .accessibilityValue(reactionCount > 0 ? "\(reactionCount)" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onLike() }
        .accessibilityIdentifier("home.action.like.\(post.id)")
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

    private func hover(at point: CGPoint) {
        let hit = reactionFrames.first { $0.value.insetBy(dx: -3, dy: -26).contains(point) }?.key
        if hit != hoveredReaction {
            hoveredReaction = hit
            if hit != nil { HapticEngine.shared.play(.selection) }
        }
    }

    private func apply(_ option: PostEmojiReaction) {
        HapticEngine.shared.play(.confirmation)
        PostEmojiReactionStore.shared.set(option.emoji == PostEmojiReaction.heart.emoji ? nil : option.emoji, for: post.id)
        closePicker()
        heartBurst += option.emoji == PostEmojiReaction.heart.emoji ? 1 : 0
        Task { await app.postActions.setReaction(post, reaction: option.reaction) }
    }

    private func openGrid() {
        closePicker()
        HapticEngine.shared.play(.contextOpen)
        showsReactionGrid = true
    }

    private func closePicker() {
        withAnimation(calm ? nil : .snappy(duration: 0.2)) { showsReactions = false }
        hoveredReaction = nil
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
                    reactionBar
                        .position(
                            x: geo.size.width / 2,
                            y: max(34, heartFrame.minY - 36)
                        )
                }
            }
            .transition(.opacity)
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 2) {
            ForEach(PostEmojiReaction.quick) { option in
                reactionItem(id: option.emoji) {
                    Text(option.emoji).font(.system(size: 27))
                }
                .accessibilityLabel(option.title)
                .onTapGesture { apply(option) }
            }
            reactionItem(id: "+") {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post.reaction.picker")
    }

    private func reactionItem<Content: View>(id: String, @ViewBuilder content: () -> Content) -> some View {
        let hovered = hoveredReaction == id
        return content()
            .frame(width: 42, height: 42)
            .scaleEffect(hovered ? 1.55 : 1, anchor: .bottom)
            .offset(y: hovered ? -10 : 0)
            .animation(calm ? nil : .spring(response: 0.22, dampingFraction: 0.6), value: hovered)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { reactionFrames[id] = $0 }
            .contentShape(Rectangle())
    }

    // MARK: Context panel

    @ViewBuilder
    private var panelLayer: some View {
        if showsPanel {
            ImmersivePostContextPanel(
                post: post,
                isOwnPost: isOwnPost,
                capabilities: app.postActions.capabilities,
                onSelect: { action in
                    closePanel()
                    perform(action)
                },
                onClose: closePanel
            )
            .padding(.top, 8)
            .padding(.trailing, 8)
            .transition(calm ? .opacity : .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func openPanel() {
        HapticEngine.shared.play(.dragThreshold)
        withAnimation(calm ? nil : .spring(response: 0.34, dampingFraction: 0.8)) { showsPanel = true }
    }

    private func closePanel() {
        withAnimation(calm ? nil : .snappy(duration: 0.22)) { showsPanel = false }
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

    // MARK: Comment bar

    private var commentBar: some View {
        HStack(spacing: 10) {
            if let profile = app.profile.ownProfile {
                ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 26)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            Text("Add a comment…")
                .font(.system(.subheadline, design: font))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onComment) {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment with a photo")
            Button(action: onComment) {
                Text("GIF")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.2))
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment with a GIF")
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(height: 44)
        .modulaGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
        .onTapGesture(perform: onComment)
        .gesture(
            DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
                .onEnded { value in
                    if value.translation.height < -PostGestureThresholds.commentSheetThreshold { onComment() }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add a comment")
        .accessibilityHint("Opens comments. Swipe up to open.")
        .accessibilityIdentifier("post.comment.prompt.\(post.id)")
    }

    @ViewBuilder
    private func extraBlocks(_ canonical: ModulaPost) -> some View {
        ForEach(canonical.content.filter { !$0.isMediaFirst }) { block in
            if case .link(let value) = block {
                ModulaLinkPreview(content: value) { openURL($0) }
            }
        }
    }

    // MARK: Text card

    @ViewBuilder
    private func textCard(_ canonical: ModulaPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                authorButton(canonical, onMedia: false)
                Spacer(minLength: 6)
                moreButton
            }
            if post.text?.isEmpty == false {
                PostBody(post: post)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenPost)
                    .accessibilityAction(named: "Open Post", onOpenPost)
                    .accessibilityIdentifier("post.open.\(post.id)")
            }
            if case .audio(let value)? = canonical.content.first {
                ImmersiveMusicPlayer(attachment: value.attachment) {
                    viewer = ImmersiveViewerItem(attachment: value.attachment, gallery: [])
                }
            } else if !canonical.content.isEmpty || canonical.context.module != nil {
                PostCanonicalContent(
                    source: post,
                    videoCoordinator: videoCoordinator,
                    onOpenAttachment: { attachment in
                        if let media = post.media.first(where: { $0.id == attachment.id }) { onOpenMedia?(media) }
                    },
                    onOpenModule: onOpenModule
                )
            }
            textActions
            commentBar
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
        }
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [glow.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), Color.primary.opacity(0.06), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .shadow(color: glow.opacity(0.14), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private var textActions: some View {
        HStack(spacing: 2) {
            heartControl(vertical: false)
                .foregroundStyle(.secondary)
            pillButton("Comment", symbol: "bubble.right", count: post.replyCount, active: false, action: onComment)
                .accessibilityIdentifier("home.action.comment.\(post.id)")
            pillButton("Repost", symbol: "arrow.2.squarepath", count: post.repostCount, active: post.reposted, action: onRepost)
                .accessibilityIdentifier("home.action.repost.\(post.id)")
            Spacer(minLength: 0)
            pillButton(post.saved ? "Unsave" : "Save", symbol: post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, action: onSave)
                .accessibilityIdentifier("home.action.save.\(post.id)")
            pillButton("Share", symbol: "paperplane", count: 0, active: false, action: share)
        }
    }

    private func pillButton(_ title: String, symbol: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                if let text = ModulaCountFormat.compact(count) {
                    Text(text).font(.system(size: 12, weight: .semibold, design: font).monospacedDigit())
                }
            }
            .foregroundStyle(active ? app.appearance.accent.color : .secondary)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    ZStack {
                        Color(white: 0.14)
                        ProgressView().tint(.white)
                    }
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

/// "+" grid of custom emoji reactions; each emoji enlarges while pressed.
private struct ReactionGridSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
                    ForEach(PostEmojiReaction.grid, id: \.self) { emoji in
                        Button {
                            HapticEngine.shared.play(.selection)
                            onPick(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(EmojiPressStyle())
                        .accessibilityLabel(emoji)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
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
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
struct ImmersiveVideoProgress: View {
    let controller: ModulaVideoPlaybackController

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize()
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.28))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: max(2, geo.size.width * controller.progress))
                    }
            }
            .frame(height: 3)
            .accessibilityElement()
            .accessibilityLabel("Video progress")
            .accessibilityValue("\(Int(controller.progress * 100)) percent")
            Button { controller.toggleMute() } label: {
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
        let elapsed = total * controller.progress
        return "\(Self.clock(elapsed)) / \(Self.clock(total))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
