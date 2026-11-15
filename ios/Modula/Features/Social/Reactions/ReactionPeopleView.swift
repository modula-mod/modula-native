import SwiftUI

/// Reactions summary: total, the viewer's reaction and a per-kind breakdown with proportional bars.
/// Data: GET /v1/posts/:id/reactions (`viewerReaction`, `total`, `byType`). The server does not
/// return who reacted, so no people are listed (no fabricated names).
struct ReactionPeopleView: View {
    let postID: String
    var summary: ReactionSummary?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: ReactionSummary?
    @State private var loading = false
    @State private var failed = false
    @State private var filter: ReactionKind?
    @State private var barsIn = false

    private var current: ReactionSummary? { loaded ?? summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let current, current.total > 0 {
                    header(current)
                    breakdown(current)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ContentUnavailableView {
                        Label(failed ? "Couldn't load reactions" : "No reactions yet", systemImage: "face.smiling")
                    } description: {
                        Text(failed ? "Pull to try again." : "Reactions on this post show up here.")
                    }
                    .padding(.top, 40)
                }
                if !ReactionBackendCapabilities.reactionsListHTTP, (current?.total ?? 0) > 0 {
                    Label("Counts only. Modula doesn't share who reacted.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .modulaSoftScrollEdge()
        .navigationTitle("Reactions")
        .task { if loaded == nil { await load() } }
        .onAppear {
            // Bars grow in once (skipped with Reduce Motion).
            if reduceMotion { barsIn = true } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.05)) { barsIn = true }
            }
        }
        .accessibilityIdentifier("post.people.reactions")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let fresh = await app.postActions.refreshReactionSummary(postID: postID) {
            withAnimation(reduceMotion ? nil : .snappy) { loaded = fresh }
            failed = false
        } else if current == nil {
            failed = true
        }
    }

    private func header(_ summary: ReactionSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: -6) {
                ForEach(summary.presentKinds.sorted { summary.count(for: $0) > summary.count(for: $1) }.prefix(3), id: \.self) { kind in
                    Text(kind.emoji)
                        .font(.title2)
                        .padding(4)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.total, format: .number)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(summary.total)))
                Text(summary.total == 1 ? "reaction" : "reactions")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let mine = summary.viewerReaction {
                Label("You · \(mine.emoji)", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .accessibilityLabel("You reacted \(mine.title)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ summary: ReactionSummary) -> some View {
        let kinds = summary.presentKinds.sorted { summary.count(for: $0) > summary.count(for: $1) }
        let top = max(kinds.first.map { summary.count(for: $0) } ?? 1, 1)
        return VStack(spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                let count = summary.count(for: kind)
                let selected = filter == kind
                Button {
                    HapticEngine.shared.play(.selection)
                    withAnimation(reduceMotion ? nil : .snappy) { filter = selected ? nil : kind }
                } label: {
                    HStack(spacing: 12) {
                        Text(kind.emoji).font(.title3).frame(width: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(kind.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(count, format: .number)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(percent(count, of: summary.total))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            GeometryReader { geo in
                                Capsule().fill(Color.primary.opacity(0.08))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.primary.opacity(selected || filter == nil ? 0.85 : 0.3))
                                            .frame(width: barsIn ? geo.size.width * CGFloat(count) / CGFloat(top) : 0)
                                    }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title), \(count) of \(summary.total)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func percent(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }
}
