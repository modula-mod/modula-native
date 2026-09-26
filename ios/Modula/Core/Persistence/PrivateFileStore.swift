import Foundation

/// Application Support persistence with CompletenessUntilFirstUserAuthentication.
/// Prefer this over Documents for private drafts, command history, and local collections.
struct PrivateFileStore: Sendable {
    enum Domain: String, Sendable {
        case commands = "commands"
        case drafts = "drafts"
        case draftMedia = "draft-media"
        case collections = "collections"
        case share = "share"
        case spotlight = "spotlight"
        case nodusConversations = "nodus/conversations"
        case nodusKnowledge = "nodus/knowledge"
        case nodusMemory = "nodus/memory"
        case nodusLearning = "nodus/learning"
    }

    private let domain: Domain
    nonisolated(unsafe) private let fileManager: FileManager

    init(domain: Domain, fileManager: FileManager = .default) {
        self.domain = domain
        self.fileManager = fileManager
    }

    var directoryURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("digital.modula.app", isDirectory: true)
            .appendingPathComponent(domain.rawValue, isDirectory: true)
    }

    func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directoryURL
        try? url.setResourceValues(values)
    }

    func url(filename: String) -> URL {
        let parts = filename.split(separator: "/").map(String.init)
        guard let last = parts.last else { return directoryURL }
        var url = directoryURL
        for part in parts.dropLast() {
            url = url.appendingPathComponent(part, isDirectory: true)
        }
        return url.appendingPathComponent(last, isDirectory: false)
    }

    func loadData(filename: String) throws -> Data? {
        let file = url(filename: filename)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    func saveData(_ data: Data, filename: String) throws {
        try ensureDirectory()
        let file = url(filename: filename)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(filename: String) throws {
        let file = url(filename: filename)
        guard fileManager.fileExists(atPath: file.path) else { return }
        try fileManager.removeItem(at: file)
    }
}
