import SwiftUI

/// Compact floating reaction picker anchored near Like. Selection stays local until release.
struct PostReactionPicker: View {
    let current: SocialReaction?
    var multiEnabled: Bool
    var onSelect: (SocialReaction?) -> Void
    var onCancel: () -> Void

    private var candidates: [SocialReaction] {
        if multiEnabled {
            return ReactionKind.allCases.map(\.socialReaction)
        }
        return SocialReaction.networkSupported
    }

    var body: some View {
        ModulaReactionBar(
            items: candidates.map {
                ModulaReactionItem(id: $0, title: $0.accessibilityName, systemImage: $0.systemImage)
            },
            selectedID: current,
            compact: true,
            maximumVisibleItems: 6,
            onSelect: onSelect,
            onOverflow: multiEnabled ? {} : nil
        )
        .accessibilityIdentifier("post.reaction.picker")
    }
}
