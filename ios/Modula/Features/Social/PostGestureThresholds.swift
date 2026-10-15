import CoreGraphics
import Foundation
import SwiftUI

/// Bubbles reaction/emoji picker presentation up to `PostSwipeActions` so share/save pans disable.
struct PostReactionPickerPresentedKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Marks this subtree as presenting a reaction/emoji picker (or its long-press menu).
    func postReactionPickerPresented(_ presented: Bool) -> some View {
        preference(key: PostReactionPickerPresentedKey.self, value: presented)
    }
}

/// Centralized gesture ownership thresholds for the post interaction system.
enum PostGestureThresholds {
    /// Long-press duration for post body / card chrome (preview + options sheet).
    static let longPressDuration: TimeInterval = 0.42

    /// Like-control long-press. Opens the reaction picker — never the post preview.
    static let reactionLongPressDuration: TimeInterval = 0.28

    /// Minimum drag distance before a gesture claims ownership.
    static let dragActivationDistance: CGFloat = 12

    /// Horizontal translation must exceed vertical by this ratio for carousel ownership.
    static let horizontalDominanceRatio: CGFloat = 1.35

    /// Vertical translation must exceed horizontal by this ratio for rail morph.
    static let verticalDominanceRatio: CGFloat = 1.35

    /// Distance to morph action rail into context actions.
    static let railMorphThreshold: CGFloat = 56

    /// Distance inside the comment bar zone before expanding the comments sheet.
    static let commentSheetThreshold: CGFloat = 48

    /// Hit target for compact glyphs (•••, rail icons).
    static let minimumHitTarget: CGFloat = 44

    /// Reaction scrub must move this far before changing candidate (spam protection).
    static let reactionCandidateSpacing: CGFloat = 44

    /// Horizontal translation that commits swipe-to-share / swipe-to-save.
    static let swipeCommitDistance: CGFloat = 92

    /// Leave the leading edge to system back-swipe.
    static let swipeLeadingExclusion: CGFloat = 32

    /// Leave the trailing edge to the Edge Picker scrub.
    static let swipeTrailingExclusion: CGFloat = 48
}
