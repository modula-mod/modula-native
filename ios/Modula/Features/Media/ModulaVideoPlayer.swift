import AVKit
import Observation
import SwiftUI
import UIKit

/// Shared playback surface for post video, story video, and reels.
/// Only the owner should keep a player attached; distant pages must call `release()`.
@MainActor @Observable
final class ModulaVideoPlaybackController {
    private(set) var state: MediaPlaybackState = .idle
    private(set) var player: AVPlayer?
    private(set) var progress: Double = 0
    /// Fraction of the item buffered ahead (0…1), published in ~2% steps.
    private(set) var buffered: Double = 0
    private(set) var duration: TimeInterval = 0
    /// Settings → Media → Video → "Start muted", then last in-session mute choice.
    private(set) var isMuted: Bool
    /// Playback rate (1 / 1.5 / 2). Persists for the lifetime of this controller.
    private(set) var rate: Float = 1
    var autoplayAllowed = true
    /// Full-screen viewer: reopen long videos where you left off (this device; last 40 videos).
    var resumesPosition = false
    private var timeObserver: Any?

    init() {
        if UserDefaults.standard.object(forKey: "modula.video.lastMuted") != nil {
            isMuted = UserDefaults.standard.bool(forKey: "modula.video.lastMuted")
        } else {
            isMuted = ModulaPreferences.videoStartsMuted
        }
    }

    func attach(url: URL) {
        guard player?.currentItem?.asset as? AVURLAsset == nil ||
                (player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        release()
        ModulaSignpost.event("VideoAttach", url.isFileURL ? "file" : "stream")
        // Speed: a pre-rolled item (Reels neighbours) and a recycled AVPlayer from the shared pool, so
        // swiping to the next reel doesn't pay for player + asset setup on the main thread.
        let item = ModulaPlayerPool.shared.takeItem(for: url)
        let next = ModulaPlayerPool.shared.borrow()
        next.replaceCurrentItem(with: item)
        // Local files start immediately; streams keep stall protection.
        next.automaticallyWaitsToMinimizeStalling = !url.isFileURL
        next.actionAtItemEnd = .pause
        next.isMuted = isMuted
        // Bug fix: assigning `rate` here *started* playback on attach (AVPlayer.rate > 0 == playing), so
        // pages that only attached (off-screen neighbours, autoplay disabled) played audio/decoded video
        // in the background. `defaultRate` is the rate `play()` will use.
        next.defaultRate = rate
        if resumesPosition, let seconds = ModulaPlaybackPositions.position(for: url) {
            next.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            ModulaToastCenter.shared.show("Resumed at \(ModulaPlaybackPositions.clock(seconds))", symbol: "play.circle")
        }
        player = next
        state = .preparing
        timeObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak next] time in
            guard let self, let next else { return }
            Task { @MainActor in
                let total = next.currentItem?.duration.seconds ?? 0
                let duration = total.isFinite ? max(0, total) : 0
                // Only publish real changes: duration is constant once known.
                if duration != self.duration { self.duration = duration }
                let progress = duration > 0 ? min(max(time.seconds / duration, 0), 1) : 0
                if progress != self.progress { self.progress = progress }
                if duration > 0, let range = next.currentItem?.loadedTimeRanges.last?.timeRangeValue {
                    let end = min(max((range.start.seconds + range.duration.seconds) / duration, 0), 1)
                    if abs(end - self.buffered) >= 0.02 || (end >= 0.999 && self.buffered < 0.999) { self.buffered = end }
                }
            }
        }
    }

    /// The URL actually loaded (downloaded file or stream), for handing off to the dock.
    var currentURL: URL? { (player?.currentItem?.asset as? AVURLAsset)?.url }
    var currentSeconds: Double {
        let t = player?.currentTime().seconds ?? 0
        return t.isFinite ? max(0, t) : 0
    }

    /// Seek to an absolute time then play (dock hand-off keeps the viewer's position).
    func start(at seconds: Double) {
        guard let player else { return }
        if seconds > 0.5 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity) { [weak self] _ in
                Task { @MainActor in self?.play() }
            }
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        // Sound on → a `.playback` session so audio survives the silent switch and PiP is possible.
        if !isMuted {
            ModulaPiP.activatePlaybackSession(mixing: false)
            // One sound-on video at a time: starting another pauses the mini player.
            let dock = ModulaVideoDock.shared.controller
            if dock !== self, dock.state == .playing { dock.pause() }
        }
        player.play()
        player.rate = rate
        state = .playing
    }

    func pause() {
        player?.pause()
        if state == .playing { state = .paused }
    }

    func toggle() {
        if state == .playing { pause() } else { play() }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        if !isMuted, state == .playing { ModulaPiP.activatePlaybackSession(mixing: false) }
        UserDefaults.standard.set(isMuted, forKey: "modula.video.lastMuted")
    }

    /// Seek to a normalised progress 0…1. Keeps play/pause state.
    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let target = CMTime(seconds: duration * clamped, preferredTimescale: 600)
        let wasPlaying = state == .playing
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress = clamped
                if wasPlaying { self.player?.play(); self.player?.rate = self.rate; self.state = .playing }
            }
        }
    }

    /// Relative seek in seconds (keyboard / accessibility skip).
    func skip(by seconds: Double) {
        guard duration > 0 else { return }
        seek(to: min(max((currentSeconds + seconds) / duration, 0), 1))
    }

    /// Cycle 1x → 1.5x → 2x → 1x. Applies immediately if playing.
    func cycleRate() -> Float {
        let next: Float
        switch rate {
        case ..<1.25: next = 1.5
        case ..<1.75: next = 2
        default: next = 1
        }
        rate = next
        if state == .playing { player?.rate = next }
        return next
    }

    func setRate(_ value: Float) {
        rate = value
        player?.defaultRate = value
        if state == .playing { player?.rate = value }
    }

    func release() {
        if resumesPosition, let url = currentURL {
            ModulaPlaybackPositions.record(currentSeconds, duration: duration, for: url)
        }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        // A player showing in Picture in Picture keeps playing after its cell scrolls away;
        // ModulaPiP recycles it once PiP stops.
        if let player {
            if ModulaPiP.shared.isActive(player) {
                ModulaPiP.shared.recycleWhenStopped(player)
            } else {
                ModulaPlayerPool.shared.recycle(player)
            }
        }
        player = nil
        state = .idle
        progress = 0
        duration = 0
        buffered = 0   // bug fix: the next video showed the previous one's buffer bar
    }
}

