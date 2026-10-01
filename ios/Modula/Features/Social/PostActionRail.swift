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

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                ForEach(contextActions) { action in
                    Button {
                        perform(action)
                        dismissContext()
                    } label: {
                        Image(systemName: action.systemImage ?? "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.resolvedAccessibilityLabel)
                }
            } else {
                railButton(
                    title: post.viewerReaction?.accessibilityName ?? "Like",
                    symbol: post.viewerReaction?.systemImage ?? "heart",
                    count: ModulaCountFormat.compact(max(post.reactionCount, post.likeCount)),
                    active: post.viewerReaction != nil,
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
                    count: ModulaCountFormat.compact(post.replyCount),
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
                    count: ModulaCountFormat.compact(post.repostCount + post.quoteCount),
                    active: false,
                    action: onShare
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .modulaMaterial(.control, in: Capsule(), depth: .raised)
        .offset(y: morphProgress * 0.15)
        .gesture(railMorphGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post action rail")
        .accessibilityIdentifier("post.action.rail.\(post.id)")
        .accessibilityAction(named: "Choose reaction") { showsReactions = true }
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? app.appearance.accent.color : .primary)
                if let count {
                    Text(count)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: PostGestureThresholds.minimumHitTarget, height: PostGestureThresholds.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
