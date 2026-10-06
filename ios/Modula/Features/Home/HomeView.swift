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
    @State private var reportTarget: SocialPost?
    @State private var blockTarget: SocialPost?
    /// True once the story tray has scrolled under the navigation bar; the
    /// tray then "folds" into a small avatar stack beside the title.
    @State private var storyTrayFolded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            // The header "+" is the single create entry on Home.
                            StoryTray(groups: StoryStore.homeTrayGroups(app.stories.trayGroups), compact: true) { group in
                                Task { await openStory(group) }
                            }
                            .padding(.horizontal, -ModulaLayout.contentInset)
                            // Bleed to the screen edges but start the first story on the
                            // content inset (it used to sit 4pt from the edge).
                            .contentMargins(.horizontal, ModulaLayout.contentInset, for: .scrollContent)
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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Bool output keeps this cheap: the action only runs when the
                // fold state flips, not on every scrolled frame.
                geometry.contentOffset.y + geometry.contentInsets.top > 150
            } action: { _, folded in
                withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                    storyTrayFolded = folded
                }
            }
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
            if storyTrayFolded, showsStoryTray, !foldedStoryGroups.isEmpty {
                ToolbarItem(placement: .principal) {
                    foldedStoryTray
                }
            }
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
                ModulaErrorBanner(message: message, identifier: "home.banner") {
                    app.home.clearActionError()
                }
            }
        }
        .sheet(item: $commentsPost) { post in
            PostCommentsSheet(postID: post.id)
        }
        .confirmationDialog(
            "Report this post?",
            isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }),
            titleVisibility: .visible,
            presenting: reportTarget
        ) { post in
            ForEach(["Spam", "Harassment or bullying", "Inappropriate content", "Misinformation", "Something else"], id: \.self) { reason in
                Button(reason, role: .destructive) { report(post, reason: reason) }
            }
            Button("Cancel", role: .cancel) { reportTarget = nil }
        } message: { post in
            Text("Reports about @\(post.author?.handle ?? "this account") are reviewed by Modula.")
        }
        .confirmationDialog(
            "Block this account?",
            isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
            titleVisibility: .visible,
            presenting: blockTarget
        ) { post in
            Button("Block @\(post.author?.handle ?? "author")", role: .destructive) { block(post) }
            Button("Cancel", role: .cancel) { blockTarget = nil }
        } message: { _ in
            Text("They won’t be able to follow you or see your posts, and you won’t see theirs.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native.home")
        .accessibilityValue(RouteSerializer.serialize(.home(mode)))
    }

    private var messagesAccessibilityLabel: String {
        if let count = app.messaging.accountUnreadCount, count > 0 {
            return String(localized: "Messages, \(count) unread")
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
                            // Settings → Sharing decides copy / iOS sheet / Modula sheet.
                            PostSharing.share(resolved, app: app)
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
                        videoCoordinator: videoCoordinator,
                        style: .immersive
                    )
                    // Posts run full width and flow around the Edge Picker bulge.
                    .padding(.trailing, -trailingInteractionInset)
                    .padding(.leading, -leadingInteractionInset)
                    .modulaEdgeFlow()
                    .modulaScrollReveal()
                    .onAppear {
                        if post.id == state.items.suffix(3).first?.id || post.id == state.items.last?.id {
                            Task { await app.home.loadMore(mode) }
                        }
                    }
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
        .modulaShimmer()
        .accessibilityIdentifier("home.loading")
    }

    private var showsStoryTray: Bool {
        app.auth.isSignedIn || !app.stories.trayGroups.isEmpty
    }

    /// Up to three people with stories (unseen first) for the folded tray.
    private var foldedStoryGroups: [StoryGroup] {
        let real = app.stories.trayGroups.filter { !$0.isComposerPlaceholder }
        let unseen = real.filter { $0.ring == .unseen }
        return Array((unseen.isEmpty ? real : unseen).prefix(3))
    }

    private var foldedStoryTray: some View {
        let groups = foldedStoryGroups
        let unseenCount = app.stories.trayGroups.filter { !$0.isComposerPlaceholder && $0.ring == .unseen }.count
        return Button {
            guard let first = groups.first else { return }
            Task { await openStory(first) }
        } label: {
            HStack(spacing: ModulaSpacing.xs) {
                Text("Modula")
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: -8) {
                    ForEach(groups) { group in
                        ModulaAvatar(initials: group.author.initials, url: group.author.avatarURL, size: 24)
                            .padding(1.5)
                            .background(
                                Circle().strokeBorder(
                                    group.ring == .unseen ? app.appearance.accent.color : Color.secondary.opacity(0.4),
                                    lineWidth: 1.5
                                )
                            )
                    }
                }
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .top).combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unseenCount > 0 ? String(localized: "Stories, \(unseenCount) new") : String(localized: "Stories"))
        .accessibilityHint("Opens the first story")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.stories.folded")
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

    private func report(_ post: SocialPost, reason: String) {
        reportTarget = nil
        guard let author = post.author else { return }
        Task {
            if await app.profile.report(profileID: author.id, category: reason, details: "Post \(post.id)") {
                app.postActions.hideLocally(post)
                app.home.syncVisibleEngagement()
                app.navigation.flash("Thanks, report sent", symbol: "checkmark.shield")
            }
        }
    }

    private func block(_ post: SocialPost) {
        blockTarget = nil
        guard let author = post.author else { return }
        Task {
            if await app.profile.block(profileID: author.id) {
                app.postActions.hideLocally(post)
                app.home.syncVisibleEngagement()
                app.navigation.flash("Blocked @\(author.handle)", symbol: "hand.raised")
            }
        }
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
            app.navigation.flash("Link copied", symbol: "link")
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
        case "not-interested":
            app.postActions.hideLocally(post)
            app.home.syncVisibleEngagement()
            app.navigation.flash("You’ll see fewer posts like this", symbol: "eye.slash")
        case "notify":
            app.navigation.flash("Post notifications aren’t available yet", symbol: "bell.slash")
        case "report":
            reportTarget = post
            HapticEngine.shared.play(.warning)
        case "follow-author":
            if let author = post.author {
                Task {
                    if await app.profile.follow(profileID: author.id, handle: author.handle) {
                        app.navigation.flash("Following @\(author.handle)", symbol: "person.badge.plus")
                    }
                }
            }
        case "lists-author":
            app.navigation.flash("Lists aren’t available yet", symbol: "list.bullet.rectangle")
        case "mute-author":
            if let author = post.author {
                Task {
                    if await app.profile.mute(profileID: author.id) {
                        app.navigation.flash("Muted @\(author.handle)", symbol: "speaker.slash")
                    }
                }
            }
        case "block-author":
            blockTarget = post
            HapticEngine.shared.play(.warning)
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