struct ModulaVideoPlayer: View {
    let resource: MediaResource
    var isActive: Bool
    var controller: ModulaVideoPlaybackController
    var fallbackPoster: UIImage? = nil
    var onToggle: (() -> Void)? = nil
    /// Built-in play glyph + progress capsule (immersive cards draw their own).
    var showsChrome = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            poster
            if let player = controller.player, isActive, resource.canPlayVideo {
                // Speed: a bare AVPlayerLayer instead of AVKit's VideoPlayer (no hidden transport
                // controls, gesture recognisers or Now Playing chrome per feed cell). The layer stays
                // transparent until the first frame is ready, so the poster shows instead of black.
                ModulaPlayerLayerView(player: player, autoPiP: !controller.isMuted && controller.state == .playing)
                    .allowsHitTesting(false)
                    .opacity(controller.state == .idle ? 0 : 1)
            }
            if showsChrome, controller.state == .paused || controller.state == .preparing || !isActive {
                Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.35), in: Circle())
                    .opacity(controller.state == .playing ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if showsChrome, controller.player != nil, isActive {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView(value: controller.progress)
                            .tint(.white)
                            .accessibilityLabel("Video progress")
                            .accessibilityValue("\(Int(controller.progress * 100)) percent")
                        Text(timeLabel)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                        Button {
                            controller.toggleMute()
                        } label: {
                            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel(controller.isMuted ? "Unmute video" : "Mute video")
                        Menu {
                            Button("Mini player", systemImage: "rectangle.inset.bottomright.filled") {
                                ModulaVideoDock.shared.dock(from: controller, title: resource.altText ?? "Video", aspect: resourceAspect)
                            }
                            if ModulaPiP.isSupported {
                                Button("Picture in Picture", systemImage: "pip.enter") { ModulaPiP.shared.start(controller.player) }
                            }
                        } label: {
                            Image(systemName: "pip.enter").frame(width: 36, height: 36)
                        }
                        .foregroundStyle(.white)
                        .accessibilityLabel("Keep watching")
                        .accessibilityHint("Mini player or Picture in Picture")
                    }
                    .padding(.horizontal, 10)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isActive, resource.canPlayVideo else { return }
            controller.toggle()
            if controller.state == .playing, ModulaPreferences.hapticOnPlay {
                HapticEngine.shared.play(.lightImpact)
            }
            onToggle?()
        }
        .onChange(of: isActive) { _, active in
            if active { activate() } else { controller.pause() }
        }
        .onChange(of: resource.url) { _, _ in
            if isActive { activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leave a sound-on video playing so iOS can start Picture in Picture automatically;
            // ModulaPiP pauses it if PiP didn't start shortly after backgrounding.
            if phase != .active, !ModulaPiP.shared.keepsAlive(controller.player) { controller.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .modulaPauseBackgroundVideo)) { _ in
            if !ModulaPiP.shared.isActive(controller.player) { controller.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            // Low Power Mode switched on mid-scroll: honour "Pause autoplay in Low Power Mode".
            if controller.state == .playing,
               !ModulaPreferences.allowsVideoAutoplay(systemReduceMotion: reduceMotion) {
                controller.pause()
            }
        }
        .onDisappear { if !ModulaPiP.shared.isActive(controller.player) { controller.pause() } }
        .onAppear { if isActive { activate() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityAction(named: controller.state == .playing ? "Pause" : "Play") {
            controller.toggle()
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let fallbackPoster {
            Image(uiImage: fallbackPoster).resizable().scaledToFill()
        } else if let posterURL = resource.posterURL ?? (resource.kind == .image ? resource.url : nil) {
            ModulaRemoteImage(url: posterURL, cacheKey: "media:\(resource.id):poster", maximumPixelSize: 1_600) { phase in
                switch phase {
                case .success(let image):
                    Image(uiImage: image).resizable().scaledToFill()
                default:
                    posterPlaceholder
                }
            }
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.black
            Image(systemName: "video").font(.largeTitle).foregroundStyle(.white.opacity(0.32))
        }
    }

    private func activate() {
        guard resource.canPlayVideo, let url = resource.url else { return }
        controller.attach(url: url)
        if controller.autoplayAllowed {
            // Reduce Motion, Settings → Battery & Data (Low Power / Data saver / extra
            // motion reduction) decide whether feed video starts on its own.
            if ModulaPreferences.allowsVideoAutoplay(systemReduceMotion: reduceMotion) {
                controller.play()
            } else {
                controller.pause()
            }
        }
    }

    private var resourceAspect: CGFloat {
        guard let d = resource.dimensions, d.width > 0, d.height > 0 else { return 16.0 / 9.0 }
        return CGFloat(d.width) / CGFloat(d.height)
    }

    private var accessibilityLabel: String {
        let duration: String
        if let value = resource.duration {
            duration = "Duration \(Int(value.rounded())) seconds"
        } else {
            duration = "Video"
        }
        return [resource.altText, duration].compactMap { $0 }.joined(separator: ", ")
    }

    private var timeLabel: String {
        let remaining = max(0, Int((controller.duration * (1 - controller.progress)).rounded()))
        return String(format: "-%d:%02d", remaining / 60, remaining % 60)
    }
}


/// Lightweight AVPlayerLayer host shared by feed, story and reel video.
struct ModulaPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Arm "start PiP automatically when the app goes to the background" for this layer.
    var autoPiP = false

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = gravity
        view.attach(player)
        view.setAutoPiP(autoPiP)
        return view
    }

    func updateUIView(_ view: PlayerLayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.attach(player) }
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
        view.setAutoPiP(autoPiP)
    }

    static func dismantleUIView(_ view: PlayerLayerUIView, coordinator: ()) {
        // In PiP: keep the layer (and its player) alive until PiP stops.
        if ModulaPiP.shared.isActive(view.playerLayer.player) {
            ModulaPiP.shared.retainUntilStopped(view)
            return
        }
        view.detach()
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var readyObservation: NSKeyValueObservation?
        private(set) var pip: AVPictureInPictureController?

        func setAutoPiP(_ armed: Bool) {
            guard let pip else { return }
            // Two layers can show one player (dock tile + expanded); the visible, most recently
            // updated one owns PiP so closing the other doesn't leave the player unregistered.
            if let player = playerLayer.player { ModulaPiP.shared.register(pip, for: player) }
            let want = armed && ModulaPiP.autoStartEnabled
            if pip.canStartPictureInPictureAutomaticallyFromInline != want {
                pip.canStartPictureInPictureAutomaticallyFromInline = want
            }
        }

        func attach(_ player: AVPlayer) {
            playerLayer.player = player
            if pip == nil, ModulaPiP.isSupported {
                let controller = AVPictureInPictureController(playerLayer: playerLayer)
                controller?.delegate = ModulaPiP.shared
                pip = controller
            }
            if let pip { ModulaPiP.shared.register(pip, for: player) }
            playerLayer.opacity = playerLayer.isReadyForDisplay ? 1 : 0
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                Task { @MainActor [weak self] in self?.applyReady(ready) }
            }
        }

        private func applyReady(_ ready: Bool) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            playerLayer.opacity = ready ? 1 : 0
            CATransaction.commit()
            if ready { ModulaSignpost.event("VideoFirstFrame") }
        }

        func detach() {
            readyObservation = nil
            if let player = playerLayer.player { ModulaPiP.shared.unregister(for: player, pip: pip) }
            playerLayer.player = nil
        }
    }
}


