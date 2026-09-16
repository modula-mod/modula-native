import CoreGraphics
import Foundation

enum MediaKind: String, Hashable, Sendable {
    case image
    case video
    case audio
    case unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "image", "photo", "jpeg", "jpg", "png", "webp", "gif": self = .image
        case "video", "mp4", "mov": self = .video
        case "audio", "music": self = .audio
        default: self = .unknown
        }
    }
}

struct MediaDimensions: Hashable, Sendable {
    var width: Int
    var height: Int

    var aspectRatio: CGFloat? {
        guard width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}

enum MediaPlaybackState: Hashable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case failed
}

struct MediaCacheKey: Hashable, Sendable {
    let kind: MediaKind
    let identifier: String
}

/// Shared media descriptor for profile, posts, stories, and reels.
/// Distinct DTO types should map into this instead of inventing parallel image models.
struct MediaResource: Hashable, Sendable, Identifiable {
    let id: String
    let kind: MediaKind
    let url: URL?
    let posterURL: URL?
    let altText: String?
    let dimensions: MediaDimensions?
    let duration: TimeInterval?
    let cacheKey: MediaCacheKey

    var canPlayVideo: Bool { kind == .video && url != nil }

    init(
        id: String,
        kind: MediaKind,
        url: URL?,
        posterURL: URL? = nil,
        altText: String? = nil,
        dimensions: MediaDimensions? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.posterURL = posterURL
        self.altText = altText
        self.dimensions = dimensions
        self.duration = duration
        self.cacheKey = MediaCacheKey(kind: kind, identifier: id)
    }
}

enum MediaPayloadDecoder {
    static func resource(from value: JSONValue, fallbackID: String) -> MediaResource? {
        let id = value["id"]?.string ?? fallbackID
        let url = (value["url"]?.string ?? value["src"]?.string).flatMap(URL.init(string:))
        let poster = (value["posterUrl"]?.string ?? value["poster"]?.string ?? value["thumbnailUrl"]?.string)
            .flatMap(URL.init(string:))
        let kind = MediaKind(parsing: value["kind"]?.string ?? value["type"]?.string)
        if url == nil && poster == nil && kind == .unknown { return nil }
        let width = value["width"]?.int ?? value["dimensions"]?["width"]?.int
        let height = value["height"]?.int ?? value["dimensions"]?["height"]?.int
        let dimensions: MediaDimensions?
        if let width, let height {
            dimensions = MediaDimensions(width: width, height: height)
        } else {
            dimensions = nil
        }
        let duration = value["duration"]?.number ?? value["durationMs"]?.number.map { $0 / 1000 }
        return MediaResource(
            id: id,
            kind: kind == .unknown && url != nil ? .image : kind,
            url: url,
            posterURL: poster,
            altText: emptyToNil(value["altText"]?.string ?? value["alt"]?.string),
            dimensions: dimensions,
            duration: duration
        )
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
