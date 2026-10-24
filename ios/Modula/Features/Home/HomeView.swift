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
    @Environment(\.modulaHeroScope) private var heroScope
    @Environment(\.colorScheme) private var colorScheme
    /// Ambient colour: the post most on screen tints the page background.
    /// Isolated in its own observable so ambient changes never re-run this (large) body mid-scroll.
    @State private var ambient = HomeAmbientModel()
    /// Comments pulled down collapse into this floating bubble; tap it to reopen.
    @State private var commentsBubble: SocialPost?
    @State private var lastCommentsPost: SocialPost?
    @State private var bubbleExpiry: Task<Void, Never>?

    var body: some View {
        let state = app.home.state(for: mode)
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !showsStoryTray { modeCaption }
                            if showsStoryTray {
                                let trayGroups = StoryStore.homeTrayGroups(app.stories.trayGroups)
                                HStack(alignment: .center, spacing: 10) {
                                    // One header row: Stories + the feed caption ("Following").
                                    Text("Stories")
                                        .font(.headline)
                                    Text(mode.heroSubtitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.primary.opacity(0.72))
                                        .lineLimit(1)
                                        .accessibilityIdentifier("home.hero")
                                        .accessibilityLabel(mode.heroTitle)
                                    Spacer(minLength: 8)
                                    Button {
                                        app.navigation.push(.reels(.feed))
                                        HapticEngine.shared.play(.navigation)
                                    } label: {
                                        Label("Reels", systemImage: "play.rectangle.fill")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .frame(height: 26)
                                            .background(app.appearance.accent.color.gradient, in: Capsule())
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .shadow(color: app.appearance.accent.color.opacity(0.25), radius: 5, y: 2)
                                    // 44pt hit area without shifting the pill off the content edge.
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Watch Reels")
                                    .accessibilityIdentifier("home.open-reels")
                                }
                                StoryTray(
                                    groups: trayGroups,
                                    compact: false,
                                    onSelect: { group in Task { await openStory(group) } },
                                    onCreate: {
                                        app.navigation.push(.stories(.create))
                                        HapticEngine.shared.play(.navigation)
                                    }
                                )
                                // Edge to edge: bleed past both content insets so rings scroll off-screen
                                // under the trailing fade instead of being clipped mid-ring.
                                .padding(.leading, -(ModulaLayout.contentInset + leadingInteractionInset))
                                .padding(.trailing, -(ModulaLayout.contentInset + trailingInteractionInset))
                                .contentMargins(.leading, ModulaLayout.contentInset + leadingInteractionInset, for: .scrollContent)
                                .transition(.opacity)
                            }
                            if app.home.isOfflineHint && !state.items.isEmpty {
                                offlineBanner
                            }
                        }
                        .padding(.leading, ModulaLayout.contentInset + leadingInteractionInset)
                        .padding(.trailing, ModulaLayout.contentInset + trailingInteractionInset)

                        feedContent(state)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, shellChromeMetrics.contentBottomInset)
                    .modulaPullContentEffects()
                }
            }
            .modulaSoftScrollEdge()
            .onScrollGeometryChange(for: Bool.self) { [storyTrayFolded] geometry in
                // Bool output keeps this cheap: the action only runs when the
                // fold state flips. Hysteresis stops the toolbar swap flickering
                // (and the header jumping) when scrolling back up near the Stories row.
                let y = geometry.contentOffset.y + geometry.contentInsets.top
                return storyTrayFolded ? y > 110 : y > 170
            } action: { _, folded in
                withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                    storyTrayFolded = folded
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { HomeMascotCompanion.noteActivity() }
                ModulaScrollActivity.shared.set(phase.isScrolling)
            }
            .modulaShellPullActions {
                await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
                await app.stories.refresh()
                HapticEngine.shared.play(.lightImpact)
                ModulaMascotEvent.post(.refresh)
            }

            if state.newerAvailable {
                newerPill
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            HomeMascotCompanion()
                .padding(.horizontal, 8)
                .frame(height: 260)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .background { HomeAmbientLayer(model: ambient, update: updateAmbient) }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Modula")
        .navigationBarTitleDisplayMode(.inline)
        .modulaSidebarTrigger()
        .toolbar {
            if storyTrayFolded, showsStoryTray, !foldedStoryGroups.isEmpty {
                ToolbarItem(placement: .principal) {
                    foldedStoryTray
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Group {
                        switch app.appearance.brandWordmark {
                        case .modula:
                            ModulaWordmark(height: ModulaLayout.homeWordmarkHeight)
                        case .moliboos:
                            MoliboosWordmark(height: ModulaLayout.homeWordmarkHeight)
                        }
                    }
                    .accessibilityAddTraits(.isHeader)
                }
            }
            // Create + Messages share one glass capsule instead of two mismatched pills.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Create", systemImage: "plus") {
                    app.navigation.open(.compose(.post))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.create")
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
        .sheet(item: $commentsPost, onDismiss: collapseCommentsToBubble) { post in
            PostCommentsSheet(postID: post.id, commentCount: post.replyCount, postAuthorID: post.author?.id)
        }
        .overlay(alignment: .bottomTrailing) {
            if let bubble = commentsBubble {
                CommentsFloatingBubble(post: app.posts.resolved(bubble), accent: app.appearance.accent.color) {
                    reopenComments(bubble)
                } onClose: {
                    withAnimation(.spring(duration: 0.3)) { commentsBubble = nil }
                }
                .padding(.trailing, 16 + trailingInteractionInset)
                .padding(.bottom, 70)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            }
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
                    .padding(.horizontal, ModulaLayout.contentInset)
            case .failed(let message) where state.items.isEmpty:
                ModulaErrorState(message: message) {
                    Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
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
                .padding(.horizontal, ModulaLayout.contentInset)
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
                            if !resolved.liked { ModulaMascotEvent.post(.like) }
                            Task { await app.home.toggleLike(resolved, mode: mode) }
                        },
                        onComment: {
                            openComments(resolved)
                        },
                        onRepost: {
                            ModulaMascotEvent.post(.repost)
                            Task { await app.home.toggleRepost(resolved, mode: mode) }
                        },
                        onSave: {
                            if !resolved.saved { ModulaMascotEvent.post(.save) }
                            Task { await app.home.toggleSave(resolved, mode: mode) }
                        },
                        onShare: {
                            // Settings → Sharing decides copy / iOS sheet / Modula sheet.
                            ModulaMascotEvent.post(.share)
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
                    // Swipe left = share, right = save. Nested PDF/media carousels keep paging.
                    .modifier(PostSwipeActions(
                        enabled: resolved.media.count <= 1,
                        saved: resolved.saved,
                        accent: app.appearance.accent.color,
                        onSave: {
                            if !resolved.saved { ModulaMascotEvent.post(.save) }
                            Task { await app.home.toggleSave(resolved, mode: mode) }
                            app.navigation.flash(resolved.saved ? "Removed from Bookmarks" : "Saved to Bookmarks", symbol: resolved.saved ? "bookmark.slash" : "bookmark.fill")
                        },
                        onShare: {
                            ModulaMascotEvent.post(.share)
                            PostSharing.share(resolved, app: app)
                        }
                    ))
                    .padding(.horizontal, ModulaLayout.postBleedGutter)
                    .modulaEdgeFlow()
                    .modulaScrollReveal()
                    .onScrollVisibilityChange(threshold: 0.55) { visible in
                        if visible, ambient.postID != resolved.id { ambient.postID = resolved.id }
                    }
                    .onAppear {
                        prefetchAhead(after: post)
                        if post.id == state.items.suffix(3).first?.id || post.id == state.items.last?.id {
                            Task { await app.home.loadMore(mode) }
                        }
                    }
                }
                if mode != .forYou, state.loadState == .loaded, app.home.visiblePosts(for: mode).count < 3 {
                    HomeCatchUpSection(
                        excluding: Set(app.home.visiblePosts(for: mode).map(\.id)),
                        onOpen: { openPost($0) }
                    )
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
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
        .padding(.horizontal, ModulaLayout.contentInset)
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
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.primary.opacity(0.08)).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Color.primary.opacity(0.10)).frame(width: 128, height: 12)
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 72, height: 10)
                        }
                        Spacer()
                        Circle().fill(Color.primary.opacity(0.06)).frame(width: 28, height: 28)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary.opacity(index == 1 ? 0.07 : 0.05))
                        .frame(height: index == 1 ? 280 : 220)
                        .overlay(alignment: .bottomTrailing) {
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 44, height: 140)
                                .padding(12)
                        }
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 40)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
            }
        }
        .padding(.top, 8)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading posts")
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
                ModulaWordmark(height: 22)
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
            // Ring → full story zoom (and swipe down shrinks it back into the ring).
            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "story", key: group.id), for: route)
            app.navigation.push(route)
            HapticEngine.shared.play(.navigation)
        }
    }

    // MARK: Comments bubble

    private func openComments(_ post: SocialPost) {
        bubbleExpiry?.cancel()
        withAnimation(.spring(duration: 0.3)) { commentsBubble = nil }
        lastCommentsPost = post
        commentsPost = post
        HapticEngine.shared.play(.contextOpen)
    }

    private func reopenComments(_ post: SocialPost) {
        HapticEngine.shared.play(.lightImpact)
        openComments(post)
    }

    private func collapseCommentsToBubble() {
        guard let post = lastCommentsPost else { return }
        lastCommentsPost = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.7)) {
            commentsBubble = post
        }
        bubbleExpiry?.cancel()
        bubbleExpiry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { commentsBubble = nil }
        }
    }

    // MARK: Ambient colour

    private func updateAmbient() async {
        guard !ModulaEffectGate.reduceMotion(reduceMotion), let id = ambient.postID,
              let post = app.home.visiblePosts(for: mode).first(where: { $0.id == id }) else { return }
        // Debounce flings: only settle on posts that stay on screen.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        let media = app.posts.resolved(post).media.first
        guard let media, let url = media.thumbnailURL ?? media.previewURL ?? (media.isVideo ? nil : media.url) else {
            withAnimation(.easeInOut(duration: 0.9)) { ambient.color = nil }
            return
        }
        let colour = await ModulaImageTint.tint(for: url, cacheKey: "ambient:\(url.path)", client: app.client)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.9)) { ambient.color = colour }
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


