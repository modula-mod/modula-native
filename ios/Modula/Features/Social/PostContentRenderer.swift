import AVFoundation
import Observation
import PDFKit
import SwiftUI

enum PostPresentation: Sendable {
    case feed
    case detail
}

enum PostRendererKind: Equatable, Sendable {
    case image, gallery, video, pdf, document, audio, link

    static func resolve(_ block: PostContentBlock) -> Self {
        switch block {
        case .image: .image
        case .imageGallery: .gallery
        case .video: .video
        case .pdf: .pdf
        case .document: .document
        case .audio: .audio
        case .link: .link
        }
    }
}

@MainActor @Observable
final class FeedVideoCoordinator {
    private(set) var activeVideoID: AttachmentID?
    private var visibility: [AttachmentID: Double] = [:]
    let activationThreshold: Double

    init(activationThreshold: Double = 0.55) {
        self.activationThreshold = activationThreshold
    }

    func updateVisibility(id: AttachmentID, fraction: Double) {
        visibility[id] = min(max(fraction, 0), 1)
        activeVideoID = visibility
            .filter { $0.value >= activationThreshold }
            .max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    func remove(id: AttachmentID) {
        visibility[id] = nil
        if activeVideoID == id {
            activeVideoID = visibility.filter { $0.value >= activationThreshold }.max { $0.value < $1.value }?.key
        }
    }
}

struct PostCarouselState: Equatable, Sendable {
    private(set) var page = 0
    let count: Int

    init(count: Int, page: Int = 0) {
        self.count = max(0, count)
        self.page = min(max(page, 0), max(0, count - 1))
    }

    mutating func select(_ proposed: Int) {
        page = min(max(proposed, 0), max(0, count - 1))
    }
}

struct ModulaPostContentRenderer: View {
    let post: ModulaPost
    var presentation: PostPresentation = .feed
    var videoCoordinator: FeedVideoCoordinator?
    var onOpenAttachment: (ModulaAttachment) -> Void
    var onOpenLink: (URL) -> Void
    var onOpenModule: (SocialPostModule) -> Void
    /// Flush attachments into the parent card (no nested card chrome).
    var embeddedAttachments = false

    private var visibleBlocks: [PostContentBlock] {
        presentation == .detail
            ? post.content
            : Array(post.content.prefix(ModulaPostLayoutPolicy.resolve(post).feedAttachmentLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            ForEach(visibleBlocks) { block in
                blockView(block)
            }
            if presentation == .feed, post.content.count > visibleBlocks.count {
                Label("+\(post.content.count - visibleBlocks.count) attachments", systemImage: "paperclip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(post.content.count - visibleBlocks.count) more attachments")
            }
            if let module = post.context.module {
                PostModuleChip(module: module) { onOpenModule(module) }
            }
            metadata
        }
    }

    @ViewBuilder
    private func blockView(_ block: PostContentBlock) -> some View {
        if let attachment = block.attachment, attachment.resolvedRemoteState != .ready {
            AttachmentRemoteStateSurface(attachment: attachment)
        } else {
            switch block {
            case .image(let value):
                ModulaPostImage(attachment: value.attachment, immersive: true) { onOpenAttachment(value.attachment) }
            case .imageGallery(let value):
                ModulaPostImageGallery(attachments: value.attachments, onOpen: onOpenAttachment)
            case .video(let value):
                ModulaVideoSurface(attachment: value.attachment, coordinator: videoCoordinator) { onOpenAttachment(value.attachment) }
            case .pdf(let value):
                ModulaPDFSurface(attachment: value.attachment, onOpen: { onOpenAttachment(value.attachment) }, embedded: embeddedAttachments)
            case .document(let value):
                ModulaDocumentCard(attachment: value.attachment, onOpen: { onOpenAttachment(value.attachment) }, embedded: embeddedAttachments)
            case .audio(let value):
                ModulaAudioSurface(attachment: value.attachment, onExpand: { onOpenAttachment(value.attachment) }, embedded: embeddedAttachments)
            case .link(let value):
                ModulaLinkPreview(content: value, onOpen: onOpenLink, embedded: embeddedAttachments)
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        let chips = [
            post.context.audioTitle.map { ("music.note", $0) },
            post.context.location.map { ("location", $0) },
            post.context.collection.map { ("square.stack.3d.up", $0) },
            post.context.topic.map { ("number", $0) }
        ].compactMap { $0 }
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ModulaSpacing.xs) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        ModulaPostMetadataChip(systemImage: chip.0, title: chip.1)
                    }
                }
            }
        }
    }
}

