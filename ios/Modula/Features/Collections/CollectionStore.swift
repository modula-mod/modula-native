import Foundation
import Observation

actor GreenfieldCollectionRepository {
    private let client: GreenfieldClient

    init(client: GreenfieldClient) { self.client = client }

    func collections(cursor: String? = nil) async throws -> CollectionCursorPage<ModulaCollection> {
        let value = try await client.authenticatedJSON("GET", path: page("/v1/me/collections", cursor: cursor))
        return CollectionCursorPage(
            items: try (value["items"]?.array ?? []).map(Self.collection),
            nextCursor: value["nextCursor"]?.string
        )
    }

    func allCollections() async throws -> [ModulaCollection] {
        var result: [ModulaCollection] = []
        var cursor: String?
        repeat {
            let page = try await collections(cursor: cursor)
            result.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    func create(name: String) async throws -> ModulaCollection {
        let value = try await client.authenticatedJSON("POST", path: "/v1/me/collections", body: .object(["name": .string(name)]))
        return try Self.collection(value["collection"] ?? value)
    }

    func rename(id: String, name: String, expectedVersion: Int) async throws -> ModulaCollection {
        let value = try await client.authenticatedJSON("PATCH", path: Self.collectionPath(id), body: .object([
            "name": .string(name), "expectedVersion": .number(Double(expectedVersion)),
        ]))
        return try Self.collection(value["collection"] ?? value)
    }

    func delete(id: String, expectedVersion: Int) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE", path: "\(Self.collectionPath(id))?expectedVersion=\(expectedVersion)"
        )
    }

    func collection(id: String) async throws -> ModulaCollection {
        let value = try await client.authenticatedJSON("GET", path: Self.collectionPath(id))
        return try Self.collection(value["collection"] ?? value)
    }

    func allItems(collectionID: String) async throws -> [GreenfieldCollectionItem] {
        var result: [GreenfieldCollectionItem] = []
        var cursor: String?
        repeat {
            let path = page("\(Self.collectionPath(collectionID))/items", cursor: cursor)
            let value = try await client.authenticatedJSON("GET", path: path)
            result.append(contentsOf: try (value["items"]?.array ?? []).map(Self.item))
            cursor = value["nextCursor"]?.string
        } while cursor != nil
        return result
    }

    func add(collectionID: String, postID: String) async throws -> GreenfieldCollectionItem {
        let escapedPost = postID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? postID
        let _: JSONValue = try await client.authenticatedJSON(
            "POST", path: "/v1/posts/\(escapedPost)/save", body: .object([:])
        )
        let value = try await client.authenticatedJSON(
            "POST", path: "\(Self.collectionPath(collectionID))/items", body: .object(["postId": .string(postID)])
        )
        return try Self.item(value["item"] ?? value)
    }

    func remove(collectionID: String, itemID: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE", path: "\(Self.collectionPath(collectionID))/items/\(Self.escaped(itemID))"
        )
    }

    private func page(_ path: String, cursor: String?) -> String {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: cursor)]
            .filter { $0.value != nil }
        guard let query = components.percentEncodedQuery else { return path }
        return "\(path)?\(query)"
    }

    nonisolated private static func collectionPath(_ id: String) -> String { "/v1/me/collections/\(escaped(id))" }
    nonisolated private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    nonisolated private static func collection(_ value: JSONValue) throws -> ModulaCollection {
        guard let id = value["id"]?.string, let name = value["name"]?.string,
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        return ModulaCollection(
            id: id, name: name, storage: .greenfield, itemIDs: [],
            createdAt: SocialPayloadDecoder.decodeDate(value["createdAt"]?.string) ?? Date(),
            updatedAt: SocialPayloadDecoder.decodeDate(value["updatedAt"]?.string) ?? Date(),
            isDefault: false, version: version, syncState: .synced
        )
    }

    nonisolated private static func item(_ value: JSONValue) throws -> GreenfieldCollectionItem {
        guard let id = value["id"]?.string, let postID = value["postId"]?.string,
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        return GreenfieldCollectionItem(
            id: id, postID: postID, available: value["available"]?.bool ?? false,
            post: value["post"].flatMap(SocialPayloadDecoder.post), version: version
        )
    }
}

/// Account-scoped local cache with an authenticated, replayable GreenField mutation queue.
@MainActor @Observable
final class CollectionStore {
    private struct SyncCache: Codable { var mutations: [CollectionMutation] }

    private let fileStore: PrivateFileStore
    private let legacyFilename = "collections.json"
    private let repository: GreenfieldCollectionRepository?
    let capabilities: CollectionBackendCapabilities
    private(set) var accountID: String?
    private(set) var collections: [ModulaCollection] = []
    private(set) var pendingMutations: [CollectionMutation] = []
    private(set) var isRefreshing = false
    private(set) var isReplaying = false
    var error: String?

