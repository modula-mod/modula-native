import Foundation

typealias SocialPostID = String

enum SocialPostKind: String, Hashable, Sendable {
    case text, media, link, module, unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "text": self = .text
        case "media", "image", "photo": self = .media
        case "link": self = .link
        case "module": self = .module
        default: self = .unknown
        }
    }
}

enum SocialReaction: String, Hashable, Sendable, CaseIterable {
    case like, love, laugh, fire, celebrate, insightful, support, curious

    init(parsing raw: String?) {
        let key = (raw ?? "").lowercased()
        self = Self(rawValue: key) ?? .like
    }
}

struct SocialAuthor: Identifiable, Hashable, Sendable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: URL?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var routeID: String { handle.isEmpty ? id : handle }
}

struct SocialPostMedia: Hashable, Sendable, Identifiable {
    let id: String
    let url: URL?
    let altText: String?
    let kind: String

    var isImage: Bool { kind == "image" || kind.isEmpty }
}

struct SocialPostLink: Hashable, Sendable {
    let url: URL?
    let title: String?
    let description: String?
    let domain: String?
}

struct SocialPostModule: Hashable, Sendable {
    let id: String
    let name: String?
    let status: String?
}

struct SocialPost: Identifiable, Hashable, Sendable {
    let id: SocialPostID
    let author: SocialAuthor?
    let createdAt: Date
    let feed: String?
    let text: String?
    let kind: SocialPostKind
    let audience: String?
    let media: [SocialPostMedia]
    let link: SocialPostLink?
    let module: SocialPostModule?
    let glowColour: String?
    var liked: Bool
    var saved: Bool
    var reposted: Bool
    var viewerReaction: SocialReaction?
    var likeCount: Int
    var replyCount: Int
    var repostCount: Int
    var quoteCount: Int
    var reactionCount: Int

    var hasMedia: Bool { !media.isEmpty }
    var primaryMedia: SocialPostMedia? { media.first }

    var voiceOverSummary: String {
        let who = author?.displayName ?? "Someone"
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (body?.isEmpty == false) ? body! : kind.rawValue + " post"
        return "\(who). \(content)."
    }
}

struct HomePage: Sendable, Equatable {
    var items: [SocialPost]
    var nextCursor: String?
    var hasMore: Bool
    var rankingVersion: String?
}

enum FeedSummarySource: Hashable, Sendable {
    case aggregate
    case agent
}

struct FeedSummary: Hashable, Sendable {
    let source: FeedSummarySource
    let postCount: Int
    let likeCount: Int
    let replyCount: Int
    let mediaCount: Int
    let moduleCount: Int
    let authorNames: [String]
    let highlights: [String]
    let rankingVersion: String?
    let generatedAt: Date

    static func aggregate(from posts: [SocialPost], rankingVersion: String?) -> FeedSummary {
        let likes = posts.reduce(0) { $0 + $1.likeCount }
        let replies = posts.reduce(0) { $0 + $1.replyCount }
        let media = posts.filter(\.hasMedia).count
        let modules = posts.filter { $0.kind == .module || $0.module != nil }.count
        var counts: [String: Int] = [:]
        for post in posts {
            if let name = post.author?.displayName {
                counts[name, default: 0] += 1
            }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var highlights: [String] = []
        if !posts.isEmpty { highlights.append("\(posts.count) posts in loaded window") }
        if likes > 0 { highlights.append("\(likes) likes") }
        if replies > 0 { highlights.append("\(replies) replies") }
        if media > 0 { highlights.append("\(media) with media") }
        if modules > 0 { highlights.append("\(modules) module updates") }
        return FeedSummary(
            source: .aggregate,
            postCount: posts.count,
            likeCount: likes,
            replyCount: replies,
            mediaCount: media,
            moduleCount: modules,
            authorNames: Array(top),
            highlights: highlights,
            rankingVersion: rankingVersion,
            generatedAt: Date()
        )
    }
}

enum SocialPayloadDecoder {
    static func homePage(from value: JSONValue) -> HomePage {
        let items: [JSONValue]
        if let array = value.array {
            items = array
        } else {
            items = value["items"]?.array ?? value["posts"]?.array ?? []
        }
        let nextCursor = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let hasMore = value["hasMore"]?.bool
            ?? value["has_more"]?.bool
            ?? (nextCursor != nil)
        let ranking = value["rankingVersion"]?.string ?? value["ranking_version"]?.string
        return HomePage(
            items: items.compactMap(post),
            nextCursor: nextCursor,
            hasMore: hasMore,
            rankingVersion: ranking
        )
    }

