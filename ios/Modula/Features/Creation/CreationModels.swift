import Foundation

enum CreationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case post
    case photo
    case video
    case link
    case poll
    case carousel
    case audio
    case movie
    case story
    case reel

    init(_ route: ComposeRoute) {
        switch route {
        case .post: self = .post
        case .photo: self = .photo
        case .video: self = .video
        case .link: self = .link
        case .poll: self = .poll
        case .carousel: self = .carousel
        case .audio: self = .audio
        case .movie: self = .movie
        }
    }

    var composeRoute: ComposeRoute? {
        switch self {
        case .post: .post
        case .photo: .photo
        case .video: .video
        case .link: .link
        case .poll: .poll
        case .carousel: .carousel
        case .audio: .audio
        case .movie: .movie
        case .story, .reel: nil
        }
    }

    var title: String {
        switch self {
        case .post: "Post"
        case .photo: "Photo"
        case .video: "Video"
        case .link: "Link"
        case .poll: "Poll"
        case .carousel: "Carousel"
        case .audio: "Audio"
        case .movie: "Movie"
        case .story: "Story"
        case .reel: "Reel"
        }
    }

    var publishLabel: String {
        switch self {
        case .story: "Share"
        case .reel: "Post"
        default: "Post"
        }
    }
}

enum CreationState: String, Codable, Sendable, Hashable {
    case editing
    case saved
    case preparing
    case uploading
    case processing
    case publishing
    case published
    case failed
    case cancelled
    case discarded
}

enum AudienceSelection: String, Codable, Sendable, Hashable, CaseIterable {
    case everyone = "public"
    case followers
    case onlyMe = "private"

    var greenfieldValue: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .followers: "Followers"
        case .onlyMe: "Only Me"
        }
    }

    var explanation: String {
        switch self {
        case .everyone: "Anyone on Modula can see this post."
        case .followers: "People who follow you can see this post."
        case .onlyMe: "Only you can see this post."
        }
    }

    init(greenfield raw: String?) {
        switch (raw ?? "").lowercased() {
        case "followers": self = .followers
        case "private", "only-me", "only_me": self = .onlyMe
        default: self = .everyone
        }
    }
}

struct CreationMedia: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var kind: Kind
    var filename: String
    var altText: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int?
    var duration: TimeInterval?
    var sensitive: Bool
    var mimeType: String? = nil
    var originalFilename: String? = nil
    var checksum: String? = nil
    var remoteAttachmentID: String? = nil
    var uploadState: DraftAttachmentState? = nil
    var uploadProgress: Double? = nil
    var uploadError: String? = nil
    var pageCount: Int? = nil
    var uploadSessionID: String? = nil
    var pendingAttachmentID: String? = nil

    enum Kind: String, Codable, Sendable, Hashable {
        case image
        case video
        case audio
        case pdf
        case document
        case unknown
    }

    var hasAltText: Bool {
        !altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum DraftAttachmentState: String, Codable, Sendable, Hashable {
    case local, preparing, readyToUpload, uploading, processing, ready, failed, cancelled
}

/// Early UX mirror of Greenfield's authoritative attachment policy.
enum CreationAttachmentPolicy {
    private static let MiB = 1_024 * 1_024

    static func maximumBytes(for mimeType: String) -> Int? {
        switch mimeType.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) {
        case "image/jpeg", "image/png", "image/webp", "image/heic": 20 * MiB
        case "video/mp4", "video/quicktime": 100 * MiB
        case "audio/mpeg", "audio/mp4", "audio/wav": 50 * MiB
        case "application/pdf": 50 * MiB
        case "text/plain", "text/rtf", "application/rtf", "application/msword",
             "application/vnd.ms-powerpoint", "application/vnd.ms-excel",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
             "application/vnd.openxmlformats-officedocument.presentationml.presentation",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/zip": 25 * MiB
        default: nil
        }
    }

    static func accepts(mimeType: String, byteCount: Int) -> Bool {
        guard let maximum = maximumBytes(for: mimeType) else { return false }
        return byteCount > 0 && byteCount <= maximum
    }
}

struct LinkDraft: Codable, Equatable, Hashable, Sendable {
    var urlString: String
    var title: String?
    var description: String?
    var domain: String?
    var imageURLString: String?
    var previewFromServer: Bool

    var url: URL? { URL(string: urlString) }
}

