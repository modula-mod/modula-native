import Foundation
import Observation

protocol AttachmentRemoteDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

struct URLSessionAttachmentDownloader: AttachmentRemoteDownloading {
    func download(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AttachmentDownloadError.invalidResponse
        }
        return temporaryURL
    }
}

enum AttachmentDownloadError: LocalizedError, Equatable {
    case unavailable
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: "This attachment is unavailable."
        case .invalidResponse: "The attachment could not be downloaded."
        case .cancelled: "The download was cancelled."
        }
    }
}

enum AttachmentDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading
    case downloaded(URL)
    case failed(String)
}

actor AttachmentDownloadManager {
    static let shared = AttachmentDownloadManager()

    private let store: PrivateFileStore
    private let downloader: any AttachmentRemoteDownloading
    private var inFlight: [AttachmentID: Task<URL, Error>] = [:]

    init(
        store: PrivateFileStore = PrivateFileStore(domain: .attachmentDownloads),
        downloader: any AttachmentRemoteDownloading = URLSessionAttachmentDownloader()
    ) {
        self.store = store
        self.downloader = downloader
    }

    func cachedURL(for attachment: ModulaAttachment) -> URL? {
        if let local = attachment.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        let filename = cacheFilename(for: attachment)
        return store.fileExists(filename: filename) ? store.url(filename: filename) : nil
    }

    func download(_ attachment: ModulaAttachment) async throws -> URL {
        if let cached = cachedURL(for: attachment) { return cached }
        guard let remoteURL = attachment.remoteURL else { throw AttachmentDownloadError.unavailable }
        if let existing = inFlight[attachment.id] { return try await existing.value }

        let store = store
        let downloader = downloader
        let filename = cacheFilename(for: attachment)
        let task = Task<URL, Error> {
            try Task.checkCancellation()
            let temporaryURL = try await downloader.download(from: remoteURL)
            try Task.checkCancellation()
            return try store.saveFile(at: temporaryURL, filename: filename)
        }
        inFlight[attachment.id] = task
        defer { inFlight[attachment.id] = nil }
        do {
            return try await task.value
        } catch is CancellationError {
            throw AttachmentDownloadError.cancelled
        }
    }

    func cancel(_ attachmentID: AttachmentID) {
        inFlight[attachmentID]?.cancel()
        inFlight[attachmentID] = nil
    }

    func remove(_ attachment: ModulaAttachment) throws {
        cancel(attachment.id)
        try store.remove(filename: cacheFilename(for: attachment))
    }

    func activeDownloadCount() -> Int { inFlight.count }

    private func cacheFilename(for attachment: ModulaAttachment) -> String {
        let ext = attachment.uniformType?.preferredFilenameExtension
            ?? attachment.remoteURL?.pathExtension.nilIfEmpty
            ?? "data"
        let safeID = attachment.id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return "\(safeID).\(ext)"
    }
}

@MainActor @Observable
final class AttachmentDownloadModel {
    private(set) var state: AttachmentDownloadState = .notDownloaded
    private var task: Task<Void, Never>?
    private let manager: AttachmentDownloadManager

    init(manager: AttachmentDownloadManager = .shared) {
        self.manager = manager
    }

    func prepare(_ attachment: ModulaAttachment, downloadsRemote: Bool) {
        task?.cancel()
        task = Task {
            if let local = await manager.cachedURL(for: attachment) {
                state = .downloaded(local)
                return
            }
            guard downloadsRemote else {
                state = .notDownloaded
                return
            }
            state = .downloading
            do {
                state = .downloaded(try await manager.download(attachment))
            } catch is CancellationError {
                state = .notDownloaded
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel(_ attachmentID: AttachmentID) {
        task?.cancel()
        task = nil
        Task { await manager.cancel(attachmentID) }
        state = .notDownloaded
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
