import CoreGraphics
import Foundation

typealias PostID = String

struct PostAuthor: Identifiable, Hashable, Sendable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: URL?
    var isVerified = false
    var status: String?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count > 1 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(displayName.prefix(2)).uppercased()
    }
}
struct PostContext: Hashable, Sendable {
    var feed: String?
    var location: String?
    var audience: String?
    var visibility: PostVisibility
    var audioTitle: String?
    var collection: String?
    var topic: String?
    var module: SocialPostModule?
}

struct ImageContent: Hashable, Sendable { let attachment: ModulaAttachment }
struct ImageGalleryContent: Hashable, Sendable { let attachments: [ModulaAttachment] }
struct VideoContent: Hashable, Sendable { let attachment: ModulaAttachment }
struct PDFContent: Hashable, Sendable { let attachment: ModulaAttachment }
struct DocumentContent: Hashable, Sendable { let attachment: ModulaAttachment }
struct AudioContent: Hashable, Sendable { let attachment: ModulaAttachment }
struct LinkContent: Hashable, Sendable {
    let destination: URL?
    let title: String?
    let description: String?
    let domain: String?
    let imageURL: URL?
    let faviconURL: URL?
}

enum PostContentBlock: Hashable, Sendable, Identifiable {
    case image(ImageContent)
    case imageGallery(ImageGalleryContent)
    case video(VideoContent)
    case pdf(PDFContent)
    case document(DocumentContent)
    case audio(AudioContent)
    case link(LinkContent)

    var id: String {
        switch self {
        case .image(let value): "image:\(value.attachment.id)"
        case .imageGallery(let value): "gallery:\(value.attachments.map(\.id).joined(separator: ","))"
        case .video(let value): "video:\(value.attachment.id)"
        case .pdf(let value): "pdf:\(value.attachment.id)"
        case .document(let value): "document:\(value.attachment.id)"
        case .audio(let value): "audio:\(value.attachment.id)"
        case .link(let value): "link:\(value.destination?.absoluteString ?? value.title ?? "unknown")"
        }
    }

    var attachment: ModulaAttachment? {
        switch self {
        case .image(let value): value.attachment
        case .video(let value): value.attachment
        case .pdf(let value): value.attachment
        case .document(let value): value.attachment
        case .audio(let value): value.attachment
        case .imageGallery, .link: nil
        }
    }

    var isMediaFirst: Bool {
        switch self {
        case .image, .imageGallery, .video: true
        case .pdf, .document, .audio, .link: false
        }
    }
}

/// A visual strategy for the canonical post model. These values never create a
/// second post domain; they only let the shared shell choose an appropriate rhythm.
enum PostPresentationStyle: String, Equatable, Sendable, CaseIterable {
    case conversational
    case editorial
    case immersiveImage
    case immersiveVideo
    case gallery
    case document
    case audio
    case mixed
}

struct ModulaPostLayoutPolicy: Equatable, Sendable {
    let style: PostPresentationStyle
    let prefersActionRail: Bool
    let feedAttachmentLimit: Int

    /// Short landscape surfaces cannot contain a five-action vertical rail.
    static func canOverlayActionRail(aspectRatio: Double?) -> Bool {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return false }
        return aspectRatio <= 1
    }

    static func resolve(_ post: ModulaPost) -> Self {
        guard post.content.count <= 1 else {
            return .init(style: .mixed, prefersActionRail: false, feedAttachmentLimit: 2)
        }
        guard let first = post.content.first else {
            return .init(style: .conversational, prefersActionRail: false, feedAttachmentLimit: 0)
        }
        switch first {
        case .image:
            return .init(style: .immersiveImage, prefersActionRail: true, feedAttachmentLimit: 1)
        case .imageGallery:
            return .init(style: .gallery, prefersActionRail: true, feedAttachmentLimit: 1)
        case .video:
            return .init(style: .immersiveVideo, prefersActionRail: true, feedAttachmentLimit: 1)
        case .pdf, .document, .link:
            return .init(style: .document, prefersActionRail: false, feedAttachmentLimit: 1)
        case .audio:
            return .init(style: .audio, prefersActionRail: false, feedAttachmentLimit: 1)
        }
    }
}

struct ModulaPost: Identifiable, Hashable, Sendable {
    let id: PostID
    let author: PostAuthor?
    let createdAt: Date
    let editedAt: Date?
    let body: String?
    let content: [PostContentBlock]
    let context: PostContext
    var engagement: PostEngagement

    var isMediaFirst: Bool { content.first?.isMediaFirst == true }
    var presentationStyle: PostPresentationStyle { ModulaPostLayoutPolicy.resolve(self).style }
    var hasAttachments: Bool { !content.isEmpty }
    var shareURL: URL { URL(string: "https://modula.digital/post/\(id)")! }
}

enum ModulaPostMapper {
    static func map(_ post: SocialPost) -> ModulaPost {
        let attachments = post.media.map(attachment)
        var blocks: [PostContentBlock] = []

        if attachments.count > 1, attachments.allSatisfy({ $0.kind == .image }) {
            blocks.append(.imageGallery(.init(attachments: Array(attachments.prefix(10)))))
        } else {
            blocks.append(contentsOf: attachments.map(block))
        }
        if let link = post.link {
            blocks.append(.link(.init(
                destination: link.url,
                title: link.title,
                description: link.description,
                domain: link.domain,
                imageURL: link.imageURL,
                faviconURL: nil
            )))
        }

        return ModulaPost(
            id: post.id,
            author: post.author.map {
                PostAuthor(id: $0.id, handle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL)
            },
            createdAt: post.createdAt,
            editedAt: post.editedAt,
            body: post.text,
            content: blocks,
            context: PostContext(
                feed: post.feed,
                location: attachments.compactMap(\.metadata.location).first,
                audience: post.audience,
                visibility: post.visibility,
                audioTitle: attachments.first(where: { $0.kind == .audio })?.metadata.title,
                collection: nil,
                topic: nil,
                module: post.module
            ),
            engagement: post.engagement
        )
    }

    static func attachment(_ media: SocialPostMedia) -> ModulaAttachment {
        let filename = media.filename ?? media.url?.lastPathComponent
        let kind = AttachmentKind.resolve(mimeType: media.mimeType, filename: filename, declaredKind: media.kind)
        let dimensions: CGSize? = {
            if let width = media.width, let height = media.height, width > 0, height > 0 {
                return CGSize(width: width, height: height)
            }
            guard let ratio = media.aspectRatio, ratio > 0 else { return nil }
            return CGSize(width: ratio * 1_000, height: 1_000)
        }()
        return ModulaAttachment(
            id: media.id,
            kind: kind,
            remoteURL: media.url,
            previewURL: media.previewURL,
            thumbnailURL: media.thumbnailURL,
            mimeType: media.mimeType,
            filename: filename,
            byteSize: media.byteSize,
            dimensions: dimensions,
            duration: media.duration,
            accessibilityDescription: media.altText,
            metadata: AttachmentMetadata(
                title: media.title,
                creator: media.creator,
                pageCount: media.pageCount,
                documentID: kind == .pdf || kind == .document ? media.id : nil
            ),
            remoteState: AttachmentRemoteState(parsing: media.status)
        )
    }

    static func block(_ attachment: ModulaAttachment) -> PostContentBlock {
        switch attachment.kind {
        case .image: .image(.init(attachment: attachment))
        case .video: .video(.init(attachment: attachment))
        case .pdf: .pdf(.init(attachment: attachment))
        case .document, .unknown: .document(.init(attachment: attachment))
        case .audio: .audio(.init(attachment: attachment))
        }
    }
}
