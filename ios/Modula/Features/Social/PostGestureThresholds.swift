import CoreGraphics
import Foundation

/// Centralized gesture ownership thresholds for the post interaction system.
enum PostGestureThresholds {
    /// Long-press duration before reaction picker / context preview opens.
    static let longPressDuration: TimeInterval = 0.42

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
}
