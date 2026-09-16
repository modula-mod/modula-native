import Foundation
import Observation

/// Device-local recent commands. Never syncs to Greenfield. Never stores sensitive values.
@MainActor @Observable
final class CommandRecentsStore {
    private let store: PrivateFileStore
    private let filename = "recents.json"
    private let limit: Int
    private(set) var recentIDs: [CommandID] = []

    init(limit: Int = 16, store: PrivateFileStore = PrivateFileStore(domain: .commands)) {
        self.limit = limit
        self.store = store
        load()
    }

    func record(_ command: ModulaCommand) {
        guard Self.isSafeForRecents(command) else { return }
        var next = recentIDs.filter { $0 != command.id }
        next.insert(command.id, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        recentIDs = next
        persist()
    }

    func clear() {
        recentIDs = []
        try? store.remove(filename: filename)
    }

    /// Privacy filter: reject commands whose titles/subtitles look like message bodies or draft text.
    static func isSafeForRecents(_ command: ModulaCommand) -> Bool {
        if command.category == .developer { return false }
        switch command.action {
        case .shareStart, .functionInvoke:
            return false
        case .searchStart(let query) where (query?.isEmpty == false):
            // Do not remember free-form search terms.
            return false
        default:
            break
        }
        let blob = ([command.title, command.subtitle].compactMap { $0 } + command.aliases).joined(separator: " ")
        if blob.count > 80 { return false }
        if blob.contains("\"") || blob.contains("“") || blob.contains("”") { return false }
        return true
    }

    private func load() {
        guard let data = try? store.loadData(filename: filename),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            recentIDs = []
            return
        }
        recentIDs = decoded.map(CommandID.init(rawValue:))
    }

    private func persist() {
        let payload = recentIDs.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? store.saveData(data, filename: filename)
    }
}
