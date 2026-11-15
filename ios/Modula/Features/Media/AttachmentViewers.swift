import AVKit
import Observation
import PDFKit
import QuickLook
import SwiftUI

enum AttachmentViewerRoute: Equatable, Sendable {
    case image
    case video
    case pdf
    case document
    case audio
    case unsupported

    static func resolve(_ attachment: ModulaAttachment) -> Self {
        guard attachment.isAvailable else { return .unsupported }
        switch attachment.kind {
        case .image: return AttachmentViewerRoute.image
        case .video: return AttachmentViewerRoute.video
        case .pdf: return AttachmentViewerRoute.pdf
        case .document: return AttachmentViewerRoute.document
        case .audio: return AttachmentViewerRoute.audio
        case .unknown: return AttachmentViewerRoute.unsupported
        }
    }
}

struct AttachmentViewerRouter: View {
    let attachment: ModulaAttachment
    var imageGallery: [ModulaAttachment] = []
    var onDismiss: () -> Void

    var body: some View {
        switch AttachmentViewerRoute.resolve(attachment) {
        case .image:
            let images = imageGallery.filter { $0.kind == .image && $0.isAvailable }
            let gallery = images.contains(where: { $0.id == attachment.id }) ? images : [attachment]
            ModulaMediaViewer(
                items: gallery.map {
                    ModulaMediaViewerItem(
                        id: $0.id,
                        title: $0.displayName,
                        source: ($0.playableURL ?? $0.bestPreviewURL).map(ModulaMediaViewerSource.remote),
                        accessibilityDescription: $0.accessibilityLabel
                    )
                },
                initialID: attachment.id,
                onDismiss: onDismiss
            )
        case .video:
            ModulaVideoViewer(attachment: attachment, onDismiss: onDismiss)
        case .pdf:
            ModulaPDFViewer(attachment: attachment, onDismiss: onDismiss)
        case .document:
            ModulaDocumentPreview(attachment: attachment, onDismiss: onDismiss)
        case .audio:
            ModulaAudioViewer(attachment: attachment, onDismiss: onDismiss)
                .modulaPullDownToDismiss(onDismiss)
        case .unsupported:
            NavigationStack {
                ContentUnavailableView(
                    "Attachment unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("This attachment has no supported local or remote content.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) }
                }
            }
        }
    }
}

