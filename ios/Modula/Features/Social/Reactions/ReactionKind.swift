import Foundation

/// Preferred Modula reaction vocabulary. Backend identifiers are semantic strings, not emoji.
enum ReactionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case like
    case love
    case laugh
    case wow
    case support
    case sad
    case angry

    var title: String {
        switch self {
        case .like: "Like"
        case .love: "Love"
        case .laugh: "Laugh"
        case .wow: "Wow"
        case .support: "Support"
        case .sad: "Sad"
        case .angry: "Angry"
        }
    }

    var symbolName: String {
        switch self {
        case .like: "hand.thumbsup.fill"
        case .love: "heart.fill"
        case .laugh: "face.smiling.fill"
        case .wow: "star.fill"
        case .support: "hand.raised.fill"
        case .sad: "cloud.rain.fill"
        case .angry: "bolt.fill"
        }
    }

    var glyph: String {
        switch self {
        case .like: "👍"
        case .love: "❤️"
        case .laugh: "😂"
        case .wow: "😮"
        case .support: "🫶"
        case .sad: "😢"
        case .angry: "😡"
        }
    }

    init(parsing raw: String?) {
        let key = (raw ?? "").lowercased()
        if let value = ReactionKind(rawValue: key) {
            self = value
            return
        }
        switch key {
        case "fire": self = .wow
        case "celebrate": self = .love
        case "insightful": self = .wow
        case "curious": self = .wow
        default: self = .like
        }
    }

    var socialReaction: SocialReaction {
        switch self {
        case .like: .like
        case .love: .love
        case .laugh: .laugh
        case .wow: .fire
        case .support: .support
        case .sad: .like
        case .angry: .like
        }
    }

    static func from(social: SocialReaction) -> ReactionKind {
        switch social {
        case .like: .like
        case .love: .love
        case .laugh: .laugh
        case .fire, .insightful, .curious: .wow
        case .celebrate: .love
        case .support: .support
        }
    }
}

struct ReactionSummary: Hashable, Sendable {
    var total: Int
    var viewerReaction: ReactionKind?
    var breakdown: [ReactionKind: Int]

    static let empty = ReactionSummary(total: 0, viewerReaction: nil, breakdown: [:])

    /// Decode only from explicit payload. Never fabricate from visible people.
    static func decode(from value: JSONValue?) -> ReactionSummary? {
        guard let value else { return nil }
        let breakdownValue = value["breakdown"]
            ?? value["reactionBreakdown"]
            ?? value["byType"]
            ?? value["by_type"]
        if let breakdownValue {
            var breakdown: [ReactionKind: Int] = [:]
            if case .object(let object) = breakdownValue {
                for (key, count) in object {
                    if let amount = count.int {
                        breakdown[ReactionKind(parsing: key)] = amount
                    }
                }
            }
            let viewer = (value["viewerReaction"]?.string ?? value["viewer_reaction"]?.string).map { ReactionKind(parsing: $0) }
            let total = value["total"]?.int ?? breakdown.values.reduce(0, +)
            return ReactionSummary(total: total, viewerReaction: viewer, breakdown: breakdown)
        }
        return nil
    }

    func count(for kind: ReactionKind) -> Int {
        breakdown[kind] ?? 0
    }

    var presentKinds: [ReactionKind] {
        ReactionKind.allCases.filter { count(for: $0) > 0 }
    }
}

enum ReactionBackendCapabilities {
    /// GET `/v1/posts/:id/reactions` is live (`viewerReaction`, `total`, `byType`).
    /// Mutation (PUT/DELETE) is still like-toggle only until authenticated write is verified.
    static let multiReactionHTTP = false
    static let breakdownHTTP = true
    static let reactionsListHTTP = false
}