/// Recycles a few AVPlayers and pre-rolls the next/previous reel's item.
/// AVPlayer creation + first item setup is the visible cost when a reel page becomes active; with
/// the pool the active page reuses a warm player and (for neighbours) an item whose asset keys
/// are already loaded.
@MainActor
final class ModulaPlayerPool {
    static let shared = ModulaPlayerPool()
    private var idle: [AVPlayer] = []
    private var prepared: [URL: AVPlayerItem] = [:]
    private var preparedOrder: [URL] = []
    static let maxIdlePlayers = 3
    static let maxPreparedItems = 3

    private init() {}

    var idleCount: Int { idle.count }
    var preparedCount: Int { prepared.count }

    func borrow() -> AVPlayer {
        if let player = idle.popLast() { return player }
        return AVPlayer()
    }

    func recycle(_ player: AVPlayer) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        guard idle.count < Self.maxIdlePlayers, !idle.contains(where: { $0 === player }) else { return }
        idle.append(player)
    }

    /// Starts loading `url`'s asset so a later `takeItem(for:)` is ready to play.
    func prepare(_ url: URL) {
        guard prepared[url] == nil else { return }
        let item = Self.makeItem(url)
        prepared[url] = item
        preparedOrder.append(url)
        while preparedOrder.count > Self.maxPreparedItems {
            let evicted = preparedOrder.removeFirst()
            prepared[evicted] = nil
        }
        ModulaSignpost.event("VideoPrepare", url.isFileURL ? "file" : "stream")
    }

    func takeItem(for url: URL) -> AVPlayerItem {
        if let item = prepared.removeValue(forKey: url) {
            preparedOrder.removeAll { $0 == url }
            // An item can be attached to one player only; a used/failed one is rebuilt.
            if item.status != .failed { return item }
        }
        return Self.makeItem(url)
    }

    func drain() {
        idle.removeAll()
        prepared.removeAll()
        preparedOrder.removeAll()
    }

    private static func makeItem(_ url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [.isPlayable, .duration, .tracks])
        // Speed: start on a short buffer (remote streams) instead of AVFoundation's large default.
        item.preferredForwardBufferDuration = url.isFileURL ? 0 : 2.5
        return item
    }
}