private struct AttachmentRemoteStateSurface: View {
    let attachment: ModulaAttachment
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(attachment.resolvedRemoteState.isTerminalFailure ? Color.secondary : app.appearance.liveAccent)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(attachment.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !attachment.resolvedRemoteState.isTerminalFailure { ProgressView().controlSize(.small) }
        }
        .padding(ModulaSpacing.sm)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(attachment.displayName)")
    }

    private var title: String {
        switch attachment.resolvedRemoteState {
        case .created, .uploading, .uploaded: "Upload is finishing"
        case .processing: "Attachment is processing"
        case .failed: "Attachment failed"
        case .expired: "Attachment expired"
        case .rejected: "Attachment was rejected"
        case .ready: "Attachment ready"
        }
    }

    private var symbol: String {
        attachment.resolvedRemoteState.isTerminalFailure ? "exclamationmark.triangle" : "gearshape.2"
    }
}

struct ModulaPostImage: View {
    let attachment: ModulaAttachment
    var immersive = false
    var onOpen: () -> Void
    @State private var retryID = 0

    var body: some View {
        ModulaRemoteImage(
            url: attachment.bestPreviewURL ?? attachment.playableURL,
            cacheKey: "attachment:\(attachment.id):feed-image",
            maximumPixelSize: 2_000,
            retryID: retryID
        ) { phase in
            switch phase {
            case .success(let image): Image(uiImage: image).resizable().scaledToFit()
            case .failure: attachmentFailure
            case .loading: attachmentPlaceholder.overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: adaptiveMaximumHeight)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: immersive ? ModulaRadius.small : ModulaRadius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityLabel(attachment.accessibilityLabel)
        .accessibilityHint("Opens full-screen media viewer")
        .accessibilityIdentifier("post.attachment.\(attachment.id)")
    }

    private var adaptiveMaximumHeight: CGFloat {
        guard let dimensions = attachment.dimensions, dimensions.width > 0 else { return 360 }
        return dimensions.height / dimensions.width > 2.2 ? 440 : 520
    }

    private var attachmentPlaceholder: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(minHeight: 180)
    }

