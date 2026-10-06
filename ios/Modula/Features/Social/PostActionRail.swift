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
    @State private var morphProgress: CGFloat = 0
    @State private var showsContext = false
    @State private var showsReactions = false

    private var contextActions: [ModulaContextAction] {
        PostContextActions.railContextActions(saved: post.saved, capabilities: app.postActions.capabilities)
            .filter { onContextAction != nil || ["share", "copy-link", "save", "save-collection"].contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsContext {
                HStack {
                    Text("Post actions").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button(action: dismissContext) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close post actions")
                }
                .frame(width: 204)
                ForEach(contextActions) { action in
                    Button {
                        perform(action)
                        dismissContext()
                    } label: {
                        Label(action.title, systemImage: action.systemImage ?? "ellipsis")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 204, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.resolvedAccessibilityLabel)
                }
            } else {
                railButton(title: "More actions", symbol: "ellipsis", count: nil, active: false) {
                    showsContext = true
                }
                railButton(
                    title: post.viewerReaction?.accessibilityName ?? "Like",
                    symbol: post.viewerReaction?.systemImage ?? (post.liked ? "heart.fill" : "heart"),
                    count: max(post.reactionCount, post.likeCount) > 0 ? ModulaCountFormat.compact(max(post.reactionCount, post.likeCount)) : nil,
                    active: post.viewerReaction != nil || post.liked,
                    action: onLike
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: PostGestureThresholds.longPressDuration)
                        .onEnded { _ in
                            HapticEngine.shared.play(.contextOpen)
                            if let onReactLongPress { onReactLongPress() } else { showsReactions = true }
                        }
                )
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
        }
        .padding(.vertical, 8)
        .padding(.horizontal, showsContext ? 16 : 4)
        .foregroundStyle(.white)
        .background { railBackground }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(glass ? 0.08 : 0.14)))
        .offset(y: morphProgress * 0.15)
        .gesture(railMorphGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post action rail")
        .accessibilityIdentifier("post.action.rail.\(post.id)")
        .accessibilityAction(named: "Choose reaction") {
            if let onReactLongPress { onReactLongPress() } else { showsReactions = true }
        }
        .accessibilityAction(named: "More actions") { showsContext = true }
        .contextMenu {
            ForEach(contextActions) { action in
                Button(action.title, systemImage: action.systemImage ?? "ellipsis") { perform(action) }
            }
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
        if glass && !opaque && !showsContext {
            Color.clear.modulaGlass(in: shape, interactive: false, tint: .black.opacity(0.22), specular: true)
        } else {
            shape.fill(.black.opacity(opaque ? 1 : (showsContext ? 0.96 : 0.72)))
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

    private var railMorphGesture: some Gesture {
        DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 0, vertical > horizontal * PostGestureThresholds.verticalDominanceRatio else { return }
                morphProgress = min(vertical, PostGestureThresholds.railMorphThreshold * 1.5)
                if vertical >= PostGestureThresholds.railMorphThreshold, !showsContext {
                    showsContext = true
                    HapticEngine.shared.play(.dragThreshold)
                }
            }
            .onEnded { _ in
                if !showsContext {
                    withAnimation(ModulaMotion.animation(.dismiss, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                        morphProgress = 0
                    }
                }
            }
    }

    private func dismissContext() {
        withAnimation(ModulaMotion.animation(.railCollapse, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
            showsContext = false
            morphProgress = 0
        }
    }
}
