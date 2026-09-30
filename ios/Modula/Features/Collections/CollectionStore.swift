import Foundation
import Observation

/// Local-first collections. Server sync stays OPEN until Greenfield confirms collections.
@MainActor @Observable
final class CollectionStore {
    private let fileStore: PrivateFileStore
    private let filename = "collections.json"
    let capabilities: CollectionBackendCapabilities
    private(set) var collections: [ModulaCollection] = []
    var error: String?

    init(
        capabilities: CollectionBackendCapabilities = .production,
        fileStore: PrivateFileStore = PrivateFileStore(domain: .collections)
    ) {
        self.capabilities = capabilities
        self.fileStore = fileStore
        load()
        ensureDefaultSaved()
    }

    var userCollections: [ModulaCollection] {
        collections.filter { !$0.isDefault }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var defaultSaved: ModulaCollection? {
        collections.first(where: \.isDefault)
    }

    func create(name: String) -> ModulaCollection? {
        guard capabilities.localCollections else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = Date()
        let collection = ModulaCollection(
            id: UUID().uuidString,
            name: trimmed,
            storage: .local,
            itemIDs: [],
            createdAt: now,
            updatedAt: now,
            isDefault: false
        )
        collections.append(collection)
        return persist() ? collection : nil
    }

    func rename(id: String, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }), !collections[index].isDefault else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
        collections[index].updatedAt = Date()
        persist()
    }

    func delete(id: String) {
        guard let collection = collections.first(where: { $0.id == id }), !collection.isDefault else { return }
        collections.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func add(postID: String, to collectionID: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return false }
        guard !collections[index].itemIDs.contains(postID) else { return true }
        collections[index].itemIDs.append(postID)
        collections[index].updatedAt = Date()
        return persist()
    }

    func remove(postID: String, from collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].itemIDs.removeAll { $0 == postID }
        collections[index].updatedAt = Date()
        persist()
    }

    private func ensureDefaultSaved() {
        guard !collections.contains(where: \.isDefault) else { return }
        let now = Date()
        collections.insert(
            ModulaCollection(
                id: "saved-default",
                name: "Saved",
                storage: .local,
                itemIDs: [],
                createdAt: now,
                updatedAt: now,
                isDefault: true
            ),
            at: 0
        )
        persist()
    }

    private func load() {
        guard let data = try? fileStore.loadData(filename: filename),
              let decoded = try? JSONDecoder().decode([ModulaCollection].self, from: data) else {
            collections = []
            return
        }
        collections = decoded
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(collections)
            try fileStore.saveData(data, filename: filename)
            error = nil
            return true
        } catch {
            // Restore disk truth: failed writes must not appear as saved changes.
            load()
            self.error = "Couldn’t save the collection on this iPhone. Free up storage and try again."
            return false
        }
    }
}