struct PollDraft: Codable, Equatable, Hashable, Sendable {
    var question: String
    var options: [PollOptionDraft]
    var durationHours: Int
    var allowsMultiple: Bool

    struct PollOptionDraft: Identifiable, Codable, Equatable, Hashable, Sendable {
        var id: String
        var text: String
    }

    static let minimumOptions = 2

    static func blank(optionLimit: Int = 4) -> PollDraft {
        let count = max(minimumOptions, min(optionLimit, 4))
        return PollDraft(
            question: "",
            options: (0..<count).map { _ in .init(id: UUID().uuidString, text: "") },
            durationHours: 24,
            allowsMultiple: false
        )
    }
}

struct MentionDraft: Codable, Equatable, Hashable, Sendable {
    var handle: String
    var accountID: String?
    var displayName: String?
}

struct LocationAttachment: Codable, Equatable, Hashable, Sendable {
    var placeID: String
    var name: String
    var subtitle: String?
}

struct MediaAccessibilityMetadata: Codable, Equatable, Hashable, Sendable {
    var altTextByMediaID: [String: String]
    var contentWarning: String?
    var sensitive: Bool

    static let empty = MediaAccessibilityMetadata(altTextByMediaID: [:], contentWarning: nil, sensitive: false)
}

struct CreationDraft: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var accountID: String
    var kind: CreationKind
    var text: String
    var media: [CreationMedia]
    var link: LinkDraft?
    var poll: PollDraft?
    var audience: AudienceSelection
    var mentions: [MentionDraft]
    var topics: [String]
    var location: LocationAttachment?
    var accessibility: MediaAccessibilityMetadata
    var state: CreationState
    var lastEdited: Date
    var idempotencyKey: String
    var publishError: String?
    var originPath: String?

    static func fresh(
        kind: CreationKind,
        accountID: String,
        audience: AudienceSelection,
        originPath: String? = nil
    ) -> CreationDraft {
        CreationDraft(
            id: UUID().uuidString,
            accountID: accountID,
            kind: kind,
            text: "",
            media: [],
            link: nil,
            poll: kind == .poll ? PollDraft.blank(optionLimit: 4) : nil,
            audience: audience,
            mentions: [],
            topics: [],
            location: nil,
            accessibility: .empty,
            state: .editing,
            lastEdited: Date(),
            idempotencyKey: UUID().uuidString,
            publishError: nil,
            originPath: originPath
        )
    }

    /// Share Extension / pasteboard entry — architecture only in N4F (no extension target).
    static func fromShare(text: String?, url: URL?, imageIDs: [String], accountID: String) -> CreationDraft {
        var draft = CreationDraft.fresh(kind: url != nil ? .link : (imageIDs.isEmpty ? .post : .photo), accountID: accountID, audience: .everyone)
        draft.text = text ?? ""
        if let url {
            draft.link = LinkDraft(urlString: url.absoluteString, title: nil, description: nil, domain: url.host, imageURLString: nil, previewFromServer: false)
        }
        draft.media = imageIDs.map {
            CreationMedia(id: $0, kind: .image, filename: $0, altText: "", pixelWidth: nil, pixelHeight: nil, byteCount: nil, duration: nil, sensitive: false)
        }
        return draft
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasContent: Bool {
        !trimmedText.isEmpty
            || !media.isEmpty
            || !(link?.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(poll?.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var preview: String {
        if !trimmedText.isEmpty { return String(trimmedText.prefix(80)) }
        if let link, !link.urlString.isEmpty { return link.title ?? link.urlString }
        if !media.isEmpty { return media.count == 1 ? "Photo draft" : "Media draft" }
        if let poll, !poll.question.isEmpty { return poll.question }
        return "Empty draft"
    }

    var isPublishing: Bool {
        switch state {
        case .preparing, .uploading, .processing, .publishing: true
        default: false
        }
    }
}

enum CreationValidation: Equatable, Sendable {
    case empty
    case kindUnavailable(CreationKind)
    case unsupportedMedia
    case tooManyFiles(limit: Int)
    case invalidURL
    case pollTooFewOptions
    case pollMissingQuestion
    case missingAccount
    case offlinePublishDisabled

    var accessibilityHint: String {
        switch self {
        case .empty: "Write something to publish."
        case .kindUnavailable(let kind): "\(kind.title) publishing isn’t available yet."
        case .unsupportedMedia: "This media type can’t be published yet."
        case .tooManyFiles(let limit): "You can attach up to \(limit) items."
        case .invalidURL: "Enter a valid link."
        case .pollTooFewOptions: "Polls need at least two options."
        case .pollMissingQuestion: "Add a poll question."
        case .missingAccount: "Sign in to publish."
        case .offlinePublishDisabled: "Publishing needs a connection. Your draft is safe."
        }
    }
}

enum CreationValidator {
    static func problem(for draft: CreationDraft, capabilities: CreationCapabilities) -> CreationValidation? {
        if draft.accountID.isEmpty { return .missingAccount }
        if !capabilities.canPublish(draft.kind) { return .kindUnavailable(draft.kind) }
        if draft.kind == .link {
            guard let link = draft.link, let url = link.url, url.scheme == "https" || url.scheme == "http" else {
                return .invalidURL
            }
        }
        if draft.kind == .poll {
            let options = draft.poll?.options.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
            if draft.poll?.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return .pollMissingQuestion
            }
            if options.count < PollDraft.minimumOptions { return .pollTooFewOptions }
        }
        if !draft.media.isEmpty {
            if draft.media.contains(where: { $0.kind == .video }) && !capabilities.videoPost {
                return .unsupportedMedia
            }
            if draft.media.contains(where: { $0.kind == .audio }) && !capabilities.audioPost {
                return .unsupportedMedia
            }
            if draft.media.contains(where: { $0.kind == .image }) && !capabilities.photoPost && draft.kind != .story {
                return .unsupportedMedia
            }
            if draft.media.count > 1 && !capabilities.carouselPost {
                return .tooManyFiles(limit: 1)
            }
            if let limit = capabilities.maxMediaCount, draft.media.count > limit {
                return .tooManyFiles(limit: limit)
            }
        }
        if !draft.hasContent { return .empty }
        return nil
    }
}

enum CreationEntityParser {
    static func mentions(in text: String) -> [MentionDraft] {
        handles(in: text, prefix: "@").map { MentionDraft(handle: $0) }
    }

    static func topics(in text: String) -> [String] {
        handles(in: text, prefix: "#")
    }

    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range), let url = match.url else {
            return nil
        }
        return url
    }

    private static func handles(in text: String, prefix: Character) -> [String] {
        var result: [String] = []
        let tokens = text.split { $0.isWhitespace || $0.isNewline }
        for token in tokens {
            guard token.first == prefix else { continue }
            let value = token.dropFirst().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !value.isEmpty { result.append(String(value)) }
        }
        return result
    }
}