// MARK: - Image prefetch (keeps the next cards' photos decoded before they scroll in)

extension HomeView {
    fileprivate func prefetchAhead(after post: SocialPost) {
        let items = app.home.visiblePosts(for: mode)
        guard let index = items.firstIndex(where: { $0.id == post.id }) else { return }
        for next in items.dropFirst(index + 1).prefix(4) {
            for media in next.media.prefix(2) {
                let attachment = ModulaPostMapper.attachment(media)
                guard attachment.kind == .image else { continue }
                ModulaImagePrefetcher.prefetch(
                    url: attachment.bestPreviewURL ?? attachment.playableURL,
                    cacheKey: "attachment:\(attachment.id):feed-image",
                    maximumPixelSize: 2_000,
                    client: app.client
                )
            }
        }
    }
}


// MARK: - Post swipe actions

/// Horizontal swipe on a feed post: left shares, right saves. The pan only begins for
/// clearly horizontal movement away from both screen edges (back-swipe + Edge Picker).
/// Nested horizontal scroll views (PDF pages, galleries) keep priority.
/// Disabled while a reaction/emoji picker is presented (`PostReactionPickerPresentedKey`).
struct PostSwipeActions: ViewModifier {
    var enabled: Bool
    var saved: Bool
    var accent: Color
    var onSave: () -> Void
    var onShare: () -> Void
    @AppStorage("gestures.postSwipeActions") private var allowed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var armed = false
    @State private var reactionPickerPresented = false
    private var threshold: CGFloat { PostGestureThresholds.swipeCommitDistance }
    /// Share/save pan is live only when settings allow it and no reaction picker is up.
    private var swipeArmed: Bool { enabled && allowed && !reactionPickerPresented }

