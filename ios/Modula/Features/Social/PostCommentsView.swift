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
            let comment = try await repository.createComment(postID: postID, text: text, parentID: parentID)
            items.insert(comment, at: 0)
            draft = ""
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

    @Environment(AppEnvironment.self) private var app
    @State private var store: PostCommentsStore?
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSheet {
                Capsule()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            }
            content
            composer
        }
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
                ContentUnavailableView("No comments yet", systemImage: "bubble.right", description: Text("Start the discussion."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(roots(store.items)) { comment in
                        commentRow(comment, store: store)
                        let replies = store.items.filter { $0.parentID == comment.id }
                        if !replies.isEmpty {
                            ForEach(replies.prefix(3)) { reply in
                                commentRow(reply, store: store, indented: true)
                            }
                            if comment.replyCount > replies.count {
                                Text("View \(comment.replyCount) replies")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(app.appearance.accent.color)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    if store.hasMore {
                        Button("Load more") {
                            Task { await store.loadMore() }
                        }
                        .disabled(store.isLoadingMore)
                    }
                }
                .listStyle(.plain)
                .modulaSoftScrollEdge()
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
                ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 32)
            } else {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author?.displayName ?? "Someone")
                        .font(.subheadline.weight(.semibold))
                    Text(ActivityRelativeTime.string(from: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if comment.isEdited {
                        Text("Edited").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(comment.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount) likes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(comment.voiceOverSummary)
        .modulaContextMenu(
            actions: PostContextActions.commentMenu(
                isOwn: comment.author?.id == app.auth.account?.accountId,
                capabilities: app.postActions.capabilities
            ),
            onSelect: { handleCommentAction($0, comment: comment, store: store) }
        )
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
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
                        url: nil,
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
            .background(.bar)
        }
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

    private func handleCommentAction(_ action: ModulaContextAction, comment: SocialComment, store: PostCommentsStore) {
        switch action.id {
        case "copy":
            UIPasteboard.general.string = comment.text
            HapticEngine.shared.play(.lightImpact)
        case "delete":
            Task { await store.delete(comment) }
        default:
            break
        }
    }
}

struct PostCommentsSheet: View {
    let postID: SocialPostID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ModulaSheet(detents: [.compact, .medium, .large]) {
            PostCommentsView(postID: postID, isSheet: true, onClose: { dismiss() })
        }
    }
}
