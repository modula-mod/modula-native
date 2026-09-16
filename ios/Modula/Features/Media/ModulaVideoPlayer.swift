import AVKit
import Observation
import SwiftUI

/// Shared playback surface for post video, story video, and reels.
/// Only the owner should keep a player attached; distant pages must call `release()`.
@MainActor @Observable
final class ModulaVideoPlaybackController {
    private(set) var state: MediaPlaybackState = .idle
    private(set) var player: AVPlayer?
    var autoplayAllowed = true

    func attach(url: URL) {
        guard player?.currentItem?.asset as? AVURLAsset == nil ||
                (player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        release()
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        next.actionAtItemEnd = .pause
        player = next
        state = .preparing
    }

    func play() {
        guard let player else { return }
        player.play()
        state = .playing
    }

    func pause() {
        player?.pause()
        if state == .playing { state = .paused }
    }

    func toggle() {
        if state == .playing { pause() } else { play() }
    }

    func release() {
        player?.pause()
        player = nil
        state = .idle
    }
}

struct ModulaVideoPlayer: View {
    let resource: MediaResource
    var isActive: Bool
        var controller: ModulaVideoPlaybackController
    var onToggle: (() -> Void)? = nil

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
            if controller.state == .paused || controller.state == .preparing || !isActive {
                Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.35), in: Circle())
                    .opacity(controller.state == .playing ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isActive, resource.canPlayVideo else { return }
            controller.toggle()
            onToggle?()
        }
        .onChange(of: isActive) { _, active in
            if active { activate() } else { controller.pause() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.pause() }
        }
        .onDisappear { controller.pause() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityAction(named: controller.state == .playing ? "Pause" : "Play") {
            controller.toggle()
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL = resource.posterURL ?? (resource.kind == .image ? resource.url : nil) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.black
                }
            }
        } else {
            Color.black
        }
    }

    private func activate() {
        guard resource.canPlayVideo, let url = resource.url else { return }
        controller.attach(url: url)
        if controller.autoplayAllowed {
            if reduceMotion { controller.pause() } else { controller.play() }
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
}
