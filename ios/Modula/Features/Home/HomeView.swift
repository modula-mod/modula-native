import SwiftUI

struct HomeView: View {
    let mode: HomeMode
    @Environment(AppEnvironment.self) private var app
    @State private var headerProgress: CGFloat = 0

    var body: some View {
        let state = app.home.state(for: mode)
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Keep the progress probe outside LazyVStack so recycling cannot drop it.
                    ModulaScrollProgressReader()
                    LazyVStack(alignment: .leading, spacing: 18) {
                        hero
                        quickAccessShelf
                        if app.home.isOfflineHint && !state.items.isEmpty {
                            offlineBanner
                        }
                        feedContent(state)
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 4)
                    .padding(.bottom, 120)
                }
            }
            .modulaScrollProgressTracking(progress: $headerProgress)
            .modulaSoftScrollEdge()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                headerProgress = ModulaScrollProgress.progress(offsetY: max(0, newOffset), collapseDistance: 72)
            }
            .refreshable {
                await app.home.refresh(mode, signedIn: app.auth.isSignedIn)
            }

            ModulaProgressiveHeader(
                largeTitle: "Modula",
                compactTitle: "Modula",
                progress: headerProgress
            ) {
                Button {
                    app.navigation.open(.settings(.root))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            if state.newerAvailable {
                newerPill
                    .padding(.top, 96)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .modulaCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: mode) {
            await app.home.loadIfNeeded(mode, signedIn: app.auth.isSignedIn)
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            Task { await app.home.refresh(mode, signedIn: app.auth.isSignedIn) }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native.home")
        .accessibilityValue(RouteSerializer.serialize(.home(mode)))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.heroSubtitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(mode.heroTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, maxHeight: 120)
        .padding(.top, 96)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.hero")
    }

    private var quickAccessShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                shelfChip(title: "Product Hub", symbol: "shippingbox") {
                    app.navigation.open(.productHub(.featured))
                }
                shelfChip(title: "Compose", symbol: "square.and.pencil") {
                    app.navigation.open(.compose(.post))
                }
            }
        }
        .accessibilityIdentifier("home.shelf")
    }

    private func shelfChip(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.navigation)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(app.appearance.accent.color.opacity(0.12), in: Capsule())
                .foregroundStyle(app.appearance.accent.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
            case _ where state.items.isEmpty:
                emptyState
                    .padding(.top, 20)
            default:
                ForEach(state.items) { post in
                    PostCard(
                        post: post,
                        onOpenPost: { openPost(post) },
                        onOpenAuthor: { openAuthor(post) },
                        onLike: {
                            Task { await app.home.toggleLike(post, mode: mode) }
                        },
                        onComment: {
                            app.navigation.open(.post(post.id, .comments))
                            HapticEngine.shared.play(.navigation)
                        },
                        onRepost: {
                            Task { await app.home.toggleRepost(post, mode: mode) }
                        },
                        onSave: {
                            Task { await app.home.toggleSave(post, mode: mode) }
                        }
                    )
                    .onAppear {
                        if post.id == state.items.suffix(3).first?.id || post.id == state.items.last?.id {
                            Task { await app.home.loadMore(mode) }
                        }
                    }
                    Divider().opacity(0.35)
                }
                if state.loadState == .loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("home.loading-more")
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

    private func openPost(_ post: SocialPost) {
        app.navigation.open(.post(post.id, .root))
        HapticEngine.shared.play(.navigation)
    }

    private func openAuthor(_ post: SocialPost) {
        guard let author = post.author else { return }
        // Push onto the current Home stack — never hijack the Profile tab root.
        app.navigation.push(.profile(author.routeID, .overview))
        HapticEngine.shared.play(.navigation)
    }
}
