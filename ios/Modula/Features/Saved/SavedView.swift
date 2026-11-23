import SwiftUI

struct SavedView: View {
    var section: SavedSection = .root
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""
    @State private var folder: String?
    @State private var newFolderFor: String?? = nil
    @State private var newFolderName = ""
    @State private var renaming: String?
    private var folders: SavedFolderStore { SavedFolderStore.shared }

    var body: some View {
        Group {
            if showsPosts, app.saved.backendListOpen {
                ModulaEmptyState(
                    title: "Saved",
                    message: "Saved posts aren’t available from this account yet.",
                    symbol: "bookmark"
                )
            } else if showsPosts, (!app.saved.loaded || app.saved.loading) && app.saved.posts.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 92)
                        }
                    }
                    .padding(.horizontal, 16)
                    .redacted(reason: .placeholder)
                }
                .scrollDisabled(true)
                .accessibilityLabel("Loading saved posts")
            } else if showsPosts, let error = app.saved.error, app.saved.posts.isEmpty {
                ModulaErrorState(message: error) {
                    Task { await app.saved.load(force: true) }
                }
            } else {
                savedList
            }
        }
        .modulaCanvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("saved.root")
        .task { await app.saved.load() }
        .modulaRefreshable { await app.saved.load(force: true) }
    }

    private var showsPosts: Bool { section == .root || section == .posts }
    private var showsModules: Bool { section == .root || section == .modules }
    private var showsLinks: Bool { section == .root || section == .links }

    private var savedList: some View {
        List {
            Section {
                Text("Saved posts load from your account. Modules and links can’t be saved yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsPosts, !app.saved.posts.isEmpty { folderRail }
            if showsPosts { postsSection }
            if showsModules { unavailableSection("Modules", "Saved modules aren’t available. There’s no saved-modules route.") }
            if showsLinks { unavailableSection("Links & Media", "Saved links aren’t available. There’s no saved-links route.") }
        }
        .listStyle(.insetGrouped)
        .modulaSoftScrollEdge()
        // Local filter over the loaded saved posts (text and author), no extra requests.
        .searchable(text: $query, prompt: "Search saved posts")
        .alert(renaming == nil ? "New Folder" : "Rename Folder", isPresented: Binding(
            get: { newFolderFor != nil || renaming != nil },
            set: { if !$0 { newFolderFor = nil; renaming = nil } }
        )) {
            TextField("Folder name", text: $newFolderName)
            Button(renaming == nil ? "Create" : "Save") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                withAnimation(.snappy) {
                    if let old = renaming {
                        folders.rename(old, to: name)
                        if folder == old { folder = String(name.prefix(32)) }
                    } else {
                        folders.create(name)
                        if case .some(.some(let postID)) = newFolderFor { folders.assign(postID, to: name) }
                    }
                }
                HapticEngine.shared.play(.success)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Folders are kept on this iPhone.")
        }
    }

    /// Bookmark folders (on this iPhone; the saved-posts API has no folders).
    private var folderRail: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    folderChip(nil, title: "All", count: app.saved.posts.count)
                    ForEach(folders.folders, id: \.self) { name in
                        folderChip(name, title: name, count: folders.count(in: name, among: app.saved.posts.map(\.id)))
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { newFolderName = name; renaming = name }
                                Button("Delete Folder", systemImage: "trash", role: .destructive) {
                                    withAnimation(.snappy) { folders.delete(name); if folder == name { folder = nil } }
                                }
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Button { newFolderName = ""; newFolderFor = .some(nil) } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .selection))
                    .accessibilityIdentifier("saved.folder.new")
                }
                .padding(.vertical, 2)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: folders.folders)
            }
            .scrollClipDisabled()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    private func folderChip(_ name: String?, title: String, count: Int) -> some View {
        let on = folder == name
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { folder = name }
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: name == nil ? "bookmark.fill" : (on ? "folder.fill" : "folder"))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).lineLimit(1)
                Text("\(count)").monospacedDigit().foregroundStyle(on ? Color.modulaOnPrimary.opacity(0.7) : .secondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.modulaOnPrimary : .primary)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background { if on { Capsule().fill(Color.modulaPrimaryFill) } }
            .modulaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("saved.folder.\(name ?? "all")")
    }

    private var filteredPosts: [SocialPost] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = folder.map { f in app.saved.posts.filter { folders.folder(of: $0.id) == f } } ?? app.saved.posts
        guard !q.isEmpty else { return base }
        return base.filter { post in
            let p = app.posts.resolved(post)
            return (p.text ?? "").localizedCaseInsensitiveContains(q)
                || (p.author?.displayName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var postsSection: some View {
        Section {
            if app.saved.posts.isEmpty && app.saved.loaded {
                Text("Bookmark a post and it will show up here.")
                    .foregroundStyle(.secondary)
            } else {
                let shown = filteredPosts
                if shown.isEmpty {
                    Text(query.isEmpty ? "Nothing in “\(folder ?? "")” yet. Long-press a saved post to move it here." : "No saved posts match “\(query)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, post in
                    SavedPostRow(post: app.posts.resolved(post), folder: folders.folder(of: post.id), folders: folders.folders, onMove: { target in
                        withAnimation(.snappy) { folders.assign(post.id, to: target) }
                        HapticEngine.shared.play(.success)
                    }, onNewFolder: {
                        newFolderName = ""; newFolderFor = .some(post.id)
                    }) {
                        Task { await app.saved.unsave(postID: post.id, postActions: app.postActions) }
                    }
                    // Light stagger for the first screenful only.
                    .modulaAppear(delay: Double(min(index, 8)) * 0.03)
                }
                if app.saved.hasMore, query.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await app.saved.loadMore() }
                }
            }
        } header: {
            HStack {
                Text("Posts")
                Spacer()
                Text(app.saved.posts.isEmpty ? "None yet" : "\(app.saved.posts.count) \(app.saved.posts.count == 1 ? "item" : "items")")
            }
        }
    }

    private func unavailableSection(_ title: String, _ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(.secondary)
        } header: {
            Text(title)
        }
    }

    private var title: String {
        switch section {
        case .root, .posts: "Saved"
        case .modules: "Saved Modules"
        case .links: "Saved Links"
        }
    }
}

