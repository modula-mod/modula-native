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
    @State private var feedFilter: HomeFeedFilter = HomeFeedFilter(rawValue: UserDefaults.standard.string(forKey: "home.feedFilter.default") ?? "") ?? .all
    @AppStorage("home.feedFilter.default") private var defaultFeedFilterRaw = HomeFeedFilter.all.rawValue
    @State private var editingQuickActions = false
    @State private var showsBackToTop = false
    @AppStorage(HomeQuickAction.storageKey) private var quickActionsRaw = HomeQuickAction.defaultRaw

    var body: some View {
        let state = app.home.state(for: mode)
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Vertical rhythm on the spacing scale: sections 12pt apart, a section's own
                    // header and content 8pt apart (Gestalt proximity), matching the Home reference.
                    LazyVStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
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
                                            .background(app.appearance.liveAccent.gradient, in: Capsule())
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .shadow(color: app.appearance.liveAccent.opacity(0.25), radius: 5, y: 2)
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

                        greetingHero
                            .padding(.leading, ModulaLayout.contentInset + leadingInteractionInset)
                            .padding(.trailing, ModulaLayout.contentInset + trailingInteractionInset)
                            .padding(.bottom, ModulaSpacing.xxs)

                        if HomeTodayFlags.isEnabled {
                            HomeTodayCard()
                                .padding(.leading, ModulaLayout.contentInset + leadingInteractionInset)
                                .padding(.trailing, ModulaLayout.contentInset + trailingInteractionInset)
                        }

                        feedFilterChips
                            .padding(.bottom, ModulaSpacing.xxs)

                        feedContent(state)
                    }
                    .padding(.top, ModulaSpacing.xxs)
                    .padding(.bottom, shellChromeMetrics.contentBottomInset)
                    .modulaPullContentEffects()
                    .modulaScrollsToTopOnReselect(.home)
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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 2_400
            } action: { _, far in
                withAnimation(.easeOut(duration: 0.2)) { showsBackToTop = far }
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
            } else if showsBackToTop {
                backToTopPill
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
                CommentsFloatingBubble(post: app.posts.resolved(bubble), accent: app.appearance.liveAccent) {
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

    /// Greeting hero (reference: scenic card, name in display type, glass quick actions inside the card).
    /// Name comes from the signed-in profile, the scene/greeting from the device clock.
    private var greetingHero: some View {
        let now = Date()
        let name = HomeGreeting.name(
            displayName: app.profile.ownProfile?.displayName,
            handle: app.profile.ownProfile?.handle ?? app.auth.account?.primaryHandle
        )
        let hour = Calendar.current.component(.hour, from: now)
        let scene = (hour >= 20 || hour < 6) ? "SceneMoonLake" : "SceneMountainLake"
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Label(HomeGreeting.line(for: now), systemImage: HomeGreeting.symbol(for: now))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .symbolRenderingMode(.multicolor)
                    Spacer(minLength: 8)
                    Text(HomeGreeting.dateChip(now))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .modulaGlass(in: Capsule(), interactive: false)
                }
                Text(name)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                Text(HomeMolibooGreeting.mood(hour: hour, streak: MascotProgressStore.shared.streak))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if MascotProgressStore.shared.streak > 1 {
                    Label("\(MascotProgressStore.shared.streak)-day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 10).frame(height: 26)
                        .modulaGlass(in: Capsule(), interactive: false, tint: .orange.opacity(0.35))
                        .accessibilityIdentifier("home.greeting.streak")
                }
                Text("Your space. Your people. Your modules.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                Button {
                    app.navigation.open(.settings(.whatsNew(.root)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    HStack(spacing: 8) {
                        Text("What’s new")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityIdentifier("home.greeting.whats-new")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, ModulaLayout.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 14)
            greetingActions
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background {
            ZStack {
                LinearGradient(colors: [app.appearance.liveAccent, Color(hex: "#1B3A4B")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(scene)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.black.opacity(0.42), .black.opacity(0.05), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(alignment: .trailing) {
            Image(HomeMolibooGreeting.sprout(hour: hour))
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                .padding(.trailing, 12)
                .offset(y: -6)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.greeting")
    }

    private var greetingActions: some View {
        ModulaGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(HomeQuickAction.decode(quickActionsRaw)) { item in
                    greetingAction(item.title, item.symbol, "home.greeting.\(item.rawValue)") { run(item) }
                        .contextMenu {
                            Button("Customise quick actions", systemImage: "slider.horizontal.3") { editingQuickActions = true }
                        }
                }
            }
        }
        .sheet(isPresented: $editingQuickActions) {
            HomeQuickActionEditor(raw: $quickActionsRaw)
                .presentationDetents([.medium, .large])
        }
    }

    private func run(_ item: HomeQuickAction) {
        switch item {
        case .write: app.navigation.open(.compose(.post))
        case .create:
            if app.stories.capabilities.create { app.navigation.push(.stories(.create)) } else { app.navigation.open(.compose(.post)) }
        case .vault:
            if let product = app.catalogue.product("digital.modula.vault-notes") {
                app.navigation.open(.productHub(.module(product.id, .overview)))
            } else {
                app.navigation.open(.productHub(.featured))
            }
        case .moliboos: app.navigation.open(.settings(.moliboo))
        case .browse: app.navigation.open(.discover(.trending))
        case .reels: app.navigation.push(.reels(.feed))
        case .messages: app.navigation.push(.messages(.inbox))
        case .modules: app.navigation.open(.productHub(.featured))
        case .saved: app.navigation.open(.saved(.root))
        }
    }

    private func greetingAction(_ title: String, _ symbol: String, _ identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.navigation)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true, tint: .white.opacity(0.08), specular: true)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    /// Reference filter chips; each filters the loaded feed by real post fields.
    private var feedFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeFeedFilter.allCases) { filter in
                    let selected = feedFilter == filter
                    Button {
                        withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                            feedFilter = filter
                        }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label(filter.title, systemImage: filter.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selected ? app.appearance.liveAccent : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(selected ? app.appearance.liveAccent.opacity(0.14) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? app.appearance.liveAccent.opacity(0.45) : .clear, lineWidth: 1))
                            .modulaGlass(in: Capsule(), interactive: true)
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Long-press: make this the filter Home opens with.
                    .contextMenu {
                        let count = app.home.visiblePosts(for: mode).filter(filter.matches).count
                        Text("\(count) loaded \(count == 1 ? "post" : "posts")")
                        if defaultFeedFilterRaw == filter.rawValue {
                            Button("Default filter", systemImage: "checkmark") {}
                                .disabled(true)
                        } else {
                            Button("Open Home with \(filter.title)", systemImage: "pin") {
                                defaultFeedFilterRaw = filter.rawValue
                                feedFilter = filter
                                app.navigation.flash("Home opens with \(filter.title)", symbol: filter.symbol)
                            }
                        }
                        if defaultFeedFilterRaw != HomeFeedFilter.all.rawValue {
                            Button("Reset to All", systemImage: "arrow.uturn.backward") {
                                defaultFeedFilterRaw = HomeFeedFilter.all.rawValue
                                feedFilter = .all
                            }
                        }
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint("Long-press to make this the default")
                    .accessibilityIdentifier("home.filter.\(filter.rawValue)")
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset + leadingInteractionInset)
        }
        .scrollClipDisabled()
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

    private var backToTopPill: some View {
        Button {
            ModulaTabReselect.post(.home)
            HapticEngine.shared.play(.selection)
        } label: {
            Label("Back to top", systemImage: "arrow.up")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .modulaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.backToTop")
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
                .background(app.appearance.liveAccent, in: Capsule())
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
                // Perf: filter + resolve the feed once per body pass instead of three times.
                let visiblePosts = HomeFeedOrdering.friendsFirst(
                    app.home.visiblePosts(for: mode).filter(feedFilter.matches),
                    friendIDs: mode == .following ? [] : Set(app.home.state(for: .following).items.compactMap { $0.author?.id }),
                    ownID: app.auth.account?.accountId
                )
                if visiblePosts.isEmpty {
                    ModulaEmptyState(title: "No \(feedFilter.title.lowercased()) yet", message: "Try another filter or pull to refresh.", symbol: feedFilter.symbol)
                        .padding(.horizontal, ModulaLayout.contentInset)
                        .padding(.top, 20)
                }
                ForEach(visiblePosts) { post in
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
                        accent: app.appearance.liveAccent,
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
                    .modulaScrollReveal()
                    .onScrollVisibilityChange(threshold: 0.55) { visible in
                        if visible, ambient.postID != resolved.id { ambient.postID = resolved.id }
                    }
                    .onAppear {
                        ModulaPerf.mark("firstFeedRow")
                        prefetchAhead(after: post, in: visiblePosts)
                        if post.id == state.items.suffix(3).first?.id || post.id == state.items.last?.id {
                            Task { await app.home.loadMore(mode) }
                        }
                    }
                }
                if mode != .forYou, state.loadState == .loaded, visiblePosts.count < 3 {
                    HomeCatchUpSection(
                        excluding: Set(visiblePosts.map(\.id)),
                        onOpen: { openPost($0) }
                    )
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                if state.loadState == .loaded, !state.hasMore, state.nextCursor == nil,
                   state.loadMoreError == nil, visiblePosts.count >= 3 {
                    HomeCaughtUpMarker {
                        Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 20)
                }
                if state.loadState == .loadingMore {
                    // Enhancements-50: a post-shaped skeleton holds the slot the next page fills.
                    ModulaSkeletonRow(showsMedia: false)
                        .padding(.horizontal, ModulaLayout.contentInset)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading more posts")
                        .accessibilityIdentifier("home.loading-more")
                }
                if state.loadState == .loaded, let message = state.loadMoreError {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            HapticEngine.shared.play(.selection)
                            Task { await app.home.loadMore(mode) }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, ModulaSpacing.lg).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .modulaAccentCTA()
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
            .tint(app.appearance.liveAccent)
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
                    .tint(app.appearance.liveAccent)
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
                                    group.ring == .unseen ? app.appearance.liveAccent : Color.secondary.opacity(0.4),
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
    /// Uses the list the ForEach already built: recomputing `visiblePosts` (filter + resolve
    /// over the whole feed) on every row appearance was O(n²) while scrolling.
    fileprivate func prefetchAhead(after post: SocialPost, in items: [SocialPost]) {
        guard let index = items.firstIndex(where: { $0.id == post.id }) else { return }
        for next in items.dropFirst(index + 1).prefix(4) {
            for media in next.media.prefix(2) {
                let attachment = ModulaPostMapper.attachment(media)
                guard attachment.kind == .image else { continue }
                ModulaImagePrefetcher.prefetch(
                    url: attachment.bestPreviewURL ?? attachment.playableURL,
                    cacheKey: "attachment:\(attachment.id):feed-image",
                    maximumPixelSize: ModulaFeedImage.maxPixels,
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
                            ModulaDownsampledImage(url: thumb, pointSize: 56)
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

/// Home feed filter chips. Every case filters on fields the feed API already returns.
enum HomeFeedFilter: String, CaseIterable, Identifiable {
    case all, media, video, links, modules, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .media: "Photos"
        case .video: "Videos"
        case .links: "Links"
        case .modules: "Modules"
        case .text: "Thoughts"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .media: "photo.on.rectangle"
        case .video: "play.rectangle"
        case .links: "link"
        case .modules: "shippingbox"
        case .text: "text.quote"
        }
    }
    func matches(_ post: SocialPost) -> Bool {
        switch self {
        case .all: true
        case .media: post.hasMedia && !(post.kind == .video || post.kind == .movie)
        case .video: post.kind == .video || post.kind == .movie
        case .links: post.link != nil
        case .modules: post.module != nil
        case .text: !post.hasMedia && post.link == nil && post.module == nil
        }
    }
}


// MARK: - Moliboo greeting (time of day + on-device streak from MascotProgressStore)

enum HomeMolibooGreeting {
    static func mood(hour: Int, streak: Int) -> String {
        if streak >= 7 { return "A whole week together. Your Moliboo is glowing." }
        if streak >= 3 { return "\(streak) days in a row. Keep it going." }
        switch hour {
        case 5..<12: return "Fresh start. What will you build today?"
        case 12..<17: return "Build. Create. Explore."
        case 17..<21: return "Golden hour. Catch up with your people."
        default: return "Winding down. Your Moliboo is getting sleepy."
        }
    }
    /// Bundled sprout art per part of the day.
    static func sprout(hour: Int) -> String {
        switch hour {
        case 5..<12: "SproutSticker01_15_fitness"
        case 12..<17: "SproutBuilder"
        case 17..<21: "SproutSticker01_07_music_producer"
        default: "SproutSticker01_29_meditation"
        }
    }
}

// MARK: - Friends-first ordering
//
// Accounts the viewer follows are taken from the authors in the loaded Following feed (no
// separate follow-graph route is cached on device). Their posts from the last 24 hours move to
// the top, keeping server order within each group.
enum HomeFeedOrdering {
    static func friendsFirst(_ posts: [SocialPost], friendIDs: Set<String>, ownID: String?, now: Date = .now) -> [SocialPost] {
        guard !friendIDs.isEmpty else { return posts }
        let cutoff = now.addingTimeInterval(-86_400)
        var fresh: [SocialPost] = []
        var rest: [SocialPost] = []
        for post in posts {
            if let id = post.author?.id, id != ownID, friendIDs.contains(id), post.createdAt > cutoff { fresh.append(post) } else { rest.append(post) }
        }
        return fresh + rest
    }
}

// MARK: - Customisable quick actions

enum HomeQuickAction: String, CaseIterable, Identifiable {
    case write, create, vault, moliboos, browse, reels, messages, modules, saved
    static let storageKey = "home.quickActions"
    static let defaultRaw = "write,create,vault,moliboos,browse"
    static let maxCount = 5
    var id: String { rawValue }
    var title: String {
        switch self {
        case .write: "Write"
        case .create: "Create"
        case .vault: "Vault"
        case .moliboos: "Moliboos"
        case .browse: "Browse"
        case .reels: "Reels"
        case .messages: "Messages"
        case .modules: "Modules"
        case .saved: "Saved"
        }
    }
    var symbol: String {
        switch self {
        case .write: "square.and.pencil"
        case .create: "sparkles"
        case .vault: "doc.text"
        case .moliboos: "pawprint"
        case .browse: "safari"
        case .reels: "play.rectangle"
        case .messages: "message"
        case .modules: "shippingbox"
        case .saved: "bookmark"
        }
    }
    static func decode(_ raw: String) -> [HomeQuickAction] {
        let items = raw.split(separator: ",").compactMap { HomeQuickAction(rawValue: String($0)) }
        return items.isEmpty ? decode(defaultRaw) : Array(items.prefix(maxCount))
    }
}

struct HomeQuickActionEditor: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    private var selected: [HomeQuickAction] { HomeQuickAction.decode(raw) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeQuickAction.allCases) { item in
                        let on = selected.contains(item)
                        Button {
                            var list = selected
                            if on { if list.count > 1 { list.removeAll { $0 == item } } }
                            else if list.count < HomeQuickAction.maxCount { list.append(item) }
                            raw = list.map(\.rawValue).joined(separator: ",")
                            HapticEngine.shared.play(.selection)
                        } label: {
                            HStack {
                                Label(item.title, systemImage: item.symbol).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? app.appearance.liveAccent : .secondary)
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(!on && selected.count >= HomeQuickAction.maxCount)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                } footer: {
                    Text("Pick up to \(HomeQuickAction.maxCount). Saved on this iPhone.")
                }
            }
            .navigationTitle("Quick actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Reset") { raw = HomeQuickAction.defaultRaw } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Today card (feature-flagged; game-systems routes are not live)

enum HomeTodayFlags {
    static let key = "dev.home.today"
    /// Off by default until the game-systems routes (daily quests, buffs) exist on GreenField.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Hook for the upcoming game-systems API. Returns nil until a route exists, so the card never
/// invents quests or buffs.
struct HomeTodaySnapshot: Equatable {
    struct Quest: Identifiable, Equatable { let id: String; let title: String; let progress: Int; let goal: Int }
    struct Buff: Identifiable, Equatable { let id: String; let title: String; let endsAt: Date }
    var quests: [Quest]
    var buffs: [Buff]
}

enum HomeTodayProvider {
    static func load(client: GreenfieldClient) async -> HomeTodaySnapshot? { nil }
}

struct HomeTodayCard: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot: HomeTodaySnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Label("\(MascotProgressStore.shared.streak)", systemImage: "flame.fill")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(MascotProgressStore.shared.streak)-day streak")
            }
            if let snapshot, !(snapshot.quests.isEmpty && snapshot.buffs.isEmpty) {
                ForEach(snapshot.quests) { quest in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quest.title).font(.subheadline.weight(.semibold))
                        ProgressView(value: Double(quest.progress), total: Double(max(quest.goal, 1))).tint(app.appearance.liveAccent)
                    }
                }
                ForEach(snapshot.buffs) { buff in
                    Label(buff.title, systemImage: "bolt.fill").font(.caption)
                }
            } else {
                Text("Daily quests and active buffs appear here when Moliboo game systems launch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
        .task { snapshot = await HomeTodayProvider.load(client: app.client) }
        .accessibilityIdentifier("home.today")
    }
}


/// End of the loaded feed: nothing older to page in.
struct HomeCaughtUpMarker: View {
    var onRefresh: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(app.appearance.liveAccent)
                    .accessibilityHidden(true)
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
            }
            Text("You’re all caught up")
                .font(.headline)
            Text("You’ve seen everything new in this feed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                HapticEngine.shared.play(.selection)
                onRefresh()
            } label: {
                Label("Check for new posts", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .modulaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.caughtup.refresh")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.caughtup")
    }
}
