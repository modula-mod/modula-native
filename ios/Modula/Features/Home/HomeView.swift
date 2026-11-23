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
    @AppStorage(HomeSectionLayout.storageKey) private var homeSectionsRaw = HomeSectionLayout.defaultRaw
    @State private var editingHome = false
    /// Header bottom edge in global space: the scroll view's top + its top safe-area inset (the
    /// nav bar with search/bell/chat). Passed to post cards so their action rail stays below it.
    @State private var topChromeBottom: CGFloat = 0
    /// Bottom safe-area inset the system reserves for the scroll view (tab bar etc.).
    @State private var scrollBottomSafeArea: CGFloat = 0

    var body: some View {
        let state = app.home.state(for: mode)
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Vertical rhythm on the spacing scale: sections 12pt apart, a section's own
                    // header and content 8pt apart (Gestalt proximity), matching the Home reference.
                    LazyVStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                        // Sections in the order (and visibility) chosen in Edit Home; the feed stays last.
                        ForEach(HomeSectionLayout.visible(homeSectionsRaw)) { section in
                            homeSection(section, state: state)
                        }

                        Button {
                            editingHome = true
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Label("Edit Home", systemImage: "slider.horizontal.3")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, ModulaLayout.contentInset + leadingInteractionInset)
                        .accessibilityIdentifier("home.edit")

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
            .modulaFreezesScrollDuringReactions()
            .environment(\.modulaTopChromeBottom, topChromeBottom)
            .onGeometryChange(for: CGFloat.self) { proxy in
                (proxy.frame(in: .global).minY + proxy.safeAreaInsets.top).rounded()
            } action: { topChromeBottom = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom.rounded() } action: { scrollBottomSafeArea = $0 }
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
            if HomeSectionLayout.isVisible(.moliboo, in: homeSectionsRaw) {
                HomeMascotCompanion()
                    .padding(.horizontal, 8)
                    .frame(height: 260)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .sheet(isPresented: $editingHome) { HomeSectionEditor(raw: $homeSectionsRaw).modulaSheetStyle() }
        // Back online: a feed that failed (or is showing the offline warm page) refreshes itself.
        .onReceive(NotificationCenter.default.publisher(for: .modulaConnectivityRestored)) { _ in
            let failed: Bool = { if case .failed = app.home.state(for: mode).loadState { return true }; return false }()
            guard failed || app.home.isOfflineHint else { return }
            Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
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
            // Search + Activity + Messages share one glass capsule (Create moved to the
            // "What's on your mind?" composer card on the page).
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass") {
                    app.navigation.open(.search(.root(nil)))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.search")
                Button {
                    app.navigation.select(.activity)
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if let count = app.activity.state(for: .all).unreadCount, count > 0 {
                                UnreadBadge(count: count)
                                    .scaleEffect(0.7)
                                    .offset(x: 6, y: -6)
                            }
                        }
                }
                .accessibilityLabel("Activity")
                .accessibilityIdentifier("home.activity")
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
            Group {
                PostCommentsSheet(postID: post.id, commentCount: post.replyCount, postAuthorID: post.author?.id)
            }
            .modulaSheetStyle()
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

    // MARK: Customisable sections (Edit Home)

    @ViewBuilder
    private func homeSection(_ section: HomeSection, state: HomeModeState) -> some View {
        let leading = ModulaLayout.contentInset + leadingInteractionInset
        let trailing = ModulaLayout.contentInset + trailingInteractionInset
        switch section {
        case .stories:
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
                                                .foregroundStyle(Color.modulaOnPrimary)
                                                .padding(.horizontal, 10)
                                                .frame(height: 26)
                                                .background(Color.modulaPrimaryFill, in: Capsule())
                                                .contentShape(Capsule())
                                        }
                                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
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
        case .greeting:
            greetingHero
                .padding(.leading, leading)
                .padding(.trailing, trailing)
                .padding(.bottom, ModulaSpacing.xxs)
        case .quickActions:
            // Quick actions sit on the page (not on the photo): primary text on glass
            // reads in light mode, where white-on-light-glass tiles were unreadable.
            greetingActions
                .padding(.leading, leading)
                .padding(.trailing, trailing)
        case .composer:
            if app.auth.isSignedIn {
                HomeComposerPrompt()
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
            }
        case .modules:
            if app.auth.isSignedIn {
                HomeModulesBanner()
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
            }
        case .today:
            if HomeTodayFlags.isEnabled {
                HomeTodayCard()
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
            }
        case .moliboo:
            // Moliboo is the floating companion overlay; this slot only controls visibility.
            EmptyView()
        case .board, .pinnedModules, .connect, .favourites, .recentChats, .reels, .quote:
            HomeExtraSection(section: section)
                .padding(.leading, leading)
                .padding(.trailing, trailing)
                .modulaAppear()
        }
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
                Button {
                    HapticEngine.shared.play(.navigation)
                    app.navigation.open(app.navigation.root(for: .profile))
                } label: {
                    Text(name)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                }
                .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
                .accessibilityHint("Opens your profile")
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
                HomeGlanceChips()
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
            .padding(.bottom, ModulaLayout.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
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
        HStack(spacing: 4) {
            ForEach(HomeQuickAction.decode(quickActionsRaw)) { item in
                greetingAction(item.title, item.symbol, "home.greeting.\(item.rawValue)") { run(item) }
                    .contextMenu {
                        Button("Customise quick actions", systemImage: "slider.horizontal.3") { editingQuickActions = true }
                    }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .sheet(isPresented: $editingQuickActions) {
            HomeQuickActionEditor(raw: $quickActionsRaw)
                .presentationDetents([.medium, .large])
                .modulaSheetStyle()
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(app.appearance.liveAccent.opacity(colorScheme == .dark ? 0.22 : 0.13), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: nil))
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    /// Reference filter chips; each filters the loaded feed by real post fields.
    private var feedFilterChips: some View {
        // Shared segmented control; long-press the row to make the current filter Home's default.
        ModulaSegmentedControl("Feed filter", selection: Binding(get: { feedFilter }, set: { filter in
            withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) { feedFilter = filter }
        }), options: HomeFeedFilter.allCases, symbol: { $0.symbol }, identifier: { "home.filter.\($0.rawValue)" }) { $0.title }
            // Full-bleed rail: when the chips scroll they run to the screen edges with an inset,
            // instead of being clipped at the right padding.
            .scrollInset(ModulaLayout.contentInset + leadingInteractionInset)
            .contextMenu {
                let count = app.home.visiblePosts(for: mode).filter(feedFilter.matches).count
                Text("\(count) loaded \(count == 1 ? "post" : "posts")")
                if defaultFeedFilterRaw == feedFilter.rawValue {
                    Button("Default filter", systemImage: "checkmark") {}
                        .disabled(true)
                } else {
                    Button("Open Home with \(feedFilter.title)", systemImage: "pin") {
                        defaultFeedFilterRaw = feedFilter.rawValue
                        app.navigation.flash("Home opens with \(feedFilter.title)", symbol: feedFilter.symbol)
                    }
                }
                if defaultFeedFilterRaw != HomeFeedFilter.all.rawValue {
                    Button("Reset to All", systemImage: "arrow.uturn.backward") {
                        defaultFeedFilterRaw = HomeFeedFilter.all.rawValue
                        feedFilter = .all
                    }
                }
            }
            .accessibilityHint("Long-press to make the selected filter the default")

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
        Label("Back to top", systemImage: "arrow.up")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modulaGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
            .onTapGesture {
                ModulaTabReselect.post(.home)
                HapticEngine.shared.play(.selection)
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                // Long-press: back to top and refresh.
                ModulaTabReselect.post(.home)
                HapticEngine.shared.play(.lightImpact)
                Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Long-press to also refresh")
            .accessibilityAction(named: "Back to top and refresh") {
                ModulaTabReselect.post(.home)
                Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
            }
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
                    friendIDs: mode == .following ? [] : app.home.followingAuthorIDs(),
                    ownID: app.auth.account?.accountId
                )
                if visiblePosts.isEmpty {
                    ModulaEmptyState(title: "No \(feedFilter.title.lowercased()) yet", message: "Try another filter or pull to refresh.", symbol: feedFilter.symbol)
                        .padding(.horizontal, ModulaLayout.contentInset)
                        .padding(.top, 20)
                }
                ForEach(visiblePosts) { post in
                    let resolved = app.posts.resolved(post)
                    // Speed: the card's body only re-runs when this row's inputs change (post state,
                    // ownership, mode) — not on every unrelated feed body pass (ambient, chips, pills).
                    ModulaEquatableRow(key: HomeFeedRowKey(post: resolved, mode: mode, ownID: app.auth.account?.accountId)) {
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
                                // Send button: always a sheet (Settings → Sharing picks Modula or iOS).
                                ModulaMascotEvent.post(.share)
                                PostSharing.send(resolved, app: app)
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
                    }
                    .equatable()
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
                    HomeCaughtUpMarker(updated: state.lastRefresh) {
                        Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 20)
                    // End of feed sits fully above the tab bar + Following/For You accessory: add
                    // whatever the bottom safe area doesn't already reserve for that chrome.
                    .padding(.bottom, 20 + max(0, shellChromeMetrics.occupiedBottomHeight - scrollBottomSafeArea))
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
                        .modulaPrimaryCTA()
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
            .buttonStyle(.modulaPrimary)
            .tint(.primary)
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
                    .buttonStyle(.modulaPrimary)
                    .tint(.primary)
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
                    .modulaGlass(in: Circle(), interactive: true, tint: nil)
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
                        ProgressView(value: Double(quest.progress), total: Double(max(quest.goal, 1))).tint(.primary)
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
    var updated: Date? = nil
    var onRefresh: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
            }
            Text("You’re all caught up")
                .font(.headline)
            Text("You’ve seen everything new in this feed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let updated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("home.caughtup.updated")
            }
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
        // Its own glass card, so it never reads as ghost text drifting under the bottom bars.
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.caughtup")
    }
}


/// "What's waiting" chips in the Home greeting. Only non-zero counts show; each opens its place.
struct HomeGlanceChips: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let chats = app.messaging.accountUnreadCount ?? 0
        let alerts = app.activity.state(for: .all).unreadCount ?? 0
        let stories = app.stories.trayGroups.reduce(0) { $0 + ((!$1.isOwn && $1.hasStories && $1.ring == .unseen) ? 1 : 0) }
        if chats + alerts + stories > 0 {
            HStack(spacing: 6) {
                if chats > 0 { chip("\(chats) chat\(chats == 1 ? "" : "s")", symbol: "bubble.left.fill", id: "chats") { app.navigation.open(.messages(.inbox)) } }
                if alerts > 0 { chip("\(alerts) alert\(alerts == 1 ? "" : "s")", symbol: "bell.fill", id: "alerts") { app.navigation.open(.activity(.all)) } }
                if stories > 0 { chip("\(stories) stor\(stories == 1 ? "y" : "ies")", symbol: "circle.dashed", id: "stories") { app.navigation.open(.stories(.root)) } }
            }
            .accessibilityIdentifier("home.glance")
        }
    }

    private func chip(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.navigation)
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .modulaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.glance.\(id)")
    }
}


