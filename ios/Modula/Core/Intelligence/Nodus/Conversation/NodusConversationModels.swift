import Foundation

enum NodusReasoningMode: String, Sendable, Codable, CaseIterable {
    case standard
    case deep

    var displayName: String { self == .deep ? "Think" : "Standard" }
}

enum NodusMessageRole: String, Sendable, Codable {
    case user
    case nodus
}

enum NodusCitationKind: String, Sendable, Codable {
    case knowledge
    case web
}

struct NodusCitation: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let kind: NodusCitationKind
    let title: String
    let sourceName: String
    let collectionName: String?
    let location: String?
    let url: URL?
    let retrievedAt: Date?
    let excerpt: String?

    init(
        id: UUID = UUID(),
        kind: NodusCitationKind,
        title: String,
        sourceName: String,
        collectionName: String? = nil,
        location: String? = nil,
        url: URL? = nil,
        retrievedAt: Date? = nil,
        excerpt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceName = sourceName
        self.collectionName = collectionName
        self.location = location
        self.url = url
        self.retrievedAt = retrievedAt
        self.excerpt = excerpt
    }
}

struct NodusResponseDetails: Sendable, Codable, Equatable {
    let reasoningMode: NodusReasoningMode
    let searchEnabled: Bool
    let searchedWeb: Bool
    let knowledgeChunkCount: Int
    let memoryItemIDs: [UUID]
    let searchResultCount: Int
    let generationDuration: Double?
    let retrievalDuration: Double?
    let searchDuration: Double?
    let inferencePasses: Int
}

struct NodusMessage: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let role: NodusMessageRole
    let text: String
    let createdAt: Date
    let answer: NodusAnswer?
    let requestID: UUID?
    let citations: [NodusCitation]
    let details: NodusResponseDetails?

    init(
        id: UUID = UUID(),
        role: NodusMessageRole,
        text: String,
        createdAt: Date = Date(),
        answer: NodusAnswer? = nil,
        requestID: UUID? = nil,
        citations: [NodusCitation] = [],
        details: NodusResponseDetails? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.answer = answer
        self.requestID = requestID
        self.citations = citations
        self.details = details
    }
}

struct NodusConversation: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    let modelID: String
    let modelStage: NodusModelStage
    var reasoningMode: NodusReasoningMode
    var searchEnabled: Bool
    var attachedKnowledgeCollectionIDs: Set<UUID>
    var memoryEnabled: Bool
    var pinned: Bool
    var messages: [NodusMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelID: String = "nodus-r7-experimental",
        modelStage: NodusModelStage = .experimentalCandidate,
        reasoningMode: NodusReasoningMode = .standard,
        searchEnabled: Bool = false,
        attachedKnowledgeCollectionIDs: Set<UUID> = [],
        memoryEnabled: Bool = true,
        pinned: Bool = false,
        messages: [NodusMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
        self.modelStage = modelStage
        self.reasoningMode = reasoningMode
        self.searchEnabled = searchEnabled
        self.attachedKnowledgeCollectionIDs = attachedKnowledgeCollectionIDs
        self.memoryEnabled = memoryEnabled
        self.pinned = pinned
        self.messages = messages
    }

    var preview: String {
        messages.last?.text.replacingOccurrences(of: "\n", with: " ") ?? "No messages yet"
    }

    static func fallbackTitle(for firstUserMessage: String) -> String {
        let singleLine = firstUserMessage
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "New Chat" }
        let limit = 52
        if singleLine.count <= limit { return singleLine }
        return String(singleLine.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