enum CreationPayloadEncoder {
    /// Fields documented for `POST /v1/posts`. No guessed keys.
    static func textPostBody(from draft: CreationDraft) -> JSONValue {
        .object([
            "text": .string(draft.trimmedText),
            "kind": .string("text"),
            "audience": .string(draft.audience.greenfieldValue),
            "idempotencyKey": .string(draft.idempotencyKey)
        ])
    }

    static func postBody(from draft: CreationDraft) -> JSONValue {
        var body: [String: JSONValue] = [
            "text": .string(draft.trimmedText),
            "audience": .string(draft.audience.greenfieldValue),
            "idempotencyKey": .string(draft.idempotencyKey)
        ]
        if !draft.media.isEmpty {
            body["content"] = .array(draft.media.enumerated().compactMap { _, item in
                guard let attachmentID = item.remoteAttachmentID else { return nil }
                var entry: [String: JSONValue] = [
                    "type": .string(item.kind.attachmentType),
                    "attachmentId": .string(attachmentID)
                ]
                // Greenfield rejects `caption: null` with 400 VALIDATION_FAILED
                // ("Invalid attachment caption"): the key must be a string or absent.
                let caption = item.altText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty { entry["caption"] = .string(String(caption.prefix(500))) }
                return .object(entry)
            })
        }
        return .object(body)
    }

    static func keys(in body: JSONValue) -> [String] {
        guard case .object(let object) = body else { return [] }
        return object.keys.sorted()
    }
}

private extension CreationMedia.Kind {
    var attachmentType: String {
        switch self {
        case .image: "image"
        case .video: "video"
        case .audio: "audio"
        case .pdf: "pdf"
        case .document, .unknown: "document"
        }
    }
}