/// "What's on your mind?" entry: one tap to the composer, or straight to photo / video.
private struct HomeComposerPrompt: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            avatar
            Button {
                open(.post)
            } label: {
                Text("What’s on your mind?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.composer.prompt")
            icon("photo.on.rectangle", "Photo", .photo)
            icon("video", "Video", .video)
            icon("plus", "More ways to post", .post, prominent: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.composer")
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = app.profile.tabBarAvatar {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
    }

    private func icon(_ symbol: String, _ label: String, _ route: ComposeRoute, prominent: Bool = false) -> some View {
        Button {
            open(route)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? Color.modulaOnPrimary : Color.primary)
                .frame(width: 36, height: 36)
                .background {
                    if prominent { Circle().fill(Color.modulaPrimaryFill) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .accessibilityLabel(label)
    }

    private func open(_ route: ComposeRoute) {
        app.navigation.open(.compose(route))
        HapticEngine.shared.play(.navigation)
    }
}

/// Modules hero banner: installed count + one tap to the Modules sheet (same as swipe-up).
private struct HomeModulesBanner: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let accent = app.appearance.liveAccent
        let count = app.catalogue.installedIDs.count
        Button {
            HapticEngine.shared.play(.contextOpen)
            app.navigation.openModulesDock()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your modules")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(count == 0 ? "Explore what you can add to Modula" : (count == 1 ? "1 installed · swipe up on the bar anytime" : "\(count) installed · swipe up on the bar anytime"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [accent.opacity(0.14), accent.opacity(0.03)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
        .accessibilityIdentifier("home.modules.banner")
    }
}

// MARK: - Home sections (Edit Home)

enum HomeSection: String, CaseIterable, Identifiable {
    case stories, greeting, quickActions, composer, modules, today, moliboo
    // t240u: richer Home. New sections arrive hidden (except Board) so upgrades don't reshuffle Home.
    case board, pinnedModules, connect, favourites, recentChats, reels, quote
    var id: String { rawValue }

    var isDefaultVisible: Bool {
        switch self {
        case .pinnedModules, .connect, .favourites, .recentChats, .reels, .quote: false
        default: true
        }
    }

    /// Sections with per-section density / style options in Edit Home.
    var hasOptions: Bool {
        switch self {
        case .pinnedModules, .favourites, .recentChats, .reels, .quote: true
        default: false
        }
    }

    var blurb: String {
        switch self {
        case .stories: "Story rings and Reels"
        case .greeting: "Scene, name and streak"
        case .quickActions: "Write, Create, Vault…"
        case .composer: "Start a post"
        case .modules: "Installed modules"
        case .today: "Your day at a glance"
        case .moliboo: "Floating companion"
        case .board: "Widgets from your Board"
        case .pinnedModules: "Modules pinned in the dock"
        case .connect: "Your Modula Number"
        case .favourites: "One-tap calls"
        case .recentChats: "Latest conversations"
        case .reels: "Jump into Reels"
        case .quote: "Quote and on this day"
        }
    }

    var title: String {
        switch self {
        case .stories: "Stories"
        case .greeting: "Greeting"
        case .quickActions: "Quick actions"
        case .composer: "What’s on your mind?"
        case .modules: "Recently opened modules"
        case .today: "Today"
        case .moliboo: "Moliboo"
        case .board: "Board widgets"
        case .pinnedModules: "Pinned modules"
        case .connect: "Modula Connect"
        case .favourites: "Calls favourites"
        case .recentChats: "Recent chats"
        case .reels: "Reels"
        case .quote: "Quote · On this day"
        }
    }

    var symbol: String {
        switch self {
        case .stories: "circle.dashed"
        case .greeting: "sun.max"
        case .quickActions: "square.grid.2x2"
        case .composer: "square.and.pencil"
        case .modules: "shippingbox"
        case .today: "calendar"
        case .moliboo: "sparkles"
        case .board: "square.grid.2x2.fill"
        case .pinnedModules: "pin"
        case .connect: "antenna.radiowaves.left.and.right"
        case .favourites: "star"
        case .recentChats: "bubble.left.and.bubble.right"
        case .reels: "play.rectangle"
        case .quote: "quote.opening"
        }
    }
}

/// Persisted as one string: section ids in order, hidden ones prefixed with "-".
/// Unknown ids are dropped; sections added in later versions append visible.
enum HomeSectionLayout {
    static let storageKey = "home.sections.v1"
    static let defaultRaw = HomeSection.allCases.map { ($0.isDefaultVisible ? "" : "-") + $0.rawValue }.joined(separator: ",")

    struct Entry: Identifiable, Equatable {
        let section: HomeSection
        var visible: Bool
        var id: String { section.rawValue }
    }

    static func decode(_ raw: String) -> [Entry] {
        var seen = Set<HomeSection>()
        var entries: [Entry] = []
        for token in raw.split(separator: ",") {
            let hidden = token.hasPrefix("-")
            guard let section = HomeSection(rawValue: String(hidden ? token.dropFirst() : token)),
                  seen.insert(section).inserted else { continue }
            entries.append(Entry(section: section, visible: !hidden))
        }
        for section in HomeSection.allCases where !seen.contains(section) {
            entries.append(Entry(section: section, visible: section.isDefaultVisible))
        }
        return entries
    }

    static func encode(_ entries: [Entry]) -> String {
        entries.map { ($0.visible ? "" : "-") + $0.section.rawValue }.joined(separator: ",")
    }

    static func visible(_ raw: String) -> [HomeSection] {
        decode(raw).filter(\.visible).map(\.section)
    }

    static func isVisible(_ section: HomeSection, in raw: String) -> Bool {
        decode(raw).first { $0.section == section }?.visible ?? true
    }
}

/// Per-section display options (Edit Home). Stored as "section=density.style" pairs.
enum HomeSectionOptions {
    static let storageKey = "home.sections.options.v1"

    enum Density: String, CaseIterable, Identifiable { case compact, regular, large; var id: Self { self }
        var title: String { switch self { case .compact: "Compact"; case .regular: "Regular"; case .large: "Large" } }
    }
    enum Style: String, CaseIterable, Identifiable { case card, plain; var id: Self { self }
        var title: String { switch self { case .card: "Glass card"; case .plain: "Plain" } }
    }
    struct Value: Equatable { var density: Density = .regular; var style: Style = .card }

    static func decode(_ raw: String) -> [HomeSection: Value] {
        var out: [HomeSection: Value] = [:]
        for pair in raw.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, let section = HomeSection(rawValue: String(kv[0])) else { continue }
            let parts = kv[1].split(separator: ".")
            var v = Value()
            if let d = parts.first.flatMap({ Density(rawValue: String($0)) }) { v.density = d }
            if parts.count > 1, let st = Style(rawValue: String(parts[1])) { v.style = st }
            out[section] = v
        }
        return out
    }

    static func encode(_ map: [HomeSection: Value]) -> String {
        map.filter { $0.value != Value() }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value.density.rawValue).\($0.value.style.rawValue)" }
            .joined(separator: ";")
    }

    static func value(_ section: HomeSection, in raw: String) -> Value { decode(raw)[section] ?? Value() }
}