    private var attachmentFailure: some View {
        attachmentPlaceholder.overlay {
            VStack(spacing: 8) {
                Label("Couldn’t load photo", systemImage: "photo.badge.exclamationmark")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button("Retry", systemImage: "arrow.clockwise") { retryID += 1 }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct ModulaPostImageGallery: View {
    let attachments: [ModulaAttachment]
    var onOpen: (ModulaAttachment) -> Void
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                ForEach(Array(attachments.prefix(10).enumerated()), id: \.element.id) { index, attachment in
                    ModulaPostImage(attachment: attachment, immersive: true) { onOpen(attachment) }
                        .tag(index)
                        .accessibilityLabel("\(attachment.accessibilityLabel), image \(index + 1) of \(attachments.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 330)
            Text("\(page + 1) / \(attachments.count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.black.opacity(0.56), in: Capsule())
                .padding(ModulaSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image gallery")
        .accessibilityValue("Image \(page + 1) of \(attachments.count)")
    }
}

struct ModulaVideoSurface: View {
    let attachment: ModulaAttachment
    var coordinator: FeedVideoCoordinator?
    var onExpand: () -> Void
    var height: CGFloat? = 280
    var cornerRadius: CGFloat = ModulaRadius.small
    var allowsPlayback = true
    /// Extra top inset for the expand control when the surface sits under
    /// overlaid chrome (e.g. the Reels top bar).
    var controlsTopInset: CGFloat = 0
    /// Immersive feed card: no expand button (the rail has one), thin progress bar + time.
    var immersive = false
    /// Optional host-owned controller (Reels drives pause/speed/mute from its own gestures).
    var externalController: ModulaVideoPlaybackController? = nil
    @State private var ownController = ModulaVideoPlaybackController()
    private var controller: ModulaVideoPlaybackController { externalController ?? ownController }
    @State private var download = AttachmentDownloadModel()
    @State private var decodedPoster: UIImage?
    @State private var waitingForTap = false
    @Environment(AppEnvironment.self) private var app

    private var loadLabel: String {
        if let bytes = attachment.byteSize, bytes > 0 {
            return "Load video · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }
        return "Load video"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ModulaVideoPlayer(
                resource: MediaResource(
                    id: attachment.id,
                    kind: .video,
                    url: playableURL,
                    posterURL: attachment.bestPreviewURL,
                    altText: attachment.accessibilityDescription,
                    dimensions: attachment.dimensions.map { MediaDimensions(width: Int($0.width), height: Int($0.height)) },
                    duration: attachment.duration
                ),
                isActive: allowsPlayback && (coordinator?.activeVideoID == attachment.id || coordinator == nil),
                controller: controller,
                fallbackPoster: decodedPoster,
                showsChrome: !immersive
            )
            .frame(maxWidth: .infinity).frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            switch download.state {
            case .failed:
                VStack(spacing: 8) {
                    Label("Video couldn’t be prepared", systemImage: "video.badge.exclamationmark")
                    Button("Retry", systemImage: "arrow.clockwise") {
                        download.retry(attachment, manager: app.attachmentDownloads)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ModulaRadius.small))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .downloading:
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notDownloaded:
                if waitingForTap {
                    // Data saver / "Data saver" playback quality: nothing is fetched until asked.
                    Button {
                        waitingForTap = false
                        download.retry(attachment, manager: app.attachmentDownloads)
                    } label: {
                        Label(loadLabel, systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHint("Downloads this video. Data saver is on.")
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .downloaded:
                EmptyView()
            }

            if !immersive {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.48), in: Circle())
                }
                .accessibilityLabel("Open full-screen video")
                .padding(ModulaSpacing.xs)
                .padding(.top, controlsTopInset)
            }
        }
        .overlay {
            if immersive, controller.player != nil, controller.state == .paused {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .modulaGlass(in: Circle(), interactive: false)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if immersive, controller.player != nil {
                ImmersiveVideoProgress(controller: controller)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { reportVisibility(geometry.frame(in: .global)) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in reportVisibility(frame) }
            }
        }
        .onDisappear {
            coordinator?.remove(id: attachment.id)
            controller.release()
        }
        .task(id: attachment.id) {
            // Settings → Media → Video quality / Battery & Data → Data saver.
            let prefetch = ModulaPreferences.prefetchesVideo()
            waitingForTap = !prefetch
            download.prepare(attachment, downloadsRemote: prefetch, manager: app.attachmentDownloads)
        }
        .onChange(of: download.state) { _, state in
            guard case .downloaded(let url) = state, attachment.bestPreviewURL == nil else { return }
            generatePoster(from: url)
        }
    }

    private var playableURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return attachment.localFileURL
    }

    private func generatePoster(from url: URL) {
        Task {
            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1_400, height: 1_400)
                guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else { return nil }
                return UIImage(cgImage: cgImage)
            }.value
            decodedPoster = image
        }
    }

    private func reportVisibility(_ frame: CGRect) {
        guard frame.height > 0 else { return }
        let viewport = UIScreen.main.bounds
        let visible = frame.intersection(viewport)
        let fraction = visible.isNull ? 0 : Double(max(0, visible.height / frame.height))
        coordinator?.updateVisibility(id: attachment.id, fraction: fraction)
    }
}

struct ModulaPDFSurface: View {
    let attachment: ModulaAttachment
    var onOpen: () -> Void
    /// When true, sits flush inside a parent card (no second-card chrome).
    var embedded = false
    @Environment(AppEnvironment.self) private var app
    @State private var download = AttachmentDownloadModel()
    @State private var reader: PDFReaderLaunch?
    @State private var readingVersion = 0
    @Namespace private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var corner: CGFloat { embedded ? 14 : ModulaRadius.medium }

    private var fileURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return nil
    }

    private var failed: Bool {
        if case .failed = download.state { return true }
        return false
    }

    var body: some View {
        ModulaPDFInlineCarousel(
            attachment: attachment,
            fileURL: fileURL,
            failed: failed,
            height: embedded ? 400 : 420,
            onRetry: {
                Task {
                    try? await app.attachmentDownloads.remove(attachment)
                    download.retry(attachment, manager: app.attachmentDownloads)
                }
            },
            readingVersion: readingVersion,
            onOpen: { page in
                // Open our own immersive reader (zoom morph from the card); fall back to the host viewer.
                if let fileURL { reader = PDFReaderLaunch(url: fileURL, page: page) }
                else { PDFReaderStartPage.set(page, for: attachment.id); onOpen() }
            }
        )
        .background(Color.primary.opacity(embedded ? 0.03 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.primary.opacity(0.08))
            }
        }
        .matchedTransitionSource(id: attachment.id, in: zoomNamespace)
        .task(id: attachment.id) {
            download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads)
        }
        .onDisappear { if reader == nil { download.cancel(attachment.id) } }
        .fullScreenCover(item: $reader, onDismiss: { readingVersion &+= 1 }) { launch in
            let content = ModulaPDFImmersiveReader(url: launch.url, key: attachment.id, title: attachment.displayName, startPage: launch.page) { reader = nil }
            if reduceMotion {
                content
            } else {
                content.navigationTransition(.zoom(sourceID: attachment.id, in: zoomNamespace))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.accessibilityLabel)
    }
}

struct PDFReaderLaunch: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let page: Int
}

/// Hands the tapped carousel page to the full-screen reader (consumed once).
@MainActor
enum PDFReaderStartPage {
    private static var pages: [AttachmentID: Int] = [:]
    static func set(_ page: Int, for id: AttachmentID) { pages[id] = max(0, page) }
    static func take(for id: AttachmentID) -> Int { pages.removeValue(forKey: id) ?? 0 }
}

struct ModulaDocumentCard: View {
    let attachment: ModulaAttachment
    var onOpen: () -> Void
    var embedded = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ModulaSpacing.sm) {
                documentIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(documentDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
            }
            .padding(embedded ? 10 : ModulaSpacing.sm)
            .background(
                Color.primary.opacity(embedded ? 0.04 : 0.045),
                in: RoundedRectangle(cornerRadius: embedded ? 12 : ModulaRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.accessibilityLabel)
        .accessibilityHint("Downloads and opens a Quick Look preview")
    }

    private var documentDetail: String {
        [attachment.uniformType?.localizedDescription, attachment.byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "Document"
    }

    @ViewBuilder private var documentIcon: some View {
        if let previewURL = attachment.bestPreviewURL {
            ModulaRemoteImage(url: previewURL, cacheKey: "attachment:\(attachment.id):document-preview", maximumPixelSize: 320) { phase in
                if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: attachment.kind.defaultSystemImage).font(.title2).foregroundStyle(app.appearance.liveAccent) }
            }
            .frame(width: 48, height: 52).clipped()
            .background(app.appearance.liveAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
            .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.small))
        } else {
            Image(systemName: attachment.kind.defaultSystemImage)
                .font(.title2).foregroundStyle(app.appearance.liveAccent)
                .frame(width: 48, height: 52)
                .background(app.appearance.liveAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
        }
    }
}

struct ModulaAudioSurface: View {
    let attachment: ModulaAttachment
    var onExpand: () -> Void
    var embedded = false
    @State private var audio = ModulaAudioPlayerState()
    @State private var download = AttachmentDownloadModel()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            HStack(spacing: ModulaSpacing.sm) {
                Button {
                    if let url = playableURL { audio.attach(url: url); audio.toggle() }
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.bold()).foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(app.appearance.liveAccent, in: Circle())
                }
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                .disabled(playableURL == nil)
                VStack(alignment: .leading, spacing: 5) {
                    Text(attachment.metadata.title ?? attachment.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(attachment.metadata.creator ?? "Audio").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        ForEach(0..<22, id: \.self) { index in
                            Capsule().fill(index < Int(audio.progress * 22) ? app.appearance.liveAccent : Color.secondary.opacity(0.3))
                                .frame(width: 3, height: CGFloat(7 + ((index * 7) % 13)))
                        }
                    }
                    .accessibilityHidden(true)
                }
                Spacer()
                Button(action: onExpand) { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Open audio player")
            }
            if case .downloading = download.state {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 54)
            } else if case .failed = download.state {
                HStack {
                    Label("Audio unavailable", systemImage: "waveform.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Retry", systemImage: "arrow.clockwise") {
                        download.retry(attachment, manager: app.attachmentDownloads)
                    }
                    .labelStyle(.iconOnly)
                }
                .padding(.horizontal, ModulaSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }
        }
        .padding(embedded ? 10 : ModulaSpacing.sm)
        .background(
            Color.primary.opacity(embedded ? 0.04 : 0.045),
            in: RoundedRectangle(cornerRadius: embedded ? 12 : ModulaRadius.medium, style: .continuous)
        )
        .onDisappear { audio.release() }
        .task(id: attachment.id) {
            download.prepare(attachment, downloadsRemote: true, manager: app.attachmentDownloads)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.accessibilityLabel)
    }

    private var playableURL: URL? {
        if case .downloaded(let url) = download.state { return url }
        return attachment.localFileURL
    }
}

