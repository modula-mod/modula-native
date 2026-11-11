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
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        next.actionAtItemEnd = .pause
        next.isMuted = isMuted
        next.rate = rate
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

    func play() {
        guard let player else { return }
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
        if state == .playing { player?.rate = value }
    }

    func release() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
        state = .idle
        progress = 0
        duration = 0
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
                VideoPlayer(player: player)
                    .disabled(true)
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
            if phase != .active { controller.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            // Low Power Mode switched on mid-scroll: honour "Pause autoplay in Low Power Mode".
            if controller.state == .playing,
               !ModulaPreferences.allowsVideoAutoplay(systemReduceMotion: reduceMotion) {
                controller.pause()
            }
        }
        .onDisappear { controller.pause() }
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
