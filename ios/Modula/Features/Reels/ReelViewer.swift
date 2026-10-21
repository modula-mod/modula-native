import SwiftUI
import UIKit

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
    @State private var feedTab: ReelFeedTab = .forYou

    var body: some View {
        Group {
            switch app.reels.loadState {
            case .loading where app.reels.items.isEmpty:
                ReelLoadingShimmer()
            case .failed(let message) where app.reels.items.isEmpty:
                ModulaErrorState(message: message) {
                    Task { await app.reels.refresh() }
                }
            case _ where app.reels.items.isEmpty:
                ModulaEmptyState(
                    title: "No Reels yet",
                    message: "When short videos land in your feed, they’ll show up here. Pull to refresh anytime.",
                    symbol: "play.rectangle.on.rectangle"
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
        .overlay(alignment: .top) {
            if app.reels.loadState == .refreshing {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                    .padding(8)
                    .modulaGlass(in: Circle(), interactive: false, tint: .black.opacity(0.3))
                    .padding(.top, topBarBottom + 6)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityLabel("Refreshing")
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.reels.loadState == .refreshing)
        .safeAreaInset(edge: .top) {
            // Floating glass chrome over a soft scrim instead of a solid band.
            HStack(spacing: 12) {
                ModulaGlassIconButton(title: "Back", systemImage: "chevron.left", foreground: .white) {
                    app.navigation.close()
                }
                ReelFeedTabs(tab: $feedTab)
                Spacer()
                Button {
                    HapticEngine.shared.play(.navigation)
                    app.navigation.open(.compose(.video))
                } label: {
                    Label("Create", systemImage: "video.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.modulaPress)
                .modulaGlass(in: Capsule(), tint: app.appearance.accent.color.opacity(0.45), specular: true)
                .accessibilityLabel("Post a video")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .background {
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .fullScreenCover(item: $expandedVideo) { attachment in
            AttachmentViewerRouter(attachment: attachment, onDismiss: { expandedVideo = nil })
        }
        .onChange(of: app.reels.activeID) { _, id in prefetchNeighbours(of: id) }
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
                    .modifier(ReelPageTransition(reduceMotion: reduceMotion))
                    .id(reel.id)
                }
            }
            .scrollTargetLayout()
        }
        .modulaSoftScrollEdge()
        // Pull past the top of the first reel to refresh; feedback is a small spinner, no text.
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y < -90 } action: { _, pulled in
            if pulled, app.reels.loadState != .refreshing { Task { await app.reels.refresh() } }
        }
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

    /// Warm the cache for the previous/next two reels so paging never lands on a spinner.
    private func prefetchNeighbours(of id: ReelID?) {
        guard let id, let index = app.reels.index(of: id), ModulaPreferences.prefetchesVideo() else { return }
        let manager = app.attachmentDownloads
        for offset in [1, -1, 2] {
            let i = index + offset
            guard app.reels.items.indices.contains(i), let attachment = app.reels.items[i].attachment else { continue }
            Task.detached(priority: .utility) { _ = try? await manager.download(attachment) }
        }
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
    @State private var heartBurst = 0
    @State private var heartPoint: CGPoint? = nil
    @State private var clearDisplay = false
    @State private var showsQuickMenu = false
    @State private var captionsOn = true
    @State private var edgeBoost = false
    @State private var playback = ModulaVideoPlaybackController()

    var body: some View {
        ZStack {
            poster
            // KEEP: module/video permission gate — do not remove or "fix".
            if let attachment = reel.attachment, app.reels.capabilities.videoPlayback {
                ModulaVideoSurface(attachment: attachment, coordinator: coordinator, onExpand: onExpand,
                                   height: nil, cornerRadius: 0, allowsPlayback: isActive,
                                   controlsTopInset: controlsTopInset, immersive: true,
                                   externalController: playback)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(false ? 0.72 : 1, anchor: .top)
                    .clipShape(RoundedRectangle(cornerRadius: false ? 18 : 0, style: .continuous))
            }
            if !clearDisplay {
                // Legibility scrims: top (tabs/Create), right edge (rail) and bottom (caption),
                // so overlays stay readable over busy video such as screen recordings.
                LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: controlsTopInset + 40)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 90)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.74),
                        .init(color: .black.opacity(0.18), location: 0.84),
                        .init(color: .black.opacity(0.55), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            DoubleTapHeartBurst(trigger: heartBurst, point: heartPoint)
            if !clearDisplay {
                HStack(alignment: .bottom, spacing: 0) {
                    ReelCaptionBlock(reel: reel)
                        .padding(.leading, 14)
                        .padding(.bottom, 56)
                    Spacer(minLength: 8)
                    ReelTikTokRail(
                        reel: reel,
                        post: resolved,
                        isPlaying: playback.state == .playing && isActive,
                        onComment: onComment,
                        onShare: {
                            app.navigation.presented = .universalShare(.post(
                                id: resolved.id,
                                authorName: resolved.author?.displayName,
                                excerpt: resolved.text,
                                hasMedia: true
                            ))
                        }
                    )
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
            if !clearDisplay, reel.attachment != nil {
                Button {
                    playback.toggleMute()
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .modulaGlass(in: Circle(), tint: .black.opacity(0.25))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isMuted ? "Unmute" : "Mute")
                .accessibilityIdentifier("reels.mute")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, controlsTopInset + 10)
                .padding(.trailing, 14)
            }
            if edgeBoost {
                Text("2×")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modulaGlass(in: Capsule(), interactive: false, tint: .black.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, controlsTopInset + 12)
                    .allowsHitTesting(false)
            }
            if showsQuickMenu {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { showsQuickMenu = false }
                ReelQuickMenu(
                    rate: playback.rate,
                    captionsOn: captionsOn,
                    clearDisplay: clearDisplay,
                    onRate: { rate in
                        playback.setRate(rate)
                        app.navigation.flash(String(format: "Speed %.2g×", rate), symbol: "gauge.with.needle")
                    },
                    onNotInterested: {
                        app.postActions.hideLocally(resolved)
                        app.navigation.flash("We'll show fewer like this", symbol: "eye.slash")
                    },
                    onSave: { Task { await app.postActions.toggleSave(resolved) } },
                    onToggleCaptions: { captionsOn.toggle() },
                    onToggleClear: { clearDisplay.toggle() },
                    onDismiss: { showsQuickMenu = false }
                )
            }
        }
        .contentShape(Rectangle())
        // Double tap = like with a heart at the finger; single tap = pause/resume.
        .gesture(
            SpatialTapGesture(count: 2).onEnded { event in
                guard ModulaPreferences.doubleTapToLike else { return }
                heartPoint = event.location
                let post = resolved
                if !post.liked { Task { await app.postActions.toggleLike(post) } }
                HapticEngine.shared.play(.lightImpact)
                heartBurst += 1
            }
            .exclusively(before: TapGesture().onEnded {
                guard reel.attachment != nil, !showsQuickMenu else { return }
                playback.toggle()
                HapticEngine.shared.play(.selection)
            })
        )
        .onLongPressGesture(minimumDuration: 0.45) {
            HapticEngine.shared.play(.contextOpen)
            showsQuickMenu = true
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Hold left/right edge for 2× speed flash (visual; playback rate via toast if controller not exposed here).
                    let w = UIScreen.main.bounds.width
                    let onEdge = value.startLocation.x < 28 || value.startLocation.x > w - 28
                    if onEdge, value.translation == .zero || abs(value.translation.width) < 8 {
                        if !edgeBoost {
                            edgeBoost = true
                            playback.setRate(2)
                            HapticEngine.shared.play(.selection)
                        }
                    }
                }
                .onEnded { _ in
                    if edgeBoost { playback.setRate(1) }
                    edgeBoost = false
                }
        )
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
        parts.append(String(localized: "\(resolved.likeCount) likes"))
        parts.append(String(localized: "\(resolved.replyCount) comments"))
        return parts.joined(separator: ", ")
    }
}

struct ReelOverlay: View {
    let reel: SocialPost
    var shareRoute: AppRoute
    var onComment: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var captionExpanded = false

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                creatorRow
                if let caption = reel.text, !caption.isEmpty {
                    captionView(caption)
                }
                commentPill
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
                },
                glass: true
            )
            .padding(.trailing, 10)
            .padding(.bottom, 36)
        }
    }

    private var creatorRow: some View {
        Button {
            if let route = reel.author?.routeID {
                app.navigation.push(.profile(route, .overview))
                HapticEngine.shared.play(.navigation)
            }
        } label: {
            HStack(spacing: 10) {
                ModulaAvatar(initials: reel.author?.initials ?? "?", url: reel.author?.avatarURL, size: 38)
                    .padding(2)
                    .background(
                        Circle().stroke(
                            AngularGradient(colors: [app.appearance.accent.color, .white.opacity(0.9), app.appearance.accent.color], center: .center),
                            lineWidth: 2
                        )
                    )
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(reel.author?.displayName ?? "Creator")
                            .font(.headline)
                            .lineLimit(1)
                        if reel.author?.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(app.appearance.accent.color)
                                .accessibilityLabel("Verified")
                        }
                    }
                    if let handle = reel.author?.handle, !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }
            .padding(.trailing, 12)
            .padding(4)
            .modulaGlass(in: Capsule(), interactive: false, tint: .black.opacity(0.18))
        }
        .buttonStyle(.modulaPress)
    }

    private func captionView(_ caption: String) -> some View {
        Button {
            withAnimation(ModulaEffectGate.reduceMotion(systemReduceMotion) ? nil : .spring(response: 0.36, dampingFraction: 0.86)) {
                captionExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(captionExpanded ? 10 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if caption.count > 90 {
                    Text(captionExpanded ? "less" : "more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            .frame(maxWidth: 300, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityHint(captionExpanded ? "Collapses the caption" : "Expands the caption")
    }

    /// Slim "Add a comment…" strip, matching media post cards.
    private var commentPill: some View {
        Button(action: onComment) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(reel.replyCount > 0 ? "View \(ModulaCountFormat.compact(reel.replyCount) ?? "\(reel.replyCount)") comments" : "Add a comment…")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.modulaPress)
        .accessibilityIdentifier("reels.comment.prompt")
    }
}

/// Neighbouring reels recede slightly while paging (static under Reduce Motion).
private struct ReelPageTransition: ViewModifier {
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        if ModulaEffectGate.reduceMotion(reduceMotion) {
            content
        } else {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                view
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .brightness(phase.isIdentity ? 0 : -0.18)
            }
        }
    }
}

struct DiscoverReelsShelf: View {
    let reels: [Reel]
    var onOpen: (Reel) -> Void
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reels")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(reels) { reel in
                        Button {
                            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "reel", key: reel.id), for: .reels(.reel(reel.id)))
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
                                    Image(systemName: "play.fill")
                                        .font(.title3)
                                        .frame(width: 38, height: 38)
                                        .modulaGlass(in: Circle(), interactive: false, tint: .black.opacity(0.15))
                                        .padding(.bottom, 8)
                                    Text(reel.creator.displayName)
                                        .font(.caption.weight(.semibold))
                                    if let caption = reel.caption {
                                        Text(caption).font(.caption2).lineLimit(2)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(10)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                            )
                            .modulaHeroSource("reel", key: reel.id)
                        }
                        .buttonStyle(.modulaPressTilt)
                        .modulaCarouselReveal()
                        .accessibilityLabel("Reel by \(reel.creator.displayName)")
                    }
                }
            }
        }
        .accessibilityIdentifier("discover.reels.shelf")
    }
}
