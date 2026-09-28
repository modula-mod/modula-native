import Foundation

protocol MediaUploading: Sendable {
    var supportsProgress: Bool { get }
    var supportsCancellation: Bool { get }
    var supportsBackground: Bool { get }

    func upload(
        _ media: PreparedMedia,
        progress: @escaping @Sendable (Double) -> Void,
        sessionCreated: @escaping @Sendable (_ uploadID: String, _ attachmentID: String) -> Void
    ) async throws -> UploadedMedia
}

struct PreparedMedia: Sendable, Equatable {
    var id: String
    var kind: CreationMedia.Kind
    var data: Data?
    var fileURL: URL?
    var mimeType: String
    var filename: String
    var altText: String
    var byteCount: Int
    var checksum: String?
    var width: Int?
    var height: Int?
    var duration: TimeInterval?
    var pageCount: Int?
    var uploadSessionID: String?
    var pendingAttachmentID: String?

    init(id: String, kind: CreationMedia.Kind, data: Data, mimeType: String, filename: String, altText: String) {
        self.id = id; self.kind = kind; self.data = data; self.fileURL = nil; self.mimeType = mimeType
        self.filename = filename; self.altText = altText; self.byteCount = data.count; self.checksum = nil
        self.width = nil; self.height = nil; self.duration = nil; self.pageCount = nil
        self.uploadSessionID = nil; self.pendingAttachmentID = nil
    }

    init(id: String, kind: CreationMedia.Kind, fileURL: URL, mimeType: String, filename: String, altText: String,
         byteCount: Int, checksum: String?, width: Int?, height: Int?, duration: TimeInterval?, pageCount: Int?,
         uploadSessionID: String? = nil, pendingAttachmentID: String? = nil) {
        self.id = id; self.kind = kind; self.data = nil; self.fileURL = fileURL; self.mimeType = mimeType
        self.filename = filename; self.altText = altText; self.byteCount = byteCount; self.checksum = checksum
        self.width = width; self.height = height; self.duration = duration; self.pageCount = pageCount
        self.uploadSessionID = uploadSessionID; self.pendingAttachmentID = pendingAttachmentID
    }
}

struct UploadedMedia: Sendable, Equatable {
    var id: String
    var remoteID: String
    var url: URL?
    var altText: String
}

struct GreenfieldMediaUploader: MediaUploading {
    var client: GreenfieldClient
    var supportsProgress: Bool { true }
    var supportsCancellation: Bool { true }
    var supportsBackground: Bool { false }

    func upload(
        _ media: PreparedMedia,
        progress: @escaping @Sendable (Double) -> Void,
        sessionCreated: @escaping @Sendable (String, String) -> Void
    ) async throws -> UploadedMedia {
        let sourceURL: URL
        var temporaryURL: URL?
        if let fileURL = media.fileURL {
            sourceURL = fileURL
        } else if let data = media.data {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            sourceURL = url; temporaryURL = url
        } else {
            throw MediaUploadError.failed
        }
        defer { if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) } }
        var metadata: [String: JSONValue] = [:]
        if let width = media.width { metadata["width"] = .number(Double(width)) }
        if let height = media.height { metadata["height"] = .number(Double(height)) }
        if let duration = media.duration { metadata["duration"] = .number(duration) }
        if let pageCount = media.pageCount { metadata["pageCount"] = .number(Double(pageCount)) }
        func createSession() async throws -> (uploadID: String, attachmentID: String) {
            var request: [String: JSONValue] = [
                "filename": .string(media.filename), "mimeType": .string(media.mimeType),
                "size": .number(Double(media.byteCount)), "metadata": .object(metadata)
            ]
            if let checksum = media.checksum { request["checksum"] = .string(checksum) }
            let session = try await client.authenticatedJSON("POST", path: "/v1/attachments/uploads", body: .object(request))
            guard let createdUploadID = session["uploadId"]?.string,
                  let attachmentID = session["attachmentId"]?.string else { throw APIError.invalidResponse }
            sessionCreated(createdUploadID, attachmentID)
            return (createdUploadID, attachmentID)
        }

        let uploadID: String
        if let existingUploadID = media.uploadSessionID,
           let pendingAttachmentID = media.pendingAttachmentID {
            do {
                let value = try await client.authenticatedJSON("GET", path: "/v1/attachments/\(pendingAttachmentID)")
                let attachment = value["attachment"] ?? value
                switch attachment["status"]?.string {
                case "ready":
                    return UploadedMedia(
                        id: media.id, remoteID: pendingAttachmentID,
                        url: attachment["originalURL"]?.string.flatMap(URL.init(string:)), altText: media.altText
                    )
                case "created", "failed":
                    uploadID = existingUploadID
                default:
                    uploadID = try await createSession().uploadID
                }
            } catch APIError.rejected(let status, _) where status == 404 {
                uploadID = try await createSession().uploadID
            }
        } else {
            uploadID = try await createSession().uploadID
        }
        let response = try await client.authenticatedUpload(
            path: "/v1/attachments/uploads/\(uploadID)/content", fileURL: sourceURL, progress: progress
        )
        let attachment = response["attachment"] ?? response
        guard let remoteID = attachment["id"]?.string else { throw APIError.invalidResponse }
        return UploadedMedia(id: media.id, remoteID: remoteID,
                             url: attachment["originalURL"]?.string.flatMap(URL.init(string:)), altText: media.altText)
    }
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
        progress: @escaping @Sendable (Double) -> Void,
        sessionCreated: @escaping @Sendable (String, String) -> Void
    ) async throws -> UploadedMedia {
        _ = media
        _ = progress
        _ = sessionCreated
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
        progress: @escaping @Sendable (Double) -> Void,
        sessionCreated: @escaping @Sendable (String, String) -> Void
    ) async throws -> UploadedMedia {
        sessionCreated("upload-\(media.id)", "pending-\(media.id)")
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
