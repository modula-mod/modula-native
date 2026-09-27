import CoreGraphics
import Foundation

typealias SocialPostID = String
typealias SocialCommentID = String

enum SocialPostKind: String, Hashable, Sendable {
    case text, media, link, module
    case video, carousel, poll, audio, movie
    case unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "text": self = .text
        case "media", "image", "photo": self = .media
        case "link": self = .link
        case "module": self = .module
        case "video": self = .video
        case "carousel": self = .carousel
        case "poll": self = .poll
        case "audio", "music": self = .audio
        case "movie": self = .movie
        default: self = .unknown
        }
    }

    /// Kinds Greenfield currently emits with truthful payloads.
    var isFullyRenderable: Bool {
        switch self {
        case .text, .media, .link, .module, .carousel: true
        case .video, .poll, .audio, .movie, .unknown: false
        }
    }
}

enum SocialReaction: String, Hashable, Sendable, CaseIterable {
    case like, love, laugh, fire, celebrate, insightful, support, curious

    init(parsing raw: String?) {
        let key = (raw ?? "").lowercased()
        self = Self(rawValue: key) ?? .like
    }

    var accessibilityName: String {
        switch self {
        case .like: "Like"
        case .love: "Love"
        case .laugh: "Laugh"
        case .fire: "Fire"
        case .celebrate: "Celebrate"
        case .insightful: "Insightful"
        case .support: "Support"
        case .curious: "Curious"
        }
    }

    var systemImage: String {
        switch self {
        case .like: "heart.fill"
        case .love: "heart.circle.fill"
        case .laugh: "face.smiling.fill"
        case .fire: "flame.fill"
        case .celebrate: "party.popper.fill"
        case .insightful: "lightbulb.fill"
        case .support: "hand.raised.fill"
        case .curious: "questionmark.circle.fill"
        }
    }

    /// Reactions the current like-toggle HTTP surface can commit.
    static var networkSupported: [SocialReaction] { [.like] }
}

enum PostVisibility: String, Hashable, Sendable {
    case `public`, followers, `private`, unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "public": self = .public
        case "followers": self = .followers
        case "private": self = .private
        default: self = .unknown
        }
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
    let aspectRatio: CGFloat?
    let previewURL: URL?
    let thumbnailURL: URL?
    let mimeType: String?
    let filename: String?
    let byteSize: Int64?
    let width: Int?
    let height: Int?
    let duration: TimeInterval?
    let pageCount: Int?
    let title: String?
    let creator: String?

    init(
        id: String,
        url: URL?,
        altText: String?,
        kind: String,
        aspectRatio: CGFloat?,
        previewURL: URL? = nil,
        thumbnailURL: URL? = nil,
        mimeType: String? = nil,
        filename: String? = nil,
        byteSize: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil,
        duration: TimeInterval? = nil,
        pageCount: Int? = nil,
        title: String? = nil,
        creator: String? = nil
    ) {
        self.id = id
        self.url = url
        self.altText = altText
        self.kind = kind
        self.aspectRatio = aspectRatio
        self.previewURL = previewURL
        self.thumbnailURL = thumbnailURL
        self.mimeType = mimeType
        self.filename = filename
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.duration = duration
        self.pageCount = pageCount
        self.title = title
        self.creator = creator
    }

    var isImage: Bool { kind == "image" || kind.isEmpty }
    var isVideo: Bool { kind == "video" }
}

struct SocialPostLink: Hashable, Sendable {
    let url: URL?
    let title: String?
    let description: String?
    let domain: String?
    let imageURL: URL?
}

struct SocialPostModule: Hashable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let publisher: String?
}

struct PostEngagement: Hashable, Sendable {
    var liked: Bool
    var saved: Bool
    var reposted: Bool
    var viewerReaction: SocialReaction?
    var likeCount: Int
    var replyCount: Int
    var repostCount: Int
    var quoteCount: Int
    var reactionCount: Int
    var reactionSummary: ReactionSummary? = nil
}

struct SocialPost: Identifiable, Hashable, Sendable {
    let id: SocialPostID
    let author: SocialAuthor?
    let createdAt: Date
    let editedAt: Date?
    let feed: String?
    let text: String?
    let kind: SocialPostKind
    let visibility: PostVisibility
    let audience: String?
    let media: [SocialPostMedia]
    let link: SocialPostLink?
    let module: SocialPostModule?
    let glowColour: String?
    var engagement: PostEngagement

    var liked: Bool {
        get { engagement.liked }
        set { engagement.liked = newValue }
    }
    var saved: Bool {
        get { engagement.saved }
        set { engagement.saved = newValue }
    }
    var reposted: Bool {
        get { engagement.reposted }
        set { engagement.reposted = newValue }
    }
    var viewerReaction: SocialReaction? {
        get { engagement.viewerReaction }
        set { engagement.viewerReaction = newValue }
    }
    var likeCount: Int {
        get { engagement.likeCount }
        set { engagement.likeCount = newValue }
    }
    var replyCount: Int {
        get { engagement.replyCount }
        set { engagement.replyCount = newValue }
    }
    var repostCount: Int {
        get { engagement.repostCount }
        set { engagement.repostCount = newValue }
    }
    var quoteCount: Int {
        get { engagement.quoteCount }
        set { engagement.quoteCount = newValue }
    }
    var reactionCount: Int {
        get { engagement.reactionCount }
        set { engagement.reactionCount = newValue }
    }