    static func post(_ value: JSONValue) -> SocialPost? {
        let id = value["id"]?.string ?? value["postId"]?.string
        guard let id else { return nil }
        let author = value["author"].flatMap(author)
        let mediaValues = value["media"]?.array ?? []
        let media = mediaValues.enumerated().compactMap { index, item in media(item, fallbackID: "\(id)-\(index)") }
        let linkValue = value["link"]
        let link: SocialPostLink? = linkValue.map {
            SocialPostLink(
                url: $0["url"]?.string.flatMap(URL.init(string:)),
                title: emptyToNil($0["title"]?.string),
                description: emptyToNil($0["description"]?.string ?? $0["summary"]?.string),
                domain: emptyToNil($0["domain"]?.string ?? $0["host"]?.string)
            )
        }
        let moduleValue = value["module"]
        let module: SocialPostModule? = {
            guard let moduleValue else { return nil }
            let name = moduleValue["name"]?.string
            let moduleID = moduleValue["id"]?.string
                ?? moduleValue["moduleId"]?.string
                ?? moduleValue["catalogueId"]?.string
                ?? name
            guard let moduleID else { return nil }
            return SocialPostModule(
                id: moduleID,
                name: name,
                status: moduleValue["status"]?.string
            )
        }()
        let reactionRaw = value["viewerReaction"]?.string ?? value["viewer_reaction"]?.string
        return SocialPost(
            id: id,
            author: author,
            createdAt: decodeDate(value["createdAt"]?.string ?? value["created_at"]?.string) ?? Date(),
            feed: value["feed"]?.string,
            text: emptyToNil(value["text"]?.string ?? value["caption"]?.string),
            kind: SocialPostKind(parsing: value["kind"]?.string ?? value["type"]?.string),
            audience: value["audience"]?.string,
            media: media,
            link: link,
            module: module,
            glowColour: value["glowColour"]?.string ?? value["glow_colour"]?.string,
            liked: value["liked"]?.bool ?? false,
            saved: value["saved"]?.bool ?? false,
            reposted: value["reposted"]?.bool ?? false,
            viewerReaction: reactionRaw.map { SocialReaction(parsing: $0) },
            likeCount: value["likeCount"]?.int ?? value["like_count"]?.int ?? 0,
            replyCount: value["replyCount"]?.int ?? value["reply_count"]?.int ?? 0,
            repostCount: value["repostCount"]?.int ?? value["repost_count"]?.int ?? 0,
            quoteCount: value["quoteCount"]?.int ?? value["quote_count"]?.int ?? 0,
            reactionCount: value["reactionCount"]?.int ?? value["reaction_count"]?.int ?? 0
        )
    }

    static func author(_ value: JSONValue) -> SocialAuthor? {
        let id = value["id"]?.string ?? value["accountId"]?.string ?? value["userId"]?.string
        guard let id else { return nil }
        let handle = value["handle"]?.string ?? value["primaryHandle"]?.string ?? id
        let display = value["displayName"]?.string ?? value["name"]?.string ?? handle
        return SocialAuthor(
            id: id,
            handle: handle,
            displayName: display,
            avatarURL: (value["avatarUrl"]?.string ?? value["avatar"]?.string).flatMap(URL.init(string:))
        )
    }

    static func media(_ value: JSONValue, fallbackID: String) -> SocialPostMedia? {
        let url = value["url"]?.string.flatMap(URL.init(string:))
        let alt = emptyToNil(value["altText"]?.string ?? value["alt_text"]?.string)
        let kind = value["kind"]?.string ?? value["type"]?.string ?? "image"
        if url == nil && alt == nil { return nil }
        return SocialPostMedia(
            id: value["id"]?.string ?? fallbackID,
            url: url,
            altText: alt,
            kind: kind
        )
    }

    static func decodeDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
