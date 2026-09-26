import Foundation

enum NodusMemoryScope: String, Sendable, Codable, CaseIterable {
    case global
    case conversation
}

enum NodusMemoryKind: String, Sendable, Codable, CaseIterable {
    case preference
    case instruction
    case project
    case personReference = "person-reference"
    case generalFact = "general-fact"
    case workflow

    var displayName: String {
        switch self {
        case .personReference: "Person / reference"
        case .generalFact: "General fact"
        default: rawValue.capitalized
        }
    }
}

enum NodusMemorySource: String, Sendable, Codable {
    case manual
    case suggestion
    case message
}

enum NodusMemorySensitivity: String, Sendable, Codable, CaseIterable {
    case normal
    case privateData = "private"
    case sensitive
    case prohibited
}

struct NodusMemoryItem: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var scope: NodusMemoryScope
    var conversationID: UUID?
    var kind: NodusMemoryKind
    var text: String
    let source: NodusMemorySource
    let createdAt: Date
    var updatedAt: Date
    let confirmedAt: Date
    var active: Bool
    var sensitivity: NodusMemorySensitivity
}

struct NodusMemorySuggestion: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var scope: NodusMemoryScope
    var conversationID: UUID?
    var kind: NodusMemoryKind
    var text: String
    let createdAt: Date
    let sensitivity: NodusMemorySensitivity
}

struct NodusMemoryMatch: Identifiable, Sendable, Equatable {
    let item: NodusMemoryItem
    let relevance: Double
    var id: UUID { item.id }
}

enum NodusMemoryError: Error, LocalizedError, Equatable {
    case empty
    case invalidScope
    case sensitiveInformation

    var errorDescription: String? {
        switch self {
        case .empty: "Memory text is empty."
        case .invalidScope: "Conversation Memory requires a conversation."
        case .sensitiveInformation: "Sensitive information cannot be saved automatically."
        }
    }
}