struct ModulaLinkPreview: View {
    let content: LinkContent
    var onOpen: (URL) -> Void
    var embedded = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            guard let url = content.destination, ["http", "https"].contains(url.scheme?.lowercased()) else { return }
            onOpen(url)
        } label: {
            HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                if let imageURL = content.imageURL {
                    ModulaRemoteImage(url: imageURL, cacheKey: "link:\(imageURL.absoluteString)", maximumPixelSize: 320) { phase in
                        if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
                    }
                    .frame(width: 76, height: 76).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.small))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.domain ?? content.destination?.host ?? "Link").font(.caption2.weight(.bold)).foregroundStyle(app.appearance.liveAccent)
                    if let title = content.title { Text(title).font(.subheadline.weight(.semibold)).lineLimit(2) }
                    if let description = content.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .padding(embedded ? 10 : ModulaSpacing.sm)
            .background(
                Color.primary.opacity(embedded ? 0.04 : 0.045),
                in: RoundedRectangle(cornerRadius: embedded ? 12 : ModulaRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.title ?? content.domain ?? "Link")
        .accessibilityHint("Opens in browser")
    }
}

struct ModulaPostMetadataChip: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
private final class ModulaThumbnailCache {
    static let shared = ModulaThumbnailCache()
    private let storage = NSCache<NSString, UIImage>()

    private init() { storage.countLimit = 80 }
    func image(for id: AttachmentID) -> UIImage? { storage.object(forKey: id as NSString) }
    func insert(_ image: UIImage, for id: AttachmentID) { storage.setObject(image, forKey: id as NSString) }
}

struct PostCanonicalContent: View {
    let source: SocialPost
    var presentation: PostPresentation = .feed
    var videoCoordinator: FeedVideoCoordinator?
    var onOpenAttachment: (@MainActor (ModulaAttachment) -> Void)?
    var onOpenModule: (@MainActor (SocialPostModule) -> Void)?
    var embeddedAttachments = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ModulaPostContentRenderer(
            post: ModulaPostMapper.map(source),
            presentation: presentation,
            videoCoordinator: videoCoordinator,
            onOpenAttachment: { onOpenAttachment?($0) },
            onOpenLink: { openURL($0) },
            onOpenModule: { onOpenModule?($0) },
            embeddedAttachments: embeddedAttachments
        )
    }
}