struct ModulaVideoViewer: View {
    let attachment: ModulaAttachment
    var onDismiss: () -> Void
    @State private var controller = ModulaVideoPlaybackController()
    @State private var download = AttachmentDownloadModel()
    @State private var chromeHidden = false
    @State private var stageWidth: CGFloat = 0
    @AppStorage("video.viewer.loop") private var loops = false
    @AppStorage("video.viewer.rate") private var savedRate = 1.0
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if case .downloaded(let url) = download.state {
                    // Pooled AVPlayerLayer (not AVKit's VideoPlayer) so ModulaPiP owns PiP: closing the
                    // viewer while in PiP keeps the video playing until PiP ends.
                    ZStack {
                        if let player = controller.player {
                            ModulaPlayerLayerView(player: player, autoPiP: !controller.isMuted && controller.state == .playing)
                                .ignoresSafeArea()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
                    // Double-tap the left/right third: back/forward 10 s (t176u).
                    .onTapGesture(count: 2) { location in
                        guard stageWidth > 0 else { return }
                        let third = stageWidth / 3
                        if location.x < third { controller.skip(by: -10) }
                        else if location.x > third * 2 { controller.skip(by: 10) }
                        else { controller.toggle(); return }
                        HapticEngine.shared.play(.selection)
                    }
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { chromeHidden.toggle() }
                    }
                    .overlay(alignment: .bottom) {
                        if !chromeHidden { ModulaFullscreenVideoControls(controller: controller, title: attachment.displayName, onDocked: onDismiss) }
                    }
                    .onAppear {
                        controller.autoplayAllowed = false
                        controller.resumesPosition = true
                        controller.attach(url: url)
                        // The viewer remembers the last speed you picked.
                        if savedRate != 1 { controller.setRate(Float(savedRate)) }
                        controller.play()
                    }
                    .onChange(of: controller.rate) { _, rate in savedRate = Double(rate) }
                    // Loop (toggle in the controls): restart at the end instead of pausing.
                    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
                        guard loops, let item = note.object as? AVPlayerItem, item === controller.player?.currentItem else { return }
                        controller.seek(to: 0)
                        controller.play()
                    }
                    // Hardware keyboard: space play/pause, ←/→ 10 s, M mute.
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(.space) { controller.toggle(); return .handled }
                    .onKeyPress(.leftArrow) { controller.skip(by: -10); return .handled }
                    .onKeyPress(.rightArrow) { controller.skip(by: 10); return .handled }
                    .onKeyPress(characters: CharacterSet(charactersIn: "mM"), phases: .down) { _ in controller.toggleMute(); return .handled }
                    // L loop, S speed, J/K ±5 s.
                    .onKeyPress(characters: CharacterSet(charactersIn: "lL"), phases: .down) { _ in loops.toggle(); return .handled }
                    .onKeyPress(characters: CharacterSet(charactersIn: "sS"), phases: .down) { _ in _ = controller.cycleRate(); return .handled }
                    .onKeyPress(characters: CharacterSet(charactersIn: "jJ"), phases: .down) { _ in controller.skip(by: -5); return .handled }
                    .onKeyPress(characters: CharacterSet(charactersIn: "kK"), phases: .down) { _ in controller.skip(by: 5); return .handled }
                    .accessibilityAction(named: "Toggle loop") { loops.toggle() }
                    .onDisappear { controller.release() }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(attachment.accessibilityLabel)
                    .accessibilityAction(named: controller.state == .playing ? "Pause" : "Play") {
                        controller.toggle()
                    }
                } else if case .failed(let message) = download.state {
                    ContentUnavailableView("Video unavailable", systemImage: "video.badge.exclamationmark", description: Text(message))
                        .foregroundStyle(.white)
                        .overlay(alignment: .bottom) {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                download.retry(attachment, manager: app.attachmentDownloads)
                            }
                            .buttonStyle(.modulaPrimary).padding(.bottom, 32)
                        }
                } else {
                    ProgressView("Preparing video…").tint(.white).foregroundStyle(.white)
                }
            }
            .navigationTitle(attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) }
            }
        }
        .modulaPullDownToDismiss(onDismiss)
        .task(id: attachment.id) { download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads) }
        .onDisappear { download.cancel(attachment.id) }
    }
}

struct ModulaPDFViewer: View {
    let attachment: ModulaAttachment
    var onDismiss: () -> Void
    @State private var download = AttachmentDownloadModel()
    @State private var startPage: Int?
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            switch download.state {
            case .downloaded(let url):
                ModulaPDFImmersiveReader(url: url, key: attachment.id, title: attachment.displayName, startPage: startPage, onDismiss: onDismiss)
            case .downloading, .notDownloaded:
                ZStack { Color.black.ignoresSafeArea(); ProgressView("Preparing PDF…").tint(.white).foregroundStyle(.white) }
            case .failed(let message):
                NavigationStack {
                    ContentUnavailableView {
                        Label("PDF unavailable", systemImage: "doc.richtext")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", systemImage: "arrow.clockwise") { download.retry(attachment, manager: app.attachmentDownloads) }
                            .buttonStyle(.modulaPrimary)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) } }
                }
            }
        }
        .task(id: attachment.id) {
            let page = PDFReaderStartPage.take(for: attachment.id)
            startPage = page > 0 ? page : nil
            download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads)
        }
        .onDisappear { download.cancel(attachment.id) }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var pageCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage, pageCount: $pageCount) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        // Horizontal page swipe (page view controller) with native pinch zoom.
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
        view.displaysPageBreaks = true
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.minScaleFactor = view.scaleFactorForSizeToFit
            view.maxScaleFactor = max(view.scaleFactorForSizeToFit * 5, 4)
            let count = view.document?.pageCount ?? 0
            DispatchQueue.main.async { pageCount = count }
        }
        guard let document = view.document, currentPage >= 0, currentPage < document.pageCount,
              let desired = document.page(at: currentPage), view.currentPage !== desired else { return }
        view.go(to: desired)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        @Binding var pageCount: Int

        init(currentPage: Binding<Int>, pageCount: Binding<Int>) {
            _currentPage = currentPage
            _pageCount = pageCount
            super.init()
        }

        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let document = view.document,
                  let page = view.currentPage else { return }
            currentPage = max(0, document.index(for: page))
            pageCount = document.pageCount
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

