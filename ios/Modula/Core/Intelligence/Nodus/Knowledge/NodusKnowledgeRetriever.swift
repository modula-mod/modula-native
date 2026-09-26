import Foundation

struct NodusKnowledgeRetriever: Sendable {
    func retrieve(
        query: String,
        snapshot: NodusKnowledgeSnapshot,
        collectionIDs: Set<UUID>? = nil,
        topK: Int = 6
    ) -> [NodusKnowledgeMatch] {
        let queryTerms = Self.terms(query)
        guard !queryTerms.isEmpty, topK > 0 else { return [] }
        let itemByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        let collectionByID = Dictionary(uniqueKeysWithValues: snapshot.collections.map { ($0.id, $0) })
        let candidates = snapshot.chunks.filter { collectionIDs == nil || collectionIDs!.contains($0.collectionID) }
        let documentFrequency = Dictionary(uniqueKeysWithValues: queryTerms.map { term in
            (term, candidates.reduce(0) { $0 + (Self.terms($1.text).contains(term) ? 1 : 0) })
        })
        let averageLength = max(1, Double(candidates.map { Self.terms($0.text).count }.reduce(0, +)) / Double(max(1, candidates.count)))
        return candidates.compactMap { chunk -> NodusKnowledgeMatch? in
            guard let item = itemByID[chunk.documentID], let collection = collectionByID[chunk.collectionID] else { return nil }
            let terms = Self.terms(chunk.text)
            guard !terms.isEmpty else { return nil }
            var score = 0.0
            for queryTerm in queryTerms {
                let frequency = Double(terms.filter { $0 == queryTerm }.count)
                guard frequency > 0 else { continue }
                let df = Double(documentFrequency[queryTerm] ?? 0)
                let idf = log(1 + (Double(candidates.count) - df + 0.5) / (df + 0.5))
                let lengthFactor = 1.2 * (0.25 + 0.75 * Double(terms.count) / averageLength)
                score += idf * (frequency * 2.2) / (frequency + lengthFactor)
            }
            guard score > 0 else { return nil }
            return NodusKnowledgeMatch(chunk: chunk, item: item, collection: collection, relevance: score)
        }
        .sorted { $0.relevance > $1.relevance }
        .prefix(topK)
        .map { $0 }
    }

    private static func terms(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

