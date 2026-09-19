import Foundation

enum CollectionStorage: String, Sendable, Codable, Hashable {
    case local
    case greenfield
}

struct ModulaCollection: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var name: String
    var storage: CollectionStorage
    var itemIDs: [String]
    var createdAt: Date
    var updatedAt: Date
    var isDefault: Bool

    var itemCount: Int { itemIDs.count }
}

struct CollectionItemRef: Hashable, Sendable, Codable {
    enum Kind: String, Codable, Sendable { case post, link }
    var kind: Kind
    var id: String
}

struct CollectionBackendCapabilities: Sendable, Equatable {
    var serverCollections = false
    var serverReorder = false
    var localCollections = true

    static let production = CollectionBackendCapabilities()
}
