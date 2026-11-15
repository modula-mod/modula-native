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
                Text("Named collections sync with your Modula account. A private on-device cache keeps them responsive when you’re offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(app.collections.collections.filter(\.isDefault)) { collection in
                    NavigationLink(value: AppRoute.saved(.root)) {
                        CollectionCard(collection: collection, itemCountOverride: app.saved.posts.count)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection.name), \(app.saved.posts.count) saved items")
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
        .refreshable { await app.collections.refresh() }
        .task {
            await app.collections.refresh()
            await app.saved.load()
        }
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
                    Label("Saved locally, synced to your account", systemImage: "checkmark.icloud")
                        .font(.subheadline.weight(.semibold))
                    Text("If you’re offline, the collection is queued and replays safely after sign-in and connectivity return.")
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
    @State private var showRename = false
    @State private var renameName = ""

    var body: some View {
        Group {
            if let collection = app.collections.collections.first(where: { $0.id == collectionID }) {
                List {
                    Section {
                        Text(collection.isDefault ? "Your existing Saved posts remain server-backed." : syncDescription(collection.syncState))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if collection.syncState == .conflict {
                        Section("Sync conflict") {
                            Text("This collection changed on another device. The local cache has not overwritten it.")
                                .foregroundStyle(.secondary)
                            Button("Use Server Collection") {
                                Task { await app.collections.resolveConflictUsingServer(id: collection.id) }
                            }
                        }
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
                .toolbar {
                    if !collection.isDefault {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Rename", systemImage: "pencil") {
                                renameName = collection.name
                                showRename = true
                            }
                        }
                    }
                }
                .alert("Rename Collection", isPresented: $showRename) {
                    TextField("Collection name", text: $renameName)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { app.collections.rename(id: collection.id, name: renameName) }
                        .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: {
                    Text("The new name syncs to your Modula account.")
                }
                .task(id: collection.itemIDs) { await loadPosts(collection.itemIDs) }
                // Enhancements-50: pull to re-fetch every saved post from Greenfield.
                .modulaRefreshable {
                    await app.collections.refresh()
                    await MainActor.run {
                        unavailable.removeAll()
                        posts.removeAll()
                    }
                    await loadPosts(collection.itemIDs)
                }
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
            // Enhancements-50: long-press and swipe shortcuts for the two real row actions.
            .contextMenu {
                Button("Open Post", systemImage: "arrow.up.forward.square") {
                    app.navigation.push(.post(resolved.id, .root))
                }
                Button("Remove from Collection", systemImage: "minus.circle", role: .destructive) {
                    app.collections.remove(postID: id, from: collectionID)
                    HapticEngine.shared.play(.warning)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                    app.collections.remove(postID: id, from: collectionID)
                    HapticEngine.shared.play(.warning)
                }
            }
        } else if unavailable.contains(id) {
            Label("This post is no longer available", systemImage: "exclamationmark.bubble")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: ModulaLayout.minimumTouch)
        } else {
            ModulaSkeletonRow()
                .frame(minHeight: ModulaLayout.minimumTouch)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading post")
        }
    }

    /// Enhancements-50: fetch in parallel batches of 4 instead of one-by-one.
    private func loadPosts(_ ids: [SocialPostID]) async {
        let pending = ids.filter { posts[$0] == nil && !unavailable.contains($0) }
        var index = 0
        while index < pending.count {
            guard !Task.isCancelled else { return }
            let batch = Array(pending[index..<min(index + 4, pending.count)])
            index += batch.count
            let fetches = batch.map { id in
                Task { @MainActor in (id, try? await app.postActions.loadPost(id: id)) }
            }
            for fetch in fetches {
                let (id, post) = await fetch.value
                if let post { posts[id] = post } else if !Task.isCancelled { unavailable.insert(id) }
            }
        }
    }

    private func syncDescription(_ state: CollectionSyncState) -> String {
        switch state {
        case .synced: "Synced with your Modula account."
        case .pending: "Saved locally · waiting to sync."
        case .conflict: "A newer server version needs your review."
        case .failed: "The last sync failed. Pull to retry."
        case .localOnly: "Stored in the private on-device cache."
        }
    }
}

struct CollectionCard: View {
    let collection: ModulaCollection
    var itemCountOverride: Int? = nil

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
                Text("\(itemCount) \(itemCount == 1 ? "item" : "items") · \(status)")
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
        .accessibilityLabel("\(collection.name), \(itemCount) saved items, \(status)")
    }

    private var itemCount: Int { itemCountOverride ?? collection.itemCount }

    private var status: String {
        if collection.isDefault { return "Saved" }
        switch collection.syncState {
        case .synced: "Synced"
        case .pending: "Waiting to sync"
        case .conflict: "Conflict"
        case .failed: "Sync failed"
        case .localOnly: "On this device"
        }
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
                    Text("Saved locally and synced to your account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .modulaSoftScrollEdge()
            .task { await app.collections.refresh() }
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