    init(
        client: GreenfieldClient? = nil,
        capabilities: CollectionBackendCapabilities = .production,
        fileStore: PrivateFileStore = PrivateFileStore(domain: .collections)
    ) {
        repository = client.map { GreenfieldCollectionRepository(client: $0) }
        self.capabilities = capabilities
        self.fileStore = fileStore
        load()
        ensureDefaultSaved()
    }

    var userCollections: [ModulaCollection] {
        collections.filter { !$0.isDefault }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var defaultSaved: ModulaCollection? { collections.first(where: \.isDefault) }

    func setAccountID(_ id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = normalized?.isEmpty == false ? normalized : nil
        guard next != accountID else { return }
        let legacy = accountID == nil ? collections.filter { !$0.isDefault && $0.storage == .local } : []
        _ = persist()
        accountID = next
        load()
        if next != nil, repository != nil, userCollections.isEmpty, !legacy.isEmpty {
            collections.append(contentsOf: legacy.map { value in
                var migrated = value
                migrated.syncState = .pending
                return migrated
            })
            pendingMutations.append(contentsOf: legacy.map {
                CollectionMutation(kind: .create, collectionID: $0.id, name: $0.name)
            })
        }
        ensureDefaultSaved()
        _ = persist()
        guard next != nil else { return }
        Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        guard let repository, accountID != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await replayPending()
        do {
            var server = try await repository.allCollections()
            for index in server.indices {
                let items = try await repository.allItems(collectionID: server[index].id)
                server[index].itemIDs = items.map(\.postID)
                server[index].serverItemIDsByPostID = Dictionary(uniqueKeysWithValues: items.map { ($0.postID, $0.id) })
            }
            let pendingIDs = Set(pendingMutations.map(\.collectionID))
            let localPending = collections.filter { !$0.isDefault && pendingIDs.contains($0.id) }
            collections = collections.filter(\.isDefault)
                + server.filter { !pendingIDs.contains($0.id) }
                + localPending
            error = nil
            _ = persist()
        } catch {
            self.error = message(error, fallback: "Couldn’t refresh collections. Showing the saved cache.")
        }
    }

    func create(name: String) -> ModulaCollection? {
        guard capabilities.localCollections else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 120 else {
            error = "Collection names can contain at most 120 characters."
            return nil
        }
        let now = Date()
        let collection = ModulaCollection(
            id: UUID().uuidString, name: trimmed, storage: .local, itemIDs: [],
            createdAt: now, updatedAt: now, isDefault: false,
            syncState: accountID == nil ? .localOnly : .pending
        )
        collections.append(collection)
        if accountID != nil {
            pendingMutations.append(CollectionMutation(kind: .create, collectionID: collection.id, name: trimmed))
        }
        guard persist() else {
            collections.removeAll { $0.id == collection.id }
            pendingMutations.removeAll { $0.collectionID == collection.id }
            return nil
        }
        replaySoon()
        return collection
    }

    func rename(id: String, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }), !collections[index].isDefault else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= 120 else {
            error = "Collection names can contain at most 120 characters."
            return
        }
        collections[index].name = trimmed
        collections[index].updatedAt = Date()
        if accountID != nil {
            collections[index].syncState = .pending
            pendingMutations.removeAll { $0.kind == .rename && $0.collectionID == id }
            pendingMutations.append(CollectionMutation(
                kind: .rename, collectionID: id, name: trimmed, expectedVersion: collections[index].version
            ))
        }
        _ = persist()
        replaySoon()
    }

    func delete(id: String) {
        guard let collection = collections.first(where: { $0.id == id }), !collection.isDefault else { return }
        collections.removeAll { $0.id == id }
        if accountID != nil {
            if collection.storage == .local {
                pendingMutations.removeAll { $0.collectionID == id }
            } else {
                pendingMutations.removeAll { $0.collectionID == id }
                pendingMutations.append(CollectionMutation(
                    kind: .delete, collectionID: id, expectedVersion: collection.version
                ))
            }
        }
        _ = persist()
        replaySoon()
    }

    @discardableResult
    func add(postID: String, to collectionID: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return false }
        guard !collections[index].itemIDs.contains(postID) else { return true }
        collections[index].itemIDs.append(postID)
        collections[index].updatedAt = Date()
        if accountID != nil {
            collections[index].syncState = .pending
            pendingMutations.append(CollectionMutation(kind: .add, collectionID: collectionID, postID: postID))
        }
        let saved = persist()
        replaySoon()
        return saved
    }

    func remove(postID: String, from collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].itemIDs.removeAll { $0 == postID }
        collections[index].updatedAt = Date()
        if accountID != nil {
            if let queued = pendingMutations.firstIndex(where: {
                $0.kind == .add && $0.collectionID == collectionID && $0.postID == postID
            }) {
                pendingMutations.remove(at: queued)
            } else if let itemID = collections[index].serverItemIDsByPostID.removeValue(forKey: postID) {
                collections[index].syncState = .pending
                pendingMutations.append(CollectionMutation(
                    kind: .remove, collectionID: collectionID, postID: postID, itemID: itemID
                ))
            }
        }
        _ = persist()
        replaySoon()
    }

    func resolveConflictUsingServer(id: String) async {
        guard let repository else { return }
        do {
            var server = try await repository.collection(id: id)
            let items = try await repository.allItems(collectionID: id)
            server.itemIDs = items.map(\.postID)
            server.serverItemIDsByPostID = Dictionary(uniqueKeysWithValues: items.map { ($0.postID, $0.id) })
            collections.removeAll { $0.id == id }
            collections.append(server)
            pendingMutations.removeAll { $0.collectionID == id }
            error = nil
            _ = persist()
        } catch { self.error = message(error, fallback: "Couldn’t resolve the collection conflict.") }
    }

    private func replaySoon() {
        guard accountID != nil, repository != nil else { return }
        Task { [weak self] in await self?.replayPending() }
    }

    private func replayPending() async {
        guard let repository, accountID != nil, !isReplaying else { return }
        isReplaying = true
        defer { isReplaying = false }
        while let mutation = pendingMutations.first {
            do {
                switch mutation.kind {
                case .create:
                    guard let name = mutation.name else { throw APIError.invalidResponse }
                    let created: ModulaCollection
                    do { created = try await repository.create(name: name) }
                    catch let api as APIError where Self.isConflict(api) {
                        guard let existing = (try await repository.allCollections()).first(where: {
                            $0.name.caseInsensitiveCompare(name) == .orderedSame
                        }) else { throw api }
                        created = existing
                    }
                    if collections.contains(where: { $0.id == mutation.collectionID }) {
                        remap(localID: mutation.collectionID, to: created)
                    } else {
                        // The local collection was deleted while creation was in flight.
                        // Queue an authenticated compensating delete for the server record.
                        pendingMutations.append(CollectionMutation(
                            kind: .delete, collectionID: created.id, expectedVersion: created.version
                        ))
                    }
                case .rename:
                    guard let name = mutation.name, let version = mutation.expectedVersion else { throw APIError.invalidResponse }
                    let updated: ModulaCollection
                    do {
                        updated = try await repository.rename(
                            id: mutation.collectionID, name: name, expectedVersion: version
                        )
                    } catch let api as APIError where Self.isConflict(api) {
                        let current = try await repository.collection(id: mutation.collectionID)
                        guard current.name == name else { throw api }
                        updated = current
                    }
                    replaceMetadata(updated, appliedMutationID: mutation.id)
                case .delete:
                    guard let version = mutation.expectedVersion else { throw APIError.invalidResponse }
                    do {
                        try await repository.delete(id: mutation.collectionID, expectedVersion: version)
                    } catch let api as APIError where Self.isNotFound(api) {
                        // A prior response may have been lost after the delete committed.
                    }
                case .add:
                    guard let postID = mutation.postID else { throw APIError.invalidResponse }
                    let item = try await repository.add(collectionID: mutation.collectionID, postID: postID)
                    if pendingMutations.contains(where: { $0.id == mutation.id }),
                       let index = collections.firstIndex(where: {
                           $0.id == mutation.collectionID && $0.itemIDs.contains(postID)
                       }) {
                        collections[index].serverItemIDsByPostID[postID] = item.id
                        collections[index].storage = .greenfield
                        let metadata = try await repository.collection(id: mutation.collectionID)
                        collections[index].version = metadata.version
                        collections[index].updatedAt = metadata.updatedAt
                        advanceExpectedVersions(collectionID: mutation.collectionID, to: metadata.version, excluding: mutation.id)
                    } else if collections.contains(where: { $0.id == mutation.collectionID }),
                              !pendingMutations.contains(where: {
                                  $0.kind == .delete && $0.collectionID == mutation.collectionID
                              }) {
                        // The user removed the post while this add was in flight.
                        pendingMutations.append(CollectionMutation(
                            kind: .remove, collectionID: mutation.collectionID,
                            postID: postID, itemID: item.id
                        ))
                    }
                case .remove:
                    guard let itemID = mutation.itemID else { throw APIError.invalidResponse }
                    do {
                        try await repository.remove(collectionID: mutation.collectionID, itemID: itemID)
                    } catch let api as APIError where Self.isNotFound(api) {
                        // Item deletion is idempotent from the queue's perspective.
                    }
                    if let index = collections.firstIndex(where: { $0.id == mutation.collectionID }) {
                        let metadata = try await repository.collection(id: mutation.collectionID)
                        collections[index].version = metadata.version
                        collections[index].updatedAt = metadata.updatedAt
                        advanceExpectedVersions(collectionID: mutation.collectionID, to: metadata.version, excluding: mutation.id)
                    }
                }
                pendingMutations.removeAll { $0.id == mutation.id }
                for id in collections.filter({ !$0.isDefault }).map(\.id) { markSyncedIfComplete(id) }
                error = nil
                _ = persist()
            } catch let api as APIError where Self.isConflict(api) {
                if let index = collections.firstIndex(where: { $0.id == mutation.collectionID }) {
                    collections[index].syncState = .conflict
                }
                _ = persist()
                error = "This collection changed on another device. Choose the server copy before editing it again."
                return
            } catch {
                let syncMessage = message(error, fallback: "Collections will sync when the connection recovers.")
                _ = persist()
                self.error = syncMessage
                return
            }
        }
    }

    private func remap(localID: String, to server: ModulaCollection) {
        guard let index = collections.firstIndex(where: { $0.id == localID }) else { return }
        var merged = server
        merged.itemIDs = collections[index].itemIDs
        merged.syncState = .pending
        collections[index] = merged
        for pending in pendingMutations.indices where pendingMutations[pending].collectionID == localID {
            pendingMutations[pending].collectionID = server.id
            if pendingMutations[pending].expectedVersion == nil { pendingMutations[pending].expectedVersion = server.version }
        }
    }

    private func replaceMetadata(_ server: ModulaCollection, appliedMutationID: String) {
        if let index = collections.firstIndex(where: { $0.id == server.id }) {
            let hasNewerRename = pendingMutations.contains {
                $0.kind == .rename && $0.collectionID == server.id && $0.id != appliedMutationID
            }
            if !hasNewerRename { collections[index].name = server.name }
            collections[index].storage = .greenfield
            collections[index].version = server.version
            collections[index].updatedAt = server.updatedAt
        }
        advanceExpectedVersions(collectionID: server.id, to: server.version, excluding: appliedMutationID)
    }

    private func advanceExpectedVersions(collectionID: String, to version: Int?, excluding mutationID: String) {
        guard let version else { return }
        for index in pendingMutations.indices {
            guard pendingMutations[index].collectionID == collectionID,
                  pendingMutations[index].id != mutationID,
                  pendingMutations[index].expectedVersion != nil else { continue }
            pendingMutations[index].expectedVersion = version
        }
    }

    private func markSyncedIfComplete(_ id: String) {
        guard !pendingMutations.contains(where: { $0.collectionID == id }),
              let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].storage = .greenfield
        collections[index].syncState = .synced
    }

    private func ensureDefaultSaved() {
        guard !collections.contains(where: \.isDefault) else { return }
        let now = Date()
        collections.insert(ModulaCollection(
            id: "saved-default", name: "Saved", storage: .local, itemIDs: [],
            createdAt: now, updatedAt: now, isDefault: true, syncState: .localOnly
        ), at: 0)
        _ = persist()
    }

    private var collectionsFilename: String {
        guard let accountID else { return legacyFilename }
        return "accounts/\(sanitize(accountID))/collections.json"
    }

    private var syncFilename: String {
        guard let accountID else { return "collection-sync.json" }
        return "accounts/\(sanitize(accountID))/collection-sync.json"
    }

    private func load() {
        if let data = try? fileStore.loadData(filename: collectionsFilename),
           let decoded = try? JSONDecoder().decode([ModulaCollection].self, from: data) {
            collections = decoded
        } else { collections = [] }
        if let data = try? fileStore.loadData(filename: syncFilename),
           let decoded = try? JSONDecoder().decode(SyncCache.self, from: data) {
            pendingMutations = decoded.mutations
        } else { pendingMutations = [] }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try fileStore.saveData(try JSONEncoder().encode(collections), filename: collectionsFilename)
            try fileStore.saveData(try JSONEncoder().encode(SyncCache(mutations: pendingMutations)), filename: syncFilename)
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save the collection cache on this iPhone. Free up storage and try again."
            return false
        }
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(filtered)
        return result.isEmpty ? "_unknown" : result
    }

    private func message(_ error: Error, fallback: String) -> String {
        (error as? APIError)?.userFacingMessage ?? fallback
    }

    private static func isConflict(_ error: APIError) -> Bool {
        if case .rejected(409, _) = error { return true }
        return false
    }

    private static func isNotFound(_ error: APIError) -> Bool {
        if case .rejected(404, _) = error { return true }
        return false
    }
}
