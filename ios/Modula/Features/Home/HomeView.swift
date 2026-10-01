import SwiftUI
import UIKit

struct HomeView: View {
    let mode: HomeMode
    @Environment(AppEnvironment.self) private var app
    @Environment(\.trailingInteractionInset) private var trailingInteractionInset
    @Environment(\.leadingInteractionInset) private var leadingInteractionInset
    @Environment(\.shellChromeMetrics) private var shellChromeMetrics
    @State private var videoCoordinator = FeedVideoCoordinator()
    @State private var commentsPost: SocialPost?

    var body: some View {
        let state = app.home.state(for: mode)
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        modeCaption
                        if showsStoryTray {
                            HStack {
                                Text("Stories").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Button { app.navigation.push(.stories(.create)) } label: {
                                    Image(systemName: "plus.circle").frame(width: 44, height: 44)
                                }
                                .tint(app.appearance.accent.color)
                                .accessibilityLabel("Create story")
                                Spacer()
                                Button { app.navigation.push(.reels(.feed)) } label: {
                                    Label("Watch Reels", systemImage: "play.rectangle")
                                        .font(.caption.weight(.semibold))
                                        .frame(minHeight: 44)
                                }
                                .tint(app.appearance.accent.color)
                                .accessibilityIdentifier("home.open-reels")
                            }
                            StoryTray(groups: app.stories.trayGroups, compact: true) { group in
                                Task { await openStory(group) }
                            } onCreate: {
                                app.navigation.push(.stories(.create))
                            }
                            .padding(.horizontal, -ModulaLayout.contentInset)
                            .padding(.leading, 4)
                        }
                        if app.home.isOfflineHint && !state.items.isEmpty {
                            offlineBanner
                        }
                        feedContent(state)
                    }
                    .padding(.leading, ModulaLayout.contentInset + leadingInteractionInset)
                    .padding(.trailing, ModulaLayout.contentInset + trailingInteractionInset)
                    .padding(.top, 4)
                    .padding(.bottom, shellChromeMetrics.contentBottomInset)
                    .modulaPullContentEffects()
                }
            }
            .modulaSoftScrollEdge()
            .modulaShellPullActions {
                await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                await app.stories.refresh()
            }

            if state.newerAvailable {
                newerPill
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Modula")
        .navigationBarTitleDisplayMode(.large)
        .modulaSidebarTrigger()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create", systemImage: "plus") {
                    app.navigation.open(.compose(.post))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.create")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.navigation.push(.messages(.inbox))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "message")
                        .overlay(alignment: .topTrailing) {
                            if let count = app.messaging.accountUnreadCount, count > 0 {
                                UnreadBadge(count: count)
                                    .scaleEffect(0.7)
                                    .offset(x: 6, y: -6)
                            }
                        }
                }
                .accessibilityLabel(messagesAccessibilityLabel)
            }
        }
        .task(id: mode) {
            await app.home.loadIfNeeded(mode, signedIn: app.auth.isSignedIn)
            await app.stories.loadIfNeeded()
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            Task {
                await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                await app.stories.refresh()
            }
        }
        .overlay(alignment: .bottom) {
            if let message = app.home.actionError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .onTapGesture { app.home.clearActionError() }
                    .accessibilityIdentifier("home.banner")
            }
        }
        .sheet(item: $commentsPost) { post in
            PostCommentsSheet(postID: post.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native.home")
        .accessibilityValue(RouteSerializer.serialize(.home(mode)))
    }

    private var messagesAccessibilityLabel: String {
        if let count = app.messaging.accountUnreadCount, count > 0 {
            return "Messages, \(count) unread"
        }
        return "Messages"
    }

    private var modeCaption: some View {
        Text(mode.heroSubtitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .accessibilityIdentifier("home.hero")
            .accessibilityLabel(mode.heroTitle)
    }

    private var offlineBanner: some View {
        Label("Showing cached posts", systemImage: "wifi.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("home.offline")
    }

    private var newerPill: some View {
        Button {
            app.home.acknowledgeNewer(mode)
            HapticEngine.shared.play(.selection)
        } label: {
            Text("New posts")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(app.appearance.accent.color, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.newer")
    }

    @ViewBuilder
    private func feedContent(_ state: HomeModeState) -> some View {
        if mode.requiresAuth && !app.auth.isSignedIn {
            signedOutFollowing
        } else {
            switch state.loadState {
            case .loading where state.items.isEmpty:
                skeleton
            case .failed(let message) where state.items.isEmpty:
                ModulaErrorState(message: message) {
                    Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
                }
                .padding(.top, 28)
                .accessibilityIdentifier("home.error")
            case _ where app.home.visiblePosts(for: mode).isEmpty:
                Group {
                    if state.items.isEmpty {
                        emptyState
                    } else {
                        ModulaEmptyState(
                            title: "Nothing matches this feed",
                            message: "Turn off a customise option in Feeds.",
                            symbol: "number"
                        )
                    }
                }
                .padding(.top, 20)
            default:
                ForEach(app.home.visiblePosts(for: mode)) { post in
                    let resolved = app.posts.resolved(post)
                    PostCard(
                        post: resolved,
                        showsActionRail: ModulaPostMapper.map(resolved).isMediaFirst,
                        isOwnPost: resolved.author?.id == app.auth.account?.accountId,
                        onOpenPost: { openPost(resolved) },
                        onOpenAuthor: { openAuthor(resolved) },
                        onLike: {
                            Task { await app.home.toggleLike(resolved, mode: mode) }
                        },
                        onComment: {
                            commentsPost = resolved
                            HapticEngine.shared.play(.contextOpen)
                        },
                        onRepost: {
                            Task { await app.home.toggleRepost(resolved, mode: mode) }
                        },
                        onSave: {
                            Task { await app.home.toggleSave(resolved, mode: mode) }
                        },
                        onShare: {
                            UIPasteboard.general.string = resolved.shareURL.absoluteString
                            Task { await app.postActions.recordShare(resolved) }
                            HapticEngine.shared.play(.lightImpact)
                        },
                        onMore: {
                            HapticEngine.shared.play(.contextOpen)
                        },
                        onContextAction: { action in
                            handlePostContext(action, post: resolved)
                        },
                        onOpenMedia: { _ in
                            app.navigation.open(.post(resolved.id, .root))
                        },
                        onOpenModule: { module in
                            app.navigation.push(.productHub(.module(module.id, .overview)))
                            HapticEngine.shared.play(.navigation)
                        },
                        videoCoordinator: videoCoordinator
                    )
                    .onAppear {
                        if post.id == state.items.suffix(3).first?.id || post.id == state.items.last?.id {
                            Task { await app.home.loadMore(mode) }
                        }
                    }
                    Divider().opacity(0.25)
                }
                if state.loadState == .loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("home.loading-more")
                }
                if state.loadState == .loaded, let message = state.loadMoreError {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            HapticEngine.shared.play(.selection)
                            Task { await app.home.loadMore(mode) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Retry loading more posts")
                        .accessibilityIdentifier("home.load-more-retry")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private var signedOutFollowing: some View {
        ContentUnavailableView {
            Label("Sign in to see Following", systemImage: "person.2")
        } description: {
            Text("Posts from people you follow appear here after you sign in.")
        } actions: {
            Button("Sign In") {
                app.navigation.requestAuthentication(returningTo: .home(.following))
                HapticEngine.shared.play(.navigation)
            }
            .buttonStyle(.borderedProminent)
            .tint(app.appearance.accent.color)
            .accessibilityIdentifier("home.sign-in")
        }
        .padding(.top, 24)
    }

    private var emptyState: some View {
        Group {
            if mode == .following && app.auth.isSignedIn {
                ContentUnavailableView {
                    Label("Your feed is quiet", systemImage: "moon.zzz")
                } description: {
                    Text("Follow people to fill your Following feed.")
                } actions: {
                    Button("Discover people") {
                        app.navigation.open(.discover(.people))
                        HapticEngine.shared.play(.navigation)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.accent.color)
                    .accessibilityIdentifier("home.empty.discover")
                }
            } else {
                ModulaEmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    symbol: emptySymbol
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("home.empty.\(mode.rawValue)")
    }

    private var emptyTitle: String {
        switch mode {
        case .following: "Your feed is quiet"
        case .forYou: "Nothing ranked yet"
        case .modules: "No module posts yet"
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .following: "Follow people to fill your Following feed."
        case .forYou: "Public posts will show up here as ranking fills in."
        case .modules: "Module updates and announcements appear in this stream."
        }
    }

    private var emptySymbol: String {
        switch mode {
        case .following: "moon.zzz"
        case .forYou: "safari"
        case .modules: "shippingbox"
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.primary.opacity(0.08)).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 120, height: 12)
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 80, height: 10)
                        }
                    }
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(height: 64)
                }
            }
        }
        .padding(.top, 8)
        .redacted(reason: .placeholder)
        .accessibilityIdentifier("home.loading")
    }

    private var showsStoryTray: Bool {
        app.auth.isSignedIn || !app.stories.trayGroups.isEmpty
    }

    private func openStory(_ group: StoryGroup) async {
        if let route = await app.stories.destination(for: group) {
            app.navigation.push(route)
            HapticEngine.shared.play(.navigation)
        }
    }

    private func openPost(_ post: SocialPost) {
        app.postActions.ingest(post)
        app.navigation.open(.post(post.id, .root))
        HapticEngine.shared.play(.navigation)
    }

    private func openAuthor(_ post: SocialPost) {
        guard let author = post.author else { return }
        // Push onto the current Home stack — never hijack the Profile tab root.
        app.navigation.push(.profile(author.routeID, .overview))
        HapticEngine.shared.play(.navigation)
    }

    private func handlePostContext(_ action: ModulaContextAction, post: SocialPost) {
        switch action.id {
        case "save":
            Task { await app.home.toggleSave(post, mode: mode) }
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
            Task { await app.postActions.recordShare(post) }
            HapticEngine.shared.play(.lightImpact)
        case "hide":
            app.postActions.hideLocally(post)
            app.home.syncVisibleEngagement()
        case "edit-post":
            app.navigation.open(.post(post.id, .edit))
        case "delete":
            Task {
                _ = await app.postActions.deletePost(post)
                app.home.syncVisibleEngagement()
            }
        default:
            break
        }
    }
}
