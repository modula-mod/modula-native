import SwiftUI
import UIKit

/// Vertical action rail for media-rich posts. Drag down (rail hit-region only) morphs into context actions.
/// Semantically distinct from `ModulaEdgeLoop` — this controls a content object, not screen context.
struct PostActionRail: View {
    let post: SocialPost
    var onLike: () -> Void
    var onComment: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onReactLongPress: (() -> Void)? = nil
    var onContextAction: ((ModulaContextAction) -> Void)? = nil
    /// Liquid Glass capsule (Reels). Default keeps the dark scrim used on feed cards.
    var glass = false

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var moreFrame: CGRect = .zero
    @State private var showsReactions = false

    private var contextActions: [ModulaContextAction] {
        PostContextActions.railContextActions(saved: post.saved, capabilities: app.postActions.capabilities)
            .filter { onContextAction != nil || ["share", "copy-link", "save", "save-collection"].contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
                PostMenuButton(makeRequest: { menuRequest(anchor: $0) }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { moreFrame = $0 }
                .accessibilityLabel("More actions")
                railButton(
                    title: post.viewerReaction?.accessibilityName ?? "Like",
                    symbol: post.viewerReaction?.systemImage ?? (post.liked ? "heart.fill" : "heart"),
                    count: max(post.reactionCount, post.likeCount) > 0 ? ModulaCountFormat.compact(max(post.reactionCount, post.likeCount)) : nil,
                    active: post.viewerReaction != nil || post.liked,
                    action: onLike
                )
                .exclusiveReactionLongPress {
                    HapticEngine.shared.play(.contextOpen)
                    if let onReactLongPress { onReactLongPress() } else { showsReactions = true }
                }
                .accessibilityHint("Tap to like. Touch and hold for more reactions.")
                railButton(
                    title: "Comment",
                    symbol: "bubble.right",
                    count: post.replyCount > 0 ? ModulaCountFormat.compact(post.replyCount) : nil,
                    active: false,
                    action: onComment
                )
                railButton(
                    title: post.saved ? "Unsave" : "Save",
                    symbol: post.saved ? "bookmark.fill" : "bookmark",
                    count: nil,
                    active: post.saved,
                    action: onSave
                )
                railButton(
                    title: "Share",
                    symbol: "square.and.arrow.up",
                    count: nil,
                    active: false,
                    action: onShare
                )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .foregroundStyle(.white)
        .background { railBackground }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(glass ? 0.08 : 0.14)))
                        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post action rail")
        .accessibilityIdentifier("post.action.rail.\(post.id)")
        .postReactionPickerPresented(showsReactions)
        .accessibilityAction(named: "Choose reaction") {
            if let onReactLongPress { onReactLongPress() } else { showsReactions = true }
        }
                .popover(isPresented: $showsReactions) {
            PostReactionPicker(current: post.viewerReaction, multiEnabled: app.postActions.capabilities.multiReactions,
                onSelect: { reaction in
                    showsReactions = false
                    Task { await app.postActions.setReaction(post, reaction: reaction) }
                }, onCancel: { showsReactions = false })
                .padding(8)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder private var railBackground: some View {
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if glass && !opaque {
            Color.clear.modulaGlass(in: shape, interactive: false, tint: .black.opacity(0.22), specular: true)
        } else {
            shape.fill(.black.opacity(opaque ? 1 : 0.72))
        }
    }

    private func perform(_ action: ModulaContextAction) {
        if let onContextAction { onContextAction(action); return }
        switch action.id {
        case "share": onShare()
        case "copy-link": UIPasteboard.general.string = post.shareURL.absoluteString
        case "save": onSave()
        case "save-collection": app.navigation.presented = .collectionPicker(postID: post.id)
        default: break
        }
    }

    private func railButton(title: String, symbol: String, count: String?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(active ? app.appearance.accent.color : .white)
                    .shadow(color: active ? app.appearance.accent.color.opacity(0.6) : .black.opacity(0.25), radius: active ? 6 : 2)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: active)
                if let count {
                    Text(count)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                }
            }
            .animation(.snappy, value: count)
            .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.86, haptic: nil))
        .accessibilityLabel(title)
        .accessibilityValue(count ?? "")
    }

    /// Swipe down on the rail: the glass menu grows out of the finger; keep sliding to pick an item.

    private func menuRequest(anchor: CGRect) -> PostMenuRequest {
        PostMenuRequest(
            post: post,
            isOwn: post.author?.id != nil && post.author?.id == app.auth.account?.accountId,
            anchor: anchor,
            hooks: PostMenuHooks(onSave: onSave, onShare: onShare, onContextAction: onContextAction)
        )
    }
}