struct ModulaDocumentPreview: View {
    let attachment: ModulaAttachment
    var onDismiss: () -> Void
    @State private var download = AttachmentDownloadModel()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                switch download.state {
                case .downloaded(let url):
                    QuickLookController(url: url)
                case .downloading, .notDownloaded:
                    ProgressView("Preparing document…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Preview unavailable", systemImage: "doc")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            download.retry(attachment, manager: app.attachmentDownloads)
                        }
                        .buttonStyle(.modulaPrimary)
                    }
                }
            }
            .navigationTitle(attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) }
                if case .downloaded(let url) = download.state {
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
                }
            }
        }
        .task(id: attachment.id) { download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads) }
        .onDisappear { download.cancel(attachment.id) }
    }
}

private struct QuickLookController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

@MainActor @Observable
final class ModulaAudioPlayerState {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private var player: AVPlayer?
    private var observer: Any?

    func attach(url: URL) {
        guard (player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        release()
        player = AVPlayer(url: url)
        if let player {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self, let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
                Task { @MainActor in
                    self.progress = min(max(time.seconds / duration, 0), 1)
                }
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            proximity.stop()
        } else {
            // Settings → Audio → Voice playback speed applies to every audio player.
            player.defaultRate = ModulaPreferences.voicePlaybackSpeed
            player.play()
            player.rate = ModulaPreferences.voicePlaybackSpeed
            if ModulaPreferences.hapticOnPlay { HapticEngine.shared.play(.lightImpact) }
            if ModulaPreferences.raiseToListen { proximity.start() }
        }
        isPlaying.toggle()
    }

    @ObservationIgnored private let proximity = RaiseToListenRouter()

    func release() {
        proximity.stop()
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        isPlaying = false
        progress = 0
    }
}

struct ModulaAudioViewer: View {
    let attachment: ModulaAttachment
    var onDismiss: () -> Void
    @State private var audio = ModulaAudioPlayerState()
    @State private var download = AttachmentDownloadModel()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            VStack(spacing: ModulaSpacing.lg) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 112))
                    .foregroundStyle(ModulaColor.accent)
                Text(attachment.metadata.title ?? attachment.displayName).font(.title2.bold())
                if let creator = attachment.metadata.creator { Text(creator).foregroundStyle(.secondary) }
                ProgressView(value: audio.progress).tint(ModulaColor.accent)
                if case .failed(let message) = download.state {
                    ContentUnavailableView("Audio unavailable", systemImage: "waveform.badge.exclamationmark", description: Text(message))
                    Button("Retry", systemImage: "arrow.clockwise") { download.retry(attachment, manager: app.attachmentDownloads) }
                        .buttonStyle(.bordered)
                } else {
                    Button(audio.isPlaying ? "Pause" : "Play", systemImage: audio.isPlaying ? "pause.fill" : "play.fill") { audio.toggle() }
                    .buttonStyle(.modulaPrimary)
                    .tint(ModulaColor.accent)
                    .disabled(playableURL == nil)
                }
            }
            .padding(ModulaSpacing.lg)
            .navigationTitle("Audio")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) } }
        }
        .task(id: attachment.id) { download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads) }
        .onChange(of: download.state) { _, state in
            if case .downloaded(let url) = state {
                audio.attach(url: url)
                // Settings → Audio → Playback → "Autoplay previews".
                if ModulaPreferences.audioAutoplayPreviews, !audio.isPlaying { audio.toggle() }
            }
        }
        .onDisappear { audio.release() }
    }

    private var playableURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return nil
    }
}

