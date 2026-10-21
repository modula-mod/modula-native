import ARKit
import AVFoundation
import CoreImage
import Photos
import SceneKit
import Speech
import SwiftUI
import UIKit

// MARK: - Create Story v4 — video extras (all on device)

/// One recorded segment and the playback speed it should be exported at.
struct StoryClip: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL
    var seconds: Double
    var speed: Double
}

enum StoryClipSpeed: Double, CaseIterable, Identifiable, Sendable {
    case slowest = 0.3, slow = 0.5, normal = 1, fast = 2, fastest = 3
    var id: Double { rawValue }
    var title: String {
        switch self {
        case .slowest: "0.3×"
        case .slow: "0.5×"
        case .normal: "1×"
        case .fast: "2×"
        case .fastest: "3×"
        }
    }
}

enum StoryVideoError: LocalizedError {
    case empty, export
    var errorDescription: String? {
        switch self {
        case .empty: "No clips to join."
        case .export: "Couldn’t finish that video."
        }
    }
}

/// Joins clips into one movie, applying each clip's speed (slow-mo / fast) with `scaleTimeRange`.
enum StoryClipMerger {
    static func merge(_ clips: [StoryClip]) async throws -> URL {
        guard !clips.isEmpty else { throw StoryVideoError.empty }
        if clips.count == 1, clips[0].speed == 1 { return clips[0].url }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw StoryVideoError.export }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var transform: CGAffineTransform?
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            if transform == nil { transform = try await sourceVideo.load(.preferredTransform) }
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack?.insertTimeRange(range, of: sourceAudio, at: cursor)
            }
            let scaled = CMTimeMultiplyByFloat64(duration, multiplier: 1 / clip.speed)
            if clip.speed != 1 {
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: duration), toDuration: scaled)
            }
            cursor = CMTimeAdd(cursor, scaled)
        }
        if let transform { videoTrack.preferredTransform = transform }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw StoryVideoError.export }
        let out = FileManager.default.temporaryDirectory.appending(path: "story-merged-\(UUID().uuidString).mov")
        try await session.export(to: out, as: .mov)
        return out
    }
}

// MARK: Captions (on-device Speech)

struct StoryCaption: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
    var start: Double
    var end: Double
}

enum StoryCaptioner {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }

    static func transcribe(_ url: URL) async -> Result<[StoryCaption], StoryCaptionError> {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return .failure(.denied) }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else { return .failure(.unsupported) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let once = Once()
        return await withCheckedContinuation { cont in
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard once.claim() else { return }
                    cont.resume(returning: .success(chunks(result.bestTranscription.segments)))
                } else if error != nil {
                    guard once.claim() else { return }
                    cont.resume(returning: .failure(.noSpeech))
                }
            }
        }
    }

    /// Groups words into short, readable caption lines (≤4 words or ≤1.6 s).
    private static func chunks(_ segments: [SFTranscriptionSegment]) -> [StoryCaption] {
        var out: [StoryCaption] = []
        var words: [String] = []
        var start = 0.0, end = 0.0
        for seg in segments {
            if words.isEmpty { start = seg.timestamp }
            words.append(seg.substring)
            end = seg.timestamp + seg.duration
            if words.count >= 4 || end - start > 1.6 {
                out.append(StoryCaption(text: words.joined(separator: " "), start: start, end: end + 0.15))
                words = []
            }
        }
        if !words.isEmpty { out.append(StoryCaption(text: words.joined(separator: " "), start: start, end: end + 0.3)) }
        return out
    }
}

enum StoryCaptionError: Error, Sendable {
    case denied, unsupported, noSpeech
    var message: String {
        switch self {
        case .denied: "Allow Speech Recognition in Settings to add captions."
        case .unsupported: "On-device captions aren’t available for this language."
        case .noSpeech: "No speech found in this video."
        }
    }
}

struct StoryCaptionPill: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 320)
    }
}

// MARK: Text animations

enum StoryTextAnimation: String, CaseIterable, Sendable {
    case none, fade, pop, float, pulse
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .none: "textformat"
        case .fade: "circle.lefthalf.filled"
        case .pop: "sparkle"
        case .float: "arrow.up.and.down"
        case .pulse: "waveform.path"
        }
    }

    /// Opacity / scale / y-offset (points) at time `t` seconds — shared by preview and video export.
    func state(at t: Double) -> (alpha: Double, scale: Double, dy: Double) {
        switch self {
        case .none: return (1, 1, 0)
        case .fade:
            let cycle = t.truncatingRemainder(dividingBy: 3)
            return (min(cycle / 0.6, 1), 1, 0)
        case .pop:
            let cycle = t.truncatingRemainder(dividingBy: 3)
            let p = min(cycle / 0.35, 1)
            return (p, 0.4 + 0.6 * (1 - pow(1 - p, 3)) + (p < 1 ? 0 : 0), 0)
        case .float: return (1, 1, sin(t * 2.2) * 8)
        case .pulse: return (1, 1 + 0.07 * sin(t * 5), 0)
        }
    }
}

/// Loops the text animation in the editor (static under Reduce Motion / while baking).
struct StoryTextAnimationModifier: ViewModifier {
    var animation: StoryTextAnimation
    var enabled: Bool
    func body(content: Content) -> some View {
        if animation == .none || !enabled {
            content
        } else {
            TimelineView(.animation) { context in
                let s = animation.state(at: context.date.timeIntervalSinceReferenceDate)
                content
                    .opacity(s.alpha)
                    .scaleEffect(s.scale)
                    .offset(y: s.dy)
            }
        }
    }
}

