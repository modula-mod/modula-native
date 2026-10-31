import SwiftUI

struct CollectionsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showCreate = false
    @State private var newName = ""
    @State private var pendingDelete: ModulaCollection?

    var body: some View {
        List {
            if let error = app.collections.error { Text(error).foregroundStyle(.red) }
            Section {
                Text("Save posts on this iPhone. Collections aren’t synced — there isn’t a collections API.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(app.collections.collections.filter(\.isDefault)) { collection in
                    NavigationLink(value: AppRoute.collections(.collection(collection.id))) {
                        CollectionCard(collection: collection)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
                }
            }
            Section {
                ForEach(app.collections.userCollections) { collection in
                    NavigationLink(value: AppRoute.collections(.collection(collection.id))) {
                        CollectionCard(collection: collection)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
                }
                .onDelete(perform: delete)
            } footer: {
                Text(app.collections.capabilities.serverCollections
                     ? "Collections sync with your account."
                     : "Saved on this iPhone only.")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                    HapticEngine.shared.play(.contextOpen)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Collection")
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = app.collections.error {
                        Text(error).foregroundStyle(.red)
                    }
                    TextField("Collection name", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Label("Stored on this iPhone", systemImage: "iphone")
                        .font(.subheadline.weight(.semibold))
                    Text("Collections stay on this device. There isn’t a collections API, so they aren’t synced.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(20)
                .modulaCanvas()
                .navigationTitle("New Collection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            guard app.collections.create(name: newName) != nil else { return }
                            newName = ""
                            showCreate = false
                            HapticEngine.shared.play(.confirmation)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#D66056"))
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete “\($0.name)”?" } ?? "Delete collection?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let collection = pendingDelete { app.collections.delete(id: collection.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The saved posts themselves aren’t deleted.")
        }
        .modulaCanvas()
        .accessibilityIdentifier("collections.root")
    }

    /// Swipe-to-delete asks first; deleting a collection can't be undone.
    private func delete(at offsets: IndexSet) {
        let deletable = app.collections.userCollections
        guard let index = offsets.first, index < deletable.count else { return }
        pendingDelete = deletable[index]
        HapticEngine.shared.play(.warning)
    }
}

struct CollectionDetailView: View {
    let collectionID: String
    @Environment(AppEnvironment.self) private var app
    @State private var posts: [SocialPostID: SocialPost] = [:]
    @State private var unavailable: Set<SocialPostID> = []

    var body: some View {
        Group {
            if let collection = app.collections.collections.first(where: { $0.id == collectionID }) {
                List {
                    Section {
                        Text(collection.storage == .local ? "Saved on this iPhone only." : "Collections stay on this iPhone. They aren’t synced.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Posts") {
                        if collection.itemIDs.isEmpty {
                            Text("No posts yet. Save a post to this collection from its … menu.")
                                .foregroundStyle(.secondary)
                        } else {
                            // Render the saved posts instead of their raw IDs.
                            ForEach(collection.itemIDs, id: \.self) { id in
                                row(for: id)
                            }
                            .onDelete { offsets in
                                for index in offsets where collection.itemIDs.indices.contains(index) {
                                    app.collections.remove(postID: collection.itemIDs[index], from: collection.id)
                                }
                                HapticEngine.shared.play(.warning)
                            }
                        }
                    }
                }
                .modulaSoftScrollEdge()
                .modulaCanvas()
                .navigationTitle(collection.name)
                .task(id: collection.itemIDs) { await loadPosts(collection.itemIDs) }
            } else {
                ModulaEmptyState(title: "Collection", message: "This collection is no longer available.", symbol: "rectangle.stack")
            }
        }
        .accessibilityIdentifier("collections.detail")
    }

    @ViewBuilder
    private func row(for id: SocialPostID) -> some View {
        if let post = posts[id] {
            let resolved = app.posts.resolved(post)
            Button {
                app.navigation.push(.post(resolved.id, .root))
                HapticEngine.shared.play(.navigation)
            } label: {
                HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                    if let author = resolved.author {
                        ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 36)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resolved.author?.displayName ?? "Post")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(ActivityRelativeTime.string(from: resolved.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let text = resolved.text, !text.isEmpty {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        } else if !resolved.media.isEmpty {
                            Label("Photo or video", systemImage: "photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: ModulaLayout.minimumTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the post")
            .accessibilityIdentifier("collections.post.\(id)")
        } else if unavailable.contains(id) {
            Label("This post is no longer available", systemImage: "exclamationmark.bubble")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: ModulaLayout.minimumTouch)
        } else {
            HStack(spacing: ModulaSpacing.xs) {
                ProgressView()
                Text("Loading post…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .accessibilityElement(children: .combine)
        }
    }

    private func loadPosts(_ ids: [SocialPostID]) async {
        for id in ids where posts[id] == nil && !unavailable.contains(id) {
            guard !Task.isCancelled else { return }
            do {
                posts[id] = try await app.postActions.loadPost(id: id)
            } catch {
                if Task.isCancelled { return }
                unavailable.insert(id)
            }
        }
    }
}

struct CollectionCard: View {
    let collection: ModulaCollection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.isDefault ? "bookmark.fill" : "rectangle.stack")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: "#D66056"))
                .frame(width: 36, height: 36)
                .background(Color(hex: "#D66056").opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.body.weight(.semibold))
                Text("\(collection.itemCount) \(collection.itemCount == 1 ? "item" : "items") · \(collection.storage == .local ? "On This Device" : "On your account")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(collection.isDefault ? "Smart Collection" : "My Collection")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "#D66056"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#D66056").opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items, \(collection.storage == .local ? "on this device" : "on your account")")
    }
}

struct CollectionPicker: View {
    let postID: String
    var onDone: (() -> Void)?
    @Environment(AppEnvironment.self) private var app
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error = app.collections.error { Text(error).foregroundStyle(.red) }
                Section("Collections") {
                    ForEach(app.collections.collections.filter { !$0.isDefault }) { collection in
                        Button {
                            guard app.collections.add(postID: postID, to: collection.id) else { return }
                            HapticEngine.shared.play(.confirmation)
                            onDone?()
                            dismiss()
                        } label: {
                            CollectionCard(collection: collection)
                        }
                    }
                }
                Section("New Collection") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") {
                            if let created = app.collections.create(name: newName) {
                                guard app.collections.add(postID: postID, to: created.id) else { return }
                                newName = ""
                                HapticEngine.shared.play(.confirmation)
                                onDone?()
                                dismiss()
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Stored on this iPhone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Save to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("collections.picker")
    }
}
