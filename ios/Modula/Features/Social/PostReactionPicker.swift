import SwiftUI

/// Any-emoji reactions are **local-only**: the backend mutates likes only
/// (`ReactionBackendCapabilities.multiReactionHTTP == false`), so they are kept on this device.
@MainActor
@Observable
final class LocalEmojiReactionStore {
    static let shared = LocalEmojiReactionStore()
    private let key = "reactions.localEmoji"
    private(set) var byPost: [String: String]

    private init() { byPost = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }

    func emoji(for postID: String) -> String? { byPost[postID] }

    func set(_ emoji: String?, for postID: String) {
        byPost[postID] = emoji
        UserDefaults.standard.set(byPost, forKey: key)
    }
}

/// Compact floating glass reaction bar anchored near Like. Selection stays local until release.
struct PostReactionPicker: View {
    let current: SocialReaction?
    var multiEnabled: Bool
    var postID: String? = nil
    var onSelect: (SocialReaction?) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = LocalEmojiReactionStore.shared
    @State private var showsEmojiPanel = false
    @State private var burst: String?
    @State private var burstTrigger = 0

    private var candidates: [SocialReaction] {
        multiEnabled ? SocialReaction.allCases : [.like]
    }

    private var customEmoji: String? { postID.flatMap { store.emoji(for: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("React")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 6) {
                    ModulaReactionBar(
                        items: candidates.map {
                            ModulaReactionItem(id: $0, title: $0.accessibilityName, systemImage: $0.systemImage)
                        },
                        selectedID: current,
                        compact: false,
                        maximumVisibleItems: 8,
                        onSelect: { reaction in fire(symbol: reaction?.systemImage) { onSelect(reaction) } },
                        onOverflow: nil
                    )
                    if let customEmoji {
                        Button { setCustom(nil) } label: {
                            Text(customEmoji).font(.system(size: 24)).frame(width: 46, height: 52)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityLabel("Remove \(customEmoji) reaction")
                    }
                    if postID != nil {
                        Button {
                            HapticEngine.shared.play(.selection)
                            showsEmojiPanel = true
                        } label: {
                            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: 46, height: 52)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Circle(), interactive: true)
                        .accessibilityLabel("Any emoji")
                    }
                }
            }
            if customEmoji != nil {
                Text("Emoji reactions stay on this device")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .overlay { PickerReactionBurst(glyph: burst, trigger: burstTrigger).allowsHitTesting(false) }
        .sheet(isPresented: $showsEmojiPanel) {
            ModulaEmojiGrid { emoji in
                showsEmojiPanel = false
                setCustom(emoji)
            }
            .padding(.top, 12)
            .presentationDetents([.medium, .large])
            .modulaSheetStyle()
        }
        .accessibilityIdentifier("post.reaction.picker")
    }

    private func setCustom(_ emoji: String?) {
        guard let postID else { return }
        store.set(emoji, for: postID)
        if let emoji { fire(glyph: emoji) {} } else { HapticEngine.shared.play(.selection) }
    }

    /// Plays the burst, then commits (immediately when Reduce Motion is on).
    private func fire(symbol: String? = nil, glyph: String? = nil, then commit: @escaping () -> Void) {
        guard !reduceMotion, symbol != nil || glyph != nil else { commit(); return }
        burst = glyph ?? symbol.map { "sf:\($0)" }
        burstTrigger += 1
        // Speed: commit (optimistic update + network) almost immediately; the burst keeps playing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: commit)
    }
}

/// Radial burst of the chosen reaction: a centre pop, a soft shock ring and 10 pieces on
/// varied radii/rotations. One animated value drives everything (cheap; no per-piece state).
private struct PickerReactionBurst: View {
    let glyph: String?
    let trigger: Int
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            if let glyph, progress < 1 {
                Circle()
                    .stroke(Color.accentColor.opacity(0.5 * Double(1 - progress)), lineWidth: 3 * (1 - progress) + 0.5)
                    .frame(width: 30 + 110 * progress, height: 30 + 110 * progress)
                piece(glyph)
                    .scaleEffect(progress < 0.35 ? 0.6 + progress * 3 : 1.65 - (progress - 0.35) * 0.9)
                    .opacity(Double(progress < 0.6 ? 1 : (1 - progress) / 0.4))
                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10 * 2 * .pi + (i.isMultiple(of: 2) ? 0.15 : -0.1)
                    let reach: CGFloat = i % 3 == 0 ? 70 : (i % 3 == 1 ? 54 : 42)
                    piece(glyph)
                        .scaleEffect((0.45 + progress * 0.45) * (i % 3 == 0 ? 0.8 : 1))
                        .rotationEffect(.degrees(Double(i % 2 == 0 ? 1 : -1) * 40 * Double(progress)))
                        .offset(x: cos(angle) * reach * progress, y: sin(angle) * reach * 0.8 * progress - 10 * progress)
                        .opacity(Double(1 - progress))
                }
            }
        }
        .onChange(of: trigger) { _, _ in
            progress = 0
            withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { progress = 0.999 }
        }
    }

    @ViewBuilder private func piece(_ glyph: String) -> some View {
        if glyph.hasPrefix("sf:") {
            Image(systemName: String(glyph.dropFirst(3))).symbolVariant(.fill).foregroundStyle(Color.accentColor).font(.system(size: 16, weight: .bold))
        } else {
            Text(glyph).font(.system(size: 20))
        }
    }
}
