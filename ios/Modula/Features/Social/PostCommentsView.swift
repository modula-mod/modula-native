import PhotosUI
import SwiftUI
import UIKit
import Translation
import UniformTypeIdentifiers

@MainActor @Observable
final class PostCommentsStore {
    private let repository: GreenfieldPostRepository
    private let postState: PostStateStore
    let postID: SocialPostID

    private(set) var items: [SocialComment] = []
    private(set) var nextCursor: String?
    private(set) var hasMore = false
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isSending = false
    /// Autosaved per post so an unsent comment survives closing the sheet or the app.
    var draft = "" { didSet { UserDefaults.standard.set(draft.isEmpty ? nil : draft, forKey: draftKey) } }
    var composerError: String?
    var replyingTo: SocialComment?
    var quoting: SocialComment?
    private(set) var hashtagSuggestions: [String] = []
    private var hashtagTask: Task<Void, Never>?
    /// Handle of the post's author (pinning is theirs).
    private(set) var postAuthorHandle: String?
    private var draftKey: String { "comments.draft.\(postID)" }
    /// Photos/videos (uploading or uploaded) and GIFs queued for the next comment.
    private(set) var pendingMedia: [PendingCommentMedia] = []
    private(set) var mentionSuggestions: [ModulaComposerMention] = []
    private let client: GreenfieldClient
    private var mentionTask: Task<Void, Never>?
    static let characterLimit = 5000
    private(set) var loadingReplies: Set<SocialCommentID> = []
    private(set) var expandedReplies: Set<SocialCommentID> = []

