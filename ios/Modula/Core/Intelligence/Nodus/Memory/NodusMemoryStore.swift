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


// MARK: - Automatic memory extraction (feature 3)
//
// Deterministic, high-precision extraction of memory candidates from a user
// turn. Only the user's own words are mined; the assistant's reply is never
// a source. Candidates are proposed through `suggest()` — which silently
// drops anything classified above `.normal` — and are never saved without
// the user's approval in the suggestion queue. At most two candidates per
// turn, and only from clear statement patterns ("my birthday is…",
// "I like…", "remember that…") so questions and small talk never become
// memories. No model call, no new dependency: pure string matching.

enum NodusMemoryExtractor {
    struct Candidate: Sendable, Equatable {
        let text: String
        let kind: NodusMemoryKind
        let scope: NodusMemoryScope
    }

    static func candidates(question: String) -> [Candidate] {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return [] }
        var found: [Candidate] = []
        var seen = Set<String>()
        func add(_ sentence: String, kind: NodusMemoryKind, scope: NodusMemoryScope) {
            let clean = normalized(sentence)
            guard clean.count >= 8, clean.count <= 200 else { return }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { return }
            found.append(Candidate(text: clean, kind: kind, scope: scope))
        }
        // 1. Birthdays — a fact about a person.
        if let s = sentence(containing: "birthday is", in: text) { add(s, kind: .personReference, scope: .global) }
        // 2. What the user is working on.
        if let s = sentence(containing: "i'm working on", in: text) ?? sentence(containing: "i am working on", in: text) { add(s, kind: .project, scope: .conversation) }
        if let s = sentence(containing: "my project is", in: text) { add(s, kind: .project, scope: .conversation) }
        // 3. Likes and preferences.
        if let s = sentence(containing: "i like ", in: text) ?? sentence(containing: "i love ", in: text) ?? sentence(containing: "i prefer ", in: text) { add(s, kind: .preference, scope: .global) }
        if let s = sentence(containing: "i don't like ", in: text) ?? sentence(containing: "i dislike ", in: text) { add(s, kind: .preference, scope: .global) }
        // 4. Explicit "remember that".
        if let clause = clause(after: "remember that ", in: text) ?? clause(after: "remember my ", in: text) {
            add(clause, kind: .generalFact, scope: .global)
        }
        // 5. Standing instructions ("always…", "never…").
        if let s = sentence(startingWith: "always ", in: text) ?? sentence(startingWith: "never ", in: text) { add(s, kind: .instruction, scope: .conversation) }
        // 6. Facts about a person ("my sister is a doctor").
        if let s = sentence(startingWith: "my ", containing: " is ", in: text) { add(s, kind: .personReference, scope: .global) }
        return Array(found.prefix(2))
    }

    /// The sentence containing `marker` (case-insensitive), or nil.
    private static func sentence(containing marker: String, in text: String) -> String? {
        for part in splitSentences(text) {
            if part.lowercased().contains(marker) { return part }
        }
        return nil
    }

    /// The first sentence starting with `prefix` (case-insensitive), or nil.
    private static func sentence(startingWith prefix: String, in text: String) -> String? {
        for part in splitSentences(text) {
            if part.lowercased().hasPrefix(prefix) { return part }
        }
        return nil
    }

    /// The first sentence starting with `prefix` and containing `marker`, or nil.
    private static func sentence(startingWith prefix: String, containing marker: String, in text: String) -> String? {
        for part in splitSentences(text) {
            let lower = part.lowercased()
            if lower.hasPrefix(prefix) && lower.contains(marker) { return part }
        }
        return nil
    }

    /// The text after `marker` in the sentence that contains it (for "remember that …").
    private static func clause(after marker: String, in text: String) -> String? {
        for part in splitSentences(text) {
            let lower = part.lowercased()
            guard let range = lower.range(of: marker) else { continue }
            let rest = String(part[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { continue }
            return rest
        }
        return nil
    }

    private static func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Capitalise, collapse whitespace, cap at 200 characters, end with a full stop.
    private static func normalized(_ s: String) -> String {
        var t = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        if t.count > 200 { t = String(t.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !t.isEmpty else { return t }
        t = String(t.prefix(1)).uppercased() + String(t.dropFirst())
        if !t.hasSuffix(".") { t += "." }
        return t
    }
}
