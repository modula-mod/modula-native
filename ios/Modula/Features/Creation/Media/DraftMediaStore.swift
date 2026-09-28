import Foundation

/// App-private draft media. Never stores picker URLs or auth material.
struct DraftMediaStore: Sendable {
    private let fileStore: PrivateFileStore
    nonisolated(unsafe) private let fileManager: FileManager

    init(fileStore: PrivateFileStore = PrivateFileStore(domain: .draftMedia), fileManager: FileManager = .default) {
        self.fileStore = fileStore
        self.fileManager = fileManager
    }

    func importJPEG(_ data: Data, accountID: String, id: String = UUID().uuidString, width: Int?, height: Int?) throws -> CreationMedia {
        let filename = "\(sanitize(accountID))/\(id).jpg"
        try fileStore.saveData(data, filename: filename)
        return CreationMedia(
            id: id,
            kind: .image,
            filename: filename,
            altText: "",
            pixelWidth: width,
            pixelHeight: height,
            byteCount: data.count,
            duration: nil,
            sensitive: false,
            mimeType: "image/jpeg",
            originalFilename: "\(id).jpg",
            uploadState: .readyToUpload
        )
    }

    func importData(
        _ data: Data,
        accountID: String,
        id: String = UUID().uuidString,
        kind: CreationMedia.Kind,
        mimeType: String,
        originalFilename: String,
        width: Int? = nil,
        height: Int? = nil,
        duration: TimeInterval? = nil,
        pageCount: Int? = nil
    ) throws -> CreationMedia {
        let ext = URL(fileURLWithPath: originalFilename).pathExtension.lowercased()
        let suffix = ext.isEmpty ? "bin" : String(ext.prefix(12))
        let filename = "\(sanitize(accountID))/\(id).\(suffix)"
        try fileStore.saveData(data, filename: filename)
        return CreationMedia(
            id: id, kind: kind, filename: filename, altText: "", pixelWidth: width, pixelHeight: height,
            byteCount: data.count, duration: duration, sensitive: false, mimeType: mimeType,
            originalFilename: originalFilename, uploadState: .readyToUpload, pageCount: pageCount
        )
    }

    func importFile(
        at sourceURL: URL,
        accountID: String,
        id: String = UUID().uuidString,
        kind: CreationMedia.Kind,
        mimeType: String,
        originalFilename: String,
        width: Int? = nil,
        height: Int? = nil,
        duration: TimeInterval? = nil,
        pageCount: Int? = nil
    ) throws -> CreationMedia {
        let ext = sourceURL.pathExtension.lowercased()
        let suffix = ext.isEmpty ? "bin" : String(ext.prefix(12))
        let filename = "\(sanitize(accountID))/\(id).\(suffix)"
        let destination = try fileStore.saveFile(at: sourceURL, filename: filename)
        let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return CreationMedia(
            id: id, kind: kind, filename: filename, altText: "", pixelWidth: width, pixelHeight: height,
            byteCount: size, duration: duration, sensitive: false, mimeType: mimeType,
            originalFilename: originalFilename, uploadState: .readyToUpload, pageCount: pageCount
        )
    }

    func read(_ media: CreationMedia) throws -> Data? {
        try fileStore.loadData(filename: media.filename)
    }

    func fileURL(_ media: CreationMedia) -> URL {
        fileStore.url(filename: media.filename)
    }

    func remove(_ media: CreationMedia) {
        try? fileStore.remove(filename: media.filename)
    }

    func remove(ids: [String], from media: [CreationMedia]) {
        for item in media where ids.contains(item.id) {
            remove(item)
        }
    }

    func cleanupOrphans(referenced: Set<String>, accountID: String) {
        let folder = fileStore.directoryURL.appendingPathComponent(sanitize(accountID), isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let id = item.deletingPathExtension().lastPathComponent
            if !referenced.contains(id) {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    func byteCount(accountID: String? = nil) -> Int64 {
        if let accountID {
            return folderSize(fileStore.directoryURL.appendingPathComponent(sanitize(accountID), isDirectory: true))
        }
        return folderSize(fileStore.directoryURL)
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func sanitize(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = accountID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(filtered)
        return value.isEmpty ? "_unknown" : value
    }
}