    func body(content: Content) -> some View {
        Group {
            if enabled && allowed {
                content
                    .offset(x: (reduceMotion || reactionPickerPresented) ? 0 : offset)
                    .overlay {
                        if reduceMotion, !reactionPickerPresented, abs(offset) > 8 {
                            (offset > 0 ? Color.orange : accent).opacity(0.16 * min(abs(offset) / threshold, 1))
                                .allowsHitTesting(false)
                        }
                    }
                    .background {
                        HStack {
                            if !reactionPickerPresented, offset > 0 {
                                cue(saved ? "bookmark.slash.fill" : "bookmark.fill", saved ? "Unsave" : "Save", .orange, offset)
                            }
                            Spacer(minLength: 0)
                            if !reactionPickerPresented, offset < 0 {
                                cue("square.and.arrow.up", "Share", accent, -offset)
                            }
                        }
                        .padding(.horizontal, 22)
                        .allowsHitTesting(false)
                    }
                    // Keep the recognizer installed; flip `isEnabled` so an in-flight pan cancels
                    // the moment the reaction picker preference becomes true.
                    .gesture(PostSwipePan(isEnabled: swipeArmed, onChange: changed, onEnd: ended))
            } else {
                content
            }
        }
        .onPreferenceChange(PostReactionPickerPresentedKey.self) { presented in
            reactionPickerPresented = presented
            if presented {
                armed = false
                offset = 0
            }
        }
    }

