import SwiftUI

struct ReactionPeopleView: View {
    let postID: String
    var summary: ReactionSummary?
    @State private var filter: ReactionKind?

    var body: some View {
        VStack(spacing: 0) {
            if let summary, !summary.presentKinds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "All", selected: filter == nil) { filter = nil }
                        ForEach(summary.presentKinds, id: \.self) { kind in
                            filterChip(title: "\(kind.title) \(summary.count(for: kind))", selected: filter == kind) {
                                filter = kind
                            }
                            .accessibilityLabel("\(kind.title), \(summary.count(for: kind)) reactions")
                            .accessibilityAddTraits(filter == kind ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            ContentUnavailableView {
                Label("Reactions", systemImage: "face.smiling")
            } description: {
                Text(message)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Reactions")
        .accessibilityIdentifier("post.people.reactions")
    }

    private var message: String {
        if ReactionBackendCapabilities.reactionsListHTTP {
            return "People grouped by reaction."
        }
        return "People who reacted will appear here."
    }

    /// Enhancements-50: shared accent chip (selection haptic, Dynamic Type height, press spring).
    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        ModulaAccentChip(title: title, selected: selected, action: action)
    }
}
