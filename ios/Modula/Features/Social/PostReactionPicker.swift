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
        VStack(alignment: .leading, spacing: 6) {
            Text("React")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ModulaReactionBar(
                items: candidates.map {
                    ModulaReactionItem(id: $0, title: $0.accessibilityName, systemImage: $0.systemImage)
                },
                selectedID: current,
                compact: false,
                maximumVisibleItems: 8,
                onSelect: onSelect,
                onOverflow: nil
            )
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .accessibilityIdentifier("post.reaction.picker")
    }
}
