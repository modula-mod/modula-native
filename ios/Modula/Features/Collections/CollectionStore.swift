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
        persist()
        return collection
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

    func add(postID: String, to collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        guard !collections[index].itemIDs.contains(postID) else { return }
        collections[index].itemIDs.append(postID)
        collections[index].updatedAt = Date()
        persist()
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        try? fileStore.saveData(data, filename: filename)
    }
}
