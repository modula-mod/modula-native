import CryptoKit
import Foundation

struct NodusKnowledgeSnapshot: Sendable, Codable, Equatable {
    var schemaVersion = 1
    var collections: [NodusKnowledgeCollection] = []
    var items: [NodusKnowledgeItem] = []
    var chunks: [NodusKnowledgeChunk] = []
}

actor NodusKnowledgeStore {
    static let modulaCoreCollectionID = UUID(uuidString: "870f270a-7bc4-4d9b-a982-c465a9c2b001")!
    static let myKnowledgeCollectionID = UUID(uuidString: "870f270a-7bc4-4d9b-a982-c465a9c2b002")!

    private let files: PrivateFileStore
    private let filename: String
    private var state: NodusKnowledgeSnapshot

    init(files: PrivateFileStore = PrivateFileStore(domain: .nodusKnowledge), filename: String = "knowledge.json") {
        self.files = files
        self.filename = filename
        if let data = try? files.loadData(filename: filename),
           let decoded = try? Self.decoder.decode(NodusKnowledgeSnapshot.self, from: data) {
            state = decoded
        } else {
            state = NodusKnowledgeSnapshot()
        }
        state = Self.bootstrapped(state)
        if let data = try? Self.encoder.encode(state) {
            try? files.saveData(data, filename: filename)
        }
    }

    func snapshot() -> NodusKnowledgeSnapshot { state }

    func collections() -> [NodusKnowledgeCollection] {
        state.collections.sorted {
            if $0.kind != $1.kind { return $0.kind == .system }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func collection(id: UUID) -> NodusKnowledgeCollection? { state.collections.first { $0.id == id } }
    func items(collectionID: UUID? = nil) -> [NodusKnowledgeItem] {
        state.items.filter { collectionID == nil || $0.collectionID == collectionID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createCollection(name: String, now: Date = Date()) throws -> NodusKnowledgeCollection {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NodusKnowledgeImportError.emptyText }
        let collection = NodusKnowledgeCollection(
            id: UUID(), name: String(clean.prefix(100)), kind: .user,
            createdAt: now, updatedAt: now, version: nil, sourceCommit: nil,
            contentHash: nil, generationDate: nil
        )
        state.collections.append(collection)
        try persist()
        return collection
    }

    @discardableResult
    func add(
        title: String,
        sourceType: NodusKnowledgeSourceType,
        sourceName: String,
        sourceURL: URL? = nil,
        text: String,
        collectionID: UUID,
        locations: [Int: String] = [:],
        now: Date = Date()
    ) throws -> NodusKnowledgeItem {
        guard let collection = state.collections.first(where: { $0.id == collectionID }) else {
            throw NodusKnowledgeImportError.unreadable
        }
        guard !collection.isReadOnly else { throw NodusKnowledgeImportError.readOnlyCollection }
        return try addInternal(
            title: title, sourceType: sourceType, sourceName: sourceName, sourceURL: sourceURL,
            text: text, collectionID: collectionID, locations: locations, now: now
        )
    }

    func deleteItem(id: UUID) throws {
        guard let item = state.items.first(where: { $0.id == id }),
              state.collections.first(where: { $0.id == item.collectionID })?.isReadOnly == false else {
            throw NodusKnowledgeImportError.readOnlyCollection
        }
        state.items.removeAll { $0.id == id }
        state.chunks.removeAll { $0.documentID == id }
        try persist()
    }

    func deleteCollection(id: UUID) throws {
        guard state.collections.first(where: { $0.id == id })?.isReadOnly == false else {
            throw NodusKnowledgeImportError.readOnlyCollection
        }
        let itemIDs = Set(state.items.filter { $0.collectionID == id }.map(\.id))
        state.collections.removeAll { $0.id == id }
        state.items.removeAll { $0.collectionID == id }
        state.chunks.removeAll { $0.collectionID == id || itemIDs.contains($0.documentID) }
        try persist()
    }

    func search(_ query: String, collectionIDs: Set<UUID>? = nil, topK: Int = 6) -> [NodusKnowledgeMatch] {
        NodusKnowledgeRetriever().retrieve(
            query: query, snapshot: state, collectionIDs: collectionIDs, topK: topK
        )
    }

    private static func bootstrapped(_ existing: NodusKnowledgeSnapshot) -> NodusKnowledgeSnapshot {
        var state = existing
        let version = "modula-core-knowledge-v1"
        if !state.collections.contains(where: { $0.version == version }) {
            let content = ModulaCoreKnowledgeV1.content
            let collection = NodusKnowledgeCollection(
                id: Self.modulaCoreCollectionID,
                name: "Modula Core",
                kind: .system,
                createdAt: ModulaCoreKnowledgeV1.generatedAt,
                updatedAt: ModulaCoreKnowledgeV1.generatedAt,
                version: version,
                sourceCommit: ModulaCoreKnowledgeV1.sourceCommit,
                contentHash: sha256(content),
                generationDate: ModulaCoreKnowledgeV1.generatedAt
            )
            state.collections.append(collection)
            let item = NodusKnowledgeItem(
                id: UUID(), collectionID: collection.id, title: "Modula Core Architecture",
                sourceType: .system,
                sourceName: "docs/architecture/{architecture,nodus,local-intelligence,security-boundary}.md",
                sourceURL: nil, text: content, contentHash: sha256(content),
                createdAt: ModulaCoreKnowledgeV1.generatedAt,
                updatedAt: ModulaCoreKnowledgeV1.generatedAt
            )
            state.items.append(item)
            state.chunks.append(contentsOf: NodusKnowledgeChunker.chunk(
                documentID: item.id, collectionID: collection.id, text: content
            ))
        }
        if !state.collections.contains(where: { $0.id == Self.myKnowledgeCollectionID }) {
            let now = Date()
            state.collections.append(NodusKnowledgeCollection(
                id: Self.myKnowledgeCollectionID, name: "My Knowledge", kind: .user,
                createdAt: now, updatedAt: now, version: nil, sourceCommit: nil,
                contentHash: nil, generationDate: nil
            ))
        }
        return state
    }

    @discardableResult
    private func addInternal(
        title: String,
        sourceType: NodusKnowledgeSourceType,
        sourceName: String,
        sourceURL: URL? = nil,
        text: String,
        collectionID: UUID,
        locations: [Int: String] = [:],
        now: Date
    ) throws -> NodusKnowledgeItem {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NodusKnowledgeImportError.emptyText }
        let item = NodusKnowledgeItem(
            id: UUID(), collectionID: collectionID,
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            sourceType: sourceType, sourceName: sourceName, sourceURL: sourceURL,
            text: clean, contentHash: Self.sha256(clean), createdAt: now, updatedAt: now
        )
        state.items.append(item)
        state.chunks.append(contentsOf: NodusKnowledgeChunker.chunk(
            documentID: item.id, collectionID: collectionID, text: clean, locations: locations
        ))
        if let index = state.collections.firstIndex(where: { $0.id == collectionID }) {
            state.collections[index].updatedAt = now
        }
        try persist()
        return item
    }

    private func persist() throws {
        let encoder = Self.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try files.saveData(try encoder.encode(state), filename: filename)
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
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

enum NodusKnowledgeChunker {
    static func chunk(
        documentID: UUID,
        collectionID: UUID,
        text: String,
        locations: [Int: String] = [:],
        targetCharacters: Int = 1_200,
        overlapCharacters: Int = 160
    ) -> [NodusKnowledgeChunk] {
        let paragraphs = text.components(separatedBy: "\n\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            chunks.append(current)
            current = ""
        }

        func appendOversized(_ paragraph: String) {
            var start = paragraph.startIndex
            while start < paragraph.endIndex {
                let end = paragraph.index(
                    start,
                    offsetBy: targetCharacters,
                    limitedBy: paragraph.endIndex
                ) ?? paragraph.endIndex
                chunks.append(String(paragraph[start ..< end]))
                guard end < paragraph.endIndex else { break }
                start = paragraph.index(
                    end,
                    offsetBy: -min(overlapCharacters, paragraph.distance(from: start, to: end))
                )
            }
        }

        for paragraph in paragraphs {
            if paragraph.count > targetCharacters {
                flushCurrent()
                appendOversized(paragraph)
                continue
            }
            if !current.isEmpty, current.count + paragraph.count + 2 > targetCharacters {
                chunks.append(current)
                let overlap = String(current.suffix(overlapCharacters))
                current = overlap + "\n\n" + paragraph
            } else {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        flushCurrent()
        if chunks.isEmpty, !text.isEmpty { chunks = [String(text.prefix(targetCharacters))] }
        return chunks.enumerated().map { ordinal, chunk in
            NodusKnowledgeChunk(
                id: UUID(), documentID: documentID, collectionID: collectionID,
                ordinal: ordinal, text: chunk, location: locations[ordinal]
            )
        }
    }
}

private enum ModulaCoreKnowledgeV1 {
    static let sourceCommit = "ff29669b06ad76f570c5da396d045112478e0f58"
    static let generatedAt = ISO8601DateFormatter().date(from: "2026-09-24T00:00:00Z")!
    static let content = """
    # Modula

    Modula is a modular native social and personal computing platform. It is an independent Modula product; it is not Meta and is not owned by Meta, OpenAI, Google, or Anthropic.

    # Nodus

    Nodus is Modula's on-device local intelligence model and runtime. Its provider identity is modula.nodus. Nodus R7 Experimental runs locally through MLX on supported physical Apple devices. R7 is an experimental candidate and is not approved for production shipping. Nodus is not OpenAI and must not invent corporate affiliations.

    # Modules and Runtime

    Modules extend Modula through a native-owned Module Runtime. The native shell owns authentication, navigation, authorization, privacy, and cross-module mediation. Modules do not receive account credentials. Module content cannot grant itself native authority.

    # Vault Notes

    Vault Notes is a Modula module for private notes. Its module surface owns its local feature UI while the Modula native shell retains global navigation, security, and capability authority.

    # GAIA

    GAIA is Modula's planning and assistance layer. It may coordinate proposed work, but its content is not authorization. Nodus is not GAIA, though Nodus may power local intelligence within wider GAIA experiences.

    # AKI

    AKI is Modula's decision and evidence fabric. It evaluates provenance, evidence, and decisions. Nodus is not AKI and cannot declare its own generated answer to be verified truth.

    # Governor

    The Governor is Modula's authorization boundary. Intelligence output, retrieved documents, and web pages are content, not authority. They cannot grant permissions, execute arbitrary capabilities, change policy, or alter model weights.

    # Local Intelligence

    ModulaIntelligence is the native, fail-closed provider and routing layer. Local-only requests never silently fall through to a remote AI provider. modula.nodus and apple.system are local provider identities. Search may retrieve online evidence through a separately configured provider, but Nodus generation remains local.

    # Knowledge, Memory, and Learning

    Knowledge is explicit source material. Memory is user-controlled persistent context. Conversation history is neither Knowledge nor Memory. Learning Candidates are reviewed evidence for a future training mission; they are not automatically training data. Nodus never rewrites its own weights while answering.
    """
}