    init(client: GreenfieldClient, postState: PostStateStore, postID: SocialPostID, capabilities: PostBackendCapabilities = .production) {
        self.repository = GreenfieldPostRepository(client: client, capabilities: capabilities)
        self.client = client
        self.postState = postState
        self.postID = postID
        self.draft = UserDefaults.standard.string(forKey: "comments.draft.\(postID)") ?? ""
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            let page = try await repository.comments(postID: postID, cursor: nil)
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            isLoading = false
            if postAuthorHandle == nil, let post = try? await repository.post(id: postID) {
                postAuthorHandle = post.author?.handle
            }
            // Settings → Feed → "Expand reply threads": open the first few threads.
            if ModulaPreferences.feedShowReplyThreads {
                for comment in Self.threadsToExpand(page.items) {
                    await loadReplies(for: comment)
                }
            }
        } catch let api as APIError {
            loadError = api.userFacingMessage
            isLoading = false
        } catch {
            loadError = "Couldn't load comments."
            isLoading = false
        }
    }

    func loadMore() async {
        guard hasMore || nextCursor != nil, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await repository.comments(postID: postID, cursor: cursor)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            isLoadingMore = false
        } catch {
            isLoadingMore = false
            loadError = (error as? APIError)?.userFacingMessage ?? "Couldn't load more comments."
        }
    }

    func send(parentID: SocialCommentID? = nil) async -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = pendingMedia.compactMap(\.payload)
        guard !text.isEmpty || !media.isEmpty, !isSending, pendingMedia.allSatisfy(\.isReady) else { return false }
        isSending = true
        composerError = nil
        do {
            let parent = parentID ?? replyingTo.map { $0.parentID ?? $0.id }
            let comment = try await repository.createComment(postID: postID, text: text, parentID: parent, media: media, quotedCommentID: quoting?.id)
            pendingMedia = []
            quoting = nil
            items.insert(comment, at: 0)
            if let parent { expandedReplies.insert(parent) }
            draft = ""
            replyingTo = nil
            postState.adjustReplyCount(postID: postID, delta: 1)
            isSending = false
            HapticEngine.shared.play(.success)
            return true
        } catch {
            // Preserve draft on failure.
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn't send comment."
            isSending = false
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    // MARK: Comment media (real uploads through /v1/attachments)

    func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(max(0, 4 - pendingMedia.count)) {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            guard var data = try? await item.loadTransferable(type: Data.self) else {
                composerError = "That photo couldn’t be read."
                continue
            }
            var type = item.supportedContentTypes.first(where: { $0.conforms(to: isVideo ? .movie : .image) }) ?? (isVideo ? .mpeg4Movie : .jpeg)
            if !isVideo, let prepared = try? await CreationStudioStore.preparePhotoForUpload(data, type: type) {
                data = prepared.data
                type = .jpeg
            }
            await upload(data: data, type: type, kind: isVideo ? .video : .image)
        }
    }

    func addCameraImage(_ image: UIImage) async {
        guard pendingMedia.count < 4, let data = image.jpegData(compressionQuality: 0.86) else { return }
        await upload(data: data, type: .jpeg, kind: .image)
    }

    /// Pasted or dropped image data.
    func addImageData(_ data: Data) async {
        guard pendingMedia.count < 4, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) else {
            composerError = "Only images can be added here."
            return
        }
        await upload(data: jpeg, type: .jpeg, kind: .image)
    }

    func addSticker(_ sticker: ModulaSticker) {
        guard pendingMedia.count < 4 else { return }
        pendingMedia.append(PendingCommentMedia(id: "sticker:\(sticker.id):\(UUID().uuidString.prefix(4))", kind: .sticker, sticker: sticker))
    }

    func addPoll(question: String, options: [String], hours: Int?) {
        guard pendingMedia.count < 4, !pendingMedia.contains(where: { $0.kind == .poll }) else {
            composerError = "One poll per comment."
            return
        }
        pendingMedia.append(PendingCommentMedia(id: "poll:\(UUID().uuidString)", kind: .poll, poll: .init(question: question, options: options, hours: hours)))
    }

    func addLocation(latitude: Double, longitude: Double, name: String?) {
        pendingMedia.removeAll { $0.kind == .location }
        guard pendingMedia.count < 4 else { return }
        pendingMedia.append(PendingCommentMedia(id: "location:\(UUID().uuidString)", kind: .location, location: .init(latitude: latitude, longitude: longitude, name: name)))
        HapticEngine.shared.play(.success)
    }

    func addVoiceNote(_ note: ModulaVoiceNote) async {
        guard pendingMedia.count < 4, let data = try? Data(contentsOf: note.fileURL) else { return }
        await upload(data: data, type: .mpeg4Audio, kind: .voice, fileName: "Voice note.m4a", voice: note)
    }

    func addFile(_ url: URL) async {
        guard pendingMedia.count < 4 else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            composerError = "That file couldn’t be read."
            return
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        await upload(data: data, type: type, kind: .file, fileName: url.lastPathComponent)
    }

    func addGif(_ gif: ModulaGif) {
        guard pendingMedia.count < 4 else { return }
        pendingMedia.append(PendingCommentMedia(id: "gif:\(gif.id)", kind: .gif, previewURL: gif.previewURL, gif: gif))
        HapticEngine.shared.play(.selection)
    }

    func removeMedia(id: String) {
        pendingMedia.removeAll { $0.id == id }
    }

    private func upload(data: Data, type: UTType, kind: PendingCommentMedia.Kind, fileName: String? = nil, voice: ModulaVoiceNote? = nil) async {
        let id = UUID().uuidString
        let isVideo = kind == .video
        var mimeType = type.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        if kind == .voice { mimeType = "audio/mp4" }
        let filename = fileName ?? "\(id).\(type.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg"))"
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(filename)")
        try? data.write(to: localURL, options: .atomic)
        var pending = PendingCommentMedia(id: id, kind: kind, previewURL: kind == .image ? localURL : nil, progress: 0)
        pending.fileName = fileName
        pending.voice = voice
        pendingMedia.append(pending)
        let creationKind: CreationMedia.Kind = switch kind {
        case .video: .video
        case .voice: .audio
        case .file: mimeType == "application/pdf" ? .pdf : (mimeType.hasPrefix("audio/") ? .audio : .document)
        default: .image
        }
        let uploader = GreenfieldMediaUploader(client: client)
        let media = PreparedMedia(id: id, kind: creationKind, data: data, mimeType: mimeType, filename: filename, altText: "")
        do {
            let uploaded = try await uploader.upload(media, progress: { value in
                Task { @MainActor [weak self] in self?.setProgress(id: id, value) }
            }, sessionCreated: { _, _ in })
            if let index = pendingMedia.firstIndex(where: { $0.id == id }) {
                pendingMedia[index].attachmentID = uploaded.remoteID
                pendingMedia[index].progress = nil
            }
        } catch {
            if let index = pendingMedia.firstIndex(where: { $0.id == id }) {
                pendingMedia[index].failed = true
                pendingMedia[index].progress = nil
            }
            composerError = (error as? APIError)?.userFacingMessage ?? "Upload failed. Remove it and try again."
            HapticEngine.shared.play(.failure)
        }
    }

    private func setProgress(id: String, _ value: Double) {
        guard let index = pendingMedia.firstIndex(where: { $0.id == id }), pendingMedia[index].attachmentID == nil else { return }
        pendingMedia[index].progress = min(max(value, 0), 0.99)
    }

    // MARK: Mentions (Greenfield profile search)

    func updateMentionQuery(_ query: String?) {
        mentionTask?.cancel()
        guard let query, !query.isEmpty else { mentionSuggestions = []; return }
        mentionTask = Task { [client] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
            guard let value = try? await client.json("GET", path: "/v1/search?q=\(escaped)&entityType=profile&limit=6") else { return }
            let people = DiscoverPayloadDecoder.searchPage(from: value).results.compactMap(\.person)
            guard !Task.isCancelled else { return }
            mentionSuggestions = people.map {
                ModulaComposerMention(id: $0.id, handle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL)
            }
        }
    }

    // MARK: Hashtags (Greenfield suggest)

    func updateHashtagQuery(_ query: String?) {
        hashtagTask?.cancel()
        guard let query, !query.isEmpty else { hashtagSuggestions = []; return }
        hashtagTask = Task { [client] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
            guard let value = try? await client.authenticatedJSON("GET", path: "/v1/hashtags/suggest?q=\(escaped)") else { return }
            guard !Task.isCancelled else { return }
            hashtagSuggestions = (value["items"]?.array ?? []).compactMap { $0["tag"]?.string }.filter { $0 != query.lowercased() }
        }
    }

    // MARK: Reactions, polls, pins, reports

    func react(_ comment: SocialComment, type: String) async {
        guard let index = items.firstIndex(where: { $0.id == comment.id }) else { return }
        let previous = items[index]
        let removing = previous.viewerReaction == type
        var updated = previous
        var counts = Dictionary(uniqueKeysWithValues: previous.reactions.map { ($0.type, $0.count) })
        if let old = previous.viewerReaction { counts[old] = max(0, (counts[old] ?? 1) - 1) }
        if !removing { counts[type, default: 0] += 1 }
        updated.reactions = counts.filter { $0.value > 0 }.map { CommentReactionCount(type: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        updated.viewerReaction = removing ? nil : type
        updated.liked = updated.viewerReaction == "like"
        updated.likeCount = counts["like"] ?? 0
        items[index] = updated
        do {
            try await repository.setCommentReaction(commentID: comment.id, type: removing ? nil : type)
        } catch {
            if let index = items.firstIndex(where: { $0.id == comment.id }) { items[index] = previous }
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t react. Sign in and try again."
            HapticEngine.shared.play(.failure)
        }
    }

    func vote(_ comment: SocialComment, option: Int?) async {
        do {
            if let fresh = try await repository.voteCommentPoll(commentID: comment.id, postID: postID, option: option),
               let index = items.firstIndex(where: { $0.id == comment.id }) {
                items[index].media = fresh.media
            }
            HapticEngine.shared.play(.success)
        } catch {
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t vote."
            HapticEngine.shared.play(.failure)
        }
    }

    func setPinned(_ comment: SocialComment, pinned: Bool) async {
        do {
            _ = try await repository.setCommentPinned(commentID: comment.id, postID: postID, pinned: pinned)
            for index in items.indices { items[index].pinned = pinned && items[index].id == comment.id }
            items.sort { lhs, rhs in lhs.pinned && !rhs.pinned }
            HapticEngine.shared.play(.confirmation)
        } catch {
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t pin this comment."
            HapticEngine.shared.play(.failure)
        }
    }

    func report(_ comment: SocialComment, category: String) async {
        do {
            try await repository.reportComment(commentID: comment.id, category: category)
            HapticEngine.shared.play(.success)
            composerError = nil
        } catch {
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t send report."
        }
    }

    nonisolated static func threadsToExpand(_ comments: [SocialComment], limit: Int = 3) -> [SocialComment] {
        Array(comments.filter { $0.parentID == nil && $0.replyCount > 0 }.prefix(limit))
    }

    func loadReplies(for comment: SocialComment) async {
        guard loadingReplies.insert(comment.id).inserted else { return }
        defer { loadingReplies.remove(comment.id) }
        do {
            let replies = try await repository.replies(commentID: comment.id, postID: postID)
            items.removeAll { $0.parentID == comment.id }
            items.append(contentsOf: replies)
            expandedReplies.insert(comment.id)
            composerError = nil
        } catch {
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t load replies. Try again."
        }
    }

    func delete(_ comment: SocialComment) async {
        do {
            try await repository.deleteComment(commentID: comment.id)
            items.removeAll { $0.id == comment.id }
            postState.adjustReplyCount(postID: postID, delta: -1)
            HapticEngine.shared.play(.success)
        } catch {
            composerError = (error as? APIError)?.userFacingMessage ?? "Couldn't delete comment."
            HapticEngine.shared.play(.failure)
        }
    }
}

struct PostCommentsView: View {
    let postID: SocialPostID
    var isSheet: Bool = false
    var onClose: (() -> Void)? = nil
    // Detail supplies its identity/content here so conversation shares one scroll surface.
    var header: AnyView? = nil

    @Environment(AppEnvironment.self) private var app
    @State private var store: PostCommentsStore?
    @FocusState private var composerFocused: Bool
    @State private var mediaPanelActive = false
    @State private var mediaPanelTab: ModulaComposerMediaPanel.Tab = .emoji
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPollCreator = false
    @State private var showsFileImporter = false
    @State private var locating = false
    @State private var revealedSpoilers: Set<SocialCommentID> = []
    @State private var translating: String?
    @State private var swipeOffsets: [SocialCommentID: CGFloat] = [:]
    @State private var dropTargeted = false
    @State private var menuComment: SocialComment?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if isSheet {
                conversationHeader
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let header { header }
                    if !isSheet { conversationHeader }
                    content
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, isSheet ? 12 : 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .modulaSoftScrollEdge()
            // Drag images in from other apps (iPad split view / iPhone drag between apps).
            .dropDestination(for: Data.self) { items, _ in
                guard let store, !items.isEmpty else { return false }
                Task { for data in items.prefix(4) { await store.addImageData(data) } }
                HapticEngine.shared.play(.success)
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(app.appearance.accent.color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .overlay {
            if let comment = menuComment, let store {
                CommentActionOverlay(
                    comment: comment,
                    viewerReaction: comment.viewerReaction,
                    onReact: { type in Task { await store.react(comment, type: type) } },
                    onDismiss: { withAnimation(.easeOut(duration: 0.18)) { menuComment = nil } }
                ) {
                    commentMenu(comment, store: store)
                }
                .transition(.opacity)
            }
        }
        .modulaCanvas()
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, maxSelectionCount: 4, matching: .any(of: [.images, .videos]))
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await store?.addPhotos(items) }
        }
        .sheet(isPresented: $showsPollCreator) {
            CommentPollCreator { question, options, hours in store?.addPoll(question: question, options: options, hours: hours) }
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .plainText, .rtf, .zip, .audio, .data], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await store?.addFile(url) }
        }
        .translationPresentation(isPresented: Binding(get: { translating != nil }, set: { if !$0 { translating = nil } }), text: translating ?? "")
        .fullScreenCover(isPresented: $showsCamera) {
            CommentCameraPicker { image in Task { await store?.addCameraImage(image) } }
                .ignoresSafeArea()
        }
        .task(id: postID) {
            let created = PostCommentsStore(
                client: app.client,
                postState: app.posts,
                postID: postID,
                capabilities: app.postActions.capabilities
            )
            store = created
            await created.load()
            #if DEBUG
            switch DebugSettingsHarness.composerState {
            case "stickers": mediaPanelTab = .stickers; mediaPanelActive = true
            case "poll": showsPollCreator = true
            case "menu":
                try? await Task.sleep(for: .milliseconds(600))
                menuComment = created.items.first
            case "format":
                created.draft = "Shipping **rich comments** with ||spoilers|| and `code` #modula"
                composerFocused = true
            default: break
            }
            #endif
        }
        .accessibilityIdentifier(isSheet ? "post.comments.sheet" : "post.comments")
        #if DEBUG
        .onAppear {
            if DebugSettingsHarness.composerState == "gifs" {
                mediaPanelTab = .gifs
                mediaPanelActive = true
            }
        }
        #endif
    }

    private var conversationHeader: some View {
        HStack(spacing: 8) {
            Text("Comments").font(.headline)
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close comments")
            }
        }
        .padding(.horizontal, isSheet ? ModulaLayout.contentInset : 0)
        .padding(.top, isSheet ? 20 : 8)
        .padding(.bottom, isSheet ? 8 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            if store.isLoading && store.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if let loadError = store.loadError, store.items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load comments.", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") {
                        Task { await store.load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("post.comments.error")
            } else if store.items.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3).foregroundStyle(app.appearance.accent.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start the conversation").font(.subheadline.weight(.semibold))
                        Text("Be the first to leave a comment.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(roots(store.items)) { comment in
                        commentRow(comment, store: store)
                        let replies = store.items.filter { $0.parentID == comment.id }
                        if store.expandedReplies.contains(comment.id) {
                            ForEach(replies) { reply in
                                commentRow(reply, store: store, indented: true)
                            }
                        } else if comment.replyCount > 0 {
                            Button {
                                Task { await store.loadReplies(for: comment) }
                            } label: {
                                HStack(spacing: 8) {
                                    Rectangle().frame(width: 20, height: 1)
                                    Text("View \(comment.replyCount) replies")
                                    if store.loadingReplies.contains(comment.id) { ProgressView().controlSize(.mini) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(app.appearance.accent.color)
                                .padding(.leading, 42)
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.loadingReplies.contains(comment.id))
                        }
                    }
                    if store.hasMore {
                        Button("Load more") {
                            Task { await store.loadMore() }
                        }
                        .disabled(store.isLoadingMore)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func roots(_ items: [SocialComment]) -> [SocialComment] {
        items.filter { $0.parentID == nil }
    }

    private func commentRow(_ comment: SocialComment, store: PostCommentsStore, indented: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if indented {
                Color.clear.frame(width: 28)
            }
            if let author = comment.author {
                Button { openProfile(author.routeID) } label: {
                    ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(author.displayName)’s profile")
            } else {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                    Text(comment.author?.displayName ?? "Someone")
                        .font(.subheadline.weight(.semibold))
                    Text(ActivityRelativeTime.string(from: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if comment.isEdited {
                        Text("Edited").font(.caption2).foregroundStyle(.secondary)
                    }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.author?.displayName ?? "Someone").font(.subheadline.weight(.semibold))
                        Text(ActivityRelativeTime.string(from: comment.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let quoted = comment.quoted {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quoted.authorName ?? "Comment").font(.caption.weight(.semibold))
                        Text(quoted.deleted ? "Comment deleted" : quoted.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { Capsule().fill(app.appearance.accent.color).frame(width: 3) }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Quoting \(quoted.authorName ?? "a comment"): \(quoted.text)")
                }
                if !comment.text.isEmpty {
                    Text(ModulaRichText.attributed(comment.text, revealSpoilers: revealedSpoilers.contains(comment.id)))
                        .font(.body)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            guard ModulaRichText.hasSpoiler(comment.text) else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if revealedSpoilers.contains(comment.id) { revealedSpoilers.remove(comment.id) } else { revealedSpoilers.insert(comment.id) }
                            }
                            HapticEngine.shared.play(.selection)
                        }
                        .accessibilityHint(ModulaRichText.hasSpoiler(comment.text) ? "Contains a spoiler. Double-tap to reveal." : "")
                }
                if !comment.media.isEmpty {
                    CommentMediaContent(media: comment.media) { option in
                        Task { await store.vote(comment, option: option) }
                    }
                }
                if let url = ModulaLinkDetector.firstWebURL(in: comment.text), comment.media.isEmpty {
                    ModulaRichLinkCard(url: url, compact: true)
                }
                if !comment.reactions.isEmpty {
                    CommentReactionChips(reactions: comment.reactions, viewerReaction: comment.viewerReaction) { type in
                        Task { await store.react(comment, type: type) }
                    }
                }
                HStack(spacing: 18) {
                    Button("Reply") {
                        store.quoting = nil
                        store.replyingTo = comment
                        composerFocused = true
                    }
                    Button {
                        Task { await store.react(comment, type: "like") }
                        HapticEngine.shared.play(.lightImpact)
                    } label: {
                        Image(systemName: comment.viewerReaction == "like" ? "heart.fill" : "heart")
                            .foregroundStyle(comment.viewerReaction == "like" ? Color.red : Color.secondary)
                            .symbolEffect(.bounce, value: comment.viewerReaction == "like")
                    }
                    .accessibilityLabel(comment.viewerReaction == "like" ? "Unlike" : "Like")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if comment.pinned {
                Label("Pinned", systemImage: "pin.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        // Swipe left to reply (Telegram-style) with a haptic at the threshold.
        .background(alignment: .trailing) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.title3)
                .foregroundStyle(app.appearance.accent.color)
                .opacity(Double(min(abs(swipeOffsets[comment.id] ?? 0) / 64, 1)))
                .scaleEffect(min(abs(swipeOffsets[comment.id] ?? 0) / 64, 1))
                .padding(.trailing, 4)
        }
        .offset(x: swipeOffsets[comment.id] ?? 0)
        .simultaneousGesture(swipeToReply(comment, store: store))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Reply") { store.replyingTo = comment; composerFocused = true }
        .onLongPressGesture(minimumDuration: 0.35) {
            HapticEngine.shared.play(.actionConfirmed)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) { menuComment = comment }
        }
        .accessibilityAction(named: "More actions") { menuComment = comment }
    }

    private func isOwn(_ comment: SocialComment) -> Bool {
        comment.author?.handle.caseInsensitiveCompare(app.auth.account?.primaryHandle ?? "") == .orderedSame
    }

    private func swipeToReply(_ comment: SocialComment, store: PostCommentsStore) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.6, value.translation.width < 0 else { return }
                let offset = max(value.translation.width * 0.6, -90)
                let previous = swipeOffsets[comment.id] ?? 0
                if previous > -64 && offset <= -64 { HapticEngine.shared.play(.dragThreshold) }
                swipeOffsets[comment.id] = offset
            }
            .onEnded { _ in
                let triggered = (swipeOffsets[comment.id] ?? 0) <= -64
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.75)) {
                    swipeOffsets[comment.id] = nil
                }
                if triggered {
                    store.quoting = nil
                    store.replyingTo = comment
                    composerFocused = true
                }
            }
    }

    @ViewBuilder
    private func commentMenu(_ comment: SocialComment, store: PostCommentsStore) -> some View {
        Section {
            Button { menuComment = nil; store.quoting = nil; store.replyingTo = comment; composerFocused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            if comment.parentID == nil {
                Button { menuComment = nil; store.replyingTo = nil; store.quoting = comment; composerFocused = true } label: { Label("Quote", systemImage: "quote.opening") }
            }
            Button {
                UIPasteboard.general.string = comment.text
                HapticEngine.shared.play(.lightImpact)
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            if !comment.text.isEmpty {
                Button { menuComment = nil; translating = comment.text } label: { Label("Translate", systemImage: "translate") }
            }
        }
        Section {
            if comment.parentID == nil, let author = store.postAuthorHandle,
               author.caseInsensitiveCompare(app.auth.account?.primaryHandle ?? "") == .orderedSame {
                Button { menuComment = nil; Task { await store.setPinned(comment, pinned: !comment.pinned) } } label: {
                    Label(comment.pinned ? "Unpin" : "Pin", systemImage: comment.pinned ? "pin.slash" : "pin")
                }
            }
        }
        Section {
            if isOwn(comment) {
                Button(role: .destructive) { menuComment = nil; Task { await store.delete(comment) } } label: { Label("Delete", systemImage: "trash") }
            } else {
                Menu {
                    Button("Spam") { menuComment = nil; Task { await store.report(comment, category: "spam") } }
                    Button("Harassment") { menuComment = nil; Task { await store.report(comment, category: "harassment") } }
                    Button("Impersonation") { menuComment = nil; Task { await store.report(comment, category: "impersonation") } }
                    Button("Illegal content") { menuComment = nil; Task { await store.report(comment, category: "illegal-content") } }
                    Button("Something else") { menuComment = nil; Task { await store.report(comment, category: "other") } }
                } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                Button { menuComment = nil; muteAuthor(comment, store: store) } label: {
                    Label("Mute author", systemImage: "speaker.slash")
                }
            }
        }
    }

    /// Everything Greenfield comments accept: photos/videos and files (attachment pipeline),
    /// camera, GIFs (GIF proxy), first-party stickers, polls and a shared location.
    private var attachmentOptions: [ModulaComposerAttachmentOption] {
        var options = [ModulaComposerAttachmentOption(id: "photos", title: "Photos", systemImage: "photo.on.rectangle", tint: .blue)]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            options.append(ModulaComposerAttachmentOption(id: "camera", title: "Camera", systemImage: "camera.fill", tint: .gray))
        }
        options.append(ModulaComposerAttachmentOption(id: "gif", title: "GIF", systemImage: "play.square.stack.fill", tint: .purple))
        options.append(ModulaComposerAttachmentOption(id: "sticker", title: "Sticker", systemImage: "seal.fill", tint: .orange))
        options.append(ModulaComposerAttachmentOption(id: "poll", title: "Poll", systemImage: "chart.bar.fill", tint: .green))
        options.append(ModulaComposerAttachmentOption(id: "location", title: locating ? "Locating…" : "Location", systemImage: "location.fill", tint: .teal))
        options.append(ModulaComposerAttachmentOption(id: "file", title: "File", systemImage: "doc.fill", tint: .indigo))
        if UIPasteboard.general.hasImages {
            options.append(ModulaComposerAttachmentOption(id: "paste", title: "Paste", systemImage: "doc.on.clipboard.fill", tint: .pink))
        }
        return options
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let error = store?.composerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            ModulaComposer(
                text: Binding(
                    get: { store?.draft ?? "" },
                    set: { store?.draft = $0 }
                ),
                prompt: store?.replyingTo == nil ? "Add a comment…" : "Reply…",
                enabled: store != nil,
                sending: store?.isSending == true,
                attachments: store?.pendingMedia.map(\.composerAttachment) ?? [],
                showsAttachmentButton: true,
                externalFocus: Binding(
                    get: { composerFocused },
                    set: { composerFocused = $0 }
                ),
                avatar: app.auth.account.map { account in
                    ModulaComposerAvatar(
                        initials: String(account.displayName?.prefix(2) ?? account.primaryHandle.prefix(2)).uppercased(),
                        url: app.profile.ownProfile?.avatarURL
                    )
                },
                reply: store?.replyingTo.map { ModulaComposerReply(title: "Replying to \($0.author?.displayName ?? "comment")", excerpt: $0.text) }
                    ?? store?.quoting.map { ModulaComposerReply(title: "Quoting \($0.author?.displayName ?? "comment")", excerpt: $0.text) },
                onCancelReply: { store?.replyingTo = nil; store?.quoting = nil },
                attachmentOptions: attachmentOptions,
                onAttachmentOption: handleAttachmentOption,
                onRemoveAttachment: { store?.removeMedia(id: $0.id) },
                characterLimit: PostCommentsStore.characterLimit,
                mentionSuggestions: store?.mentionSuggestions ?? [],
                onMentionQuery: { store?.updateMentionQuery($0) },
                mediaPanelActive: Binding(
                    get: { mediaPanelActive },
                    set: { value in
                        if value { mediaPanelTab = .emoji }
                        mediaPanelActive = value
                    }
                ),
                hashtagSuggestions: store?.hashtagSuggestions ?? [],
                onHashtagQuery: { store?.updateHashtagQuery($0) },
                showsFormatting: true,
                onVoiceNote: { note in Task { await store?.addVoiceNote(note) } },
                onSend: { Task { _ = await store?.send() } }
            )
            .padding(.horizontal, 12)
            .accessibilityIdentifier("post.comment.composer")
            if mediaPanelActive {
                ModulaComposerMediaPanel(
                    client: app.client,
                    initialTab: mediaPanelTab,
                    onEmoji: { store?.draft.append($0) },
                    onGif: { gif in
                        store?.addGif(gif)
                        mediaPanelActive = false
                    },
                    onSticker: { sticker in
                        store?.addSticker(sticker)
                        mediaPanelActive = false
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, mediaPanelActive ? 0 : 8)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.85), value: mediaPanelActive)
        .gesture(
            DragGesture(minimumDistance: PostGestureThresholds.dragActivationDistance)
                .onEnded { value in
                    // Swipe up from comment bar expands sheet — sheet detents handle presentation.
                    guard value.translation.height < -PostGestureThresholds.commentSheetThreshold else { return }
                    let vertical = abs(value.translation.height)
                    let horizontal = abs(value.translation.width)
                    guard vertical > horizontal * PostGestureThresholds.verticalDominanceRatio else { return }
                    composerFocused = true
                    HapticEngine.shared.play(.dragThreshold)
                }
        )
        .accessibilityIdentifier("post.comment.bar")
    }

    private func handleAttachmentOption(_ option: ModulaComposerAttachmentOption) {
        switch option.id {
        case "photos": showsPhotoPicker = true
        case "camera": showsCamera = true
        case "gif", "sticker":
            composerFocused = false
            mediaPanelTab = option.id == "gif" ? .gifs : .stickers
            mediaPanelActive = true
        case "poll": showsPollCreator = true
        case "file": showsFileImporter = true
        case "paste":
            if let image = UIPasteboard.general.image, let data = image.pngData() {
                Task { await store?.addImageData(data) }
            }
        case "location":
            guard !locating else { return }
            locating = true
            Task {
                if let (coordinate, name) = await CommentLocation.current() {
                    store?.addLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name)
                } else {
                    store?.composerError = "Location isn’t available. Check Settings → Privacy → Location."
                }
                locating = false
            }
        default: break
        }
    }

    /// The sheet sits above the presenting stack, so pushing alone would land
    /// the profile *behind* the comments. Push on the underlying stack and
    /// dismiss the sheet in the same transaction so the profile is revealed.
    private func openProfile(_ id: String) {
        app.navigation.push(.profile(id, .overview))
        HapticEngine.shared.play(.navigation)
        if isSheet { onClose?() }
    }

    private func handleCommentAction(_ action: ModulaContextAction, comment: SocialComment, store: PostCommentsStore) {
        switch action.id {
        case "copy":
            UIPasteboard.general.string = comment.text
            HapticEngine.shared.play(.lightImpact)
        case "delete":
            Task { await store.delete(comment) }
        case "mute-author":
            muteAuthor(comment, store: store)
        default:
            break
        }
    }

    private func muteAuthor(_ comment: SocialComment, store: PostCommentsStore) {
        guard let author = comment.author else { return }
        do {
            Task {
                do {
                    try await GreenfieldProfileRepository(client: app.client).mute(profileID: author.id)
                    HapticEngine.shared.play(.confirmation)
                } catch {
                    store.composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t mute this author."
                }
            }
        }
    }
}

struct PostCommentsSheet: View {
    let postID: SocialPostID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDetent: ModulaSheetDetent = .medium

    /// The 30% compact detent leaves no room for header + composer on small
    /// phones (iPhone SE/mini) or at accessibility text sizes; drop it there.
    private var detents: [ModulaSheetDetent] {
        let screenHeight = UIScreen.main.bounds.height
        if screenHeight < 750 || dynamicTypeSize.isAccessibilitySize {
            return [.medium, .large]
        }
        return [.compact, .medium, .large]
    }

    var body: some View {
        ModulaSheet(detents: detents, selectedDetent: $selectedDetent) {
            PostCommentsView(postID: postID, isSheet: true, onClose: { dismiss() })
        }
    }
}


struct PendingCommentMedia: Identifiable, Equatable {
    enum Kind: Equatable { case image, video, gif, sticker, poll, location, voice, file }
    struct PollDraft: Equatable { var question: String; var options: [String]; var hours: Int? }
    struct LocationDraft: Equatable { var latitude: Double; var longitude: Double; var name: String? }
    let id: String
    let kind: Kind
    var previewURL: URL?
    var gif: ModulaGif? = nil
    var sticker: ModulaSticker? = nil
    var poll: PollDraft? = nil
    var location: LocationDraft? = nil
    var attachmentID: String? = nil
    var progress: Double? = nil
    var failed = false
    var fileName: String? = nil
    var voice: ModulaVoiceNote? = nil

    var isReady: Bool {
        if failed { return false }
        switch kind {
        case .gif: return gif != nil
        case .sticker, .poll, .location: return true
        default: return progress == nil && attachmentID != nil
        }
    }

    var payload: JSONValue? {
        switch kind {
        case .gif:
            guard let gif else { return nil }
            var item: [String: JSONValue] = [
                "type": .string("gif"), "provider": .string("giphy"), "id": .string(gif.id),
                "url": .string(gif.url.absoluteString), "previewUrl": .string(gif.previewURL.absoluteString)
            ]
            if let width = gif.width { item["width"] = .number(Double(width)) }
            if let height = gif.height { item["height"] = .number(Double(height)) }
            if let title = gif.title { item["title"] = .string(title) }
            return .object(item)
        case .sticker:
            guard let sticker else { return nil }
            return .object(["type": .string("sticker"), "stickerId": .string(sticker.id)])
        case .poll:
            guard let poll else { return nil }
            var item: [String: JSONValue] = ["type": .string("poll"), "question": .string(poll.question), "options": .array(poll.options.map { .string($0) })]
            if let hours = poll.hours { item["durationHours"] = .number(Double(hours)) }
            return .object(item)
        case .location:
            guard let location else { return nil }
            var item: [String: JSONValue] = ["type": .string("location"), "latitude": .number(location.latitude), "longitude": .number(location.longitude)]
            if let name = location.name { item["name"] = .string(name) }
            return .object(item)
        default:
            guard let attachmentID, !failed else { return nil }
            var item: [String: JSONValue] = ["type": .string("attachment"), "attachmentId": .string(attachmentID)]
            if let voice {
                item["voice"] = .object(["durationMs": .number(Double(voice.durationMs)), "waveform": .array(voice.waveform.map { .number(Double($0)) })])
            }
            return .object(item)
        }
    }

    var composerAttachment: ModulaComposerAttachment {
        let (title, symbol): (String, String) = switch kind {
        case .gif: ("GIF", "play.square.stack")
        case .video: ("Video", "video")
        case .image: ("Photo", "photo")
        case .sticker: (sticker?.emoji ?? "Sticker", "seal")
        case .poll: (poll?.question ?? "Poll", "chart.bar")
        case .location: (location?.name ?? "Location", "mappin.and.ellipse")
        case .voice: (voice.map { Duration.milliseconds($0.durationMs).formatted(.time(pattern: .minuteSecond)) } ?? "Voice", "waveform")
        case .file: (fileName ?? "File", "doc")
        }
        return ModulaComposerAttachment(id: id, title: title, systemImage: symbol, thumbnailURL: previewURL, progress: progress, failed: failed)
    }
}

/// Media on a posted comment: photos/GIFs inline, videos as a tappable still.
struct CommentMediaGrid: View {
    let media: [SocialCommentMedia]

    var body: some View {
        let columns = media.count == 1 ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(media) { item in
                ZStack {
                    ModulaAnimatedRemoteImage(url: item.kind == .gif ? (item.previewURL ?? item.url) : item.url)
                    if item.kind == .video {
                        Image(systemName: "play.fill").font(.title2).foregroundStyle(.white).shadow(radius: 4)
                    }
                    if item.kind == .gif {
                        Text("GIF").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(6)
                    }
                }
                .frame(height: columns == 1 ? min(220, 220 / max(item.aspectRatio ?? 1, 0.6) * (item.aspectRatio ?? 1)) : 120)
                .frame(maxWidth: columns == 1 ? 260 : .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(item.kind == .gif ? "GIF" : (item.kind == .video ? "Video" : "Photo"))
            }
        }
        .frame(maxWidth: columns == 1 ? 260 : .infinity, alignment: .leading)
    }
}

/// Minimal system camera capture for comments.
struct CommentCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CommentCameraPicker
        init(_ parent: CommentCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
