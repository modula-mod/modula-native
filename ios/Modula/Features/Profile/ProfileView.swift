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
            }
        }
        .sheet(item: $activityShare) { item in
            ProfileActivityShareView(url: item.url) {
                activityShare = nil
            }
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
                        .padding(.bottom, shellChromeMetrics.contentBottomInset)
                }
            }
            .modulaScrollProgressTracking(collapseDistance: 96, progress: $headerProgress)
            .modulaSoftScrollEdge()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                headerProgress = ModulaScrollProgress.progress(offsetY: max(0, newOffset), collapseDistance: 96)
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
                    offset: context.geometry.contentOffset.y
                )
            }
            .refreshable {
                await refreshCurrent()
                HapticEngine.shared.play(.lightImpact)
                ModulaMascotEvent.post(.refresh)
            }
            #if DEBUG
            .scrollPosition($debugScrollPosition)
            .task(id: profile != nil) {
                guard profile != nil, ProcessInfo.processInfo.arguments.contains("--debug-autoscroll") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                for (y, duration) in [(260.0, 1.4), (620.0, 1.8), (1_000.0, 1.8), (0.0, 2.2)] {
                    withAnimation(.easeInOut(duration: duration)) { debugScrollPosition.scrollTo(y: y) }
                    try? await Task.sleep(for: .seconds(duration + 0.8))
                }
            }
            #endif

            ModulaProgressiveHeader(
                largeTitle: largeTitle,
                compactTitle: "",
                progress: headerProgress,
                topChromeInset: ProfileFullBleedMetrics.windowSafeAreaTop
            ) {
                EmptyView()
            }
        }
        .ignoresSafeArea(edges: .top)
        .modulaCanvas()
        .environment(\.profileAccentColor, profile?.presentation.accent?.color)
        .modulaImmersiveSystemNavigation()
        .modulaSidebarTrigger()
        .toolbar {
            if headerProgress > 0.35 {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if let profile {
                            ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 28)
                        }
                        Text(compactTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .accessibilityLabel(compactTitle)
                }
            }
            if isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Profile", systemImage: "pencil") {
                        openSection(.edit)
                    }
                    .accessibilityIdentifier("profile.edit.cta")
                }
            }
            if let profile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share Profile", systemImage: "square.and.arrow.up") {
                        presentShare(profile)
                    }
                    .accessibilityIdentifier("profile.share")
                }
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

    /// Avatar colour → profile accent → cover colour → app accent.
    private var heroTint: Color {
        if let avatarTint { return avatarTint }
        if let accent = profile?.presentation.accent?.color { return accent }
        if let hex = profile?.coverColour, !hex.isEmpty { return Color(hex: hex) }
        return app.appearance.accent.color
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
        VStack(alignment: .leading, spacing: 0) {
            hero(profile)

            VStack(alignment: .leading, spacing: 22) {
                if app.profile.visitorPreviewActive, isOwnProfile {
                    ProfileVisitorPreviewBanner {
                        app.profile.setVisitorPreview(false)
                    }
                }
                primaryActions(profile)
                    .modulaPageEntrance(delay: 0.04)
                metrics(profile)
                    .modulaPageEntrance(delay: 0.08)

                if let focus = profile.focusStatus {
                    Label(focus.message ?? focus.label, systemImage: "circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityIdentifier("profile.focus")
                }

                ProfileAboutGrid(profile: profile)
                    .modulaPageEntrance(delay: 0.12)

                contentTabs(profile)
                    .modulaPageEntrance(delay: 0.16)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.leading, leadingInteractionInset)
            .padding(.trailing, trailingInteractionInset)
            .padding(.top, 8)
        }
    }

    private func hero(_ profile: ModulaProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileCover(
                coverURL: profile.coverURL,
                coverColour: profile.coverColour,
                tint: heroTint,
                scrollProgress: headerProgress,
                pocketCenterX: ModulaLayout.contentInset + ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass) / 2,
                pocketRadius: ProfileIdentityMetrics.carveRadius(avatarSize: ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)),
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
                contextActions: ProfileContextActions.avatarMenu(
                    isOwn: isOwnProfile,
                    hasPhoto: profile.avatarURL != nil
                ),
                onContextAction: { handleContextAction($0, profile: profile) }
            )
            .overlay(alignment: .topLeading) {
                if isOwnProfile && showProfileMascot {
                    ProfileMascotChip(size: 28)
                        .offset(
                            x: ModulaLayout.contentInset + ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass) + 6,
                            y: -ProfileIdentityMetrics.overlap(avatarSize: ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)) + 4
                        )
                }
            }
            ProfileIdentityBlock(profile: profile)
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.leading, leadingInteractionInset)
                .padding(.trailing, trailingInteractionInset)
                .padding(.top, 4)
        }
        .padding(.top, 0)
        .accessibilitySortPriority(100)
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

    private func metrics(_ profile: ModulaProfile) -> some View {
        ProfileActionsRow(
            profile: profile,
            selected: section == .overview ? nil : section,
            showsModules: true,
            onPosts: { openSection(.posts) },
            onFollowers: { openSection(.followers) },
            onFollowing: { openSection(.following) },
            onModules: { openSection(.modules) }
        )
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
            ProfileCover(
                coverURL: profile.coverURL,
                coverColour: profile.coverColour,
                tint: heroTint,
                scrollProgress: headerProgress,
                pocketCenterX: ModulaLayout.contentInset + ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass) / 2,
                pocketRadius: ProfileIdentityMetrics.carveRadius(avatarSize: ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)),
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
                contextActions: ProfileContextActions.avatarMenu(
                    isOwn: isOwnProfile,
                    hasPhoto: profile.avatarURL != nil
                ),
                onContextAction: { handleContextAction($0, profile: profile) }
            )
            .overlay(alignment: .topLeading) {
                if isOwnProfile && showProfileMascot {
                    ProfileMascotChip(size: 28)
                        .offset(
                            x: ModulaLayout.contentInset + ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass) + 6,
                            y: -ProfileIdentityMetrics.overlap(avatarSize: ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)) + 4
                        )
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                ProfileIdentityBlock(profile: profile)
                primaryActions(profile)
                ProfileActionsRow(
                    profile: profile,
                    selected: section,
                    showsModules: true,
                    onPosts: { openSection(.posts) },
                    onFollowers: { openSection(.followers) },
                    onFollowing: { openSection(.following) },
                    onModules: { openSection(.modules) }
                )
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 4)
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
                    .foregroundStyle(app.appearance.accent.color)
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
                .tint(app.appearance.accent.color)
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
                    .tint(app.appearance.accent.color)
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

    private func openMessaging(for profile: ModulaProfile) {
        if app.messaging.capabilities.send {
            app.navigation.push(.messages(.new))
            HapticEngine.shared.play(.navigation)
            return
        }
        if app.inMail.capabilities.send {
            app.navigation.push(.messages(.inMail(.compose)))
            HapticEngine.shared.play(.navigation)
        }
    }

    private func storyRing(for profile: ModulaProfile) -> StoryRingState? {
        app.stories.groups.first { $0.author.id == profile.id || $0.author.handle == profile.handle }?.ring
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