/// Settings → Audio → Voice → "Raise to listen".
/// While audio plays, the proximity sensor is armed; holding the phone to your ear
/// moves playback to the earpiece (only when microphone access was already granted —
/// iOS requires the play-and-record session for the receiver, and Modula never asks
/// for the microphone just for this). Lowering the phone returns to the speaker.
@MainActor
final class RaiseToListenRouter {
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        UIDevice.current.isProximityMonitoringEnabled = true
        guard UIDevice.current.isProximityMonitoringEnabled else { return }
        token = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in Self.route(toEar: UIDevice.current.proximityState) }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        if UIDevice.current.isProximityMonitoringEnabled {
            UIDevice.current.isProximityMonitoringEnabled = false
            Self.route(toEar: false)
        }
    }

    static func route(toEar: Bool) {
        let session = AVAudioSession.sharedInstance()
        if toEar {
            guard AVAudioApplication.shared.recordPermission == .granted else { return }
            try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [])
            try? session.overrideOutputAudioPort(.none)
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true)
    }
}


/// Bottom transport for the full-screen video viewer: play/pause, scrub, time, speed, mute,
/// Picture in Picture and "Mini player" (docks and closes the viewer).
struct ModulaFullscreenVideoControls: View {
    let controller: ModulaVideoPlaybackController
    var title: String
    var onDocked: () -> Void
    @State private var scrubbing: Double?
    @AppStorage("video.viewer.loop") private var loops = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(clock((scrubbing ?? controller.progress) * controller.duration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                Slider(value: Binding(
                    get: { scrubbing ?? controller.progress },
                    set: { scrubbing = $0 }
                ), in: 0...1) { editing in
                    if !editing, let value = scrubbing { controller.seek(to: value); scrubbing = nil }
                }
                .tint(.white)
                .accessibilityLabel("Video position")
                Text("-" + clock(controller.duration * (1 - (scrubbing ?? controller.progress))))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 18) {
                Button { controller.toggle() } label: {
                    Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(controller.state == .playing ? "Pause" : "Play")
                Button { _ = controller.cycleRate() } label: {
                    Text(String(format: "%.2g×", controller.rate)).font(.subheadline.weight(.bold).monospacedDigit()).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Playback speed \(String(format: "%.2g", controller.rate))")
                Button { controller.toggleMute() } label: {
                    Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
                Button {
                    loops.toggle()
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: loops ? "repeat.circle.fill" : "repeat").frame(width: 44, height: 44)
                }
                .accessibilityLabel(loops ? "Loop on" : "Loop off")
                // AirPlay to a TV / speaker (system route picker).
                ModulaAirPlayButton()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
                Spacer()
                if let file = controller.currentURL, file.isFileURL {
                    ShareLink(item: file) {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Share video")
                }
                Button {
                    ModulaVideoDock.shared.dock(from: controller, title: title, aspect: aspect)
                    onDocked()
                } label: {
                    Image(systemName: "rectangle.inset.bottomright.filled").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Mini player")
                if ModulaPiP.isSupported {
                    Button { ModulaPiP.shared.start(controller.player) } label: {
                        Image(systemName: "pip.enter").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Picture in Picture")
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, tint: .black.opacity(0.3))
        .padding(.horizontal, 12).padding(.bottom, 12)
        .transition(.opacity)
    }

    private var aspect: CGFloat {
        guard let size = controller.player?.currentItem?.presentationSize, size.width > 0, size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds.rounded() : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}


/// System AirPlay route picker, white on the dark video chrome.
struct ModulaAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