    private func cue(_ symbol: String, _ title: String, _ tint: Color, _ reveal: CGFloat) -> some View {
        let p = min(reveal / threshold, 1)
        return VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(tint).shadow(color: tint.opacity(0.5), radius: armed ? 10 : 3))
                .scaleEffect(reduceMotion ? 1 : (armed ? 1.12 : 0.6 + 0.4 * p))
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint)
        }
        .opacity(Double(p))
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.6), value: armed)
        .accessibilityHidden(true)
    }

    private func changed(_ dx: CGFloat) {
        guard !reactionPickerPresented else { return }
        offset = abs(dx) > threshold ? (dx > 0 ? 1 : -1) * (threshold + (abs(dx) - threshold) * 0.3) : dx
        let now = abs(dx) > threshold
        if now != armed {
            armed = now
            HapticEngine.shared.play(now ? .dragThreshold : .selection)
        }
    }

    private func ended(_ dx: CGFloat, _ velocity: CGFloat) {
        // Picker took over — never commit share/save from a cancelled or leftover pan.
        guard !reactionPickerPresented else {
            armed = false
            offset = 0
            return
        }
        let commit = abs(dx) > threshold || (abs(dx) > 50 && abs(velocity) > 1000)
        if commit {
            if dx < 0 { onShare() } else { onSave() }
        }
        armed = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.72)) { offset = 0 }
    }
}

struct PostSwipePan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed: onChange(dx)
        case .ended: onEnd(dx, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: onEnd(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard isEnabled else { return false }
            guard let pan = gesture as? UIPanGestureRecognizer, let window = pan.view?.window else { return false }
            let start = pan.location(in: window).x
            // Leave both edges to system back-swipe and the Edge Picker.
            if start < PostGestureThresholds.swipeLeadingExclusion
                || start > window.bounds.width - PostGestureThresholds.swipeTrailingExclusion {
                return false
            }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 2
        }

        /// PDF page sliding and media carousels own horizontal pans; this waits for them to fail.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            if let scroll = other.view as? UIScrollView, other == scroll.panGestureRecognizer {
                return scroll.contentSize.width > scroll.bounds.width + 1
            }
            return false
        }
    }
}

