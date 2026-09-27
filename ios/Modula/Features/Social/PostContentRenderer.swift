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

    private var visibleBlocks: [PostContentBlock] {
        presentation == .detail ? post.content : Array(post.content.prefix(2))
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
        switch block {
        case .image(let value):
            ModulaPostImage(attachment: value.attachment, immersive: true) { onOpenAttachment(value.attachment) }
        case .imageGallery(let value):
            ModulaPostImageGallery(attachments: value.attachments, onOpen: onOpenAttachment)
        case .video(let value):
            ModulaVideoSurface(attachment: value.attachment, coordinator: videoCoordinator) { onOpenAttachment(value.attachment) }
        case .pdf(let value):
            ModulaPDFSurface(attachment: value.attachment) { onOpenAttachment(value.attachment) }
        case .document(let value):
            ModulaDocumentCard(attachment: value.attachment) { onOpenAttachment(value.attachment) }
        case .audio(let value):
            ModulaAudioSurface(attachment: value.attachment) { onOpenAttachment(value.attachment) }
        case .link(let value):
            ModulaLinkPreview(content: value, onOpen: onOpenLink)
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

struct ModulaPostImage: View {
    let attachment: ModulaAttachment
    var immersive = false
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            AsyncImage(url: attachment.playableURL ?? attachment.bestPreviewURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: attachmentFailure
                default: attachmentPlaceholder.overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: adaptiveMaximumHeight)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: immersive ? ModulaRadius.small : ModulaRadius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
    @State private var controller = ModulaVideoPlaybackController()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ModulaVideoPlayer(
                resource: MediaResource(
                    id: attachment.id,
                    kind: .video,
                    url: attachment.playableURL,
                    posterURL: attachment.bestPreviewURL,
                    altText: attachment.accessibilityDescription,
                    dimensions: attachment.dimensions.map { MediaDimensions(width: Int($0.width), height: Int($0.height)) },
                    duration: attachment.duration
                ),
                isActive: coordinator?.activeVideoID == attachment.id || coordinator == nil,
                controller: controller
            )
            .frame(maxWidth: .infinity).frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.small, style: .continuous))

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.48), in: Circle())
            }
            .accessibilityLabel("Open full-screen video")
            .padding(ModulaSpacing.xs)
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

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                PDFPreview(attachment: attachment)
                    .frame(maxWidth: .infinity).frame(height: 230)
                    .background(Color.primary.opacity(0.05))
                HStack(spacing: ModulaSpacing.sm) {
                    Image(systemName: "doc.richtext.fill").foregroundStyle(ModulaColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(documentMetadata).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(ModulaSpacing.sm)
            }
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: ModulaRadius.medium).stroke(Color.primary.opacity(0.08)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.accessibilityLabel)
        .accessibilityHint("Opens PDF viewer")
    }

    private var documentMetadata: String {
        [attachment.metadata.pageCount.map { "\($0) pages" }, attachment.byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "PDF document"
    }
}

private struct PDFPreview: View {
    let attachment: ModulaAttachment
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let previewURL = attachment.bestPreviewURL {
                AsyncImage(url: previewURL) { phase in
                    if case .success(let value) = phase { value.resizable().scaledToFit() }
                    else { placeholder }
                }
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else { placeholder }
        }
        .task(id: attachment.id) {
            if let cached = ModulaThumbnailCache.shared.image(for: attachment.id) {
                image = cached
                return
            }
            guard let local = attachment.localFileURL, let document = PDFDocument(url: local), let page = document.page(at: 0) else { return }
            let thumbnail = page.thumbnail(of: CGSize(width: 500, height: 620), for: .cropBox)
            ModulaThumbnailCache.shared.insert(thumbnail, for: attachment.id)
            image = thumbnail
        }
    }

    private var placeholder: some View {
        ZStack { Color.primary.opacity(0.04); Image(systemName: "doc.text.image").font(.largeTitle).foregroundStyle(.tertiary) }
    }
}

struct ModulaDocumentCard: View {
    let attachment: ModulaAttachment
    var onOpen: () -> Void

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
            .padding(ModulaSpacing.sm)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
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
            AsyncImage(url: previewURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Image(systemName: attachment.kind.defaultSystemImage).font(.title2).foregroundStyle(ModulaColor.accent) }
            }
            .frame(width: 48, height: 52).clipped()
            .background(ModulaColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
            .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.small))
        } else {
            Image(systemName: attachment.kind.defaultSystemImage)
                .font(.title2).foregroundStyle(ModulaColor.accent)
                .frame(width: 48, height: 52)
                .background(ModulaColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
        }
    }
}

struct ModulaAudioSurface: View {
    let attachment: ModulaAttachment
    var onExpand: () -> Void
    @State private var audio = ModulaAudioPlayerState()

    var body: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Button {
                if let url = attachment.playableURL { audio.attach(url: url); audio.toggle() }
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.bold()).foregroundStyle(.white).frame(width: 48, height: 48)
                    .background(ModulaColor.accent, in: Circle())
            }
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            VStack(alignment: .leading, spacing: 5) {
                Text(attachment.metadata.title ?? attachment.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(attachment.metadata.creator ?? "Audio").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(0..<22, id: \.self) { index in
                        Capsule().fill(index < Int(audio.progress * 22) ? ModulaColor.accent : Color.secondary.opacity(0.3))
                            .frame(width: 3, height: CGFloat(7 + ((index * 7) % 13)))
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer()
            Button(action: onExpand) { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("Open audio player")
        }
        .padding(ModulaSpacing.sm)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
        .onDisappear { audio.release() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.accessibilityLabel)
    }
}

struct ModulaLinkPreview: View {
    let content: LinkContent
    var onOpen: (URL) -> Void

    var body: some View {
        Button {
            guard let url = content.destination, ["http", "https"].contains(url.scheme?.lowercased()) else { return }
            onOpen(url)
        } label: {
            HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                if let imageURL = content.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
                    }
                    .frame(width: 76, height: 76).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: ModulaRadius.small))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.domain ?? content.destination?.host ?? "Link").font(.caption2.weight(.bold)).foregroundStyle(ModulaColor.accent)
                    if let title = content.title { Text(title).font(.subheadline.weight(.semibold)).lineLimit(2) }
                    if let description = content.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .padding(ModulaSpacing.sm)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ModulaPostContentRenderer(
            post: ModulaPostMapper.map(source),
            presentation: presentation,
            videoCoordinator: videoCoordinator,
            onOpenAttachment: { onOpenAttachment?($0) },
            onOpenLink: { openURL($0) },
            onOpenModule: { onOpenModule?($0) }
        )
    }
}