    var hasMedia: Bool { !media.isEmpty }
    var primaryMedia: SocialPostMedia? { media.first }
    var isEdited: Bool {
        guard let editedAt else { return false }
        return abs(editedAt.timeIntervalSince(createdAt)) > 1
    }

    var shareURL: URL {
        URL(string: "https://modula.digital/post/\(id)")!
    }

    var voiceOverSummary: String {
        let who = author?.displayName ?? "Someone"
        let when = ActivityRelativeTime.string(from: createdAt)
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (body?.isEmpty == false) ? "“\(body!)”" : "\(kind.rawValue) post"
        var parts = ["\(who), \(when).", content]
        if hasMedia {
            if let alt = primaryMedia?.altText, !alt.isEmpty {
                parts.append(alt)
            } else if let name = author?.displayName {
                parts.append("Photo attached to \(name)'s post")
            } else {
                parts.append("Photo attached")
            }
        }
        var engagementBits: [String] = []
        if reactionCount > 0 || likeCount > 0 {
            engagementBits.append("\(max(reactionCount, likeCount)) reactions")
        }
        if replyCount > 0 { engagementBits.append("\(replyCount) comments") }
        if repostCount > 0 { engagementBits.append("\(repostCount) reposts") }
        if !engagementBits.isEmpty {
            parts.append(engagementBits.joined(separator: ", "))
        }
        return parts.joined(separator: " ")
    }

    mutating func apply(_ other: PostEngagement) {
        engagement = other
    }

    func mergingEngagement(from other: SocialPost) -> SocialPost {
        var copy = self
        copy.engagement = other.engagement
        return copy
    }
}

struct SocialComment: Identifiable, Hashable, Sendable {
    let id: SocialCommentID
    let postID: SocialPostID
    let author: SocialAuthor?
    let createdAt: Date
    let editedAt: Date?
    let text: String
    let parentID: SocialCommentID?
    let replyCount: Int
    var liked: Bool
    var likeCount: Int
    var isPending: Bool

    var isReply: Bool { parentID != nil }
    var isEdited: Bool {
        guard let editedAt else { return false }
        return abs(editedAt.timeIntervalSince(createdAt)) > 1
    }

    var voiceOverSummary: String {
        let who = author?.displayName ?? "Someone"
        let when = ActivityRelativeTime.string(from: createdAt)
        var parts = [who, when, "“\(text)”"]
        if likeCount > 0 { parts.append("\(likeCount) likes") }
        return parts.joined(separator: ". ")
    }
}

struct CommentPage: Sendable, Equatable {
    var items: [SocialComment]
    var nextCursor: String?
    var hasMore: Bool
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