extension Notification.Name {
    /// Backgrounded with a sound-on video but PiP didn't start: pause it.
    static let modulaPauseBackgroundVideo = Notification.Name("modula.video.pauseBackground")
}

/// Picture in Picture for the bare AVPlayerLayer surfaces (feed, reels, dock). The full-screen
/// viewer uses AVKit's `VideoPlayer`, which brings its own PiP button once the session is `.playback`.
/// Needs only the `audio` background mode, already in Info.plist; no entitlement.
@MainActor @Observable
final class ModulaPiP: NSObject {
    static let shared = ModulaPiP()
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    /// Settings key `modula.video.autoPiP` (default on): leaving the app during sound-on playback starts PiP.
    static var autoStartEnabled: Bool {
        UserDefaults.standard.object(forKey: "modula.video.autoPiP") as? Bool ?? true
    }

    private(set) var activePlayer: AVPlayer?
    @ObservationIgnored private var controllers: [ObjectIdentifier: AVPictureInPictureController] = [:]
    @ObservationIgnored private var retainedView: UIView?
    @ObservationIgnored private var recycleOnStop: AVPlayer?
    @ObservationIgnored private var backgroundToken: NSObjectProtocol?

    private override init() {
        super.init()
        backgroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_200))
                guard UIApplication.shared.applicationState == .background, ModulaPiP.shared.activePlayer == nil else { return }
                NotificationCenter.default.post(name: .modulaPauseBackgroundVideo, object: nil)
            }
        }
    }

    func isActive(_ player: AVPlayer?) -> Bool {
        guard let player, let activePlayer else { return false }
        return player === activePlayer
    }

    /// Don't pause on resign-active: PiP is showing, or iOS is about to start it automatically.
    func keepsAlive(_ player: AVPlayer?) -> Bool {
        guard let player else { return false }
        if isActive(player) { return true }
        return Self.isSupported && Self.autoStartEnabled && !player.isMuted && player.rate > 0
            && controllers[ObjectIdentifier(player)]?.canStartPictureInPictureAutomaticallyFromInline == true
    }

    func register(_ pip: AVPictureInPictureController, for player: AVPlayer) {
        controllers[ObjectIdentifier(player)] = pip
    }

    func unregister(for player: AVPlayer, pip: AVPictureInPictureController?) {
        let key = ObjectIdentifier(player)
        if let pip, controllers[key] !== pip { return }
        controllers[key] = nil
    }

    func start(_ player: AVPlayer?) {
        guard let player, let pip = controllers[ObjectIdentifier(player)] else {
            ModulaToastCenter.shared.show("Picture in Picture isn't available for this video yet.", symbol: "pip")
            return
        }
        Self.activatePlaybackSession(mixing: player.isMuted)
        if player.rate == 0 { player.play() }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            // Possible flips true a moment after the session/layer become ready.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if pip.isPictureInPicturePossible { pip.startPictureInPicture() }
            }
        }
    }

    func stop() {
        guard let activePlayer, let pip = controllers[ObjectIdentifier(activePlayer)] else { return }
        pip.stopPictureInPicture()
    }

    func retainUntilStopped(_ view: UIView) { retainedView = view }
    func recycleWhenStopped(_ player: AVPlayer) { recycleOnStop = player }

    /// `.playback` so sound plays with the silent switch on and PiP can start. Never replaces a
    /// call's `.playAndRecord` session.
    static func activatePlaybackSession(mixing: Bool) {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord else { return }
        let options: AVAudioSession.CategoryOptions = mixing ? [.mixWithOthers] : []
        if session.category != .playback || session.categoryOptions != options {
            try? session.setCategory(.playback, mode: .moviePlayback, options: options)
        }
        try? session.setActive(true)
    }

    fileprivate func didStart(_ pip: AVPictureInPictureController) {
        activePlayer = pip.playerLayer.player
        ModulaSignpost.event("PiPStart")
    }

    fileprivate func didStop(_ pip: AVPictureInPictureController) {
        let player = pip.playerLayer.player
        activePlayer = nil
        if let view = retainedView as? ModulaPlayerLayerView.PlayerLayerUIView, view.window == nil {
            view.detach()
        }
        retainedView = nil
        if let recycle = recycleOnStop, recycle === player {
            ModulaPlayerPool.shared.recycle(recycle)
        }
        recycleOnStop = nil
        ModulaSignpost.event("PiPStop")
    }
}

