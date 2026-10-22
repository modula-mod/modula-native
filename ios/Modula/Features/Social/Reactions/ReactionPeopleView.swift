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

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(TintShapeStyle().opacity(0.2)) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
                .overlay(Capsule().stroke(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.clear), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
