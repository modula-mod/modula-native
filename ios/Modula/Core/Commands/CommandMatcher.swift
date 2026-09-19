import Foundation

/// Deterministic command ranking. Not AI. No third-party fuzzy library.
enum CommandMatcher {
    static func match(
        query: String,
        in commands: [ModulaCommand],
        recentIDs: [CommandID] = [],
        limit: Int = 40
    ) -> [CommandMatch] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return [] }

        let recentBoost: [CommandID: Int] = Dictionary(
            uniqueKeysWithValues: recentIDs.enumerated().map { ($0.element, max(0, 12 - $0.offset)) }
        )

        var matches: [CommandMatch] = []
        matches.reserveCapacity(min(commands.count, limit * 2))

        for command in commands {
            guard command.availability == .available || command.availability == .requiresSignIn else { continue }
            let score = score(command: command, query: normalized) + (recentBoost[command.id] ?? 0)
            if score > 0 {
                matches.append(CommandMatch(command: command, score: score))
            }
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.command.title.localizedCaseInsensitiveCompare($1.command.title) == .orderedAscending
        }
        if matches.count > limit {
            matches = Array(matches.prefix(limit))
        }
        return matches
    }

    static func score(command: ModulaCommand, query: String) -> Int {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }

        var best = 0
        let candidates = ([command.title, command.subtitle].compactMap { $0 } + command.aliases)
            .map(normalize)
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if candidate == q {
                best = max(best, 100)
                continue
            }
            if candidate.hasPrefix(q) {
                best = max(best, 80)
                continue
            }
            if wordPrefix(candidate, query: q) {
                best = max(best, 65)
                continue
            }
            if candidate.contains(q) {
                best = max(best, 40)
                continue
            }
            if simpleFuzzy(candidate, query: q) {
                best = max(best, 20)
            }
        }
        return best
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func wordPrefix(_ candidate: String, query: String) -> Bool {
        let words = candidate.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        return words.contains { $0.hasPrefix(query) }
    }

    /// Predictable single-gap fuzzy: query characters appear in order with at most one skip in candidate.
    private static func simpleFuzzy(_ candidate: String, query: String) -> Bool {
        guard query.count >= 2, candidate.count >= query.count else { return false }
        let c = Array(candidate)
        let q = Array(query)
        var ci = 0
        var qi = 0
        var skips = 0
        while ci < c.count && qi < q.count {
            if c[ci] == q[qi] {
                ci += 1
                qi += 1
            } else {
                skips += 1
                if skips > 1 { return false }
                ci += 1
            }
        }
        return qi == q.count
    }
}
