import CoreGraphics
import Foundation
import UniformTypeIdentifiers

typealias AttachmentID = String

enum AttachmentKind: String, CaseIterable, Codable, Hashable, Sendable {
    case image
    case video
    case pdf
    case document
    case audio
    case unknown

    static func resolve(mimeType: String?, filename: String?, declaredKind: String? = nil) -> Self {
        let mime = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mime, !mime.isEmpty {
            if mime == "application/pdf" { return .pdf }
            if mime.hasPrefix("image/") { return .image }
            if mime.hasPrefix("video/") { return .video }
            if mime.hasPrefix("audio/") { return .audio }
            if documentMIMETypes.contains(mime) { return .document }
            // MIME is authoritative when supplied. Unknown MIME remains unknown rather than
            // being reclassified from an untrusted filename extension.
            return .unknown
        }

        switch declaredKind?.lowercased() {
        case "image", "photo", "media": return .image
        case "video", "movie": return .video
        case "pdf": return .pdf
        case "document", "file", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "rtf", "zip": return .document
        case "audio", "music": return .audio
        default: break
        }

        guard let ext = filename.flatMap({ URL(fileURLWithPath: $0).pathExtension.lowercased() }), !ext.isEmpty else {
            return .unknown
        }
        if ext == "pdf" { return .pdf }
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext) { return .image }
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        if ["m4a", "mp3", "wav", "aac", "aiff", "caf"].contains(ext) { return .audio }
        if ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md", "markdown", "rtf", "zip", "json"].contains(ext) { return .document }
        return .unknown
    }

    var defaultSystemImage: String {
        switch self {
        case .image: "photo"
        case .video: "video"
        case .pdf: "doc.richtext"
        case .document: "doc"
        case .audio: "waveform"
        case .unknown: "questionmark.square.dashed"
        }
    }

    private static let documentMIMETypes: Set<String> = [
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/rtf",
        "application/zip",
        "text/plain",
        "text/rtf",
        "text/markdown",
        "application/json"
    ]
}

struct AttachmentMetadata: Codable, Hashable, Sendable {
    var title: String?
    var creator: String?
    var pageCount: Int?
    var documentID: String?
    var location: String?
    var artworkURL: URL?
    var waveform: [Double]?
    var linkDescription: String?
    var domain: String?
    var faviconURL: URL?
    /// Development/catalog fallback only. Backend mapping never sets this field.
    var previewSystemImage: String?

    static let empty = AttachmentMetadata()
}

struct ModulaAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: AttachmentID
    let kind: AttachmentKind
    let remoteURL: URL?
    let previewURL: URL?
    let thumbnailURL: URL?
    let localFileURL: URL?
    let mimeType: String?
    let filename: String?
    let byteSize: Int64?
    let dimensions: CGSize?
    let duration: TimeInterval?
    let accessibilityDescription: String?
    let metadata: AttachmentMetadata

    init(
        id: AttachmentID,
        kind: AttachmentKind,
        remoteURL: URL?,
        previewURL: URL? = nil,
        thumbnailURL: URL? = nil,
        localFileURL: URL? = nil,
        mimeType: String? = nil,
        filename: String? = nil,
        byteSize: Int64? = nil,
        dimensions: CGSize? = nil,
        duration: TimeInterval? = nil,
        accessibilityDescription: String? = nil,
        metadata: AttachmentMetadata = .empty
    ) {
        self.id = id
        self.kind = kind
        self.remoteURL = remoteURL
        self.previewURL = previewURL
        self.thumbnailURL = thumbnailURL
        self.localFileURL = localFileURL
        self.mimeType = mimeType
        self.filename = filename
        self.byteSize = byteSize
        self.dimensions = dimensions.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        self.duration = duration.flatMap { $0 >= 0 ? $0 : nil }
        self.accessibilityDescription = Self.clean(accessibilityDescription)
        self.metadata = metadata
    }

    var displayName: String {
        Self.clean(filename) ?? Self.clean(metadata.title) ?? kind.rawValue.capitalized
    }

    var bestPreviewURL: URL? { thumbnailURL ?? previewURL }
    var playableURL: URL? { localFileURL ?? remoteURL }
    var isAvailable: Bool { localFileURL != nil || remoteURL != nil || bestPreviewURL != nil }

    var accessibilityLabel: String {
        var values: [String] = []
        if let accessibilityDescription { values.append(accessibilityDescription) }
        values.append(kind == .pdf ? "PDF document" : kind.rawValue.capitalized)
        values.append(displayName)
        if let pages = metadata.pageCount, pages > 0 { values.append("\(pages) pages") }
        if let byteSize, byteSize > 0 { values.append(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)) }
        if let duration, duration > 0 { values.append(Self.durationLabel(duration)) }
        return values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }.joined(separator: ", ")
    }

    var uniformType: UTType? {
        if let mimeType, let type = UTType(mimeType: mimeType) { return type }
        if let filename { return UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension) }
        return nil
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(240))
    }

    private static func durationLabel(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum AttachmentLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed(message: String)
    case retrying
    case offlineCached
    case offlineUnavailable
}
