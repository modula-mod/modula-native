import SwiftUI

/// Compact floating reaction picker anchored near Like. Selection stays local until release.
struct PostReactionPicker: View {
    let current: SocialReaction?
    var multiEnabled: Bool
    var onSelect: (SocialReaction?) -> Void
    var onCancel: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted: SocialReaction?
    @State private var lastHapticReaction: SocialReaction?

    private var candidates: [SocialReaction] {
        if multiEnabled {
            return ReactionKind.allCases.map(\.socialReaction)
        }
        return SocialReaction.networkSupported
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(candidates, id: \.self) { reaction in
                candidateButton(reaction)
            }
            if multiEnabled {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("More reactions")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background)
        .overlay(
            Capsule().stroke(.primary.opacity(reduceTransparency ? 0.2 : 0.08))
        )
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.12), radius: 12, y: 4)
        .gesture(scrubGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reaction picker")
        .accessibilityIdentifier("post.reaction.picker")
        .onAppear {
            highlighted = current
            HapticEngine.shared.play(.contextOpen)
        }
    }

    private var background: some View {
        Group {
            if reduceTransparency {
                Capsule().fill(Color(uiColor: .systemBackground))
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
    }

    private func candidateButton(_ reaction: SocialReaction) -> some View {
        let selected = highlighted == reaction || (highlighted == nil && current == reaction)
        return Button {
            commit(reaction)
        } label: {
            Image(systemName: reaction.systemImage)
                .font(.system(size: selected ? 22 : 18, weight: .semibold))
                .foregroundStyle(selected ? app.appearance.accent.color : .primary)
                .frame(width: 40, height: 40)
                .scaleEffect(selected && !reduceMotion ? 1.18 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reaction.accessibilityName)
        .accessibilityAddTraits(current == reaction ? .isSelected : [])
        .accessibilityIdentifier("post.reaction.\(reaction.rawValue)")
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let index = Int((value.location.x / PostGestureThresholds.reactionCandidateSpacing).rounded(.down))
                let clamped = max(0, min(candidates.count - 1, index))
                let reaction = candidates[clamped]
                if highlighted != reaction {
                    highlighted = reaction
                    if lastHapticReaction != reaction {
                        lastHapticReaction = reaction
                        HapticEngine.shared.play(.reactionSelect)
                    }
                }
            }
            .onEnded { _ in
                if let highlighted {
                    commit(highlighted)
                } else {
                    onCancel()
                }
            }
    }

    private func commit(_ reaction: SocialReaction) {
        HapticEngine.shared.play(.confirmation)
        onSelect(reaction)
    }
}