/// One-tap Home layouts.
enum HomePreset: String, CaseIterable, Identifiable {
    case classic, minimal, social, console, everything
    var id: Self { self }
    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .social: "Social"
        case .console: "Console"
        case .everything: "Everything"
        }
    }
    var symbol: String {
        switch self {
        case .classic: "house"
        case .minimal: "circle.dotted"
        case .social: "person.2"
        case .console: "square.grid.2x2"
        case .everything: "sparkles"
        }
    }
    var sections: [HomeSection] {
        switch self {
        case .classic: [.greeting, .quickActions, .stories, .composer, .modules, .today, .moliboo, .board]
        case .minimal: [.stories, .composer]
        case .social: [.stories, .recentChats, .favourites, .composer, .reels, .moliboo]
        case .console: [.greeting, .board, .pinnedModules, .connect, .today, .quote]
        case .everything: HomeSection.allCases
        }
    }
    var raw: String {
        let visible = sections
        let rest = HomeSection.allCases.filter { !visible.contains($0) }
        return (visible.map(\.rawValue) + rest.map { "-" + $0.rawValue }).joined(separator: ",")
    }
}

/// Edit Home: presets, a live miniature preview, show / hide, drag to reorder (with haptics),
/// and per-section density / style. Persists immediately; Reset restores defaults.
struct HomeSectionEditor: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app
    @AppStorage(HomeSectionOptions.storageKey) private var optionsRaw = ""
    @State private var entries: [HomeSectionLayout.Entry] = []
    @State private var expanded: HomeSection?

    private var visibleSections: [HomeSection] { entries.filter(\.visible).map(\.section) }
    private var activePreset: HomePreset? { HomePreset.allCases.first { HomeSectionLayout.encode(entries) == $0.raw } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section("Presets") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(HomePreset.allCases) { preset in
                                let on = activePreset == preset
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        entries = HomeSectionLayout.decode(preset.raw)
                                    }
                                    HapticEngine.shared.play(.success)
                                } label: {
                                    Label(preset.title, systemImage: preset.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(on ? Color.modulaOnPrimary : .primary)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background { if on { Capsule().fill(Color.modulaPrimaryFill) } }
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                                .modulaGlass(in: Capsule(), interactive: true)
                                .accessibilityAddTraits(on ? .isSelected : [])
                                .accessibilityIdentifier("home.edit.preset.\(preset.rawValue)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    ForEach($entries) { $entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: entry.section.symbol)
                                    .font(.body.weight(.semibold))
                                    .frame(width: 28)
                                    .symbolEffect(.bounce, value: entry.visible)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.section.title).font(.body)
                                    Text(entry.section.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if entry.section.hasOptions && entry.visible {
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            expanded = expanded == entry.section ? nil : entry.section
                                        }
                                        HapticEngine.shared.play(.selection)
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(expanded == entry.section ? Color.modulaOnPrimary : .primary)
                                            .frame(width: 32, height: 32)
                                            .background(Circle().fill(expanded == entry.section ? Color.modulaPrimaryFill : Color.primary.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(entry.section.title) options")
                                }
                                Toggle(entry.section.title, isOn: $entry.visible)
                                    .labelsHidden()
                            }
                            if expanded == entry.section && entry.visible {
                                options(for: entry.section)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .accessibilityIdentifier("home.edit.\(entry.section.rawValue)")
                    }
                    .onMove { from, to in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { entries.move(fromOffsets: from, toOffset: to) }
                        HapticEngine.shared.play(.success)
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Drag to reorder. Your feed always stays at the bottom. Weather arrives when the server offers it.")
                }
            }
            .toggleStyle(SettingsHapticToggleStyle())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            entries = HomeSectionLayout.decode(HomeSectionLayout.defaultRaw)
                        }
                        optionsRaw = ""
                        HapticEngine.shared.play(.warning)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    MessagesDoneButton { dismiss() }
                }
            }
            .onAppear { entries = HomeSectionLayout.decode(raw) }
            .onChange(of: entries) { _, value in
                raw = HomeSectionLayout.encode(value)
            }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
        .accessibilityIdentifier("home.edit.sheet")
    }

    /// Miniature Home: a bar per visible section in order, springing as you edit.
    private var preview: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                Capsule().fill(Color.primary.opacity(0.25)).frame(width: 28, height: 4).padding(.bottom, 4)
                ForEach(visibleSections.prefix(9)) { section in
                    let opt = HomeSectionOptions.value(section, in: optionsRaw)
                    HStack(spacing: 4) {
                        Image(systemName: section.symbol).font(.system(size: 7, weight: .bold))
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.35)).frame(height: 3)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: previewHeight(section, opt))
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(opt.style == .card ? 0.12 : 0.04)))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)).frame(height: 26)
                    .overlay(Text("Feed").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary))
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 96, height: 190, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5))
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text("Live preview").font(.headline)
                Text("\(visibleSections.count) of \(HomeSection.allCases.count) sections on")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let activePreset {
                    Label(activePreset.title, systemImage: activePreset.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("Custom").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: entries)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: optionsRaw)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(visibleSections.map(\.title).joined(separator: ", "))")
    }

    private func previewHeight(_ section: HomeSection, _ opt: HomeSectionOptions.Value) -> CGFloat {
        let base: CGFloat = switch section {
        case .greeting: 30
        case .board, .reels: 22
        case .stories, .favourites, .recentChats: 16
        default: 12
        }
        return base * (opt.density == .compact ? 0.75 : opt.density == .large ? 1.3 : 1)
    }

    @ViewBuilder
    private func options(for section: HomeSection) -> some View {
        let binding = Binding<HomeSectionOptions.Value>(
            get: { HomeSectionOptions.value(section, in: optionsRaw) },
            set: { value in
                var map = HomeSectionOptions.decode(optionsRaw)
                map[section] = value
                optionsRaw = HomeSectionOptions.encode(map)
                HapticEngine.shared.play(.selection)
            }
        )
        VStack(alignment: .leading, spacing: 8) {
            ModulaSegmentedControl(segments: HomeSectionOptions.Density.allCases.map { .init(id: $0, title: $0.title) },
                                   selection: binding.density, accessibilityLabel: "Density",
                                   identifier: "home.edit.\(section.rawValue).density")
            ModulaSegmentedControl(segments: HomeSectionOptions.Style.allCases.map { .init(id: $0, title: $0.title) },
                                   selection: binding.style, accessibilityLabel: "Style",
                                   identifier: "home.edit.\(section.rawValue).style")
        }
        .padding(.leading, 40)
    }
}

