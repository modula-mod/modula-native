import Foundation

private struct NodusConversationSnapshot: Sendable, Codable {
    var schemaVersion = 1
    var conversations: [NodusConversation] = []
}

actor NodusConversationStore {
    private let files: PrivateFileStore
    private let filename: String
    private var state: NodusConversationSnapshot

    init(files: PrivateFileStore = PrivateFileStore(domain: .nodusConversations), filename: String = "conversations.json") {
        self.files = files
        self.filename = filename
        if let data = try? files.loadData(filename: filename),
           let decoded = try? Self.decoder.decode(NodusConversationSnapshot.self, from: data) {
            state = decoded
        } else {
            state = NodusConversationSnapshot()
        }
    }

    func all() -> [NodusConversation] {
        state.conversations.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func conversation(id: UUID) -> NodusConversation? {
        state.conversations.first { $0.id == id }
    }

    @discardableResult
    func create(now: Date = Date()) throws -> NodusConversation {
        let conversation = NodusConversation(createdAt: now, updatedAt: now)
        state.conversations.append(conversation)
        try persist()
        return conversation
    }

    func upsert(_ conversation: NodusConversation) throws {
        if let index = state.conversations.firstIndex(where: { $0.id == conversation.id }) {
            state.conversations[index] = conversation
        } else {
            state.conversations.append(conversation)
        }
        try persist()
    }

    @discardableResult
    func append(_ message: NodusMessage, to conversationID: UUID, now: Date = Date()) throws -> NodusConversation? {
        guard let index = state.conversations.firstIndex(where: { $0.id == conversationID }) else { return nil }
        state.conversations[index].messages.append(message)
        state.conversations[index].updatedAt = now
        if message.role == .user,
           state.conversations[index].messages.filter({ $0.role == .user }).count == 1,
           state.conversations[index].title == "New Chat" {
            state.conversations[index].title = NodusConversation.fallbackTitle(for: message.text)
        }
        try persist()
        return state.conversations[index]
    }

    func rename(id: UUID, title: String, now: Date = Date()) throws {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        state.conversations[index].title = String(normalized.prefix(100))
        state.conversations[index].updatedAt = now
        try persist()
    }

    func clear(id: UUID, now: Date = Date()) throws {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[index].messages = []
        state.conversations[index].updatedAt = now
        try persist()
    }

    func delete(id: UUID) throws {
        state.conversations.removeAll { $0.id == id }
        try persist()
    }

    func search(_ query: String) -> [NodusConversation] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return all() }
        return all().filter { conversation in
            let haystack = ([conversation.title] + conversation.messages.map(\.text)).joined(separator: " ").lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    private func persist() throws {
        let encoder = Self.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try files.saveData(try encoder.encode(state), filename: filename)
    }

    private static func terms(in value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}

