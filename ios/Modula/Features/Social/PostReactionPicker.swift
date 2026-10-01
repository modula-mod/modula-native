import SwiftUI

/// Compact floating reaction picker anchored near Like. Selection stays local until release.
struct PostReactionPicker: View {
    let current: SocialReaction?
    var multiEnabled: Bool
    var onSelect: (SocialReaction?) -> Void
    var onCancel: () -> Void

    private var candidates: [SocialReaction] {
        if multiEnabled {
            return SocialReaction.allCases
        }
        return [.like]
    }

    var body: some View {
        ModulaReactionBar(
            items: candidates.map {
                ModulaReactionItem(id: $0, title: $0.accessibilityName, systemImage: $0.systemImage)
            },
            selectedID: current,
            compact: true,
            maximumVisibleItems: 8,
            onSelect: onSelect,
            onOverflow: nil
        )
        .accessibilityIdentifier("post.reaction.picker")
    }
}
