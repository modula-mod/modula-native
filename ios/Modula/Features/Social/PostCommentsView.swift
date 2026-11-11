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
    /// Top-level comments on the server's first page that this sheet hasn't shown yet.
    private(set) var newCommentCount = 0

    init(client: GreenfieldClient, postState: PostStateStore, postID: SocialPostID, capabilities: PostBackendCapabilities = .production) {
        self.repository = GreenfieldPostRepository(client: client, capabilities: capabilities)
        self.client = client
        self.postState = postState
        self.postID = postID
        self.draft = UserDefaults.standard.string(forKey: "comments.draft.\(postID)") ?? ""
    }

    /// Last first page per post (memory only) so reopening a sheet paints instantly,
    /// then refreshes in place.
    private static var firstPageCache: [SocialPostID: (items: [SocialComment], author: String?)] = [:]

    func load() async {
        if items.isEmpty, let cached = Self.firstPageCache[postID] {
            items = cached.items
            if postAuthorHandle == nil { postAuthorHandle = cached.author }
            isLoading = false
        } else {
            isLoading = items.isEmpty
        }
        loadError = nil
        do {
            // Comments and the post (for the author/pin rule) in parallel, not one after the other.
            let repository = self.repository
            let postID = self.postID
            let needsAuthor = postAuthorHandle == nil
            async let authorHandle: String? = needsAuthor ? (try? await repository.post(id: postID))?.author?.handle : nil
            let page = try await repository.comments(postID: postID, cursor: nil)
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            isLoading = false
            if needsAuthor, let handle = await authorHandle { postAuthorHandle = handle }
            Self.firstPageCache[postID] = (page.items, postAuthorHandle)
            if Self.firstPageCache.count > 24, let drop = Self.firstPageCache.keys.first(where: { $0 != postID }) {
                Self.firstPageCache[drop] = nil
            }
            // Settings → Feed → "Expand reply threads": open the first few threads together.
            if ModulaPreferences.feedShowReplyThreads {
                let threads = Self.threadsToExpand(page.items)
                await withTaskGroup(of: Void.self) { group in
                    for comment in threads {
                        group.addTask { await self.loadReplies(for: comment) }
                    }
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
        // Client-rendered stickers (animated/mascot/custom) travel as text tokens.
        let localTokens = pendingMedia.compactMap { $0.sticker.flatMap(ModulaLocalSticker.from)?.token }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (localTokens.joined(separator: " ") + (localTokens.isEmpty || typed.isEmpty ? "" : "\n") + typed)
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
            MascotProgressStore.shared.record(.comment)
            ModulaMascotEvent.post(.comment)
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

    func addVideoFile(_ url: URL) async {
        guard pendingMedia.count < 4, let data = try? Data(contentsOf: url) else { return }
        await upload(data: data, type: .quickTimeMovie, kind: .video, fileName: "Video.mov")
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
        // Only write when it changes: every @Observable write re-renders the whole comments sheet.
        guard let query, !query.isEmpty else { if !hashtagSuggestions.isEmpty { hashtagSuggestions = [] }; return }
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
            if !removing { MascotProgressStore.shared.record(.reaction) }
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

    func collapseReplies(for comment: SocialComment) {
        expandedReplies.remove(comment.id)
    }

    func checkForNewComments() async {
        guard !isLoading, !isSending,
              let page = try? await repository.comments(postID: postID, cursor: nil) else { return }
        let known = Set(items.map(\.id))
        let fresh = page.items.filter { $0.parentID == nil && !known.contains($0.id) }.count
        if fresh != newCommentCount { newCommentCount = fresh }
    }

    func showNewComments() async {
        newCommentCount = 0
        await load()
    }

    func collapseAllReplies() {
        if !expandedReplies.isEmpty { expandedReplies.removeAll() }
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

enum CommentSort: String, CaseIterable, Identifiable, Sendable {
    case best, newest, oldest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: "Top"
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}

struct PostCommentsView: View {
    let postID: SocialPostID
    var isSheet: Bool = false
    var onClose: (() -> Void)? = nil
    /// Asks the hosting sheet for more room (panel / camera opened).
    var onExpand: (() -> Void)? = nil
    // Detail supplies its identity/content here so conversation shares one scroll surface.
    var header: AnyView? = nil
    /// Known reply count from the post (shown in the header while comments load).
    var commentCount: Int? = nil
    /// Post author id — used to badge OP comments when present.
    var postAuthorID: String? = nil
    /// Bumped by the host (post detail) to scroll to the conversation and focus the composer.
    var focusComposerRequest: Int = 0

    @Environment(AppEnvironment.self) private var app
    @State private var store: PostCommentsStore?
    @FocusState private var composerFocused: Bool
    @State private var mediaPanelActive = false
    @State private var attachTrayOpen = false
    @State private var mediaPanelTab: ModulaComposerMediaPanel.Tab = .emoji
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var mediaStage: ComposeMediaStage = .collapsed
    @State private var showsScanner = false
    @State private var showsSketch = false
    @State private var showsContactPicker = false
    @State private var showsEventSheet = false
    @State private var showsAudioImporter = false
    @State private var stickerSection: String?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPollCreator = false
    @State private var showsFileImporter = false
    @State private var locating = false
    @State private var revealedSpoilers: Set<SocialCommentID> = []
    @State private var translating: String?
    @State private var dropTargeted = false
    @State private var menuComment: SocialComment?
    @State private var assistantDraft: MascotAssistantDraft?
    @State private var assistantHandled: Set<String> = []
    @State private var assistantBrain = MascotBrain()
    @AppStorage(ModulaMascotSettings.key(for: .comments)) private var commentsMascotShown = ModulaMascotSettings.defaultShown(.comments)
    /// Remembered: the comments sheet reopens with the order you last picked.
    @AppStorage("comments.sort") private var sortRaw = CommentSort.best.rawValue
    private var sort: CommentSort {
        get { CommentSort(rawValue: sortRaw) ?? .best }
        nonmutating set { sortRaw = newValue.rawValue }
    }
    @State private var searchText = ""
    @State private var showsSearch = false
    @State private var scrollTarget: SocialCommentID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if isSheet {
                conversationHeader
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let header { header }
                        if !isSheet { conversationHeader.id("post.comments.anchor") }
                        content
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, isSheet ? 12 : 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.always)
                .modulaSoftScrollEdge()
                .refreshable {
                    await store?.load()
                    HapticEngine.shared.play(.selection)
                }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollTarget = nil
                }
                .onChange(of: focusComposerRequest) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                        proxy.scrollTo("post.comments.anchor", anchor: .top)
                    }
                    composerFocused = true
                }
            }
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
                        .strokeBorder(app.appearance.liveAccent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
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
        .fullScreenCover(isPresented: $showsScanner) {
            CommentDocumentScanner { pages in Task { for page in pages { await store?.addCameraImage(page) } } }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsSketch) {
            CommentSketchSheet { image in Task { await store?.addCameraImage(image) } }
        }
        .sheet(isPresented: $showsContactPicker) {
            CommentContactPicker { text in insertIntoDraft(text) }
        }
        .sheet(isPresented: $showsEventSheet) {
            CommentEventSheet { text in insertIntoDraft(text) }
        }
        .fileImporter(isPresented: $showsAudioImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await store?.addFile(url) }
        }
        .onChange(of: mediaPanelActive) { _, open in if open { onExpand?() } }
        // Writing a comment gets the full sheet, so the feed never shows behind the composer.
        .onChange(of: composerFocused) { _, focused in if focused { onExpand?() } }
        .onChange(of: mediaStage) { _, stage in if stage.isExpanded { onExpand?() } }
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
            await scanAssistantDrafts(in: created)
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
        .sheet(item: $assistantDraft) { draft in
            MascotAssistantDraftSheet(
                draft: draft,
                onSend: { text in
                    guard let store else { return }
                    store.draft = text
                    store.replyingTo = store.items.first { $0.id == draft.commentID }
                    Task {
                        _ = await store.send()
                        assistantBrain.react(.celebrate)
                    }
                },
                onDiscard: {
                    assistantBrain.react(.shy)
                }
            )
        }
        .onChange(of: store?.items.map(\.id) ?? []) { _, _ in
            guard let store else { return }
            Task { await scanAssistantDrafts(in: store) }
        }
        #if DEBUG
        .onAppear {
            if DebugSettingsHarness.composerState == "gifs" {
                mediaPanelTab = .gifs
                mediaPanelActive = true
            }
        }
        #endif
    }

    /// Keyword assistant: only on posts the viewer authored; drafts a reply and never auto-posts unless enabled.
    @MainActor
    private func scanAssistantDrafts(in store: PostCommentsStore) async {
        let assistant = MascotAssistantStore.shared
        guard assistant.enabled else { return }
        let me = app.auth.account?.primaryHandle ?? ""
        guard !me.isEmpty,
              let author = store.postAuthorHandle,
              author.caseInsensitiveCompare(me) == .orderedSame else { return }

        for comment in store.items {
            // Don't reply to ourselves.
            if comment.author?.handle.caseInsensitiveCompare(me) == .orderedSame { continue }
            let cid = comment.id
            if assistantHandled.contains(cid) { continue }
            guard let match = assistant.match(in: comment.text) else { continue }
            assistantHandled.insert(cid)
            assistantBrain.react(.curious)
            assistantBrain.burst(.sparkle)
            MascotSound.shared.play(.pop)
            HapticEngine.shared.play(.selection)

            let draftText = await MascotAssistantVoice.draftReply(
                selection: assistant.selection,
                keyword: match.keyword,
                commentText: comment.text,
                context: assistant.context
            )
            let draft = MascotAssistantDraft(
                commentID: cid,
                keyword: match.keyword,
                originalText: comment.text,
                draftText: draftText,
                mascotRaw: assistant.kindRaw
            )
            if assistant.autoSend {
                // Explicit opt-in path — still surfaces briefly then sends.
                store.draft = draftText
                store.replyingTo = comment
                _ = await store.send()
                assistantBrain.react(.celebrate)
            } else {
                assistantDraft = draft
            }
            break // one draft at a time
        }
    }

    private var displayedCount: Int {
        // One definition everywhere: total comments *including replies* — the same number the
        // server's replyCount reports (the old root-only count read 25 vs 30).
        let live = store?.items.count ?? 0
        return max(commentCount ?? 0, live)
    }

    private var conversationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .accessibilityHidden(true)
                    Text("Comments").font(.headline)
                    if displayedCount > 0 {
                        Text("\(displayedCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minHeight: 20)
                            .background(Capsule().fill(app.appearance.liveAccent))
                            .contentTransition(.numericText(value: Double(displayedCount)))
                            .accessibilityLabel("\(displayedCount) comments")
                    }
                }
                .padding(.horizontal, isSheet ? 12 : 0)
                .frame(minHeight: isSheet ? 36 : 0)
                .background {
                    if isSheet { Color.clear.modulaGlass(in: Capsule(), interactive: false, specular: true) }
                }
                // Segmented sort (Hick: three visible choices beat a hidden menu).
                HStack(spacing: 6) {
                    ForEach(CommentSort.allCases) { option in
                        let selected = sort == option
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { sort = option }
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Text(option.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 32)
                                .background {
                                    if selected { Capsule().fill(app.appearance.liveAccent) }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityLabel("Sort by \(option.title)")
                    }
                }
                .padding(.horizontal, 3)
                .modulaGlass(in: Capsule(), interactive: false)
                .frame(minHeight: 44)
            }
            if let store, store.expandedReplies.count > 1 {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.collapseAllReplies() }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .modulaGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse all replies")
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)) {
                    showsSearch.toggle()
                    if !showsSearch { searchText = "" }
                }
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: showsSearch ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle(), interactive: true)
            .frame(width: 44, height: 44)
            .accessibilityLabel(showsSearch ? "Close search" : "Search comments")
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Circle(), interactive: true, specular: true)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Close comments")
            }
        }
        .padding(.horizontal, isSheet ? ModulaLayout.contentInset : 0)
        .padding(.top, isSheet ? 16 : 8)
        .padding(.bottom, isSheet ? 6 : 0)
        // Swipe down on the header to dismiss the sheet (close X still works).
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard isSheet, let onClose else { return }
                    let down = value.translation.height
                    guard down > 56, down > abs(value.translation.width) * 1.2 else { return }
                    HapticEngine.shared.play(.selection)
                    onClose()
                }
        )
        .accessibilityHint(isSheet ? "Swipe down to close" : "")
        if showsSearch {
            ModulaGlassSearchField(prompt: "Search comments", text: $searchText)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("post.comments.search")
        }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            if store.isLoading && store.items.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Loading comments…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .padding(.horizontal, 16)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                .padding(.top, 8)
                .accessibilityLabel("Loading comments")
            } else if let loadError = store.loadError, store.items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load comments.", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") {
                        Task { await store.load() }
                    }
                    .modulaGlass(in: Capsule(), interactive: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityIdentifier("post.comments.error")
            } else if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .foregroundStyle(app.appearance.liveAccent)
                    Text("Start the conversation")
                        .font(.subheadline.weight(.semibold))
                    Text("Be the first to leave a comment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                .padding(.top, 8)
            } else if !searchText.isEmpty && filteredRoots(store).isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No matching comments")
                        .font(.subheadline.weight(.semibold))
                    Text("Try a different name or phrase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 0)
                        .task(id: store.postID) {
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(25))
                                guard !Task.isCancelled else { return }
                                await store.checkForNewComments()
                            }
                        }
                    if store.newCommentCount > 0, searchText.isEmpty {
                        Button {
                            HapticEngine.shared.play(.selection)
                            Task { await store.showNewComments() }
                        } label: {
                            Label(store.newCommentCount == 1 ? "1 new comment" : "\(store.newCommentCount) new comments", systemImage: "arrow.up")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.liveAccent.opacity(0.35), specular: true)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("comments.newPill")
                    }
                    let rootList = filteredRoots(store)
                    ForEach(rootList) { comment in
                        commentRow(comment, store: store)
                            .onAppear { prefetchMoreIfNeeded(comment, in: rootList, store: store) }
                        let replies = filteredReplies(store, parent: comment)
                        if store.expandedReplies.contains(comment.id) || (!searchText.isEmpty && !replies.isEmpty) {
                            ForEach(replies) { reply in
                                commentRow(reply, store: store, indented: true)
                            }
                            if !replies.isEmpty || comment.replyCount > 0 {
                                Button {
                                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2)) {
                                        store.collapseReplies(for: comment)
                                    }
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    HStack(spacing: 8) {
                                        Rectangle().frame(width: 20, height: 1)
                                        Text("Hide replies")
                                        Image(systemName: "chevron.up")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 42)
                                    .frame(minHeight: 40)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hide replies")
                            }
                        } else if comment.replyCount > 0 {
                            Button {
                                Task { await store.loadReplies(for: comment) }
                            } label: {
                                HStack(spacing: 8) {
                                    Rectangle().frame(width: 20, height: 1)
                                    Text("View \(comment.replyCount) \(comment.replyCount == 1 ? "reply" : "replies")")
                                    if store.loadingReplies.contains(comment.id) { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(app.appearance.liveAccent)
                                .padding(.leading, 42)
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.loadingReplies.contains(comment.id))
                        }
                    }
                    if store.hasMore {
                        Button {
                            Task { await store.loadMore() }
                        } label: {
                            Text(store.isLoadingMore ? "Loading…" : "Load more")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .modulaGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoadingMore)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 36)
        }
    }

    private func roots(_ items: [SocialComment]) -> [SocialComment] {
        items.filter { $0.parentID == nil }
    }

    private func sortedItems(_ items: [SocialComment]) -> [SocialComment] {
        let pinned = { (c: SocialComment) in c.pinned ? 0 : 1 }
        switch sort {
        case .best:
            return items.sorted {
                if pinned($0) != pinned($1) { return pinned($0) < pinned($1) }
                let lhs = $0.likeCount + $0.reactions.reduce(0) { $0 + $1.count }
                let rhs = $1.likeCount + $1.reactions.reduce(0) { $0 + $1.count }
                if lhs != rhs { return lhs > rhs }
                return $0.createdAt > $1.createdAt
            }
        case .newest:
            return items.sorted {
                if pinned($0) != pinned($1) { return pinned($0) < pinned($1) }
                return $0.createdAt > $1.createdAt
            }
        case .oldest:
            return items.sorted {
                if pinned($0) != pinned($1) { return pinned($0) < pinned($1) }
                return $0.createdAt < $1.createdAt
            }
        }
    }

    private func sortedReplies(_ items: [SocialComment]) -> [SocialComment] {
        // Replies always read chronologically so threads stay coherent.
        items.sorted { $0.createdAt < $1.createdAt }
    }

    /// Starts the next page while ~6 comments are still below, so scrolling doesn't
    /// stop at a "Load more" button.
    private func prefetchMoreIfNeeded(_ comment: SocialComment, in list: [SocialComment], store: PostCommentsStore) {
        guard searchText.isEmpty, store.hasMore, !store.isLoadingMore,
              let index = list.lastIndex(where: { $0.id == comment.id }),
              index >= list.count - 6 else { return }
        Task { await store.loadMore() }
    }

    private func filteredRoots(_ store: PostCommentsStore) -> [SocialComment] {
        let base = roots(sortedItems(store.items))
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { comment in
            matchesSearch(comment, query: q)
                || store.items.contains { $0.parentID == comment.id && matchesSearch($0, query: q) }
        }
    }

    private func filteredReplies(_ store: PostCommentsStore, parent: SocialComment) -> [SocialComment] {
        let base = sortedReplies(store.items.filter { $0.parentID == parent.id })
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        // When searching, show matching replies even if parent thread wasn't expanded visually.
        return base.filter { matchesSearch($0, query: q) }
    }

    private func matchesSearch(_ comment: SocialComment, query: String) -> Bool {
        if comment.text.lowercased().contains(query) { return true }
        if comment.author?.displayName.lowercased().contains(query) == true { return true }
        if comment.author?.handle.lowercased().contains(query) == true { return true }
        return false
    }

    /// A comment that is only a link (optionally behind a repost glyph) renders as just the link card.
    static func isBareLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "🔁↻⟳"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func commentRow(_ comment: SocialComment, store: PostCommentsStore, indented: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if indented {
                RoundedRectangle(cornerRadius: 1)
                    .fill(app.appearance.liveAccent.opacity(0.35))
                    .frame(width: 2)
                    .padding(.vertical, 4)
                Color.clear.frame(width: 8)
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
                    if isOP(comment) {
                        Text("Author")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(app.appearance.liveAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(app.appearance.liveAccent.opacity(0.14), in: Capsule())
                            .accessibilityLabel("Original poster")
                    }
                    if comment.pinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.07), in: Capsule())
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
                    .overlay(alignment: .leading) { Capsule().fill(app.appearance.liveAccent).frame(width: 3) }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Quoting \(quoted.authorName ?? "a comment"): \(quoted.text)")
                }
                let local = ModulaLocalSticker.extract(comment.text)
                if !local.stickers.isEmpty {
                    ModulaLocalStickerRow(stickers: local.stickers)
                }
                if !local.text.isEmpty, !Self.isBareLink(local.text) {
                    Text(ModulaRichText.attributed(local.text, revealSpoilers: revealedSpoilers.contains(comment.id)))
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
                if indented, let parentID = comment.parentID {
                    Button {
                        scrollTarget = parentID
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label("Parent", systemImage: "arrow.up.to.line")
                    }
                    .accessibilityLabel("Jump to parent comment")
                }
                HStack(spacing: 6) {
                    Button {
                        store.quoting = nil
                        store.replyingTo = comment
                        composerFocused = true
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("comment.reply")
                    Button {
                        Task { await store.react(comment, type: "like") }
                        HapticEngine.shared.play(.confirmation)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: comment.viewerReaction == "like" ? "heart.fill" : "heart")
                                .foregroundStyle(comment.viewerReaction == "like" ? Color.red : Color.secondary)
                                .symbolEffect(.bounce, value: comment.viewerReaction == "like")
                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(comment.viewerReaction == "like" ? Color.red.opacity(0.9) : Color.secondary)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(comment.viewerReaction == "like" ? "Unlike" : "Like")
                    .accessibilityValue(comment.likeCount > 0 ? "\(comment.likeCount)" : "")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        // The whole row (including blank space beside short comments) takes the swipe.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .id(comment.id)
        // Swipe left to reply (Telegram-style) + double-tap like. Drag/burst state lives in the
        // row modifier so a swipe re-renders one row, not the whole comments sheet.
        .modifier(CommentRowSwipeModifier(
            accent: app.appearance.liveAccent,
            reduceMotion: reduceMotion,
            onReply: {
                store.quoting = nil
                store.replyingTo = comment
                composerFocused = true
            },
            onDoubleTap: {
                Task { await store.react(comment, type: "like") }
            }
        ))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Reply") { store.replyingTo = comment; composerFocused = true }
        .accessibilityAction(named: "Like") {
            Task { await store.react(comment, type: "like") }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            HapticEngine.shared.play(.actionConfirmed)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)) { menuComment = comment }
        }
        .accessibilityAction(named: "More actions") { menuComment = comment }
    }

    private func isOwn(_ comment: SocialComment) -> Bool {
        comment.author?.handle.caseInsensitiveCompare(app.auth.account?.primaryHandle ?? "") == .orderedSame
    }

    private func isOP(_ comment: SocialComment) -> Bool {
        guard let postAuthorID, let authorID = comment.author?.id else { return false }
        return authorID == postAuthorID
    }

    @ViewBuilder
    private func commentMenu(_ comment: SocialComment, store: PostCommentsStore) -> some View {
        Section {
            Button { menuComment = nil; store.quoting = nil; store.replyingTo = comment; composerFocused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            if comment.parentID == nil {
                Button { menuComment = nil; store.replyingTo = nil; store.quoting = comment; composerFocused = true } label: { Label("Quote", systemImage: "quote.opening") }
            }
            Button {
                menuComment = nil
                Task { await store.react(comment, type: "like") }
                HapticEngine.shared.play(.confirmation)
            } label: { Label(comment.viewerReaction == "like" ? "Unlike" : "Like", systemImage: comment.viewerReaction == "like" ? "heart.slash" : "heart") }
            Button {
                UIPasteboard.general.string = comment.text
                HapticEngine.shared.play(.lightImpact)
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button {
                menuComment = nil
                // Comments don't have a stable public URL yet — share the post link instead.
                UIPasteboard.general.string = ModulaShareLink.post(postID).absoluteString
                HapticEngine.shared.play(.lightImpact)
                app.navigation.flash("Post link copied", symbol: "link")
            } label: { Label("Copy post link", systemImage: "link") }
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
        typealias O = ModulaComposerAttachmentOption
        var options = [O(id: "photos", title: "Photos", systemImage: "photo.on.rectangle", tint: .blue)]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            options.append(O(id: "camera", title: "Camera", systemImage: "camera.fill", tint: .gray))
        }
        options += [
            O(id: "gif", title: "GIF", systemImage: "play.square.stack.fill", tint: .purple),
            O(id: "sticker", title: "Sticker", systemImage: "seal.fill", tint: .orange),
            O(id: "poll", title: "Poll", systemImage: "chart.bar.fill", tint: .green),
            O(id: "location", title: locating ? "Locating…" : "Location", systemImage: "location.fill", tint: .teal),
            O(id: "file", title: "File", systemImage: "doc.fill", tint: .indigo),
            O(id: "voice", title: "Voice note", systemImage: "waveform", tint: .red),
        ]
        if CommentDocumentScanner.isSupported {
            options.append(O(id: "scan", title: "Scan", systemImage: "doc.viewfinder.fill", tint: .cyan))
        }
        options += [
            O(id: "sketch", title: "Sketch", systemImage: "scribble.variable", tint: .pink),
            O(id: "link", title: "Link", systemImage: "link", tint: .blue),
            O(id: "event", title: "Event", systemImage: "calendar", tint: .red),
            O(id: "quote", title: "Quote post", systemImage: "quote.bubble.fill", tint: .mint),
            O(id: "code", title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", tint: .gray),
            O(id: "contact", title: "Contact", systemImage: "person.crop.circle.fill", tint: .brown),
            O(id: "audio", title: "Audio", systemImage: "music.note", tint: .orange),
            O(id: "mascot", title: "Moliboo", systemImage: "pawprint.fill", tint: .purple),
        ]
        if UIPasteboard.general.hasImages {
            options.append(O(id: "paste", title: "Paste", systemImage: "doc.on.clipboard.fill", tint: .pink))
        }
        return options
    }

    private func insertIntoDraft(_ snippet: String) {
        guard let store else { return }
        let current = store.draft
        store.draft = current.isEmpty ? snippet : current + (current.hasSuffix("\n") ? "" : "\n") + snippet
        composerFocused = true
        HapticEngine.shared.play(.selection)
    }

    @ViewBuilder
    /// "Replying to @handle" when the author has a handle; the display name only when they don't.
    private static func composerContext(_ verb: String, author: SocialAuthor?) -> String {
        if let handle = author?.handle, !handle.isEmpty { return "\(verb) @\(handle)" }
        return "\(verb) \(author?.displayName ?? "comment")"
    }

    @ViewBuilder private var composer: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let error = store?.composerError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                if mediaStage.isExpanded {
                    ComposeMediaAttachStage(
                        stage: $mediaStage,
                        accent: app.appearance.liveAccent,
                        idPrefix: "comment.media",
                        height: 300,
                        maxSelectionCount: 4,
                        matching: .any(of: [.images, .videos]),
                        cameraModes: [.photo, .video],
                        onPhotosPicked: { items in
                            Task { await store?.addPhotos(items) }
                        },
                        onCameraPhoto: { image in
                            Task { await store?.addCameraImage(image) }
                        },
                        onCameraVideo: { url in
                            Task { await store?.addVideoFile(url) }
                        }
                    )
                    .padding(.horizontal, 12)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                    .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.height > 70 {
                            withAnimation(.easeOut(duration: 0.2)) { mediaStage = .collapsed }
                        }
                    })
                }
                // Instagram-style quick reactions: one tap drops an emoji into an empty comment.
                // Leaf view reads the draft, so typing never re-evaluates this whole sheet
                // (comments list, post header) just to know whether the draft is empty.
                if composerFocused, !mediaStage.isExpanded, let store {
                    CommentQuickEmojiGate(store: store, trailing: commentsMascotShown ? 70 : 12)
                }
                // Composer + perched mascot always sit fully above the emoji/GIF panel
                // (keyboard-replacement). Opaque backing stops the comment list showing through.
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
                    reply: store?.replyingTo.map { ModulaComposerReply(title: Self.composerContext("Replying to", author: $0.author), excerpt: $0.text) }
                        ?? store?.quoting.map { ModulaComposerReply(title: Self.composerContext("Quoting", author: $0.author), excerpt: $0.text) },
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
                            if value {
                                mediaPanelTab = .emoji
                                stickerSection = nil
                                withAnimation(.easeOut(duration: 0.22)) {
                                    mediaStage = .collapsed
                                }
                            }
                            mediaPanelActive = value
                        }
                    ),
                    hashtagSuggestions: store?.hashtagSuggestions ?? [],
                    onHashtagQuery: { store?.updateHashtagQuery($0) },
                    showsFormatting: true,
                    onVoiceNote: { note in Task { await store?.addVoiceNote(note) } },
                    mascot: .comments,
                    collapsesWhenUnfocused: true,
                    // Moliboo stays with you while typing; the headroom below keeps it off the comments.
                    hidesMascotWhileComposing: false,
                    onTrayChange: { open in
                        attachTrayOpen = open
                        if open { onExpand?() }
                    },
                    onSend: {
                        // The send starts immediately; the island effect is decorative.
                        // Failures still surface through the composer error / island toast.
                        IslandSendEffect.shared.fire(store?.replyingTo == nil ? "Comment sent" : "Reply sent", accent: app.appearance.liveAccent)
                        Task { _ = await store?.send() }
                    }
                )
                .padding(.horizontal, 12)
                .accessibilityIdentifier("post.comment.composer")
            }
            // Reserve headroom for Moliboo, who perches on top of the bar, so he sits on the
            // composer's own background instead of over the last comments.
            .padding(.top, commentsMascotShown ? 48 : 6)
            .padding(.bottom, mediaPanelActive ? 10 : 8)
            .frame(maxWidth: .infinity)
            // Floating glass bar over a soft progressive fade: comments stay visible as they
            // scroll under it, and the fade (not a solid block) keeps the bar readable. The
            // top headroom is clear so Moliboo perches above the bar, never on it.
            .background {
                if mediaPanelActive {
                    canvas
                } else if composerFocused || attachTrayOpen || mediaStage.isExpanded || store?.isSending == true {
                    // Docked to the keyboard. The idle state is the floating pill, with no full-bleed bar behind it.
                    // Solid canvas with a short top fade: no live blur or mask pass while the
                    // keyboard animates and the list scrolls behind.
                    LinearGradient(stops: [
                        .init(color: canvas.opacity(0), location: 0),
                        .init(color: canvas.opacity(reduceTransparency ? 1 : 0.96), location: 0.12),
                        .init(color: canvas.opacity(reduceTransparency ? 1 : 0.96), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            // Keep the composer + mascot above the panel even if a glass layer tries to float.
            .zIndex(2)

            if mediaPanelActive {
                ModulaComposerMediaPanel(
                    client: app.client,
                    initialTab: mediaPanelTab,
                    initialStickerSection: stickerSection,
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
                .id("\(mediaPanelTab.rawValue)-\(stickerSection ?? "")")
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        // Solid fill under the whole inset (composer + panel) so nothing from the
        // comment list or the home feed peeks through the home-indicator zone.
        .background {
            if mediaPanelActive { canvas.ignoresSafeArea(edges: .bottom) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22), value: mediaPanelActive)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22), value: mediaStage)
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
        case "photos":
            composerFocused = false
            mediaPanelActive = false
            withAnimation(.easeOut(duration: 0.22)) { mediaStage = .library }
        case "camera":
            composerFocused = false
            mediaPanelActive = false
            withAnimation(.easeOut(duration: 0.22)) { mediaStage = .camera }
        case "gif", "sticker", "mascot":
            composerFocused = false
            withAnimation(.easeOut(duration: 0.22)) { mediaStage = .collapsed }
            mediaPanelTab = option.id == "gif" ? .gifs : .stickers
            stickerSection = option.id == "mascot" ? "mascots" : nil
            mediaPanelActive = true
        case "scan": showsScanner = true
        case "sketch": showsSketch = true
        case "contact": showsContactPicker = true
        case "event": showsEventSheet = true
        case "audio": showsAudioImporter = true
        case "quote": insertIntoDraft("🔁 " + ModulaShareLink.post(postID).absoluteString)
        case "link": insertIntoDraft("[link](https://)")
        case "code": insertIntoDraft("```\n\n```")
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
    var commentCount: Int? = nil
    var postAuthorID: String? = nil
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
        // Content scrolls instead of resizing the sheet: dragging the list no longer snaps
        // the sheet between detents mid-scroll (the handle/header still resize it).
        ModulaSheet(detents: detents, selectedDetent: $selectedDetent, contentScrolls: true) {
            PostCommentsView(
                postID: postID,
                isSheet: true,
                onClose: {
                    HapticEngine.shared.play(.selection)
                    dismiss()
                },
                onExpand: {
                    if selectedDetent != .large {
                        // Plain ease alongside the keyboard (no spring fighting the system curve).
                        withAnimation(.easeOut(duration: 0.25)) { selectedDetent = .large }
                    }
                },
                commentCount: commentCount,
                postAuthorID: postAuthorID
            )
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
            guard let sticker, !sticker.packID.hasPrefix("local.") else { return nil }
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


/// Shows the quick-emoji row only while the draft is empty. Owns the draft read so the parent sheet
/// is not invalidated on every keystroke.
private struct CommentQuickEmojiGate: View {
    let store: PostCommentsStore
    var trailing: CGFloat

    var body: some View {
        let empty = store.draft.isEmpty
        Group {
            if empty {
                CommentQuickEmojiRow { emoji in
                    store.draft = emoji
                    HapticEngine.shared.play(.selection)
                }
                .padding(.leading, 12)
                // Leave the trailing corner for Moliboo, who perches on the composer just below.
                .padding(.trailing, trailing)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: empty)
    }
}

/// Quick emoji above the comment composer (shown while focused with an empty draft).
struct CommentQuickEmojiRow: View {
    static let emoji = ["❤️", "🙌", "🔥", "👏", "😢", "😍", "😮", "😂"]
    var onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.emoji, id: \.self) { e in
                Button { onPick(e) } label: {
                    Text(e).font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comment \(e)")
                .accessibilityIdentifier("post.comment.quick.\(e)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post.comment.quick")
    }
}


/// Per-row swipe-to-reply and double-tap heart. Kept out of `PostCommentsView` state so
/// a drag only invalidates this row.
private struct CommentRowSwipeModifier: ViewModifier {
    let accent: Color
    let reduceMotion: Bool
    let onReply: () -> Void
    let onDoubleTap: () -> Void
    @State private var offset: CGFloat = 0
    @State private var burst = 0

    func body(content: Content) -> some View {
        content
            .background(alignment: .trailing) {
                let t = min(abs(offset) / 64, 1)
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .opacity(Double(t))
                    .scaleEffect(t)
                    .padding(.trailing, 4)
            }
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.2, value.translation.width < 0 else { return }
                        let next = max(value.translation.width * 0.6, -90)
                        if offset > -56 && next <= -56 { HapticEngine.shared.play(.dragThreshold) }
                        offset = next
                    }
                    .onEnded { _ in
                        let triggered = offset <= -56
                        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) { offset = 0 }
                        if triggered { onReply() }
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onDoubleTap()
                burst += 1
                HapticEngine.shared.play(.lightImpact)
            })
            .overlay {
                DoubleTapHeartBurst(trigger: burst)
                    .frame(width: 72, height: 72)
            }
    }
}