extension ModulaPiP: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        didStart(pictureInPictureController)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        didStop(pictureInPictureController)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        didStop(pictureInPictureController)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - Video dock (persistent mini player)

/// One mini player above every screen (hosted in RootView). Docking hands the source's URL and
/// position to the dock's own controller (players come from ModulaPlayerPool), so the source cell
/// can scroll away or be released while the dock keeps playing.
@MainActor @Observable
final class ModulaVideoDock {
    static let shared = ModulaVideoDock()

    struct Item: Equatable {
        let id = UUID()
        var url: URL
        var title: String
        /// width / height
        var aspect: CGFloat
        var route: AppRoute?
    }

    enum Corner: String, CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    private(set) var item: Item?
    var corner: Corner = Corner(rawValue: UserDefaults.standard.string(forKey: "video.dock.corner") ?? "") ?? .bottomTrailing {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "video.dock.corner") }
    }
    var expanded = false
    let controller = ModulaVideoPlaybackController()

    private init() {}

    func dock(from source: ModulaVideoPlaybackController, title: String, aspect: CGFloat, route: AppRoute? = nil) {
        guard let url = source.currentURL else { return }
        let seconds = source.currentSeconds
        source.pause()
        controller.attach(url: url)
        controller.start(at: seconds)
        item = Item(url: url, title: title, aspect: min(max(aspect, 0.5), 2.0), route: route)
        expanded = false
        HapticEngine.shared.play(.selection)
        ModulaSignpost.event("DockOpen")
    }

    func close() {
        if ModulaPiP.shared.isActive(controller.player) { ModulaPiP.shared.stop() }
        controller.release()
        item = nil
        expanded = false
        ModulaSignpost.event("DockClose")
    }
}

