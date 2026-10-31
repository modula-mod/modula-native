import SwiftUI

private enum DraftLibraryFilter: String, CaseIterable, Identifiable {
    case all, posts, stories, inMail, reels
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .posts: "Posts"
        case .stories: "Stories"
        case .inMail: "In-Mail"
        case .reels: "Reels"
        }
    }
}

struct DraftsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var pendingDiscard: (DraftKind, String)?
    @State private var filter: DraftLibraryFilter = .all

    private var items: [DraftLibraryItem] {
        switch filter {
        case .all: app.drafts.libraryItems
        case .posts: app.drafts.libraryItems.filter { $0.kind == .post }
        case .stories: app.drafts.libraryItems.filter { $0.kind == .story }
        case .inMail: app.drafts.libraryItems.filter { $0.kind == .inMail }
        case .reels: []
        }
    }

    var body: some View {
        List {
            if let error = app.drafts.saveError {
                Section {
                    Text(error)
                    Button("Retry Save") { app.drafts.flush() }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DraftLibraryFilter.allCases) { option in
                            Button(option.title) {
                                filter = option
                                HapticEngine.shared.play(.selection)
                            }
                            .font(.subheadline.weight(filter == option ? .semibold : .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .foregroundStyle(filter == option ? Color.white : Color.primary)
                            .background(filter == option ? Color(hex: "#D66056") : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                            .accessibilityAddTraits(filter == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            if filter == .reels {
                Section {
                    Text("Reel drafts aren’t stored on this device.")
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                Section {
                    ContentUnavailableView("No drafts", systemImage: "doc.text", description: Text("Unfinished posts, stories and letters appear here."))
                }
            } else {
                Section {
                    ForEach(items) { item in
                        DraftRow(item: item) {
                            continueDraft(kind: item.kind, id: item.id)
                        } onDelete: {
                            pendingDiscard = (item.kind, item.id)
                        }
                    }
                }
            }
            Section {
                Text("Drafts are saved automatically. They’re stored on this device. There isn’t a drafts API.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
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
            // Resume this exact draft (not always the primary one).
            app.drafts.pendingResumeID = id
            app.navigation.open(.messages(.inMail(.compose)))
        case .story:
            if app.stories.capabilities.create {
                app.drafts.pendingResumeID = id
                app.navigation.open(.stories(.create))
            } else {
                // Was a silent no-op.
                app.navigation.flash("Stories can’t be published yet. Your draft is kept.", symbol: "exclamationmark.circle")
            }
        }
    }
}

struct DraftRow: View {
    let item: DraftLibraryItem
    var onContinue: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onContinue) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: "#D66056"))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "#D66056").opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.preview)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text("Edited \(ModulaTimeFormat.short(item.lastEdited))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.mediaCount > 0 || item.audienceTitle != nil {
                        HStack(spacing: 8) {
                            if item.mediaCount > 0 {
                                Label("\(item.mediaCount) \(item.mediaCount == 1 ? "media item" : "media items")", systemImage: "photo")
                            }
                            if let audience = item.audienceTitle {
                                Label(audience, systemImage: "person.2")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) draft")
        .accessibilityValue("\(item.preview). Last edited \(ModulaTimeFormat.short(item.lastEdited))")
        .accessibilityHint("Continue draft")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Continue", action: onContinue)
                .tint(Color(hex: "#D66056"))
        }
        .contextMenu {
            Button("Continue", systemImage: "arrow.right.circle", action: onContinue)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var title: String {
        switch item.kind {
        case .post: "Post"
        case .inMail: "In-Mail"
        case .story: "Story"
        }
    }

    private var icon: String {
        switch item.kind {
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
