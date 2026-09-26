import Foundation

enum NodusKnowledgeSourceType: String, Sendable, Codable, CaseIterable {
    case plainText = "plain-text"
    case pastedText = "pasted-text"
    case markdown
    case txt
    case pdf
    case json
    case web
    case system
}

enum NodusKnowledgeCollectionKind: String, Sendable, Codable {
    case system
    case user
}

struct NodusKnowledgeCollection: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var name: String
    let kind: NodusKnowledgeCollectionKind
    let createdAt: Date
    var updatedAt: Date
    let version: String?
    let sourceCommit: String?
    let contentHash: String?
    let generationDate: Date?

    var isReadOnly: Bool { kind == .system }
}

struct NodusKnowledgeItem: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let collectionID: UUID
    var title: String
    let sourceType: NodusKnowledgeSourceType
    let sourceName: String
    let sourceURL: URL?
    let text: String
    let contentHash: String
    let createdAt: Date
    var updatedAt: Date
}

struct NodusKnowledgeChunk: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let documentID: UUID
    let collectionID: UUID
    let ordinal: Int
    let text: String
    let location: String?
}

struct NodusKnowledgeMatch: Identifiable, Sendable, Equatable {
    let chunk: NodusKnowledgeChunk
    let item: NodusKnowledgeItem
    let collection: NodusKnowledgeCollection
    let relevance: Double

    var id: UUID { chunk.id }
}

enum NodusKnowledgeImportError: Error, LocalizedError, Equatable {
    case unsupportedType
    case unreadable
    case noExtractableText
    case emptyText
    case readOnlyCollection
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedType: "Unsupported knowledge file type."
        case .unreadable: "The selected document could not be read."
        case .noExtractableText: "No extractable text."
        case .emptyText: "Knowledge text is empty."
        case .readOnlyCollection: "System Knowledge is read-only."
        case .fileTooLarge: "The selected document is too large for local import."
        }
    }
}