struct ModulaVideoDockHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var dismissing = false
    /// Dock → expanded: the cover zooms out of the tile (kept mounted, invisible, while expanded).
    @Namespace private var dockZoom
    private var dock: ModulaVideoDock { ModulaVideoDock.shared }

    var body: some View {
        GeometryReader { geometry in
            if let item = dock.item, let player = dock.controller.player {
                let size = tileSize(item)
                let origin = position(for: dock.corner, size: size, in: geometry)
                tile(item: item, player: player)
                    .modulaZoomSource(id: "dock", namespace: dockZoom)
                    .frame(width: size.width, height: size.height)
                    .position(x: origin.x + drag.width, y: origin.y + drag.height)
                    .opacity(dismissing || dock.expanded ? 0 : 1)
                    .allowsHitTesting(!dock.expanded)
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { drag = $0.translation }
                            .onEnded { value in finishDrag(value, size: size, origin: origin, in: geometry) }
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: dock.item)
        .fullScreenCover(isPresented: Binding(get: { dock.expanded }, set: { dock.expanded = $0 })) {
            ModulaVideoDockExpanded()
                .modulaZoomDestination(id: "dock", namespace: dockZoom, reduceMotion: ModulaEffectGate.reduceMotion(reduceMotion))
        }
    }

    private func tileSize(_ item: ModulaVideoDock.Item) -> CGSize {
        // Landscape: 176 wide. Portrait (reels): 200 tall.
        item.aspect >= 1
            ? CGSize(width: 176, height: 176 / item.aspect)
            : CGSize(width: 200 * item.aspect, height: 200)
    }

    private func position(for corner: ModulaVideoDock.Corner, size: CGSize, in geometry: GeometryProxy) -> CGPoint {
        let inset = geometry.safeAreaInsets
        let margin: CGFloat = 12
        let left = inset.leading + margin + size.width / 2
        let right = geometry.size.width - inset.trailing - margin - size.width / 2
        let top = inset.top + 56 + size.height / 2
        // Clear the floating tab bar.
        let bottom = geometry.size.height - inset.bottom - 76 - size.height / 2
        switch corner {
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: bottom)
        case .bottomTrailing: return CGPoint(x: right, y: bottom)
        }
    }

    private func finishDrag(_ value: DragGesture.Value, size: CGSize, origin: CGPoint, in geometry: GeometryProxy) {
        let projected = CGPoint(x: origin.x + value.predictedEndTranslation.width, y: origin.y + value.predictedEndTranslation.height)
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8)
        // Flung past a side edge: swipe away.
        if projected.x < -size.width * 0.1 || projected.x > geometry.size.width + size.width * 0.1 {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                drag.width = projected.x < 0 ? -geometry.size.width : geometry.size.width
                dismissing = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))
                dock.close()
                drag = .zero
                dismissing = false
            }
            HapticEngine.shared.play(.selection)
            return
        }
        let current = CGPoint(x: origin.x + value.translation.width + value.predictedEndTranslation.width * 0.25,
                              y: origin.y + value.translation.height + value.predictedEndTranslation.height * 0.25)
        let nearest = ModulaVideoDock.Corner.allCases.min { a, b in
            distance(position(for: a, size: size, in: geometry), current) < distance(position(for: b, size: size, in: geometry), current)
        } ?? .bottomTrailing
        withAnimation(spring) {
            dock.corner = nearest
            drag = .zero
        }
        HapticEngine.shared.play(.selection)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func tile(item: ModulaVideoDock.Item, player: AVPlayer) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            Color.black
            ModulaPlayerLayerView(player: player, gravity: .resizeAspectFill,
                                  autoPiP: !dock.controller.isMuted && dock.controller.state == .playing)
                .allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    Button { dock.close() } label: {
                        Image(systemName: "xmark").font(.caption.bold()).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), tint: .black.opacity(0.3))
                    .accessibilityLabel("Close mini player")
                }
                Spacer()
                HStack {
                    Button { dock.controller.toggle() } label: {
                        Image(systemName: dock.controller.state == .playing ? "pause.fill" : "play.fill")
                            .font(.caption.bold()).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), tint: .black.opacity(0.3))
                    .accessibilityLabel(dock.controller.state == .playing ? "Pause" : "Play")
                    Spacer()
                    Button { dock.controller.toggleMute() } label: {
                        Image(systemName: dock.controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption.bold()).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), tint: .black.opacity(0.3))
                    .accessibilityLabel(dock.controller.isMuted ? "Unmute" : "Mute")
                }
            }
            .foregroundStyle(.white)
            .padding(6)
            VStack {
                Spacer()
                GeometryReader { bar in
                    Capsule().fill(.white).frame(width: bar.size.width * dock.controller.progress, height: 2)
                }
                .frame(height: 2)
            }
            .allowsHitTesting(false)
        }
        .clipShape(shape)
        .padding(3)
        .modulaGlass(in: shape, specular: true)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .contentShape(shape)
        .onTapGesture {
            HapticEngine.shared.play(.navigation)
            dock.expanded = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mini player, \(item.title)")
        .accessibilityHint("Double tap to expand. Swipe off the side to close.")
        .accessibilityAction(named: "Close") { dock.close() }
        .accessibilityIdentifier("video.dock")
    }
}