    static func commentPage(from value: JSONValue, postID: SocialPostID) -> CommentPage {
        let payload = value["data"] ?? value
        let items: [JSONValue]
        if let array = payload.array {
            items = array
        } else {
            items = payload["items"]?.array ?? payload["comments"]?.array ?? []
        }
        let nextCursor = payload["nextCursor"]?.string ?? payload["next_cursor"]?.string
            ?? value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let hasMore = payload["hasMore"]?.bool
            ?? payload["has_more"]?.bool
            ?? value["hasMore"]?.bool
            ?? value["has_more"]?.bool
            ?? (nextCursor != nil)
        return CommentPage(
            items: items.compactMap { comment($0, fallbackPostID: postID) },
            nextCursor: nextCursor,
            hasMore: hasMore
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
                domain: emptyToNil($0["domain"]?.string ?? $0["host"]?.string),
                imageURL: ($0["imageUrl"]?.string ?? $0["image"]?.string ?? $0["thumbnail"]?.string)
                    .flatMap(URL.init(string:))
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
                status: moduleValue["status"]?.string,
                publisher: moduleValue["publisher"]?.string ?? moduleValue["publisherName"]?.string
            )
        }()
        let reactionRaw = value["viewerReaction"]?.string ?? value["viewer_reaction"]?.string
        let createdAt = decodeDate(value["createdAt"]?.string ?? value["created_at"]?.string) ?? Date()
        let editedAt = decodeDate(value["editedAt"]?.string ?? value["edited_at"]?.string ?? value["updatedAt"]?.string)
        let audience = value["audience"]?.string
        let kind = SocialPostKind(parsing: value["kind"]?.string ?? value["type"]?.string)
        let resolvedKind: SocialPostKind = {
            if kind == .media, media.count > 1 { return .carousel }
            return kind
        }()
        return SocialPost(
            id: id,
            author: author,
            createdAt: createdAt,
            editedAt: editedAt,
            feed: value["feed"]?.string,
            text: emptyToNil(value["text"]?.string ?? value["caption"]?.string),
            kind: resolvedKind,
            visibility: PostVisibility(parsing: audience),
            audience: audience,
            media: media,
            link: link,
            module: module,
            glowColour: value["glowColour"]?.string ?? value["glow_colour"]?.string,
            engagement: PostEngagement(
                liked: value["liked"]?.bool ?? false,
                saved: value["saved"]?.bool ?? false,
                reposted: value["reposted"]?.bool ?? false,
                viewerReaction: reactionRaw.map { SocialReaction(parsing: $0) },
                likeCount: value["likeCount"]?.int ?? value["like_count"]?.int ?? 0,
                replyCount: value["replyCount"]?.int ?? value["reply_count"]?.int ?? 0,
                repostCount: value["repostCount"]?.int ?? value["repost_count"]?.int ?? 0,
                quoteCount: value["quoteCount"]?.int ?? value["quote_count"]?.int ?? 0,
                reactionCount: value["reactionCount"]?.int ?? value["reaction_count"]?.int ?? 0,
                reactionSummary: ReactionSummary.decode(from: value["reactionSummary"] ?? value["reactions"] ?? value["reactionBreakdown"] ?? value["byType"])
            )
        )
    }

    static func comment(_ value: JSONValue, fallbackPostID: SocialPostID) -> SocialComment? {
        let id = value["id"]?.string
            ?? value["commentId"]?.string
            ?? value["comment_id"]?.string
        guard let id else { return nil }
        let deleted = value["deleted"]?.bool == true
            || value["deleted_at"]?.string != nil
            || value["deletedAt"]?.string != nil
        let text = emptyToNil(value["text"]?.string ?? value["body"]?.string) ?? ""
        guard !text.isEmpty || deleted else { return nil }
        return SocialComment(
            id: id,
            postID: value["postId"]?.string ?? value["post_id"]?.string ?? fallbackPostID,
            author: value["author"].flatMap(author) ?? authorFromActorID(
                value["author_actor_id"]?.string ?? value["authorActorId"]?.string
            ),
            createdAt: decodeDate(value["createdAt"]?.string ?? value["created_at"]?.string) ?? Date(),
            editedAt: decodeDate(value["editedAt"]?.string ?? value["edited_at"]?.string ?? value["updated_at"]?.string),
            text: text,
            parentID: value["parentId"]?.string
                ?? value["parent_id"]?.string
                ?? value["parent_comment_id"]?.string
                ?? value["parentCommentId"]?.string,
            replyCount: value["replyCount"]?.int ?? value["reply_count"]?.int ?? 0,
            liked: value["liked"]?.bool ?? false,
            likeCount: value["likeCount"]?.int ?? value["like_count"]?.int ?? 0,
            isPending: false
        )
    }

    /// Live Greenfield comments currently emit `author_actor_id` without a nested profile object.
    private static func authorFromActorID(_ raw: String?) -> SocialAuthor? {
        guard let raw, !raw.isEmpty else { return nil }
        return SocialAuthor(id: raw, handle: raw, displayName: raw, avatarURL: nil)
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
            avatarURL: (value["avatarUri"]?.string ?? value["avatarUrl"]?.string ?? value["avatar"]?.string).flatMap(URL.init(string:))
        )
    }

    static func media(_ value: JSONValue, fallbackID: String) -> SocialPostMedia? {
        let url = value["url"]?.string.flatMap(URL.init(string:))
        let alt = emptyToNil(value["altText"]?.string ?? value["alt_text"]?.string)
        let kind = value["kind"]?.string ?? value["type"]?.string ?? "image"
        if url == nil && alt == nil { return nil }
        let ratio: CGFloat?
        if let w = value["width"]?.number, let h = value["height"]?.number, h != 0 {
            ratio = CGFloat(w / h)
        } else if let aspect = value["aspectRatio"]?.number ?? value["aspect_ratio"]?.number {
            ratio = CGFloat(aspect)
        } else {
            ratio = nil
        }
        return SocialPostMedia(
            id: value["id"]?.string ?? fallbackID,
            url: url,
            altText: alt,
            kind: kind,
            aspectRatio: ratio,
            previewURL: (value["previewUrl"]?.string ?? value["preview_url"]?.string).flatMap(URL.init(string:)),
            thumbnailURL: (value["thumbnailUrl"]?.string ?? value["thumbnail_url"]?.string ?? value["posterUrl"]?.string).flatMap(URL.init(string:)),
            mimeType: emptyToNil(value["mimeType"]?.string ?? value["mime_type"]?.string ?? value["contentType"]?.string),
            filename: emptyToNil(value["filename"]?.string ?? value["fileName"]?.string ?? value["name"]?.string),
            byteSize: (value["byteSize"]?.int ?? value["byte_size"]?.int ?? value["size"]?.int).map(Int64.init),
            width: value["width"]?.int ?? value["dimensions"]?["width"]?.int,
            height: value["height"]?.int ?? value["dimensions"]?["height"]?.int,
            duration: value["duration"]?.number ?? value["durationMs"]?.number.map { $0 / 1_000 },
            pageCount: value["pageCount"]?.int ?? value["page_count"]?.int ?? value["pages"]?.int,
            title: emptyToNil(value["title"]?.string),
            creator: emptyToNil(value["creator"]?.string ?? value["artist"]?.string)
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
