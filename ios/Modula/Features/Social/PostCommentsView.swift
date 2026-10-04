import PhotosUI
import SwiftUI
import UIKit
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
    var draft = ""
    var composerError: String?
    var replyingTo: SocialComment?
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
            let comment = try await repository.createComment(postID: postID, text: text, parentID: parent, media: media)
            pendingMedia = []
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
            await upload(data: data, type: type, isVideo: isVideo)
        }
    }

    func addCameraImage(_ image: UIImage) async {
        guard pendingMedia.count < 4, let data = image.jpegData(compressionQuality: 0.86) else { return }
        await upload(data: data, type: .jpeg, isVideo: false)
    }

    func addGif(_ gif: ModulaGif) {
        guard pendingMedia.count < 4 else { return }
        pendingMedia.append(PendingCommentMedia(id: "gif:\(gif.id)", kind: .gif, previewURL: gif.previewURL, gif: gif))
        HapticEngine.shared.play(.selection)
    }

    func removeMedia(id: String) {
        pendingMedia.removeAll { $0.id == id }
    }

    private func upload(data: Data, type: UTType, isVideo: Bool) async {
        let id = UUID().uuidString
        let mimeType = type.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        let filename = "\(id).\(type.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg"))"
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: localURL, options: .atomic)
        pendingMedia.append(PendingCommentMedia(id: id, kind: isVideo ? .video : .image, previewURL: isVideo ? nil : localURL, progress: 0))
        let uploader = GreenfieldMediaUploader(client: client)
        let media = PreparedMedia(id: id, kind: isVideo ? .video : .image, data: data, mimeType: mimeType, filename: filename, altText: "")
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .modulaCanvas()
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, maxSelectionCount: 4, matching: .any(of: [.images, .videos]))
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await store?.addPhotos(items) }
        }
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
                if !comment.text.isEmpty {
                    Text(PostTextLinks.attributed(comment.text))
                        .font(.body)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !comment.media.isEmpty {
                    CommentMediaGrid(media: comment.media)
                }
                if let url = ModulaLinkDetector.firstWebURL(in: comment.text), comment.media.isEmpty {
                    ModulaRichLinkCard(url: url, compact: true)
                }
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount) likes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Reply") {
                    store.replyingTo = comment
                    composerFocused = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .modulaContextMenu(
            actions: PostContextActions.commentMenu(
                isOwn: comment.author?.handle.caseInsensitiveCompare(app.auth.account?.primaryHandle ?? "") == .orderedSame,
                capabilities: app.postActions.capabilities
            ),
            onSelect: { handleCommentAction($0, comment: comment, store: store) }
        )
    }

    /// Options shown in the glass attach menu. Only what Greenfield comments accept:
    /// photos/videos (attachment pipeline), camera, and GIFs (GIF proxy). Polls,
    /// location, files and stickers aren't supported on comments, so they're hidden.
    private var attachmentOptions: [ModulaComposerAttachmentOption] {
        var options = [ModulaComposerAttachmentOption(id: "photos", title: "Photos", systemImage: "photo.on.rectangle", tint: .blue)]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            options.append(ModulaComposerAttachmentOption(id: "camera", title: "Camera", systemImage: "camera.fill", tint: .gray))
        }
        options.append(ModulaComposerAttachmentOption(id: "gif", title: "GIF", systemImage: "play.square.stack.fill", tint: .purple))
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
                reply: store?.replyingTo.map { ModulaComposerReply(title: "Replying to \($0.author?.displayName ?? "comment")", excerpt: $0.text) },
                onCancelReply: { store?.replyingTo = nil },
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
        case "gif":
            composerFocused = false
            mediaPanelTab = .gifs
            mediaPanelActive = true
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
            guard let author = comment.author else { return }
            Task {
                do {
                    try await GreenfieldProfileRepository(client: app.client).mute(profileID: author.id)
                    HapticEngine.shared.play(.confirmation)
                } catch {
                    store.composerError = (error as? APIError)?.userFacingMessage ?? "Couldn’t mute this author."
                }
            }
        default:
            break
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
    enum Kind: Equatable { case image, video, gif }
    let id: String
    let kind: Kind
    var previewURL: URL?
    var gif: ModulaGif? = nil
    var attachmentID: String? = nil
    var progress: Double? = nil
    var failed = false

    var isReady: Bool { !failed && progress == nil && (gif != nil || attachmentID != nil) }

    var payload: JSONValue? {
        if let gif {
            var item: [String: JSONValue] = [
                "type": .string("gif"), "provider": .string("giphy"), "id": .string(gif.id),
                "url": .string(gif.url.absoluteString), "previewUrl": .string(gif.previewURL.absoluteString)
            ]
            if let width = gif.width { item["width"] = .number(Double(width)) }
            if let height = gif.height { item["height"] = .number(Double(height)) }
            if let title = gif.title { item["title"] = .string(title) }
            return .object(item)
        }
        guard let attachmentID, !failed else { return nil }
        return .object(["type": .string("attachment"), "attachmentId": .string(attachmentID)])
    }

    var composerAttachment: ModulaComposerAttachment {
        ModulaComposerAttachment(
            id: id,
            title: kind == .gif ? "GIF" : (kind == .video ? "Video" : "Photo"),
            systemImage: kind == .video ? "video" : (kind == .gif ? "play.square.stack" : "photo"),
            thumbnailURL: previewURL, progress: progress, failed: failed
        )
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
