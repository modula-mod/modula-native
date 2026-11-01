import SwiftUI
import UIKit

struct ProfileView: View {
    let userID: String?
    let section: ProfileSection
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.trailingInteractionInset) private var trailingInteractionInset
    @Environment(\.leadingInteractionInset) private var leadingInteractionInset
    @Environment(\.shellChromeMetrics) private var shellChromeMetrics
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var headerProgress: CGFloat = 0
    /// Raw content offset: drives the top-bar title so it only appears once the big name is under it.
    @State private var scrollOffset: CGFloat = 0
    @State private var heroAvatarFrame: CGRect = .zero
    @Environment(\.accessibilityReduceTransparency) private var navReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var navReduceMotion
    @AppStorage(MascotProfileSettings.showOnProfileKey) private var showProfileMascot = true
    @State private var dressUpMascot = false
    @State private var confirmsBlock = false
    @State private var confirmsReport = false
    @State private var mediaViewer: ModulaMediaViewerItem?
    @State private var mediaAction: ProfileMediaWorkspaceAction?
    @State private var showsShareSheet = false
    @State private var showsModulaCode = false
    @State private var followBusy = false
    /// People-list rows with a follow/unfollow request in flight.
    @State private var followBusyIDs: Set<String> = []
    @State private var copiedBanner = false
    @State private var activityShare: ActivityShareItem?
    /// Dominant colour of the real avatar image; tints the aurora hero and glow ring.
    @State private var avatarTint: Color?
    @State private var contentTab: ProfileContentTab = .posts
    @State private var shelf: ProfileShelfTab = .posts
    @State private var showsFrames = false
    @Namespace private var shelfNamespace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("profile.postLayout") private var postLayoutRaw = ProfilePostLayout.grid.rawValue
    #if DEBUG
    /// DEBUG-only: `--debug-autoscroll` scrolls the page for screen recordings.
    @State private var debugScrollPosition = ScrollPosition(edge: .top)
    #endif

    private var identity: ProfileIdentity {
        .resolving(routeUserID: userID)
    }

    private var accountHandle: String? {
        app.auth.account?.primaryHandle
    }

    private var session: ProfileSessionState {
        app.profile.session(for: identity, handleHint: accountHandle)
    }

    private var profile: ModulaProfile? {
        let raw = session.profile
        if app.profile.visitorPreviewActive, isOwnProfile {
            return raw?.visitorVisible
        }
        return raw
    }

    private var isOwnProfile: Bool {
        if identity == .me { return true }
        guard let profile, let accountHandle else { return false }
        return profile.handle.caseInsensitiveCompare(accountHandle) == .orderedSame
    }

    var body: some View {
        Group {
            if section == .edit {
                editDestination
            } else {
                profileChrome
            }
        }
        .task(id: taskKey) {
            await bootstrap()
            await app.stories.loadIfNeeded()
        }
        .task(id: profile?.avatarURL) {
            if isOwnProfile, let profile {
                // Lets every ModulaAvatar of "me" carry the open-to arc frame.
                ProfileAvatarOverlayStore.shared.bind(accountID: app.auth.account?.accountId)
                ProfileAvatarOverlayStore.shared.noteOwnAvatar(profile.avatarURL)
            }
            guard let url = profile?.avatarURL else {
                avatarTint = nil
                return
            }
            avatarTint = await ModulaImageTint.tint(for: url, cacheKey: "tint:\(url.path)", client: app.client)
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            Task { await bootstrap() }
        }
        .overlay(alignment: .bottom) {
            if let message = app.profile.actionError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .onTapGesture { app.profile.clearActionError() }
                    .accessibilityIdentifier("profile.banner")
            }
        }
        .confirmationDialog("Block this profile?", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    await app.profile.block(identity: identity, handleHint: profile?.handle ?? accountHandle)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report this profile?", isPresented: $confirmsReport, titleVisibility: .visible) {
            Button("Report spam", role: .destructive) {
                Task { await reportProfile(category: "spam") }
            }
            Button("Report harassment", role: .destructive) {
                Task { await reportProfile(category: "harassment") }
            }
            Button("Report other", role: .destructive) {
                Task { await reportProfile(category: "other") }
            }
            Button("Cancel", role: .cancel) {}
        }
        .profileMediaWorkspace(profile: profile, action: $mediaAction) { kind in
            guard let profile else { return }
            switch kind {
            case .avatar: openAvatarViewer(profile)
            case .cover: openCoverViewer(profile)
            }
        }
        .fullScreenCover(item: $mediaViewer) { item in
            ModulaMediaViewer(
                title: item.title,
                url: item.url,
                accessibilityDescription: item.accessibilityDescription,
                allowsShare: item.allowsShare
            ) {
                mediaViewer = nil
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let profile {
                ProfileShareSheet(
                    profile: profile,
                    onCopy: { copyProfileLink(profile) },
                    onShare: {
                        showsShareSheet = false
                        activityShare = ActivityShareItem(url: profile.shareURL)
                    },
                    onShowCode: {
                        showsShareSheet = false
                        showsModulaCode = true
                    },
                    onDismiss: { showsShareSheet = false }
                )
            }
        }
        .sheet(isPresented: $showsModulaCode) {
            if let profile {
                ModulaProfileCodeView(profile: profile) {
                    showsModulaCode = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .sheet(item: $activityShare) { item in
            ProfileActivityShareView(url: item.url) {
                activityShare = nil
            }
        }
        .sheet(isPresented: $showsFrames) {
            ProfileAvatarOverlayEditor()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if copiedBanner {
                Text("Link copied")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 56)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.\(section.rawValue)")
    }

    // MARK: - Edit

    @ViewBuilder
    private var editDestination: some View {
        if isOwnProfile || identity == .me {
            ProfileEditView()
                .task {
                    if let profile {
                        app.profile.beginEditing(from: profile)
                    } else {
                        await bootstrap()
                        if let profile = app.profile.session(for: identity, handleHint: accountHandle).profile {
                            app.profile.beginEditing(from: profile)
                        }
                    }
                }
        } else {
            ModulaEmptyState(
                title: "Can’t edit this profile",
                message: "You can only edit your own profile.",
                symbol: "pencil.slash"
            )
            .modulaCanvas()
        }
    }

    // MARK: - Main chrome

    private var profileChrome: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ModulaScrollProgressReader()
                    content
                        .padding(.top, -(ProfileFullBleedMetrics.windowSafeAreaTop + 44))
                        // Clear the tab bar + home indicator so the last post never hides under chrome.
                        .padding(.bottom, shellChromeMetrics.contentBottomInset + 64)
                }
            }
            .modulaScrollProgressTracking(collapseDistance: 96, progress: $headerProgress)
            .modulaSoftScrollEdge()
            .modifier(ProfileTopEdgeEffectHidden())
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                headerProgress = ModulaScrollProgress.progress(offsetY: max(0, newOffset), collapseDistance: 96)
                let clamped = max(0, newOffset.rounded())
                if abs(clamped - scrollOffset) >= 1 { scrollOffset = clamped }
            }
            // Save the scroll position once scrolling settles rather than on
            // every frame: each write mutated the shared ProfileStore and
            // invalidated every view observing it.
            .onScrollPhaseChange { _, newPhase, context in
                guard newPhase == .idle, let handle = profile?.handle ?? accountHandle else { return }
                app.profile.rememberScroll(
                    identity: identity,
                    handleHint: handle,
                    section: section,
                    offset: context.geometry.contentOffset.y + context.geometry.contentInsets.top
                )
            }
            // Spinner sits below the header (not in the status bar): content is pulled up
            // by the same amount it's inset, so the cover still bleeds to the top edge.
            .contentMargins(.top, ProfileFullBleedMetrics.windowSafeAreaTop + 44, for: .scrollContent)
            // Last post clears the floating tab bar.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .refreshable {
                // Own task so the refresh control tearing down can't cancel the request.
                await Task { await refreshCurrent() }.value
                HapticEngine.shared.play(.lightImpact)
                ModulaMascotEvent.post(.refresh)
            }
            #if DEBUG
            .scrollPosition($debugScrollPosition)
            .task(id: profile != nil) {
                // `--debug-scroll-y <y>`: park the page at a fixed offset (simulator screenshots).
                let args = ProcessInfo.processInfo.arguments
                if profile != nil, let i = args.firstIndex(of: "--debug-scroll-y"), i + 1 < args.count, let y = Double(args[i + 1]) {
                    try? await Task.sleep(for: .seconds(1.2))
                    debugScrollPosition.scrollTo(y: y)
                    return
                }
                guard profile != nil, ProcessInfo.processInfo.arguments.contains("--debug-autoscroll") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                for (y, duration) in [(260.0, 1.4), (620.0, 1.8), (1_000.0, 1.8), (0.0, 2.2)] {
                    withAnimation(.easeInOut(duration: duration)) { debugScrollPosition.scrollTo(y: y) }
                    try? await Task.sleep(for: .seconds(duration + 0.8))
                }
            }
            #endif

            // One progressive top blur for the whole page: strongest at the very top, fading to
            // clear, identical at rest and while scrolling. When the tabs pin it simply grows to
            // sit under them; the tabs are drawn above it, crisp on their own glass.
            ProfileTopProgressiveBlur(
                height: ProfileFullBleedMetrics.windowSafeAreaTop + 44
                    + (shelfPinned ? ProfileTopProgressiveBlur.pinnedShelfExtent : ProfileTopProgressiveBlur.restingFade),
                tint: ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas,
                reduceTransparency: navReduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
            )
            .animation(ModulaEffectGate.reduceMotion(systemReduceMotion) ? nil : .easeOut(duration: 0.2), value: shelfPinned)

            if shelfPinned, let profile {
                shelfBar(profile, floating: true)
                    .padding(.top, ProfileFullBleedMetrics.windowSafeAreaTop + 44)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: shelfPinned)
        .ignoresSafeArea(edges: .top)
        .modulaCanvas()
        .environment(\.profileAccentColor, profile?.presentation.accent?.color)
        .modulaImmersiveSystemNavigation()
        .modulaSidebarTrigger()
        .toolbar {
            ToolbarItem(placement: .principal) {
                let t = navBarProgress
                HStack(spacing: 8) {
                    if let profile {
                        // Avatar "lands" in the bar: grows from 18pt to 28pt as the hero avatar shrinks away.
                        ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 28)
                            .scaleEffect(navReduceMotion ? 1 : 0.64 + 0.36 * t)
                    }
                    Text(compactTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
                .opacity(t)
                .offset(y: navReduceMotion ? 0 : (1 - t) * 8)
                .allowsHitTesting(t > 0.5)
                .accessibilityHidden(t < 0.5)
                .accessibilityLabel(compactTitle)
            }
            // Edit profile / Share profile live in-page as Liquid Glass buttons.
            if let profile {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(ProfileContextActions.moreMenu(isOwn: isOwnProfile)) { action in
                            Button(role: action.role == .destructive ? .destructive : nil) {
                                handleContextAction(action, profile: profile)
                            } label: {
                                if let systemImage = action.systemImage {
                                    Label(action.title, systemImage: systemImage)
                                } else {
                                    Text(action.title)
                                }
                            }
                            .disabled(action.role == .disabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("profile.more")
                }
            }
        }
    }

    /// 0 → 1 as the name moves into the nav bar (eased so the bar fades in with the title).
    private var navBarProgress: CGFloat {
        // The big name sits just under the avatar, below the cover. Only once it has
        // scrolled up under the header bar does the compact avatar + name fade in.
        let safeTop = ProfileFullBleedMetrics.windowSafeAreaTop
        let cover = ProfileFullBleedMetrics.coverHeight(sizeClass: sizeClass, safeAreaTop: safeTop, accessibility: false)
        let avatar = ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)
        let nameY = cover + avatar * 0.5 + 24
        let headerBottom = safeTop + 44
        let x = min(max((scrollOffset - (nameY - headerBottom)) / 36, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Avatar colour → profile accent → cover colour → app accent.
    private var heroTint: Color {
        if let avatarTint { return avatarTint }
        if let accent = profile?.presentation.accent?.color { return accent }
        if let hex = profile?.coverColour, !hex.isEmpty { return Color(hex: hex) }
        return app.appearance.liveAccent
    }

    private var postLayout: Binding<ProfilePostLayout> {
        Binding(
            get: { ProfilePostLayout(rawValue: postLayoutRaw) ?? .grid },
            set: { postLayoutRaw = $0.rawValue }
        )
    }

    private var largeTitle: String {
        // Cover + identity carry the name; keep large title empty so it dissolves cleanly.
        ""
    }

    private var compactTitle: String {
        profile?.displayName ?? (isOwnProfile ? "Profile" : "Profile")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch session.loadState {
        case .loading where profile == nil:
            ProfileSkeleton()
                .padding(.top, 0)
        case .failed(let message) where profile == nil:
            ModulaErrorState(message: message) {
                Task { await refreshCurrent() }
            }
            .padding(.top, 120)
            .padding(.horizontal, ModulaLayout.contentInset)
        case .notFound where profile == nil:
            ModulaEmptyState(
                title: "Profile not found",
                message: "This profile doesn’t exist or is no longer available.",
                symbol: "person.crop.circle.badge.questionmark"
            )
            .padding(.top, 120)
            .padding(.horizontal, ModulaLayout.contentInset)
        case .unavailable where profile == nil:
            ModulaEmptyState(
                title: "This profile isn’t available.",
                message: "It may be private, restricted, or no longer shared with you.",
                symbol: "eye.slash"
            )
            .padding(.top, 120)
            .padding(.horizontal, ModulaLayout.contentInset)
        default:
            if let profile {
                switch section {
                case .overview:
                    overview(profile)
                case .posts:
                    postsSection(profile, embedded: false)
                case .modules:
                    modulesSection(profile, embedded: false)
                case .followers:
                    peopleSection(kind: .followers, profile: profile)
                case .following:
                    peopleSection(kind: .following, profile: profile)
                case .links:
                    linksSection(profile)
                case .connections:
                    connectionsUnavailable
                case .edit:
                    EmptyView()
                }
            } else {
                ProfileSkeleton()
            }
        }
    }

    // MARK: - Overview

    private func overview(_ profile: ModulaProfile) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            hero(profile)

            VStack(alignment: .leading, spacing: 18) {
                if app.profile.visitorPreviewActive, isOwnProfile {
                    ProfileVisitorPreviewBanner {
                        app.profile.setVisitorPreview(false)
                    }
                }

                if isOwnProfile, !ProfileAvatarOverlayStore.shared.buildingStatus.isEmpty {
                    ProfileBuildingStatusLine(text: ProfileAvatarOverlayStore.shared.buildingStatus) {
                        showsFrames = true
                    }
                    .transition(.opacity)
                }

                ProfileInfoChips(profile: profile)
                    .modulaPageEntrance(delay: 0.04)

                let mutuals = mutualFollowers(profile)
                if !mutuals.isEmpty {
                    ProfileMutualFollowersLine(people: mutuals) {
                        openSection(.followers)
                    }
                    .transition(.opacity)
                }

                metrics(profile)
                    .modulaPageEntrance(delay: 0.08)

                heroActions(profile)
                    .modulaPageEntrance(delay: 0.1)

                highlights(profile)
                    .modulaPageEntrance(delay: 0.12)

                if !session.modules.items.isEmpty {
                    ProfileFeaturedModulesRow(
                        products: session.modules.items,
                        installedIDs: app.catalogue.installedIDs,
                        onOpen: openModule,
                        onSeeAll: { openSection(.modules) }
                    )
                    .modulaPageEntrance(delay: 0.14)
                }

                linksPreviewSection(profile)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.leading, leadingInteractionInset)
            .padding(.trailing, trailingInteractionInset)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Section {
                shelfContent(profile)
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.leading, leadingInteractionInset)
                    .padding(.trailing, trailingInteractionInset)
                    .padding(.top, 8)
            } header: {
                shelfBar(profile)
            }
        }
        .task(id: profile.id) {
            await loadMutuals(profile)
        }
    }

    private func hero(_ profile: ModulaProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heroMedia(profile)
            ProfileIdentityBlock(profile: profile, showsFollowsYou: !isOwnProfile)
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.leading, leadingInteractionInset)
                .padding(.trailing, trailingInteractionInset)
                .padding(.top, 10)
        }
        .padding(.top, 0)
        .accessibilitySortPriority(100)
    }

    /// Stretchy/parallax cover with the avatar nested in its concave notch. The mascot
    /// sits at the trailing end of the avatar row, below the banner, so it never collides
    /// with the avatar, the seam, or the handle.
    private func heroMedia(_ profile: ModulaProfile) -> some View {
        let avatarSize = ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)
        return VStack(alignment: .leading, spacing: 0) {
            ProfileCover(
                coverURL: profile.coverURL,
                coverColour: profile.coverColour,
                tint: heroTint,
                scrollProgress: headerProgress,
                onTap: { openCoverViewer(profile) },
                contextActions: ProfileContextActions.coverMenu(isOwn: isOwnProfile, hasCover: profile.coverURL != nil),
                onContextAction: { handleContextAction($0, profile: profile) }
            )
            ProfileAvatarPocket(
                profile: profile,
                tint: heroTint,
                onTap: { openAvatarViewer(profile) },
                onStoryTap: { openProfileStory(profile) },
                storyRing: storyRing(for: profile),
                contextActions: avatarActions(profile),
                onContextAction: { handleContextAction($0, profile: profile) }
            )
            // The hero avatar stays in the content layer: it shrinks into its own pocket and fades
            // as it scrolls up (the bar avatar takes over), so it never floats over the details.
            .scaleEffect(navReduceMotion ? 1 : 1 - 0.45 * IslandAvatarMerge<EmptyView>.progress(for: heroAvatarFrame), anchor: .bottom)
            // Gone well before it reaches the bar (no ghost behind the title).
            .opacity(Double(max(0, 1 - IslandAvatarMerge<EmptyView>.progress(for: heroAvatarFrame) * 2.2)))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { heroAvatarFrame = $0 }
        }
    }

    private func avatarActions(_ profile: ModulaProfile) -> [ModulaContextAction] {
        var actions = ProfileContextActions.avatarMenu(isOwn: isOwnProfile, hasPhoto: profile.avatarURL != nil)
        if isOwnProfile {
            actions.insert(
                ModulaContextAction(id: "frames", title: "Frames & status", systemImage: "person.crop.circle.badge.checkmark"),
                at: 0
            )
        }
        return actions
    }

    private func heroActions(_ profile: ModulaProfile) -> some View {
        ProfileHeroActions(
            isOwn: isOwnProfile,
            tint: heroTint,
            followTitle: profile.followState.title,
            isFollowing: profile.isFollowing,
            followBusy: followBusy,
            messageTitle: messageActionTitle,
            moreActions: isOwnProfile ? [] : ProfileContextActions.moreMenu(isOwn: false),
            onEdit: { openSection(.edit) },
            onShare: { presentShare(profile) },
            onCode: {
                showsModulaCode = true
                HapticEngine.shared.play(.selection)
            },
            onFollow: {
                Task { await toggleFollowPrimary(profile) }
            },
            onMessage: { openMessaging(for: profile) },
            onNotify: {
                app.navigation.flash("Profile notifications are coming soon", symbol: "bell.badge")
            },
            onMore: { handleContextAction($0, profile: profile) }
        )
        .accessibilitySortPriority(90)
    }

    // MARK: - Highlights / mutuals / links

    @ViewBuilder
    private func highlights(_ profile: ModulaProfile) -> some View {
        let items = highlightItems(profile)
        // A lone "+ New" isn't a highlights row; show it only beside real stories.
        if items.contains(where: { $0.id != "new" }) {
            ProfileHighlightsRow(items: items, tint: heroTint)
        }
    }

    private func highlightItems(_ profile: ModulaProfile) -> [ProfileHighlightItem] {
        var items: [ProfileHighlightItem] = []
        if let group = app.stories.groups.first(where: { $0.author.id == profile.id || $0.author.handle == profile.handle }),
           group.hasStories, !group.isComposerPlaceholder {
            items.append(ProfileHighlightItem(
                id: "live",
                title: "Story",
                symbol: "play.fill",
                imageURL: profile.avatarURL,
                initials: profile.initials,
                action: { openProfileStory(profile) }
            ))
        }
        if isOwnProfile {
            items.append(ProfileHighlightItem(
                id: "new",
                title: "New",
                symbol: "plus",
                action: {
                    app.navigation.flash("Story highlights are coming soon", symbol: "sparkles")
                }
            ))
        }
        return items
    }

    private func mutualFollowers(_ profile: ModulaProfile) -> [ModulaProfile] {
        guard !isOwnProfile, let accountHandle else { return [] }
        let mine = app.profile.session(for: .me, handleHint: accountHandle).following.items
        let theirs = session.followers.items
        guard !mine.isEmpty, !theirs.isEmpty else { return [] }
        let followed = Set(mine.map { $0.handle.lowercased() })
        return theirs.filter {
            followed.contains($0.handle.lowercased())
                && $0.handle.caseInsensitiveCompare(accountHandle) != .orderedSame
        }
    }

    /// First page of my following + their followers → "Followed by …" (real data).
    private func loadMutuals(_ profile: ModulaProfile) async {
        guard !isOwnProfile, app.auth.isSignedIn, let accountHandle else { return }
        await app.profile.loadFollowingIfNeeded(.me, handle: accountHandle)
        await app.profile.loadFollowersIfNeeded(identity, handle: profile.handle)
    }

    @ViewBuilder
    private func linksPreviewSection(_ profile: ModulaProfile) -> some View {
        let links = Array(profile.publicLinks.prefix(3))
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ProfilePreviewHeader(title: "Links", showsSeeAll: profile.publicLinks.count > 3) {
                    openSection(.links)
                }
                VStack(spacing: 0) {
                    ForEach(links) { link in
                        linkRow(link)
                            .padding(.horizontal, 14)
                        if link.id != links.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .padding(.vertical, 4)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            }
            .accessibilityIdentifier("profile.links")
        }
    }

    // MARK: - Sticky shelf (Posts / Media / Modules / Saved·Liked)

    private var shelfTabs: [ProfileShelfTab] {
        isOwnProfile ? [.posts, .replies, .media, .reels, .modules, .liked, .saved] : [.posts, .replies, .media, .reels, .modules, .liked]
    }

    @State private var shelfPinned = false

    private func shelfBar(_ profile: ModulaProfile, floating: Bool = false) -> some View {
        let tabs = shelfTabs
        let selected = tabs.contains(shelf) ? shelf : .posts
        let stickTop = ProfileFullBleedMetrics.windowSafeAreaTop + 44
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        return HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    let isSelected = tab == selected
                    Button {
                        guard tab != selected else { return }
                        withAnimation(reduce ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                            shelf = tab
                        }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(isSelected ? heroTint : Color.primary.opacity(0.62))
                        .padding(.horizontal, isSelected ? 12 : 9)
                        .frame(height: 38)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(heroTint.opacity(0.16))
                                    .matchedGeometryEffect(id: "shelf.pill", in: shelfNamespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("profile.tab.\(tab.rawValue)")
                }
            }
            .padding(3)
            .padding(.trailing, 14)
            }
            // Edge fade so a clipped tab ("Mod…") reads as scrollable instead of cut off.
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.86),
                    .init(color: .black.opacity(0), location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .modulaGlass(in: Capsule(), interactive: false, specular: true)

            if selected == .posts {
                ProfilePostLayoutToggle(layout: postLayout, tint: heroTint)
                    .padding(2)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.leading, leadingInteractionInset)
        .padding(.trailing, trailingInteractionInset)
        .padding(.vertical, 8)
        // The in-scroll bar only reports whether it has reached the pin line; once pinned, a
        // copy is drawn outside the ScrollView (above a real blur strip) and this one hides.
        // A material inside the scroll content could not blur the posts scrolling under it.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
            guard !floating else { return }
            let pinned = minY <= stickTop + 2
            if pinned != shelfPinned { shelfPinned = pinned }
        }
        .opacity(floating || !shelfPinned ? 1 : 0)
        // No manual pin offset: the LazyVStack's pinned section header already rests at the
        // scroll view's top content margin (status bar + 44, i.e. right under the top bar).
        // The old offset was added on top of that, which parked the tabs ~100pt too low.
        .zIndex(1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.tabs")
    }

    @ViewBuilder
    private func shelfContent(_ profile: ModulaProfile) -> some View {
        let selected = shelfTabs.contains(shelf) ? shelf : .posts
        Group {
            switch selected {
            case .posts: postsShelf(profile, mediaOnly: false)
            case .media: postsShelf(profile, mediaOnly: true)
            case .reels: postsShelf(profile, mediaOnly: true, videoOnly: true)
            case .replies:
                // Stub: profile posts carry no reply/parent field, so replies can't be listed yet.
                ModulaEmptyState(title: "Replies", message: "Replies by this profile will show here.", symbol: "arrowshape.turn.up.left")
                    .padding(.vertical, 8)
            case .modules: modulesTab(profile)
            case .saved: savedShelf
            case .liked: likedShelf
            }
        }
        .id(selected)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        ))
        // No swipe-to-switch: horizontal gestures belong to post carousels / media; tabs switch by tap.
        .task(id: selected) {
            guard selected == .modules else { return }
            await app.profile.loadModulesIfNeeded(
                identity,
                handle: profile.handle,
                featuredIDs: profile.featuredModuleIds,
                catalogue: app.catalogue.products
            )
        }
    }

    private func postsShelf(_ profile: ModulaProfile, mediaOnly: Bool, videoOnly: Bool = false) -> some View {
        let all = session.posts.items.isEmpty ? session.overviewPreviewPosts : session.posts.items
        let media = mediaOnly ? all.filter { $0.hasMedia } : all
        let items = videoOnly ? media.filter { [.video, .movie].contains($0.kind) } : media
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                if case .loading = session.posts.loadState {
                    ProfilePostGridSkeleton()
                } else if mediaOnly {
                    ModulaEmptyState(
                        title: videoOnly ? "No reels yet" : "No media yet",
                        message: isOwnProfile
                            ? "Photos and videos you post will collect here."
                            : "Photos and videos from this profile will appear here.",
                        symbol: "photo.on.rectangle"
                    )
                    .padding(.vertical, 8)
                } else {
                    emptyPosts(isOwn: isOwnProfile, compact: true)
                }
            } else if mediaOnly || postLayout.wrappedValue == .grid {
                ProfilePostGrid(
                    posts: items,
                    tint: heroTint,
                    onOpen: { post in
                        app.navigation.open(.post(post.id, .root))
                        HapticEngine.shared.play(.navigation)
                    },
                    onReachEnd: {
                        Task { await app.profile.loadMorePosts(identity, handle: profile.handle) }
                    }
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { post in
                        postCard(post, compactAuthor: true)
                            .modulaScrollReveal()
                            .onAppear {
                                if post.id == items.last?.id {
                                    Task { await app.profile.loadMorePosts(identity, handle: profile.handle) }
                                }
                            }
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .accessibilityIdentifier(mediaOnly ? "profile.preview.media" : "profile.preview.posts")
    }

    private var savedShelf: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 64, height: 64)
                .modulaGlass(in: Circle(), interactive: false, tint: heroTint)
            Text("Only you can see what you’ve saved")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Saved posts and your collections live in Saved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                app.navigation.open(.saved(.root))
                HapticEngine.shared.play(.navigation)
            } label: {
                Label("Open Saved", systemImage: "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
            .modulaAccentCTA()
            .padding(.top, 4)
            .accessibilityIdentifier("profile.saved.open")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityIdentifier("profile.preview.saved")
    }

    private var likedShelf: some View {
        ModulaEmptyState(
            title: "Likes aren’t public yet",
            message: "Posts this profile likes will show here once Modula supports public likes.",
            symbol: "heart"
        )
        .padding(.vertical, 8)
        .accessibilityIdentifier("profile.preview.liked")
    }

    @ViewBuilder
    private func primaryActions(_ profile: ModulaProfile) -> some View {
        if !isOwnProfile {
            ProfileToolActions(
                followTitle: profile.followState.title,
                isFollowing: profile.isFollowing,
                followBusy: followBusy,
                messageTitle: messageActionTitle,
                onPrimary: {
                    Task { await toggleFollowPrimary(profile) }
                },
                onMessage: { openMessaging(for: profile) }
            )
            .accessibilitySortPriority(90)
        }
    }

    /// Compact inline stats (X / Threads style); each count opens its list.
    private func metrics(_ profile: ModulaProfile) -> some View {
        HStack(spacing: 16) {
            statLink(profile.postCount, "posts") { openSection(.posts) }
            statLink(profile.followerCount, profile.followerCount == 1 ? "follower" : "followers") { openSection(.followers) }
            statLink(profile.followingCount, "following") { openSection(.following) }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("profile.stats")
    }

    private func statLink(_ value: Int, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            (Text(ModulaCountFormat.compact(value) ?? "0").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
             + Text(" \(label)").font(.subheadline.weight(.medium)).foregroundStyle(Color.primary.opacity(0.72)))
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label)")
    }

    private func availableTabs(_ profile: ModulaProfile) -> [ProfileContentTab] {
        var tabs: [ProfileContentTab] = [.posts, .modules]
        if !profile.publicLinks.isEmpty { tabs.append(.links) }
        return tabs
    }

    private func contentTabs(_ profile: ModulaProfile) -> some View {
        let tabs = availableTabs(profile)
        let selected = tabs.contains(contentTab) ? contentTab : .posts
        return VStack(alignment: .leading, spacing: 14) {
            ModulaEffectTabs(
                tabs: tabs,
                selection: Binding(get: { selected }, set: { contentTab = $0 }),
                title: { $0.title },
                symbol: { $0.symbol },
                tint: heroTint
            )
            .accessibilityIdentifier("profile.tabs")

            Group {
                switch selected {
                case .posts: postsTab(profile)
                case .modules: modulesTab(profile)
                case .links: linksTab(profile)
                }
            }
            .id(selected)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)),
                removal: .opacity
            ))
        }
        .task(id: selected) {
            guard selected == .modules else { return }
            await app.profile.loadModulesIfNeeded(
                identity,
                handle: profile.handle,
                featuredIDs: profile.featuredModuleIds,
                catalogue: app.catalogue.products
            )
        }
    }

    private func postsTab(_ profile: ModulaProfile) -> some View {
        let items = session.posts.items.isEmpty ? session.overviewPreviewPosts : session.posts.items
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.postCount == 1 ? "1 post" : "\(ProfileCountFormatter.compact(max(profile.postCount, items.count))) posts")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty {
                    ProfilePostLayoutToggle(layout: postLayout, tint: heroTint)
                }
            }
            if items.isEmpty {
                if case .loading = session.posts.loadState {
                    ProfilePostGridSkeleton()
                } else {
                    emptyPosts(isOwn: isOwnProfile, compact: true)
                }
            } else if postLayout.wrappedValue == .grid {
                ProfilePostGrid(
                    posts: items,
                    tint: heroTint,
                    onOpen: { post in
                        app.navigation.open(.post(post.id, .root))
                        HapticEngine.shared.play(.navigation)
                    },
                    onReachEnd: {
                        Task { await app.profile.loadMorePosts(identity, handle: profile.handle) }
                    }
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { post in
                        postCard(post, compactAuthor: true)
                            .modulaScrollReveal()
                            .onAppear {
                                if post.id == items.last?.id {
                                    Task { await app.profile.loadMorePosts(identity, handle: profile.handle) }
                                }
                            }
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .accessibilityIdentifier("profile.preview.posts")
    }

    private func modulesTab(_ profile: ModulaProfile) -> some View {
        let modules = session.modules.items
        return Group {
            if modules.isEmpty {
                if case .loading = session.modules.loadState {
                    ProfilePostGridSkeleton(rows: 1)
                } else {
                    emptyModules(compact: true)
                }
            } else {
                ProfileModuleGrid(
                    products: modules,
                    installedIDs: app.catalogue.installedIDs,
                    onOpen: openModule
                )
            }
        }
        .accessibilityIdentifier("profile.preview.modules")
    }

    private func linksTab(_ profile: ModulaProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(profile.publicLinks) { link in
                linkRow(link)
                    .modulaScrollReveal()
            }
        }
        .accessibilityIdentifier("profile.preview.links")
    }

    private func postsPreview(_ profile: ModulaProfile) -> some View {
        let posts = Array(session.overviewPreviewPosts.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            ProfilePreviewHeader(title: "Posts", showsSeeAll: profile.postCount > 0 || !posts.isEmpty) {
                openSection(.posts)
            }
            if posts.isEmpty {
                emptyPosts(isOwn: isOwnProfile, compact: true)
            } else {
                ForEach(posts) { post in
                    postCard(post, compactAuthor: true)
                    Divider().opacity(0.35)
                }
            }
        }
        .accessibilityIdentifier("profile.preview.posts")
    }

    private func modulesPreview(_ profile: ModulaProfile) -> some View {
        let modules = Array(session.modules.items.prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            ProfilePreviewHeader(
                title: "Modules",
                showsSeeAll: !profile.featuredModuleIds.isEmpty || !modules.isEmpty
            ) {
                openSection(.modules)
            }
            if modules.isEmpty {
                emptyModules(compact: true)
            } else {
                ProfileModuleGrid(
                    products: modules,
                    installedIDs: app.catalogue.installedIDs,
                    onOpen: openModule
                )
            }
        }
        .accessibilityIdentifier("profile.preview.modules")
    }

    private func linksPreview(_ profile: ModulaProfile) -> some View {
        let links = Array(profile.publicLinks.prefix(3))
        return Group {
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ProfilePreviewHeader(title: "Links", showsSeeAll: profile.publicLinks.count > 3) {
                        openSection(.links)
                    }
                    ForEach(links) { link in
                        linkRow(link)
                    }
                }
                .accessibilityIdentifier("profile.preview.links")
            }
        }
    }

    // MARK: - Sections

    private func postsSection(_ profile: ModulaProfile, embedded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                sectionHero(profile)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                let items = session.posts.items
                switch session.posts.loadState {
                case .loading where items.isEmpty:
                    ProfilePostGridSkeleton()
                        .padding(.top, 8)
                case .failed where items.isEmpty:
                    ModulaErrorState(message: session.posts.lastError ?? "Unable to load posts.") {
                        Task { await app.profile.refreshPosts(identity, handle: profile.handle) }
                    }
                    .padding(.top, 28)
                case _ where items.isEmpty:
                    emptyPosts(isOwn: isOwnProfile, compact: false)
                        .padding(.top, 20)
                default:
                    ForEach(items) { post in
                        postCard(post, compactAuthor: true)
                            .modulaScrollReveal()
                            .onAppear {
                                if post.id == items.suffix(3).first?.id || post.id == items.last?.id {
                                    Task { await app.profile.loadMorePosts(identity, handle: profile.handle) }
                                }
                            }
                        Divider().opacity(0.35)
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.trailing, trailingInteractionInset)
            .padding(.leading, leadingInteractionInset)
            .padding(.top, embedded ? 0 : 8)
        }
    }

    private func modulesSection(_ profile: ModulaProfile, embedded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded {
                sectionHero(profile)
            }
            let items = session.modules.items
            if items.isEmpty {
                emptyModules(compact: false)
                    .padding(.horizontal, ModulaLayout.contentInset)
            } else {
                ProfileModuleGrid(
                    products: items,
                    installedIDs: app.catalogue.installedIDs,
                    onOpen: openModule
                )
                .padding(.horizontal, ModulaLayout.contentInset)
            }
        }
        .padding(.top, embedded ? 0 : 8)
    }

    private enum PeopleKind { case followers, following }

    private func peopleSection(kind: PeopleKind, profile: ModulaProfile) -> some View {
        let collection = kind == .followers ? session.followers : session.following
        return VStack(alignment: .leading, spacing: 0) {
            sectionHero(profile)
            LazyVStack(alignment: .leading, spacing: 0) {
                switch collection.loadState {
                case .loading where collection.items.isEmpty:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                case .failed where collection.items.isEmpty:
                    ModulaErrorState(message: collection.lastError ?? "Unable to load people.") {
                        Task {
                            if kind == .followers {
                                await app.profile.loadFollowersIfNeeded(identity, handle: profile.handle)
                            } else {
                                await app.profile.loadFollowingIfNeeded(identity, handle: profile.handle)
                            }
                        }
                    }
                    .padding(.top, 28)
                case _ where collection.items.isEmpty:
                    ModulaEmptyState(
                        title: kind == .followers ? "No followers yet" : "Not following anyone yet",
                        message: kind == .followers
                            ? "When people follow this profile, they’ll show up here."
                            : "Accounts this profile follows will appear here.",
                        symbol: "person.2"
                    )
                    .padding(.top, 20)
                default:
                    ForEach(collection.items) { person in
                        ProfilePeopleRow(
                            person: person,
                            followBusy: followBusyIDs.contains(person.routeID),
                            showsFollow: !isSameAsViewer(person),
                            onOpen: { openPerson(person) },
                            onFollow: {
                                Task { await toggleFollow(person) }
                            }
                        )
                        .modulaScrollReveal()
                        Divider().opacity(0.3)
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
        }
    }

    private func linksSection(_ profile: ModulaProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHero(profile)
            let links = profile.publicLinks
            if links.isEmpty {
                if isOwnProfile {
                    ContentUnavailableView {
                        Label("Add links to the places that matter.", systemImage: "link")
                    } description: {
                        Text("Links will appear on your public profile when the backend write path lands.")
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                } else {
                    ModulaEmptyState(
                        title: "No public links.",
                        message: "This profile hasn’t shared any links.",
                        symbol: "link"
                    )
                    .padding(.horizontal, ModulaLayout.contentInset)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(links) { link in
                        linkRow(link)
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
        }
    }

    private var connectionsUnavailable: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let profile {
                sectionHero(profile)
            }
            ModulaEmptyState(
                title: "Connections unavailable",
                message: "People connections aren’t available on profiles yet.",
                symbol: "person.2.slash"
            )
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 24)
        }
    }

    private func sectionHero(_ profile: ModulaProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heroMedia(profile)
            VStack(alignment: .leading, spacing: 16) {
                ProfileIdentityBlock(profile: profile, showsFollowsYou: !isOwnProfile)
                ProfileActionsRow(
                    profile: profile,
                    selected: section,
                    showsModules: true,
                    onPosts: { openSection(.posts) },
                    onFollowers: { openSection(.followers) },
                    onFollowing: { openSection(.following) },
                    onModules: { openSection(.modules) }
                )
                heroActions(profile)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.leading, leadingInteractionInset)
            .padding(.trailing, trailingInteractionInset)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Rows / cards

    private func postCard(_ post: SocialPost, compactAuthor: Bool) -> some View {
        let resolved = app.posts.resolved(post)
        return PostCard(
            post: resolved,
            showsCompactAuthor: compactAuthor,
            showsActionRail: post.hasMedia,
            onOpenPost: {
                app.navigation.open(.post(resolved.id, .root))
                HapticEngine.shared.play(.navigation)
            },
            onOpenAuthor: {
                // Same-person on profile; still no-op safely if tapped.
            },
            onLike: {
                Task {
                    app.postActions.ingest(resolved)
                    await app.postActions.toggleLike(resolved)
                    app.home.syncVisibleEngagement()
                }
            },
            onComment: {
                app.navigation.open(.post(resolved.id, .comments))
                HapticEngine.shared.play(.navigation)
            },
            onRepost: {
                Task {
                    app.postActions.ingest(resolved)
                    await app.postActions.toggleRepost(resolved)
                    app.home.syncVisibleEngagement()
                }
            },
            onSave: {
                Task {
                    app.postActions.ingest(resolved)
                    await app.postActions.toggleSave(resolved)
                    app.home.syncVisibleEngagement()
                }
            },
            onShare: {
                activityShare = ActivityShareItem(url: resolved.shareURL)
            },
            onContextAction: { handlePostContextAction($0, post: resolved) },
            onOpenMedia: { _ in
                app.navigation.open(.post(resolved.id, .root))
            },
            onOpenModule: { module in
                app.navigation.push(.productHub(.module(module.id, .overview)))
                HapticEngine.shared.play(.navigation)
            },
            style: .immersive
        )
        .modifier(PostSwipeActions(
            enabled: resolved.media.count <= 1,
            saved: resolved.saved,
            accent: app.appearance.liveAccent,
            onSave: {
                Task {
                    app.postActions.ingest(resolved)
                    await app.postActions.toggleSave(resolved)
                    app.home.syncVisibleEngagement()
                }
                app.navigation.flash(resolved.saved ? "Removed from Bookmarks" : "Saved to Bookmarks", symbol: resolved.saved ? "bookmark.slash" : "bookmark.fill")
            },
            onShare: {
                PostSharing.share(resolved, app: app)
            }
        ))
        .padding(.horizontal, -ModulaLayout.contentInset)
        .padding(.leading, -leadingInteractionInset)
        .padding(.trailing, -trailingInteractionInset)
        .padding(.horizontal, ModulaLayout.postBleedGutter)
        .modulaEdgeFlow()
        .accessibilityIdentifier("profile.post.\(resolved.id)")
    }

    private func linkRow(_ link: ProfileLink) -> some View {
        Button {
            if let url = link.url {
                ProfileAboutGrid.openSafely(url, openURL: openURL)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let domain = link.domain ?? link.url?.host {
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(link.url == nil)
        .accessibilityLabel(link.label)
        .accessibilityIdentifier("profile.link.\(link.id)")
    }

    @ViewBuilder
    private func emptyPosts(isOwn: Bool, compact: Bool) -> some View {
        if isOwn {
            ContentUnavailableView {
                Label("Your story starts here.", systemImage: "text.bubble")
            } description: {
                Text("Share your first post.")
            } actions: {
                Button("Create Post") {
                    app.navigation.open(.compose(.post))
                    HapticEngine.shared.play(.navigation)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.appearance.liveAccent)
                .accessibilityIdentifier("profile.empty.compose")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : 20)
        } else {
            ModulaEmptyState(
                title: "No posts yet.",
                message: "This profile hasn’t shared anything public.",
                symbol: "text.bubble"
            )
            .padding(.vertical, compact ? 4 : 12)
        }
    }

    private func emptyModules(compact: Bool) -> some View {
        Group {
            if isOwnProfile {
                ContentUnavailableView {
                    Label("Make your profile modular.", systemImage: "shippingbox")
                } description: {
                    Text("Feature the modules that represent what you use, build or share.")
                } actions: {
                    Button("Choose Modules") {
                        app.navigation.open(.productHub(.featured))
                        HapticEngine.shared.play(.navigation)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.liveAccent)
                    .accessibilityIdentifier("profile.empty.modules.choose")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 12)
            } else {
                ModulaEmptyState(
                    title: "No public modules yet.",
                    message: "This profile hasn’t featured any modules.",
                    symbol: "shippingbox"
                )
                .padding(.vertical, compact ? 4 : 12)
            }
        }
    }

    // MARK: - Actions

    private var taskKey: String {
        "\(identity.description):\(section.rawValue):\(accountHandle ?? "")"
    }

    private func bootstrap() async {
        // Load the profile and the module catalogue concurrently: the profile used to
        // wait for the whole catalogue before its first request (slow first paint).
        let catalogueLoad = Task { await app.catalogue.load() }
        await app.profile.loadIfNeeded(
            identity,
            handleHint: userID,
            accountHandle: accountHandle,
            catalogue: app.catalogue.products
        )
        await catalogueLoad.value
        if let resolved = app.profile.session(for: identity, handleHint: accountHandle).profile,
           !resolved.featuredModuleIds.isEmpty {
            await app.profile.loadModulesIfNeeded(
                identity,
                handle: resolved.handle,
                featuredIDs: resolved.featuredModuleIds,
                catalogue: app.catalogue.products
            )
        }
        guard let handle = app.profile.session(for: identity, handleHint: accountHandle).profile?.handle
                ?? accountHandle
                ?? userID
        else { return }

        let featured = app.profile.session(for: identity, handleHint: accountHandle).profile?.featuredModuleIds ?? []
        switch section {
        case .posts:
            await app.profile.loadPostsIfNeeded(identity, handle: handle)
        case .modules:
            await app.profile.loadModulesIfNeeded(
                identity,
                handle: handle,
                featuredIDs: featured,
                catalogue: app.catalogue.products
            )
        case .followers:
            await app.profile.loadFollowersIfNeeded(identity, handle: handle)
        case .following:
            await app.profile.loadFollowingIfNeeded(identity, handle: handle)
        case .overview, .links, .connections, .edit:
            break
        }
    }

    private func refreshCurrent() async {
        await app.profile.refresh(
            identity,
            handleHint: userID,
            accountHandle: accountHandle,
            catalogue: app.catalogue.products
        )
        guard let handle = profile?.handle ?? accountHandle ?? userID else { return }
        switch section {
        case .posts:
            await app.profile.refreshPosts(identity, handle: handle)
        case .modules:
            await app.profile.loadModulesIfNeeded(
                identity,
                handle: handle,
                featuredIDs: profile?.featuredModuleIds ?? [],
                catalogue: app.catalogue.products
            )
        case .followers:
            await app.profile.refreshFollowers(identity, handle: handle)
        case .following:
            await app.profile.refreshFollowing(identity, handle: handle)
        case .overview, .links, .connections, .edit:
            break
        }
    }

    private func openSection(_ next: ProfileSection) {
        if identity == .me || isOwnProfile {
            app.navigation.push(.me(next))
        } else if let routeID = profile?.routeID ?? userID {
            app.navigation.push(.profile(routeID, next))
        }
        HapticEngine.shared.play(.navigation)
    }

    private func openModule(_ moduleId: String) {
        app.navigation.push(.productHub(.module(moduleId, .overview)))
        HapticEngine.shared.play(.navigation)
    }

    private func openPerson(_ person: ModulaProfile) {
        app.navigation.push(.profile(person.routeID, .overview))
        HapticEngine.shared.play(.navigation)
    }

    private func isSameAsViewer(_ person: ModulaProfile) -> Bool {
        guard let accountHandle else { return false }
        return person.handle.caseInsensitiveCompare(accountHandle) == .orderedSame
    }

    private func toggleFollow(_ person: ModulaProfile) async {
        guard !followBusyIDs.contains(person.routeID) else { return }
        followBusyIDs.insert(person.routeID)
        defer { followBusyIDs.remove(person.routeID) }
        HapticEngine.shared.play(.selection)
        app.profile.seed(person)
        let personIdentity = ProfileIdentity.handle(person.handle)
        if person.isFollowing {
            await app.profile.unfollow(identity: personIdentity, handleHint: person.handle)
        } else {
            await app.profile.follow(
                identity: personIdentity,
                handleHint: person.handle,
                signedIn: app.auth.isSignedIn
            )
            ModulaMascotEvent.post(.follow)
        }
    }

    private func toggleFollowPrimary(_ profile: ModulaProfile) async {
        followBusy = true
        HapticEngine.shared.play(.lightImpact)
        defer { followBusy = false }
        if profile.isFollowing {
            await app.profile.unfollow(identity: identity, handleHint: profile.handle)
        } else {
            await app.profile.follow(
                identity: identity,
                handleHint: profile.handle,
                signedIn: app.auth.isSignedIn
            )
            HapticEngine.shared.play(.followComplete)
            ModulaMascotEvent.post(.follow)
        }
    }

    private func openAvatarViewer(_ profile: ModulaProfile) {
        mediaViewer = ModulaMediaViewerItem(
            title: "Profile photo",
            url: profile.avatarURL,
            accessibilityDescription: "\(profile.displayName)'s profile photo"
        )
    }

    private func openCoverViewer(_ profile: ModulaProfile) {
        guard profile.coverURL != nil else { return }
        mediaViewer = ModulaMediaViewerItem(
            title: "Cover photo",
            url: profile.coverURL,
            accessibilityDescription: "\(profile.displayName)'s cover photo"
        )
    }

    private func presentShare(_ profile: ModulaProfile) {
        showsShareSheet = true
        HapticEngine.shared.play(.lightImpact)
    }

    private func copyProfileLink(_ profile: ModulaProfile) {
        UIPasteboard.general.string = profile.shareURL.absoluteString
        withAnimation { copiedBanner = true }
        HapticEngine.shared.play(.confirmation)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                withAnimation { copiedBanner = false }
            }
        }
    }


    private var messageActionTitle: String? {
        if app.messaging.capabilities.send { return "Message" }
        if app.inMail.capabilities.send { return "Send In-Mail" }
        return nil
    }

    /// Message opens the 1:1 chat with this person (existing thread, else a starter addressed to them),
    /// never the inbox. Without chat, In-Mail compose opens already addressed to them.
    private func openMessaging(for profile: ModulaProfile) {
        let person = profile.handle.isEmpty ? profile.id : profile.handle
        if app.messaging.capabilities.send {
            if let existing = app.messaging.directConversation(with: person) {
                app.navigation.push(.messages(.conversation(existing.id)))
            } else {
                app.navigation.push(.messages(.direct(person)))
            }
            HapticEngine.shared.play(.navigation)
            return
        }
        if app.inMail.capabilities.send {
            if !profile.handle.isEmpty { app.inMail.draft.toHandle = profile.handle }
            app.navigation.push(.messages(.inMail(.compose)))
            HapticEngine.shared.play(.navigation)
        }
    }

    /// Only a real, live story rings the avatar — never the composer "+" placeholder.
    private func storyRing(for profile: ModulaProfile) -> StoryRingState? {
        guard let group = app.stories.groups.first(where: { $0.author.id == profile.id || $0.author.handle == profile.handle }),
              group.hasStories, !group.isComposerPlaceholder else { return nil }
        return group.ring
    }

    private func openProfileStory(_ profile: ModulaProfile) {
        guard let group = app.stories.groups.first(where: { $0.author.id == profile.id || $0.author.handle == profile.handle }),
              group.hasStories, !group.isComposerPlaceholder else {
            openAvatarViewer(profile)
            return
        }
        // Rail entries are summaries (no items), so resolve through the store, which hydrates.
        Task {
            guard let route = await app.stories.destination(for: group) else {
                openAvatarViewer(profile)
                return
            }
            app.navigation.push(route)
            HapticEngine.shared.play(.navigation)
        }
    }

    private func handleContextAction(_ action: ModulaContextAction, profile: ModulaProfile) {
        switch action.id {
        case "share":
            presentShare(profile)
        case "copy-link":
            copyProfileLink(profile)
        case "saved":
            app.navigation.open(.saved(.root))
            HapticEngine.shared.play(.navigation)
        case "drafts":
            app.navigation.open(.drafts(.root))
            HapticEngine.shared.play(.navigation)
        case "modula-code":
            showsModulaCode = true
        case "preview-visitor":
            app.profile.setVisitorPreview(true)
            HapticEngine.shared.play(.navigation)
        case "settings":
            app.navigation.open(.settings(.account(.root)))
            HapticEngine.shared.play(.navigation)
        case "edit":
            openSection(.edit)
        case "frames":
            showsFrames = true
            HapticEngine.shared.play(.selection)
        case "mute":
            Task {
                await app.profile.mute(identity: identity, handleHint: profile.handle)
            }
        case "block":
            confirmsBlock = true
        case "report":
            confirmsReport = true
        case "view-photo":
            openAvatarViewer(profile)
        case "view-cover":
            openCoverViewer(profile)
        case "change-photo":
            mediaAction = .pick(.avatar)
        case "edit-photo":
            mediaAction = .cropExisting(.avatar)
        case "remove-photo":
            mediaAction = .remove(.avatar)
        case "change-cover":
            mediaAction = .pick(.cover)
        case "reposition-cover":
            mediaAction = .cropExisting(.cover)
        case "remove-cover":
            mediaAction = .remove(.cover)
        default:
            break
        }
    }

    private func handlePostContextAction(_ action: ModulaContextAction, post: SocialPost) {
        HapticEngine.shared.play(.contextOpen)
        switch action.id {
        case "save":
            Task {
                app.postActions.ingest(post)
                await app.postActions.toggleSave(post)
                app.home.syncVisibleEngagement()
            }
        case "save-collection":
            app.navigation.presented = .collectionPicker(postID: post.id)
        case "copy-link":
            UIPasteboard.general.string = post.shareURL.absoluteString
            HapticEngine.shared.play(.confirmation)
            app.navigation.flash("Link copied", symbol: "link")
        case "share":
            app.navigation.presented = .universalShare(.post(
                id: post.id,
                authorName: post.author?.displayName,
                excerpt: post.text,
                hasMedia: !post.media.isEmpty
            ))
        case "hide":
            app.postActions.hideLocally(post)
        case "mute-author":
            Task {
                await app.profile.mute(identity: identity, handleHint: profile?.handle)
            }
        case "report":
            confirmsReport = true
        case "edit-post":
            app.navigation.open(.post(post.id, .edit))
        case "delete":
            Task {
                _ = await app.postActions.deletePost(post)
            }
        default:
            break
        }
    }

    private func reportProfile(category: String) async {
        guard let profile else { return }
        await app.profile.report(
            identity: identity,
            handleHint: profile.handle,
            category: category
        )
    }
}

private struct ActivityShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProfileActivityShareView: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Sticky profile shelf tabs. Posts / Media / Modules are real data; Saved (own) opens
/// the Saved library; Liked (others) is a stub until likes are public.
private enum ProfileShelfTab: String, Hashable, Identifiable {
    case posts, replies, media, reels, modules, saved, liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: "Posts"
        case .replies: "Replies"
        case .media: "Media"
        case .reels: "Reels"
        case .modules: "Modules"
        case .saved: "Saved"
        case .liked: "Likes"
        }
    }

    var symbol: String {
        switch self {
        case .posts: "square.grid.2x2"
        case .replies: "arrowshape.turn.up.left"
        case .media: "photo.on.rectangle"
        case .reels: "play.rectangle"
        case .modules: "shippingbox"
        case .saved: "bookmark"
        case .liked: "heart"
        }
    }

    /// Grid / list toggle applies to post-based shelves.
    var usesLayout: Bool { self == .posts || self == .media }
}


/// Profile's top progressive blur (replaces the old clipped header fade, the progress-driven nav
/// background and the separate pinned-tabs backing, which stacked into a hard, uneven edge).
/// Stacked materials, each masked to end lower down, so blur is strongest at the very top and
/// ramps smoothly to fully clear; no slab edge at any height.
private struct ProfileTopProgressiveBlur: View {
    /// Fade below the 44pt bar while the tabs are not pinned.
    static let restingFade: CGFloat = 34
    /// Pinned tabs (8 + 38 + 8) plus a fade below them.
    static let pinnedShelfExtent: CGFloat = 54 + 30

    let height: CGFloat
    let tint: Color
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if reduceTransparency {
                tint.mask(ramp(solidUntil: 0.6, end: 1))
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).mask(ramp(solidUntil: 0.5, end: 1.0))
                    Rectangle().fill(.thinMaterial).mask(ramp(solidUntil: 0.3, end: 0.72))
                    Rectangle().fill(.regularMaterial).mask(ramp(solidUntil: 0.12, end: 0.45))
                    tint.opacity(0.42).mask(ramp(solidUntil: 0.25, end: 0.85))
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ramp(solidUntil: CGFloat, end: CGFloat) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: solidUntil),
            .init(color: .black.opacity(0.5), location: solidUntil + (end - solidUntil) * 0.45),
            .init(color: .black.opacity(0), location: end)
        ], startPoint: .top, endPoint: .bottom)
    }
}


/// The system top scroll-edge blur also covered the pinned tabs (they sit right under the
/// bar); Profile draws its own strip behind the bar + tabs instead.
private struct ProfileTopEdgeEffectHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
