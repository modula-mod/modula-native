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
    @State private var playback = ModulaVideoPlaybackController()
    @State private var showsComments = false

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
                .modulaCanvas()
            case _ where app.reels.items.isEmpty:
                ModulaEmptyState(
                    title: "Reels",
                    message: "Short-form video will appear here when it’s available.",
                    symbol: "play.rectangle"
                )
                .modulaCanvas()
            default:
                paging
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let focusID { app.reels.activate(focusID) }
            else if let restored = app.reels.restoredID { app.reels.activate(restored) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.pause() }
        }
        .sheet(isPresented: $showsComments) {
            if let reel = current, reel.postID != nil {
                PostCommentsView(postID: reel.postID ?? reel.id)
            }
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
                        isActive: app.reels.activeID == reel.id,
                        playback: playback,
                        reduceMotion: reduceMotion,
                        onComment: {
                            guard reel.postID != nil else { return }
                            showsComments = true
                        }
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
    var playback: ModulaVideoPlaybackController
    var reduceMotion: Bool
    var onComment: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var flashPaused = false

    var body: some View {
        ZStack {
            poster
            if isActive, let media = reel.media, media.canPlayVideo, app.reels.capabilities.videoPlayback {
                ModulaVideoPlayer(resource: media, isActive: isActive, controller: playback)
            }
            ReelOverlay(reel: resolved, onComment: onComment)
            if flashPaused {
                Image(systemName: playback.state == .playing ? "play.fill" : "pause.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(22)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if app.reels.capabilities.videoPlayback {
                playback.toggle()
                flash()
            }
        }
        .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
            if pressing { playback.pause() } else if isActive { playback.play() }
        }, perform: {})
        .onChange(of: isActive) { _, active in
            if !active { playback.pause() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: playback.state == .playing ? "Pause" : "Play") { playback.toggle() }
        .accessibilityAction(named: "Open creator") {
            app.navigation.push(.profile(reel.creator.routeID, .overview))
        }
        .accessibilityIdentifier("reels.page.\(reel.id)")
    }

    private var resolved: SocialPost {
        app.posts.resolved(reel.asSocialPost())
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

    private func flash() {
        flashPaused = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            flashPaused = false
        }
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
                    app.navigation.presented = .share(.post(reel.id, .root))
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
                HStack(spacing: 12) {
                    ForEach(reels) { reel in
                        Button {
                            onOpen(reel)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: reel.posterColor ?? "#222222"))
                                    .frame(width: 132, height: 196)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reel.creator.displayName)
                                        .font(.caption.weight(.semibold))
                                    if let caption = reel.caption {
                                        Text(caption).font(.caption2).lineLimit(2)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(10)
                            }
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
