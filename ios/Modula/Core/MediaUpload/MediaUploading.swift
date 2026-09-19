import Foundation

protocol MediaUploading: Sendable {
    var supportsProgress: Bool { get }
    var supportsCancellation: Bool { get }
    var supportsBackground: Bool { get }

    func upload(
        _ media: PreparedMedia,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadedMedia
}

struct PreparedMedia: Sendable, Equatable {
    var id: String
    var kind: CreationMedia.Kind
    var data: Data
    var mimeType: String
    var filename: String
    var altText: String
}

struct UploadedMedia: Sendable, Equatable {
    var id: String
    var remoteID: String
    var url: URL?
    var altText: String
}

enum MediaUploadError: Error, Equatable {
    case unavailable
    case cancelled
    case failed
}

/// Production adapter until Greenfield upload is verified. Never reports fake progress.
struct DisabledMediaUploader: MediaUploading {
    var supportsProgress: Bool { false }
    var supportsCancellation: Bool { false }
    var supportsBackground: Bool { false }

    func upload(
        _ media: PreparedMedia,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadedMedia {
        _ = media
        _ = progress
        throw MediaUploadError.unavailable
    }
}

struct MockMediaUploader: MediaUploading {
    enum Behavior: Sendable {
        case success
        case failure
        case cancel
    }

    var behavior: Behavior = .success
    var supportsProgress: Bool { true }
    var supportsCancellation: Bool { true }
    var supportsBackground: Bool { false }

    func upload(
        _ media: PreparedMedia,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadedMedia {
        progress(0.25)
        try Task.checkCancellation()
        progress(0.6)
        switch behavior {
        case .success:
            progress(1)
            return UploadedMedia(id: media.id, remoteID: "remote-\(media.id)", url: nil, altText: media.altText)
        case .failure:
            throw MediaUploadError.failed
        case .cancel:
            throw MediaUploadError.cancelled
        }
    }
}
