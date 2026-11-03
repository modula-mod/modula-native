import Foundation

enum CollectionStorage: String, Sendable, Codable, Hashable {
    case local
    case greenfield
}

enum CollectionSyncState: String, Sendable, Codable, Hashable {
    case localOnly
    case pending
    case synced
    case conflict
    case failed
}

struct ModulaCollection: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var storage: CollectionStorage
    var itemIDs: [String]
    var createdAt: Date
    var updatedAt: Date
    var isDefault: Bool
    var version: Int?
    var serverItemIDsByPostID: [String: String]
    var syncState: CollectionSyncState

    init(
        id: String,
        name: String,
        storage: CollectionStorage,
        itemIDs: [String],
        createdAt: Date,
        updatedAt: Date,
        isDefault: Bool,
        version: Int? = nil,
        serverItemIDsByPostID: [String: String] = [:],
        syncState: CollectionSyncState? = nil
    ) {
        self.id = id
        self.name = name
        self.storage = storage
        self.itemIDs = itemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDefault = isDefault
        self.version = version
        self.serverItemIDsByPostID = serverItemIDsByPostID
        self.syncState = syncState ?? (storage == .greenfield ? .synced : .localOnly)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        storage = try values.decodeIfPresent(CollectionStorage.self, forKey: .storage) ?? .local
        itemIDs = try values.decodeIfPresent([String].self, forKey: .itemIDs) ?? []
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        version = try values.decodeIfPresent(Int.self, forKey: .version)
        serverItemIDsByPostID = try values.decodeIfPresent([String: String].self, forKey: .serverItemIDsByPostID) ?? [:]
        syncState = try values.decodeIfPresent(CollectionSyncState.self, forKey: .syncState)
            ?? (storage == .greenfield ? .synced : .localOnly)
    }

    var itemCount: Int { itemIDs.count }
}

struct CollectionItemRef: Hashable, Sendable, Codable {
    enum Kind: String, Codable, Sendable { case post, link }
    var kind: Kind
    var id: String
}

struct CollectionBackendCapabilities: Sendable, Equatable {
    var serverCollections = true
    var serverReorder = false
    var localCollections = true

    static let production = CollectionBackendCapabilities()
}

struct CollectionCursorPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
}

struct GreenfieldCollectionItem: Sendable, Equatable {
    let id: String
    let postID: String
    let available: Bool
    let post: SocialPost?
    let version: Int
}

struct CollectionMutation: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable { case create, rename, delete, add, remove }
    var id: String
    var kind: Kind
    var collectionID: String
    var name: String?
    var postID: String?
    var itemID: String?
    var expectedVersion: Int?

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        collectionID: String,
        name: String? = nil,
        postID: String? = nil,
        itemID: String? = nil,
        expectedVersion: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.collectionID = collectionID
        self.name = name
        self.postID = postID
        self.itemID = itemID
        self.expectedVersion = expectedVersion
    }
}
