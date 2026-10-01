import SwiftUI

struct ReelsRouteView: View {
    let route: ReelsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            switch route {
            case .feed:
                ReelFeedView(focusID: nil)
            case .reel(let id):
                ReelFeedView(focusID: id)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await app.reels.loadIfNeeded() }
    }
}

struct ReelFeedView: View {
    var focusID: ReelID?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var videoCoordinator = FeedVideoCoordinator()
    @State private var showsComments = false
    @State private var expandedVideo: ModulaAttachment?
    /// Bottom edge of the top bar in screen space, so page controls
    /// (full-screen button) are laid out below it instead of under it.
    @State private var topBarBottom: CGFloat = 0

    var body: some View {
        Group {
            switch app.reels.loadState {
            case .loading where app.reels.items.isEmpty:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            case .failed(let message) where app.reels.items.isEmpty:
                ModulaErrorState(message: message) {
                    Task { await app.reels.refresh() }
                }
            case _ where app.reels.items.isEmpty:
                ModulaEmptyState(
                    title: "Reels",
                    message: "Short-form video will appear here when it’s available.",
                    symbol: "play.rectangle"
                )
            default:
                paging
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        // Dark only inside Reels. `.preferredColorScheme` would flip the
        // whole window (and every other tab) to dark while Reels is open.
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let focusID { app.reels.activate(focusID) }
            else if let restored = app.reels.restoredID { app.reels.activate(restored) }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Button { app.navigation.close() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Back")
                Text("Reels").font(.title2.weight(.bold))
                Spacer()
                Button { app.navigation.open(.compose(.video)) } label: {
                    Image(systemName: "video.badge.plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Post a video")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.55))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topBarBottom = $0 }
        }
        // The navigation bar is hidden, which also removes the system
        // swipe-back. Restore it with a leading-edge drag (VoiceOver users
        // keep the Back button and the escape gesture).
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width > 80, abs(value.translation.height) < 120 {
                                HapticEngine.shared.play(.navigation)
                                app.navigation.close()
                            }
                        }
                )
                .accessibilityHidden(true)
        }
        .accessibilityAction(.escape) { app.navigation.close() }
        .sheet(isPresented: $showsComments) {
            if let reel = current, reel.postID != nil {
                PostCommentsSheet(postID: reel.postID ?? reel.id)
            }
        }
        .fullScreenCover(item: $expandedVideo) { attachment in
            AttachmentViewerRouter(attachment: attachment, onDismiss: { expandedVideo = nil })
        }
        .accessibilityIdentifier("reels.feed")
        .accessibilityValue(RouteSerializer.serialize(focusID.map { .reels(.reel($0)) } ?? .reels(.feed)))
    }

    private var current: Reel? {
        if let id = app.reels.activeID { return app.reels.reel(id: id) }
        return app.reels.items.first
    }

    private var paging: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(app.reels.items) { reel in
                    ReelPageView(
                        reel: reel,
                        isActive: app.reels.activeID == reel.id && !showsComments && expandedVideo == nil && scenePhase == .active,
                        coordinator: videoCoordinator,
                        reduceMotion: reduceMotion,
                        controlsTopInset: topBarBottom,
                        onComment: {
                            guard reel.postID != nil else { return }
                            showsComments = true
                        },
                        onExpand: { expandedVideo = reel.attachment }
                    )
                    .containerRelativeFrame(.vertical)
                    .id(reel.id)
                }
            }
            .scrollTargetLayout()
        }
        .modulaSoftScrollEdge()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(
            get: { app.reels.activeID },
            set: { if let id = $0 { app.reels.activate(id) } }
        ))
        .ignoresSafeArea()
        .background(Color.black)
        .accessibilityAction(named: "Next Reel") { move(1) }
        .accessibilityAction(named: "Previous Reel") { move(-1) }
    }

    private func move(_ delta: Int) {
        guard let id = app.reels.activeID, let index = app.reels.index(of: id) else { return }
        let next = index + delta
        guard app.reels.items.indices.contains(next) else { return }
        app.reels.activate(app.reels.items[next].id)
    }
}

