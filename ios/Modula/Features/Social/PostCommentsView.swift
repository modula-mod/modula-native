import SwiftUI
import UIKit

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
    private(set) var loadingReplies: Set<SocialCommentID> = []
    private(set) var expandedReplies: Set<SocialCommentID> = []

    init(client: GreenfieldClient, postState: PostStateStore, postID: SocialPostID, capabilities: PostBackendCapabilities = .production) {
        self.repository = GreenfieldPostRepository(client: client, capabilities: capabilities)
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
        guard !text.isEmpty, !isSending else { return false }
        isSending = true
        composerError = nil
        do {
            let parent = parentID ?? replyingTo.map { $0.parentID ?? $0.id }
            let comment = try await repository.createComment(postID: postID, text: text, parentID: parent)
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
                                    Text("View ^[\(comment.replyCount) reply](inflect: true)")
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
                Text(comment.text)
                    .font(.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if comment.likeCount > 0 {
                    Text("^[\(comment.likeCount) like](inflect: true)")
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

    private var composer: some View {
        VStack(spacing: 0) {
            if let reply = store?.replyingTo {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(reply.author?.displayName ?? "comment")").font(.caption.weight(.semibold))
                        Text(reply.text).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store?.replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 16)
            }
            if let error = store?.composerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if let account = app.auth.account {
                    ModulaAvatar(
                        initials: String(account.displayName?.prefix(2) ?? account.primaryHandle.prefix(2)).uppercased(),
                        url: app.profile.ownProfile?.avatarURL,
                        size: 32
                    )
                }
                ModulaComposer(
                    text: Binding(
                        get: { store?.draft ?? "" },
                        set: { store?.draft = $0 }
                    ),
                    prompt: "Add a comment…",
                    enabled: store != nil,
                    sending: store?.isSending == true,
                    showsAttachmentButton: false,
                    externalFocus: Binding(
                        get: { composerFocused },
                        set: { composerFocused = $0 }
                    ),
                    onSend: { Task { _ = await store?.send() } }
                )
                .accessibilityIdentifier("post.comment.composer")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
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