/// Tap-to-expand view for the dock's player. Pull down or "Minimise" to return to the dock.
struct ModulaVideoDockExpanded: View {
    @Environment(AppEnvironment.self) private var app
    private var dock: ModulaVideoDock { ModulaVideoDock.shared }
    @State private var scrubbing: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = dock.controller.player {
                ModulaPlayerLayerView(player: player, autoPiP: !dock.controller.isMuted && dock.controller.state == .playing)
                    .ignoresSafeArea()
                    .onTapGesture { dock.controller.toggle() }
            }
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ModulaGlassIconButton(title: "Minimise", systemImage: "chevron.down", foreground: .white) {
                        dock.expanded = false
                    }
                    Text(dock.item?.title ?? "Video")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if ModulaPiP.isSupported {
                        ModulaGlassIconButton(title: "Picture in Picture", systemImage: "pip.enter", foreground: .white) {
                            ModulaPiP.shared.start(dock.controller.player)
                        }
                    }
                    ModulaGlassIconButton(title: "Close", systemImage: "xmark", foreground: .white) {
                        dock.close()
                    }
                }
                Spacer()
                if let route = dock.item?.route {
                    Button("Open", systemImage: "arrow.up.forward") {
                        dock.expanded = false
                        app.navigation.push(route)
                    }
                    .buttonStyle(.modulaSecondary)
                }
                HStack(spacing: 12) {
                    Button { dock.controller.toggle() } label: {
                        Image(systemName: dock.controller.state == .playing ? "pause.fill" : "play.fill").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dock.controller.state == .playing ? "Pause" : "Play")
                    Slider(value: Binding(
                        get: { scrubbing ?? dock.controller.progress },
                        set: { scrubbing = $0 }
                    ), in: 0...1) { editing in
                        if !editing, let value = scrubbing { dock.controller.seek(to: value); scrubbing = nil }
                    }
                    .tint(.white)
                    .accessibilityLabel("Video position")
                    Button { dock.controller.toggleMute() } label: {
                        Image(systemName: dock.controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dock.controller.isMuted ? "Unmute" : "Mute")
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .modulaGlass(in: Capsule(), tint: .black.opacity(0.25))
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .modulaPullDownToDismiss { dock.expanded = false }
        .statusBarHidden()
    }
}


/// Last playback position for long videos opened full screen (≥ 60 s; kept between 10 s and the
/// last 10 s). Local only.
enum ModulaPlaybackPositions {
    private static let key = "video.positions.v1"
    private static let maxEntries = 40

    static func position(for url: URL) -> Double? {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return all[url.absoluteString]
    }

    static func record(_ seconds: Double, duration: Double, for url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let id = url.absoluteString
        if duration >= 60, seconds >= 10, seconds < duration - 10 {
            all[id] = seconds
            if all.count > maxEntries, let drop = all.keys.first(where: { $0 != id }) { all[drop] = nil }
        } else {
            all[id] = nil
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
