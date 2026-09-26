import Foundation

struct NodusMemorySnapshot: Sendable, Codable, Equatable {
    var schemaVersion = 1
    var items: [NodusMemoryItem] = []
    var suggestions: [NodusMemorySuggestion] = []
}

actor NodusMemoryStore {
    private let files: PrivateFileStore
    private let filename: String
    private var state: NodusMemorySnapshot

    init(files: PrivateFileStore = PrivateFileStore(domain: .nodusMemory), filename: String = "memory.json") {
        self.files = files
        self.filename = filename
        if let data = try? files.loadData(filename: filename),
           let decoded = try? Self.decoder.decode(NodusMemorySnapshot.self, from: data) {
            state = decoded
        } else {
            state = NodusMemorySnapshot()
        }
    }

    func snapshot() -> NodusMemorySnapshot { state }

    func items(query: String = "") -> [NodusMemoryItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.items.filter { clean.isEmpty || $0.text.lowercased().contains(clean) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func add(
        text: String,
        kind: NodusMemoryKind,
        scope: NodusMemoryScope,
        conversationID: UUID? = nil,
        source: NodusMemorySource = .manual,
        sensitivity: NodusMemorySensitivity? = nil,
        now: Date = Date()
    ) throws -> NodusMemoryItem {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NodusMemoryError.empty }
        guard scope == .global || conversationID != nil else { throw NodusMemoryError.invalidScope }
        let classification = sensitivity ?? NodusSensitiveMemoryClassifier.classify(clean)
        let item = NodusMemoryItem(
            id: UUID(), scope: scope,
            conversationID: scope == .conversation ? conversationID : nil,
            kind: kind, text: clean, source: source,
            createdAt: now, updatedAt: now, confirmedAt: now,
            active: true, sensitivity: classification
        )
        state.items.append(item)
        try persist()
        return item
    }

    @discardableResult
    func suggest(
        text: String,
        kind: NodusMemoryKind,
        scope: NodusMemoryScope,
        conversationID: UUID? = nil,
        now: Date = Date()
    ) throws -> NodusMemorySuggestion? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NodusMemoryError.empty }
        guard scope == .global || conversationID != nil else { throw NodusMemoryError.invalidScope }
        let classification = NodusSensitiveMemoryClassifier.classify(clean)
        guard classification == .normal else { return nil }
        let suggestion = NodusMemorySuggestion(
            id: UUID(), scope: scope, conversationID: scope == .conversation ? conversationID : nil,
            kind: kind, text: clean, createdAt: now, sensitivity: classification
        )
        state.suggestions.append(suggestion)
        try persist()
        return suggestion
    }

    @discardableResult
    func approveSuggestion(id: UUID, editedText: String? = nil, now: Date = Date()) throws -> NodusMemoryItem? {
        guard let suggestion = state.suggestions.first(where: { $0.id == id }) else { return nil }
        let text = editedText ?? suggestion.text
        let item = try add(
            text: text, kind: suggestion.kind, scope: suggestion.scope,
            conversationID: suggestion.conversationID, source: .suggestion,
            sensitivity: NodusSensitiveMemoryClassifier.classify(text), now: now
        )
        state.suggestions.removeAll { $0.id == id }
        try persist()
        return item
    }

    func rejectSuggestion(id: UUID) throws {
        state.suggestions.removeAll { $0.id == id }
        try persist()
    }

    func edit(id: UUID, text: String, kind: NodusMemoryKind? = nil, now: Date = Date()) throws {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NodusMemoryError.empty }
        state.items[index].text = clean
        state.items[index].kind = kind ?? state.items[index].kind
        state.items[index].updatedAt = now
        state.items[index].sensitivity = NodusSensitiveMemoryClassifier.classify(clean)
        try persist()
    }

    func setActive(id: UUID, active: Bool, now: Date = Date()) throws {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[index].active = active
        state.items[index].updatedAt = now
        try persist()
    }

    func delete(id: UUID) throws {
        state.items.removeAll { $0.id == id }
        try persist()
    }

    func clear() throws {
        state.items = []
        state.suggestions = []
        try persist()
    }

    func retrieve(query: String, conversationID: UUID?, topK: Int = 5) -> [NodusMemoryMatch] {
        NodusMemoryRetriever().retrieve(query: query, snapshot: state, conversationID: conversationID, topK: topK)
    }

    private func persist() throws {
        let encoder = Self.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try files.saveData(try encoder.encode(state), filename: filename)
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

enum NodusSensitiveMemoryClassifier {
    static func classify(_ value: String) -> NodusMemorySensitivity {
        let text = value.lowercased()
        let prohibited = [
            "password", "passcode", "api key", "secret key", "access token", "refresh token",
            "authentication token", "private key", "seed phrase", "credit card", "cvv",
        ]
        if prohibited.contains(where: text.contains) { return .prohibited }
        let sensitive = [
            "bank account", "social security", "national insurance", "medical diagnosis",
            "precise location", "home address", "passport number",
        ]
        if sensitive.contains(where: text.contains) { return .sensitive }
        return .normal
    }
}