// MARK: Looping player for the edit stage

struct StoryLoopingVideo: UIViewRepresentable {
    let url: URL
    var onTime: @MainActor @Sendable (Double) -> Void

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var observer: Any?
        var url: URL?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        configure(view)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.url != url { configure(view) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        if let observer = view.observer { view.player?.removeTimeObserver(observer) }
        view.player?.pause()
        view.observer = nil
    }

    private func configure(_ view: PlayerView) {
        if let observer = view.observer { view.player?.removeTimeObserver(observer) }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        view.looper = AVPlayerLooper(player: player, templateItem: item)
        view.player = player
        view.url = url
        view.playerLayer.player = player
        let onTime = self.onTime
        view.observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { time in
            MainActor.assumeIsolated { onTime(time.seconds) }
        }
        player.play()
    }
}

// MARK: Export with overlays + captions + animated text burned in

struct StoryAnimatedOverlay: @unchecked Sendable {
    let image: CGImage
    let animation: StoryTextAnimation
    /// Layer centre in canvas points.
    let center: CGPoint
}

struct StoryCaptionOverlay: @unchecked Sendable {
    let image: CGImage
    let start: Double
    let end: Double
}

enum StoryVideoExporter {
    /// `staticOverlay`, animated overlays and captions are rendered at canvas size; the video is aspect-filled into the canvas like the editor shows it.
    static func export(video url: URL, canvas: CGSize, staticOverlay: CGImage?, animated: [StoryAnimatedOverlay], captions: [StoryCaptionOverlay], captionCenterY: CGFloat) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let cw = canvas.width, ch = canvas.height
        let staticBox = staticOverlay.map { UncheckedBox($0) }
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let extent = source.extent
            // Map canvas points → video pixels (inverse of the editor's aspect-fill).
            let s = max(cw / max(extent.width, 1), ch / max(extent.height, 1))
            let k = 1 / s
            let ox = (extent.width - cw * k) / 2, oy = (extent.height - ch * k) / 2
            func place(_ cg: CGImage, extra: CGAffineTransform = .identity) -> CIImage {
                CIImage(cgImage: cg)
                    .transformed(by: extra)
                    .transformed(by: CGAffineTransform(scaleX: k * cw / CGFloat(cg.width), y: k * ch / CGFloat(cg.height)))
                    .transformed(by: CGAffineTransform(translationX: extent.minX + ox, y: extent.minY + oy))
            }
            var output = source
            if let box = staticBox { output = place(box.value).composited(over: output) }
            let t = request.compositionTime.seconds
            for item in animated {
                let st = item.animation.state(at: t)
                let px = item.center.x / cw * CGFloat(item.image.width)
                let py = (1 - item.center.y / ch) * CGFloat(item.image.height)
                let dy = -st.dy / ch * CGFloat(item.image.height)
                let tf = CGAffineTransform(translationX: -px, y: -py)
                    .concatenating(CGAffineTransform(scaleX: st.scale, y: st.scale))
                    .concatenating(CGAffineTransform(translationX: px, y: py + dy))
                let layer = place(item.image, extra: tf)
                    .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: st.alpha)])
                output = layer.composited(over: output)
            }
            for caption in captions where t >= caption.start && t <= caption.end {
                output = place(caption.image).composited(over: output)
            }
            request.finish(with: output.cropped(to: extent), context: nil)
        }
        _ = captionCenterY
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw StoryVideoError.export }
        session.videoComposition = composition
        let out = FileManager.default.temporaryDirectory.appending(path: "story-export-\(UUID().uuidString).mov")
        try await session.export(to: out, as: .mov)
        return out
    }

    static func saveToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}

private struct UncheckedBox<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }

// MARK: AR world stickers (ARKit world tracking)

@MainActor
final class StoryARController: ObservableObject {
    weak var view: ARSCNView?
    @Published var placed = 0
    var sticker = "✨"

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func snapshot() -> UIImage? { view?.snapshot() }

    func clear() {
        view?.scene.rootNode.childNodes.filter { $0.name == "sticker" }.forEach { $0.removeFromParentNode() }
        placed = 0
    }

    func place(at point: CGPoint) {
        guard let view,
              let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let hit = view.session.raycast(query).first else { return }
        let image = Self.render(sticker)
        let plane = SCNPlane(width: 0.14, height: 0.14)
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: plane)
        node.name = "sticker"
        node.simdTransform = hit.worldTransform
        node.simdPosition.y += 0.07
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
        view.scene.rootNode.addChildNode(node)
        placed += 1
    }

    private static func render(_ emoji: String) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { _ in
            (emoji as NSString).draw(in: CGRect(origin: CGPoint(x: 8, y: 16), size: size), withAttributes: [.font: UIFont.systemFont(ofSize: 210)])
        }
    }
}

struct StoryARView: UIViewRepresentable {
    @ObservedObject var controller: StoryARController

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = true
        controller.view = view
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        view.session.run(config)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    final class Coordinator: NSObject {
        let controller: StoryARController
        init(controller: StoryARController) { self.controller = controller }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            controller.place(at: gesture.location(in: view))
            HapticEngine.shared.play(.selection)
        }
    }
}