private struct SavedPostRow: View {
    let post: SocialPost
    var folder: String? = nil
    var folders: [String] = []
    var onMove: (String?) -> Void = { _ in }
    var onNewFolder: () -> Void = {}
    var onUnsave: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            app.postActions.ingest(post)
            app.navigation.open(.post(post.id, .root))
            HapticEngine.shared.play(.navigation)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let author = post.author {
                    ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(post.author?.displayName ?? "Post")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(ActivityRelativeTime.string(from: post.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if let folder {
                            Label(folder, systemImage: "folder.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to Folder", systemImage: "folder") {
                ForEach(folders, id: \.self) { name in
                    Button(name, systemImage: name == folder ? "checkmark" : "folder") { onMove(name) }
                }
                Button("New Folder…", systemImage: "folder.badge.plus", action: onNewFolder)
                if folder != nil {
                    Button("Remove from Folder", systemImage: "folder.badge.minus") { onMove(nil) }
                }
            }
            Button("Unsave", systemImage: "bookmark.slash", role: .destructive, action: onUnsave)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Unsave", role: .destructive, action: onUnsave)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the saved post")
    }

    private var excerpt: String {
        if let text = post.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        if !post.media.isEmpty { return "Photo or video" }
        return "Saved post"
    }
}


/// Bookmark folders kept on this iPhone (post id → folder name). The saved-posts API has no folders.
@MainActor @Observable
final class SavedFolderStore {
    static let shared = SavedFolderStore()
    private static let key = "saved.folders.v1"
    private struct Snapshot: Codable { var folders: [String]; var assignments: [String: String] }

    private(set) var folders: [String] = []
    private(set) var assignments: [String: String] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            folders = snap.folders; assignments = snap.assignments
        }
    }

    func folder(of postID: String) -> String? { assignments[postID] }
    func count(in folder: String, among ids: [String]) -> Int { ids.reduce(0) { $0 + (assignments[$1] == folder ? 1 : 0) } }

    func create(_ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !n.isEmpty, !folders.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        folders.append(n); save()
    }

    func assign(_ postID: String, to folder: String?) {
        if let folder {
            let n = String(folder.prefix(32))
            if !folders.contains(n) { folders.append(n) }
            assignments[postID] = n
        } else { assignments[postID] = nil }
        save()
    }

    func rename(_ old: String, to new: String) {
        let n = String(new.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !n.isEmpty, let i = folders.firstIndex(of: old) else { return }
        if folders.contains(n), n != old { return }
        folders[i] = n
        for (k, v) in assignments where v == old { assignments[k] = n }
        save()
    }

    func delete(_ name: String) {
        folders.removeAll { $0 == name }
        assignments = assignments.filter { $0.value != name }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Snapshot(folders: folders, assignments: assignments)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
