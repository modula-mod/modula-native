import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

typealias AttachmentID = String

enum AttachmentRemoteState: String, Codable, Hashable, Sendable {
    case created, uploading, uploaded, processing, ready, failed, expired, rejected

    init(parsing raw: String?) {
        self = raw.flatMap(Self.init(rawValue:)) ?? .ready
    }

    var isTerminalFailure: Bool {
        self == .failed || self == .expired || self == .rejected
    }
}

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
    let remoteState: AttachmentRemoteState?

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
        metadata: AttachmentMetadata = .empty,
        remoteState: AttachmentRemoteState? = nil
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
        self.remoteState = remoteState
    }

    var displayName: String {
        Self.clean(filename) ?? Self.clean(metadata.title) ?? kind.rawValue.capitalized
    }

    var bestPreviewURL: URL? { thumbnailURL ?? previewURL }
    var playableURL: URL? { localFileURL ?? remoteURL }
    var isAvailable: Bool { localFileURL != nil || remoteURL != nil || bestPreviewURL != nil }
    var resolvedRemoteState: AttachmentRemoteState { remoteState ?? .ready }
    var cacheIdentity: String { "\(id):\(kind.rawValue)" }

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

enum ModulaRemoteImagePhase {
    case loading
    case success(UIImage)
    case failure(String)
}

enum ModulaRemoteImageDecoder {
    nonisolated static func downsample(data: Data, maximumPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maximumPixelSize))
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Authenticated, downsampled image loading for Greenfield media. Cache identity is
/// supplied by the attachment/profile domain rather than a temporary access URL.
struct ModulaRemoteImage<Content: View>: View {
    let url: URL?
    let cacheKey: String
    var maximumPixelSize: CGFloat = 1_600
    var retryID = 0
    @ViewBuilder let content: (ModulaRemoteImagePhase) -> Content

    @Environment(AppEnvironment.self) private var app
    @State private var phase: ModulaRemoteImagePhase = .loading

    var body: some View {
        content(phase)
            .task(id: TaskIdentity(cacheKey: cacheKey, url: url, retryID: retryID)) {
                await load()
            }
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .failure("Media is unavailable.")
            return
        }
        if let cached = ModulaRemoteImageCache.shared.image(for: cacheKey) {
            phase = .success(cached)
            return
        }
        phase = .loading
        do {
            let client = app.client
            let data = try await ModulaRemoteImagePipeline.shared.data(for: cacheKey) {
                try await client.mediaData(from: url)
            }
            try Task.checkCancellation()
            let maximumPixelSize = maximumPixelSize
            guard let image = await Task.detached(priority: .utility, operation: {
                ModulaRemoteImageDecoder.downsample(data: data, maximumPixelSize: maximumPixelSize)
            }).value else {
                phase = .failure("The image could not be decoded.")
                return
            }
            ModulaRemoteImageCache.shared.insert(image, for: cacheKey)
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure("The image could not be loaded.")
        }
    }

    private struct TaskIdentity: Hashable {
        let cacheKey: String
        let url: URL?
        let retryID: Int
    }
}

private actor ModulaRemoteImagePipeline {
    static let shared = ModulaRemoteImagePipeline()
    private var inFlight: [String: Task<Data, Error>] = [:]

    func data(for key: String, fetch: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task { try await fetch() }
        inFlight[key] = task
        do {
            let data = try await task.value
            inFlight[key] = nil
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

@MainActor
private final class ModulaRemoteImageCache {
    static let shared = ModulaRemoteImageCache()
    private let storage = NSCache<NSString, UIImage>()

    private init() {
        storage.countLimit = 120
        storage.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(for key: String) -> UIImage? {
        storage.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        storage.setObject(image, forKey: key as NSString, cost: min(pixels * 4, Int.max))
    }
}
