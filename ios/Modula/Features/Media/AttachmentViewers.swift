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
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if case .downloaded(let url) = download.state {
                    VideoPlayer(player: controller.player)
                        .onAppear {
                            controller.autoplayAllowed = false
                            controller.attach(url: url)
                            controller.play()
                        }
                        .onDisappear { controller.release() }
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
                            .buttonStyle(.borderedProminent).padding(.bottom, 32)
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
        .task(id: attachment.id) { download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads) }
        .onDisappear { download.cancel(attachment.id) }
    }
}

struct ModulaPDFViewer: View {
    let attachment: ModulaAttachment
    var onDismiss: () -> Void
    @State private var download = AttachmentDownloadModel()
    @State private var currentPage = 0
    @State private var pageCount = 0
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                switch download.state {
                case .downloaded(let url):
                    ZStack(alignment: .bottom) {
                        PDFKitView(url: url, currentPage: $currentPage, pageCount: $pageCount)
                            .accessibilityLabel(attachment.accessibilityLabel)
                        if pageCount > 0 {
                            HStack(spacing: ModulaSpacing.sm) {
                                Button("Previous page", systemImage: "chevron.left") { currentPage = max(0, currentPage - 1) }
                                    .labelStyle(.iconOnly).disabled(currentPage == 0)
                                Text("\(currentPage + 1) / \(pageCount)").font(.caption.monospacedDigit().weight(.semibold))
                                    .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
                                Button("Next page", systemImage: "chevron.right") { currentPage = min(pageCount - 1, currentPage + 1) }
                                    .labelStyle(.iconOnly).disabled(currentPage >= pageCount - 1)
                            }
                            .padding(.horizontal, ModulaSpacing.md).padding(.vertical, ModulaSpacing.xs)
                            .background(.regularMaterial, in: Capsule()).padding(.bottom, ModulaSpacing.sm)
                        }
                    }
                case .downloading, .notDownloaded:
                    ProgressView("Preparing PDF…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("PDF unavailable", systemImage: "doc.richtext")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            download.retry(attachment, manager: app.attachmentDownloads)
                        }
                        .buttonStyle(.borderedProminent)
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

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var pageCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage, pageCount: $pageCount) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .systemBackground
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            pageCount = view.document?.pageCount ?? 0
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
                        .buttonStyle(.borderedProminent)
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
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func release() {
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
                    .buttonStyle(.borderedProminent)
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
            if case .downloaded(let url) = state { audio.attach(url: url) }
        }
        .onDisappear { audio.release() }
    }

    private var playableURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return nil
    }
}