/// Collapsed comments: a glass bubble that floats over Home until tapped or dismissed.
struct CommentsFloatingBubble: View {
    let post: SocialPost
    var accent: Color
    var onOpen: () -> Void
    var onClose: () -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(accent.gradient))
                    .modulaGlass(in: Circle(), interactive: true, tint: accent.opacity(0.25))
                    .shadow(color: accent.opacity(0.45), radius: 14, y: 6)
                if post.replyCount > 0 {
                    Text(post.replyCount > 99 ? "99+" : "\(post.replyCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .offset(drag)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    // Fling it away to dismiss; otherwise it springs home.
                    if abs(value.translation.width) > 90 || value.translation.height > 90 {
                        onClose()
                    }
                    withAnimation(.spring(duration: 0.3)) { drag = .zero }
                }
        )
        .contextMenu {
            Button("Open comments", systemImage: "bubble.left.and.bubble.right", action: onOpen)
            Button("Dismiss", systemImage: "xmark", action: onClose)
        }
        .accessibilityLabel("Comments, \(post.replyCount)")
        .accessibilityHint("Reopens the comments you were reading")
        .accessibilityAction(named: "Dismiss", onClose)
        .accessibilityIdentifier("home.comments.bubble")
    }
}

/// Ambient tint state, observed only by `HomeAmbientLayer`.
@MainActor @Observable
final class HomeAmbientModel {
    var postID: SocialPostID?
    var color: Color?
}

/// Soft wash of the on-screen post's dominant colour. Sampled from a tiny thumbnail
/// through the shared image pipeline and cached (`ModulaImageTint`). Off with Reduce Motion.
private struct HomeAmbientLayer: View {
    let model: HomeAmbientModel
    let update: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let color = model.color, !ModulaEffectGate.reduceMotion(reduceMotion) {
                Rectangle()
                    .fill(color.opacity(colorScheme == .dark ? 0.26 : 0.16))
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.45), location: 0.45), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: model.postID) { await update() }
    }
}


/// Short feed? Fill the space with suggested posts from For You (already-fetched data, no new endpoint).
private struct HomeCatchUpSection: View {
    let excluding: Set<SocialPostID>
    var onOpen: (SocialPost) -> Void
    @Environment(AppEnvironment.self) private var app

    private var posts: [SocialPost] {
        Array(app.home.visiblePosts(for: .forYou)
            .filter { !excluding.contains($0.id) }
            .filter { post in
                guard let a = post.author else { return false }
                if let own = app.profile.ownProfile, own.handle.caseInsensitiveCompare(a.handle) == .orderedSame { return false }
                if ModulaFixtureFilter.isFixture(name: a.displayName, handle: a.handle) { return false }
                return !(post.text ?? "").isEmpty || !post.media.isEmpty
            }
            .prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModulaSectionHeader(title: "Catch up", subtitle: "Suggested for you")
            if posts.isEmpty {
                Text("You're all caught up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(posts) { post in
                Button { onOpen(post) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ModulaAvatar(
                            initials: post.author?.initials ?? "?",
                            url: post.author?.avatarURL,
                            size: 34,
                            name: post.author?.displayName
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(post.author?.displayName ?? "Modula")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let text = post.text, !text.isEmpty {
                                Text(text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                        if let thumb = post.media.lazy.compactMap({ $0.thumbnailURL ?? $0.previewURL ?? $0.url }).first {
                            AsyncImage(url: thumb) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.primary.opacity(0.06)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(12)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
            }
        }
        .task { await app.home.loadIfNeeded(.forYou, signedIn: app.auth.isSignedIn) }
        .accessibilityIdentifier("home.catch-up")
    }
}
