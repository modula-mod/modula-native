import Foundation

struct NodusFreshnessClassifier: Sendable {
    func classify(_ question: String, referenceDate: Date = Date()) -> NodusFreshness {
        let normalized = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let currentMarkers = [
            "today", "right now", "currently", "current ", "latest", "newest", "yesterday",
            "this week", "weather", "news", "stock price", "bitcoin worth", "exchange rate",
            "prime minister", "president", "ceo of", "version of ios", "won the match",
        ]
        if currentMarkers.contains(where: normalized.contains) { return .currentDataRequired }

        let staleMarkers = ["recent", "modern", "supported version", "available model", "market leader"]
        if staleMarkers.contains(where: normalized.contains) { return .possiblyStale }

        let unknownMarkers = ["undocumented", "unpublished", "unknown protocol", "unidentified", "unspecified source"]
        if unknownMarkers.contains(where: normalized.contains) { return .unknown }

        let stableMarkers = [
            "explain", "define", "what causes", "what is photosynthesis", "capital of",
            "difference between", "calculate", "summarize", "rewrite", "classify",
        ]
        if stableMarkers.contains(where: normalized.contains) { return .stable }
        return .stable
    }
}