struct ReelPageView: View {
    let reel: Reel
    var isActive: Bool
    var coordinator: FeedVideoCoordinator
    var reduceMotion: Bool
    var controlsTopInset: CGFloat = 0
    var onComment: () -> Void
    var onExpand: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            poster
            if let attachment = reel.attachment, app.reels.capabilities.videoPlayback {
                ModulaVideoSurface(attachment: attachment, coordinator: coordinator, onExpand: onExpand,
                                   height: nil, cornerRadius: 0, allowsPlayback: isActive,
                                   controlsTopInset: controlsTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            ReelOverlay(reel: resolved, shareRoute: shareRoute, onComment: onComment)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 48)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Open creator") {
            app.navigation.push(.profile(reel.creator.routeID, .overview))
        }
        .accessibilityIdentifier("reels.page.\(reel.id)")
    }

    private var resolved: SocialPost {
        app.posts.resolved(reel.asSocialPost())
    }

    /// Share the backing post when there is one; otherwise the reel itself
    /// (a reel id is not a post id).
    private var shareRoute: AppRoute {
        if let postID = reel.postID { return .post(postID, .root) }
        return .reels(.reel(reel.id))
    }

    private var poster: some View {
        ZStack {
            Color(hex: reel.posterColor ?? "#111111")
            if let caption = reel.caption {
                Text(caption)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(28)
                    .opacity(reel.media?.url == nil ? 1 : 0)
            }
        }
        .ignoresSafeArea()
    }

    private var accessibilityLabel: String {
        var parts = [reel.creator.displayName]
        if let caption = reel.caption { parts.append(caption) }
        if let duration = reel.durationLabel { parts.append(duration) }
        parts.append("\(resolved.likeCount) likes")
        parts.append("\(resolved.replyCount) comments")
        return parts.joined(separator: ", ")
    }
}

struct ReelOverlay: View {
    let reel: SocialPost
    var shareRoute: AppRoute
    var onComment: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if let route = reel.author?.routeID {
                        app.navigation.push(.profile(route, .overview))
                        HapticEngine.shared.play(.navigation)
                    }
                } label: {
                    HStack {
                        ModulaAvatar(initials: reel.author?.initials ?? "?", url: reel.author?.avatarURL, size: 36)
                        Text(reel.author?.displayName ?? "Creator")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                if let caption = reel.text {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 28)
            Spacer(minLength: 8)
            PostActionRail(
                post: reel,
                onLike: { Task { await app.postActions.toggleLike(reel) } },
                onComment: onComment,
                onSave: { Task { await app.postActions.toggleSave(reel) } },
                onShare: {
                    app.navigation.presented = .share(shareRoute)
                }
            )
            .padding(.trailing, 10)
            .padding(.bottom, 36)
        }
    }
}

struct DiscoverReelsShelf: View {
    let reels: [Reel]
    var onOpen: (Reel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reels")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(reels) { reel in
                        Button {
                            onOpen(reel)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: reel.posterColor ?? "#222222"))
                                    .frame(width: 132, height: 196)
                                if let url = reel.media?.posterURL {
                                    ModulaRemoteImage(url: url, cacheKey: "reel-poster:\(reel.id)", maximumPixelSize: 480) { phase in
                                        if case .success(let image) = phase {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        }
                                    }
                                    .frame(width: 132, height: 196).clipped()
                                }
                                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                                    .frame(width: 132, height: 196)
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: "play.fill").font(.title3).padding(.bottom, 12)
                                    Text(reel.creator.displayName)
                                        .font(.caption.weight(.semibold))
                                    if let caption = reel.caption {
                                        Text(caption).font(.caption2).lineLimit(2)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(10)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reel by \(reel.creator.displayName)")
                    }
                }
            }
        }
        .accessibilityIdentifier("discover.reels.shelf")
    }
}