// MARK: - New Home sections (t240u)

struct HomeExtraSection: View {
    let section: HomeSection
    @Environment(AppEnvironment.self) private var app
    @AppStorage(HomeSectionOptions.storageKey) private var optionsRaw = ""
    @AppStorage(ModulesDockPrefs.pinnedKey) private var pinnedRaw = ""

    private var opt: HomeSectionOptions.Value { HomeSectionOptions.value(section, in: optionsRaw) }
    private var scale: CGFloat { opt.density == .compact ? 0.8 : opt.density == .large ? 1.2 : 1 }

    var body: some View {
        Group {
            switch section {
            case .board: HomeBoardRail()
            case .pinnedModules: pinnedModules
            case .connect: ConnectPromoCard()
            case .favourites: favourites
            case .recentChats: recentChats
            case .reels: reels
            case .quote: HomeQuoteCard(compact: opt.density == .compact)
            default: EmptyView()
            }
        }
        .padding(opt.style == .card && section != .connect && section != .board ? 14 : 0)
        .background {
            if opt.style == .card && section != .connect && section != .board {
                Color.clear.modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func header(_ title: String, action: String, route: AppRoute) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action) {
                app.navigation.push(route)
                HapticEngine.shared.play(.navigation)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
    }

    private var pinnedModules: some View {
        let installed = app.catalogue.installedIDs
        let pinned = ModulesDockPrefs.decode(pinnedRaw)
        let ids = pinned.isEmpty ? Array(installed).sorted() : pinned
        let products = ids.compactMap { id in app.catalogue.products.first { $0.moduleId == id } }
        return VStack(alignment: .leading, spacing: 10) {
            header(pinned.isEmpty ? "Your modules" : "Pinned modules", action: "All", route: .productHub(.collection(.installed)))
            if products.isEmpty {
                Text("Pin modules from the Modules dock to keep them here.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(products) { product in
                            Button {
                                app.navigation.open(.module(product.moduleId, localPath: nil))
                                HapticEngine.shared.play(.navigation)
                            } label: {
                                VStack(spacing: 6) {
                                    ProductArtwork(product: product, size: 52 * scale)
                                    Text(product.name).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(width: 72 * scale)
                                }
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                            .modulaCarouselReveal()
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .modulaHorizontalRail()
            }
        }
    }

    private var favourites: some View {
        let favs = app.calls.favourites.compactMap { CallsDirectory.contact(forConversation: $0, app: app) }
        return VStack(alignment: .leading, spacing: 10) {
            header("Favourites", action: "Calls", route: .messages(.calls))
            if favs.isEmpty {
                Text("Star people in Calls to call them from Home.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(favs) { c in
                            Button {
                                if let id = c.conversationID { CallsActions.call(id, kind: .audio, app: app) }
                            } label: {
                                VStack(spacing: 6) {
                                    ModulaAvatar(initials: c.initials, url: c.avatarURL, size: 52 * scale, name: c.name)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "phone.fill").font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white).frame(width: 20, height: 20)
                                                .background(Circle().fill(Color.green))
                                        }
                                    Text(c.name).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.center).frame(width: 70 * scale)
                                }
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: .selection))
                            .accessibilityLabel("Call \(c.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .modulaHorizontalRail()
            }
        }
    }

    private var recentChats: some View {
        let count = opt.density == .compact ? 3 : opt.density == .large ? 6 : 4
        let recent = Array(app.messaging.visibleConversations.prefix(count))
        return VStack(alignment: .leading, spacing: 10) {
            header("Recent chats", action: "Messages", route: .messages(.inbox))
            if recent.isEmpty {
                Text("Your latest conversations show up here.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(recent) { c in
                Button {
                    app.navigation.push(.messages(.conversation(c.id)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    HStack(spacing: 12) {
                        let p = c.participants.first
                        ModulaAvatar(initials: p?.initials ?? "?", url: p?.avatarURL, size: 36 * scale, name: c.title)
                        Text(c.title).font(.subheadline.weight(c.isUnread ? .bold : .regular)).foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if c.isUnread { Circle().fill(Color.primary).frame(width: 8, height: 8).transition(.scale) }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
            }
        }
    }

    private var reels: some View {
        Button {
            app.navigation.push(.reels(.feed))
            HapticEngine.shared.play(.navigation)
        } label: {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color.primary.opacity(0.22 - Double(i) * 0.05), Color.primary.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 64 * scale, height: 100 * scale)
                        .overlay(Image(systemName: "play.fill").font(.title3).foregroundStyle(.primary.opacity(0.6)))
                        .rotationEffect(.degrees(Double(i - 1) * 4))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reels").font(.headline).foregroundStyle(.primary)
                    Text("Short videos from people you follow").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Watch", systemImage: "play.fill").font(.caption.weight(.bold))
                        .foregroundStyle(Color.modulaOnPrimary)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(Color.modulaPrimaryFill))
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
        .accessibilityLabel("Watch Reels")
        .accessibilityIdentifier("home.section.reels")
    }
}

/// On-device quote of the day plus a date fact; changes at midnight.
struct HomeQuoteCard: View {
    var compact = false
    private static let quotes: [(String, String)] = [
        ("Simplicity is the ultimate sophistication.", "Leonardo da Vinci"),
        ("Make it work, make it right, make it fast.", "Kent Beck"),
        ("The best way to predict the future is to invent it.", "Alan Kay"),
        ("Stay hungry, stay foolish.", "Whole Earth Catalog"),
        ("Small steps every day.", "Unknown"),
        ("Done is better than perfect.", "Sheryl Sandberg"),
        ("What we think, we become.", "Buddha"),
        ("Creativity is intelligence having fun.", "Albert Einstein"),
        ("Well begun is half done.", "Aristotle"),
        ("Do one thing every day that scares you.", "Eleanor Roosevelt"),
        ("The details are not the details. They make the design.", "Charles Eames"),
        ("Be so good they can't ignore you.", "Steve Martin")
    ]

    var body: some View {
        let now = Date()
        let cal = Calendar.current
        let day = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        let total = cal.range(of: .day, in: .year, for: now)?.count ?? 365
        let q = Self.quotes[day % Self.quotes.count]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.0).font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(q.1).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !compact {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("On this day", systemImage: "calendar").font(.caption.weight(.bold))
                        Spacer()
                        Text("Day \(day) · \(total - day) to go").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView(value: Double(day), total: Double(total)).tint(.primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.section.quote")
    }
}


/// Identity of one feed row's rendered state.
struct HomeFeedRowKey: Equatable, Sendable {
    let post: SocialPost
    let mode: HomeMode
    let ownID: String?
}
