import SwiftUI
import UIKit

struct PostDetailView: View {
    let postID: String
    var section: PostSection = .root

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shellChromeMetrics) private var shellChromeMetrics
    @State private var post: SocialPost?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var focusComposerRequest = 0
    @State private var showsShareSheet = false
    @State private var attachmentViewerItem: ModulaAttachment?
    @State private var confirmDelete = false
    @State private var editText = ""
    @State private var moreFrame: CGRect = .zero

    private var isOwn: Bool {
        guard let handle = post?.author?.handle, let own = app.auth.account?.primaryHandle else { return false }
        return handle.caseInsensitiveCompare(own) == .orderedSame
    }

    var body: some View {
        Group {
            switch section {
            case .comments:
                commentsDestination
            case .likes, .shares:
                PostPeopleListView(postID: postID, section: section)
            case .reactions:
                ReactionPeopleView(postID: postID)
            case .edit:
                editDestination
            case .root:
                rootDestination
            }
        }
        .modulaCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: postID) { await load() }
        .sheet(isPresented: $showsShareSheet) {
            if let post {
                PostShareSheet(post: post) {
                    showsShareSheet = false
                }
            }
        }
        .fullScreenCover(item: $attachmentViewerItem) { item in
            AttachmentViewerRouter(attachment: item, imageGallery: postImageGallery) { attachmentViewerItem = nil }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Post", role: .destructive) {
                Task {
                    if let post, await app.postActions.deletePost(post) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("native.post")
        .accessibilityValue(RouteSerializer.serialize(.post(postID, section)))
    }

    private var postImageGallery: [ModulaAttachment] {
        guard let post else { return [] }
        return post.media
            .map(ModulaPostMapper.attachment)
            .filter { $0.kind == .image }
    }

    @ViewBuilder
    private var rootDestination: some View {
        Group {
                if isLoading && post == nil {
                    skeleton
                } else if let loadError, post == nil {
                    unavailable(loadError)
                } else if let base = post {
                    let resolved = app.posts.resolved(base)
                    PostCommentsView(
                        postID: postID,
                        header: AnyView(
                            VStack(alignment: .leading, spacing: 14) {
                                detailChrome(resolved)
                                engagementSummary(resolved)
                                Divider().opacity(0.45)
                            }
                        ),
                        focusComposerRequest: focusComposerRequest
                    )
                }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
    }

    private var commentsDestination: some View {
        PostCommentsView(postID: postID, isSheet: false)
            .modulaSoftScrollEdge()
            .navigationTitle("Comments")
            .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var editDestination: some View {
        if app.postActions.capabilities.editOwnPost, let post, isOwn {
            PostEditView(post: post, text: $editText) {
                Task {
                    if let updated = await app.postActions.editPost(post, text: editText) {
                        self.post = updated
                        app.navigation.open(.post(postID, .root))
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Edit Post")
        } else {
            ContentUnavailableView(
                "Editing unavailable",
                systemImage: "pencil.slash",
                description: Text("Post editing is not enabled for this account yet.")
            )
            .modulaSoftScrollEdge()
            .navigationTitle("Edit Post")
        }
    }

    private var navigationTitle: String {
        if let name = post?.author?.displayName {
            return "\(name) · Post"
        }
        return "Post"
    }

    /// Same shell as the Home feed (ImmersivePostCard): reaction dock + emoji/colours, repost,
    /// bookmark, share, double-tap to like and the "…" menu. Comments live inline below, so the
    /// comment button is dropped and any comment intent focuses the inline composer.
    private func detailChrome(_ post: SocialPost) -> some View {
        ImmersivePostCard(
            post: post,
            isOwnPost: isOwn,
            onOpenPost: {},
            onOpenAuthor: { openAuthor(post) },
            onLike: {
                if !post.liked { ModulaMascotEvent.post(.like) }
                Task { await app.postActions.toggleLike(post); app.home.syncVisibleEngagement() }
            },
            onComment: { focusComposer() },
            onRepost: {
                ModulaMascotEvent.post(.repost)
                Task { await app.postActions.toggleRepost(post); app.home.syncVisibleEngagement() }
            },
            onSave: {
                if !post.saved { ModulaMascotEvent.post(.save) }
                Task { await app.postActions.toggleSave(post); app.home.syncVisibleEngagement() }
            },
            onShare: {
                ModulaMascotEvent.post(.share)
                if PostSharing.method() == .modulaSheet {
                    showsShareSheet = true
                } else {
                    PostSharing.share(post, app: app)
                }
            },
            onContextAction: { handleContext($0, post: post) },
            onOpenMedia: { attachmentViewerItem = ModulaPostMapper.attachment($0) },
            onOpenModule: { module in
                app.navigation.push(.productHub(.module(module.id, .overview)))
                HapticEngine.shared.play(.navigation)
            },
            showsCommentAffordances: false,
            style: .detail
        )
        // Flush, full-width: bleed past the list's content inset with no gutter.
        .padding(.horizontal, -ModulaLayout.contentInset)
    }

    private func focusComposer() {
        HapticEngine.shared.play(.selection)
        focusComposerRequest += 1
    }

    private func engagementSummary(_ post: SocialPost) -> some View {
        HStack(spacing: 16) {
            // Same number the heart shows (reactions include likes); comment total lives in the
            // Comments header so the two can't disagree.
            let reactions = max(post.reactionCount, post.likeCount)
            if reactions > 0 {
                Button {
                    app.navigation.open(.post(postID, .likes))
                } label: {
                    Text(reactions == 1 ? "1 like" : "\(reactions) likes")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            if post.repostCount > 0 {
                Button {
                    app.navigation.open(.post(postID, .shares))
                } label: {
                    Text(post.repostCount == 1 ? "1 repost" : "\(post.repostCount) reposts")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(post.voiceOverSummary)
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label("This post isn't available.", systemImage: "eye.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await load() } }
        }
        .padding(.top, 40)
        .accessibilityIdentifier("post.unavailable")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 120, height: 12)
                    Capsule().fill(Color.primary.opacity(0.06)).frame(width: 80, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(height: 72)
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)).frame(height: 200)
            HStack {
                Capsule().fill(Color.primary.opacity(0.06)).frame(width: 44, height: 14)
                Capsule().fill(Color.primary.opacity(0.06)).frame(width: 44, height: 14)
                Capsule().fill(Color.primary.opacity(0.06)).frame(width: 44, height: 14)
            }
        }
        .redacted(reason: .placeholder)
        .padding(.top, 12)
        .accessibilityIdentifier("post.skeleton")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let post {
                PostMenuButton(makeRequest: { menuRequest(for: post, anchor: $0) }) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { moreFrame = $0 }
                .accessibilityIdentifier("post.detail.more")
            }
        }
    }

    private func menuRequest(for post: SocialPost, anchor: CGRect) -> PostMenuRequest {
        PostMenuRequest(
            post: post,
            isOwn: isOwn,
            anchor: anchor == .zero ? moreFrame : anchor,
            hooks: PostMenuHooks(
                onSave: { Task { await app.postActions.toggleSave(post) } },
                onShare: {
                    if PostSharing.method() == .modulaSheet {
                        showsShareSheet = true
                    } else {
                        PostSharing.share(post, app: app)
                    }
                },
                onContextAction: { action in handleContext(action, post: post) }
            )
        )
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let loaded = try await app.postActions.loadPost(id: postID)
            post = loaded
            editText = loaded.text ?? ""
            isLoading = false
        } catch let api as APIError {
            if api == .invalidResponse || api.code == nil {
                loadError = "This post isn't available."
            } else {
                loadError = api.userFacingMessage
            }
            isLoading = false
        } catch {
            loadError = "This post isn't available."
            isLoading = false
        }
    }

    private func openAuthor(_ post: SocialPost) {
        if let author = post.author {
            app.navigation.push(.profile(author.routeID, .overview))
            HapticEngine.shared.play(.navigation)
        }
    }

    private func handleContext(_ action: ModulaContextAction, post: SocialPost) {
        switch action.id {
        case "save":
            Task { await app.postActions.toggleSave(post) }
        case "save-collection":
            app.navigation.presented = .collectionPicker(postID: post.id)
            HapticEngine.shared.play(.contextOpen)
        case "copy-link":
            UIPasteboard.general.string = post.shareURL.absoluteString
            HapticEngine.shared.play(.lightImpact)
        case "share":
            app.navigation.presented = .universalShare(.post(
                id: post.id,
                authorName: post.author?.displayName,
                excerpt: post.text,
                hasMedia: !post.media.isEmpty
            ))
        case "edit-post":
            app.navigation.open(.post(postID, .edit))
        case "delete":
            confirmDelete = true
            HapticEngine.shared.play(.warning)
        case "hide", "not-interested":
            app.postActions.hideLocally(post)
            dismiss()
        case "mute-author":
            // Actually mute (was: opened the author's profile).
            if let author = post.author {
                Task {
                    if await app.profile.mute(profileID: author.id) {
                        app.navigation.flash("Muted \(author.displayName)", symbol: "speaker.slash")
                    }
                }
            }
        default:
            break
        }
    }
}

struct PostShareSheet: View {
    let post: SocialPost
    var onDismiss: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var showsSystemShare = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let author = post.author {
                        Text(author.displayName)
                            .font(.headline.weight(.semibold))
                    }
                    if let text = post.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .lineLimit(4)
                    }
                    Text(post.shareURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))

                Button {
                    UIPasteboard.general.string = post.shareURL.absoluteString
                    HapticEngine.shared.play(.lightImpact)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                        .padding(.horizontal, 14)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                ShareLink(item: PostSharing.shareText(for: post)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                        .padding(.horizontal, 14)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    Task { await app.postActions.recordShare(post) }
                    HapticEngine.shared.play(.lightImpact)
                })

                Spacer()
            }
            .padding(20)
            .modulaSoftScrollEdge()
            .navigationTitle("Share Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("post.share.sheet")
    }
}

struct PostEditView: View {
    let post: SocialPost
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        Form {
            Section("Body") {
                TextField("What's happening?", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityIdentifier("post.edit.body")
            }
            if post.hasMedia {
                Section {
                    Text("Media can't be edited here yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .modulaSoftScrollEdge()
        .safeAreaInset(edge: .bottom) {
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("post.edit.save")
        }
    }
}

struct PostPeopleListView: View {
    let postID: String
    let section: PostSection
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .modulaSoftScrollEdge()
        .navigationTitle(title)
        .accessibilityIdentifier("post.people.\(section.rawValue)")
    }

    private var title: String {
        switch section {
        case .likes: "Likes"
        case .reactions: "Reactions"
        case .shares: "Shares"
        default: "People"
        }
    }

    private var symbol: String {
        switch section {
        case .likes: "heart"
        case .reactions: "face.smiling"
        case .shares: "arrow.2.squarepath"
        default: "person.2"
        }
    }

    private var message: String {
        switch section {
        case .likes:
            return app.postActions.capabilities.likesList
                ? "People who liked this post."
                : "Who liked this isn’t available yet."
        case .reactions:
            return app.postActions.capabilities.reactionsList
                ? "People grouped by reaction."
                : "A breakdown of reactions isn’t available yet."
        case .shares:
            return app.postActions.capabilities.sharesList
                ? "People who shared this post."
                : "Only a share count is available — identities aren't provided."
        default:
            return "Unavailable."
        }
    }
}
