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
            sensitive: false
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
