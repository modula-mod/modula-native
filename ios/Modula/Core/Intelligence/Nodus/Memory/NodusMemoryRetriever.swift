import Foundation

struct NodusMemoryRetriever: Sendable {
    func retrieve(
        query: String,
        snapshot: NodusMemorySnapshot,
        conversationID: UUID?,
        topK: Int = 5
    ) -> [NodusMemoryMatch] {
        let queryTerms = terms(query)
        guard !queryTerms.isEmpty, topK > 0 else { return [] }
        return snapshot.items.compactMap { item -> NodusMemoryMatch? in
            guard item.active else { return nil }
            if item.scope == .conversation, item.conversationID != conversationID { return nil }
            let memoryTerms = terms(item.text)
            let overlap = Set(queryTerms).intersection(memoryTerms)
            guard !overlap.isEmpty else { return nil }
            var score = Double(overlap.count) / Double(max(1, Set(queryTerms).count))
            if item.kind == .instruction || item.kind == .preference { score += 0.15 }
            if item.scope == .conversation { score += 0.1 }
            return NodusMemoryMatch(item: item, relevance: score)
        }
        .sorted { lhs, rhs in
            if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
            return lhs.item.updatedAt > rhs.item.updatedAt
        }
        .prefix(topK)
        .map { $0 }
    }

    private func terms(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

