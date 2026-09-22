import SwiftUI

struct DraftsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var pendingDiscard: (DraftKind, String)?

    var body: some View {
        List {
            if app.drafts.allPreviews.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "doc.text", description: Text("Unfinished posts and letters appear here."))
            } else {
                ForEach(app.drafts.allPreviews, id: \.id) { item in
                    DraftRow(
                        kind: item.kind,
                        preview: item.preview,
                        lastEdited: item.lastEdited
                    ) {
                        continueDraft(kind: item.kind, id: item.id)
                    } onDelete: {
                        pendingDiscard = (item.kind, item.id)
                    }
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Drafts")
        .accessibilityIdentifier("drafts.root")
        .confirmationDialog(
            "Discard draft?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                if let pending = pendingDiscard {
                    app.drafts.discard(kind: pending.0, id: pending.1)
                    HapticEngine.shared.play(.warning)
                }
                pendingDiscard = nil
            }
            Button("Cancel", role: .cancel) { pendingDiscard = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func continueDraft(kind: DraftKind, id: String) {
        HapticEngine.shared.play(.navigation)
        switch kind {
        case .post:
            app.drafts.pendingResumeID = id
            app.navigation.presented = .composer(.post)
        case .inMail:
            app.navigation.open(.messages(.inMail(.compose)))
        case .story:
            if app.stories.capabilities.create {
                app.navigation.open(.stories(.create))
            }
        }
        _ = id
    }
}

struct DraftRow: View {
    let kind: DraftKind
    let preview: String
    let lastEdited: Date
    var onContinue: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onContinue) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(preview)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(lastEdited, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) draft")
        .accessibilityValue("\(preview). Last edited \(lastEdited.formatted(.relative(presentation: .named)))")
        .accessibilityHint("Continue draft")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Continue", action: onContinue)
        }
        .contextMenu {
            Button("Continue", systemImage: "arrow.right.circle", action: onContinue)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var title: String {
        switch kind {
        case .post: "Post"
        case .inMail: "In-Mail"
        case .story: "Story"
        }
    }

    private var icon: String {
        switch kind {
        case .post: "square.and.pencil"
        case .inMail: "envelope"
        case .story: "circle.dashed"
        }
    }
}

/// Offered when opening compose with an existing draft.
struct DraftRestorePrompt: View {
    var onContinue: () -> Void
    var onStartNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue your draft?")
                .font(.title3.weight(.semibold))
            Text("You have an unfinished post. Continue editing or start a new one.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Start New") {
                    onStartNew()
                    dismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Continue Draft") {
                    onContinue()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .accessibilityIdentifier("drafts.restore")
    }
}
