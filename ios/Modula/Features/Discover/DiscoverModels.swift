import Foundation

enum DiscoverLoadState: Equatable {
    case idle
    case loading
    case loaded
    case refreshing
    case loadingMore
    case failed(String)
}

struct DiscoverPerson: Identifiable, Hashable, Sendable {
    let id: String
    let handle: String
    let displayName: String
    let kind: String?
    let bio: String?
    let avatarURL: URL?
    let followerCount: Int?
    let followingCount: Int?
    let postCount: Int?
    let isFollowing: Bool
    let followsViewer: Bool
    let isVerified: Bool
    let joinedAt: Date?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var routeID: String { handle.isEmpty ? id : handle }

    var usefulness: Int {
        var score = 0
        if let bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 4 }
        if (postCount ?? 0) > 0 { score += 3 }
        if (followerCount ?? 0) > 0 { score += 2 }
        return score
    }
}

enum FollowState: String, Hashable, Sendable {
    case none
    case following
    case requested

    var title: String {
        switch self {
        case .none: "Follow"
        case .following: "Following"
        case .requested: "Requested"
        }
    }
}

extension DiscoverPerson {
    var followState: FollowState { isFollowing ? .following : .none }
}

struct DiscoverTopic: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let postCount: Int?
    let summary: String?

    var query: String { label }

    var postCountLabel: String? {
        guard let postCount else { return nil }
        return Self.formatCount(postCount) + " posts"
    }

    static func formatCount(_ value: Int) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        if value >= 10_000 {
            return String(format: "%.1fK", locale: posix, Double(value) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        }
        if value >= 1_000 {
            return String(format: "%.1fK", locale: posix, Double(value) / 1_000)
        }
        return "\(value)"
    }
}

enum DiscoverPostKind: String, Hashable, Sendable {
    case text, media, image, video, link, unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "text": self = .text
        case "media": self = .media
        case "image", "photo": self = .image
        case "video": self = .video
        case "link": self = .link
        default: self = .unknown
        }
    }
}

struct DiscoverPostMedia: Hashable, Sendable {
    let url: URL?
    let altText: String?
    let colour: String?
    let title: String?
}

struct DiscoverPost: Identifiable, Hashable, Sendable {
    let id: String
    let author: DiscoverPerson?
    let createdAt: Date?
    let text: String?
    let kind: DiscoverPostKind
    let media: DiscoverPostMedia?
    let likeCount: Int?
    let replyCount: Int?
    let audience: String?
}

struct DiscoverFeaturedModule: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: String?
    let catalogueID: String?
}

struct DiscoverDashboard: Hashable, Sendable {
    var people: [DiscoverPerson]
    var topics: [DiscoverTopic]
    var posts: [DiscoverPost]
    var featuredModules: [DiscoverFeaturedModule]
    var media: [DiscoverPostMedia]
}

struct DiscoverPage<Item: Hashable & Sendable>: Hashable, Sendable {
    var items: [Item]
    var nextCursor: String?
}

typealias PeoplePage = DiscoverPage<DiscoverPerson>
typealias TopicsPage = DiscoverPage<DiscoverTopic>
typealias PostsPage = DiscoverPage<DiscoverPost>
typealias ModulesPage = DiscoverPage<CatalogueProduct>

struct SearchHit: Identifiable, Hashable, Sendable {
    let id: String
    let entityType: String
    let title: String
    let excerpt: String?
    let score: Double?
    let handle: String?
    let person: DiscoverPerson?
    let post: DiscoverPost?
    let moduleID: String?
    let topic: DiscoverTopic?

    var destination: AppRoute? {
        switch entityType {
        case "profile":
            let routeID = person?.routeID ?? handle ?? id
            return .profile(routeID, .overview)
        case "post":
            return .post(id, .root)
        case "module", "module-release":
            if let moduleID { return .productHub(.module(moduleID, .overview)) }
            return nil
        default:
            return nil
        }
    }

    static func from(topic: DiscoverTopic) -> SearchHit {
        SearchHit(
            id: topic.id,
            entityType: "topic",
            title: topic.label,
            excerpt: topic.postCountLabel,
            score: topic.postCount.map(Double.init),
            handle: nil,
            person: nil,
            post: nil,
            moduleID: nil,
            topic: topic
        )
    }
}

struct SearchPage: Hashable, Sendable {
    var results: [SearchHit]
    var nextCursor: String?
}

struct PeopleFilters: Equatable, Hashable, Sendable {
    var followingOnly = false
    var newestFirst = false

    var isActive: Bool { followingOnly || newestFirst }
}

struct PostFilters: Equatable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all, text, media, links
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .text: "Text"
            case .media: "Photos"
            case .links: "Links"
            }
        }
    }

    var kind: Kind = .all
    var isActive: Bool { kind != .all }
}

struct ModuleFilters: Equatable, Hashable, Sendable {
    var installedOnly = false
    var firstPartyOnly = false
    var compatibleOnly = false

    var isActive: Bool { installedOnly || firstPartyOnly || compatibleOnly }
}

struct TopicFilters: Equatable, Hashable, Sendable {
    var isActive: Bool { false }
}

enum DiscoverPayloadDecoder {
    static func dashboard(from value: JSONValue) -> DiscoverDashboard {
        let people = (value["suggestedProfiles"]?.array ?? []).compactMap(person)
        let topics = (value["trendingTopics"]?.array ?? []).compactMap(topic)
        let featured = (value["featuredModules"]?.array ?? []).compactMap(featuredModule)
        let media = (value["media"]?.array ?? []).compactMap(mediaItem)
        return DiscoverDashboard(people: people, topics: topics, posts: [], featuredModules: featured, media: media)
    }

    static func searchPage(from value: JSONValue) -> SearchPage {
        let results = (value["results"]?.array ?? []).compactMap(searchHit)
        let cursor = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        return SearchPage(results: results, nextCursor: cursor)
    }

    static func postsPage(from value: JSONValue) -> PostsPage {
        let items: [JSONValue]
        if let array = value.array { items = array }
        else { items = value["items"]?.array ?? value["posts"]?.array ?? [] }
        let cursor = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        return PostsPage(items: items.compactMap(post), nextCursor: cursor)
    }

    static func person(_ value: JSONValue) -> DiscoverPerson? {
        let id = value["id"]?.string ?? value["accountId"]?.string ?? value["userId"]?.string
        let handle = value["handle"]?.string ?? value["primaryHandle"]?.string
        guard let id else { return nil }
        let display = value["displayName"]?.string ?? value["name"]?.string ?? handle ?? "Member"
        let verified = !(value["identityClaims"]?.array ?? []).isEmpty
            || value["verified"]?.bool == true
        return DiscoverPerson(
            id: id,
            handle: handle ?? id,
            displayName: display,
            kind: value["kind"]?.string,
            bio: emptyToNil(value["bio"]?.string),
            avatarURL: (value["avatarUrl"]?.string ?? value["avatar"]?.string).flatMap(URL.init(string:)),
            followerCount: value["followerCount"]?.int ?? value["follower_count"]?.int,
            followingCount: value["followingCount"]?.int ?? value["following_count"]?.int,
            postCount: value["postCount"]?.int ?? value["post_count"]?.int,
            isFollowing: value["isFollowing"]?.bool ?? false,
            followsViewer: value["followsViewer"]?.bool ?? false,
            isVerified: verified,
            joinedAt: decodeDate(value["joinedAt"]?.string ?? value["joined_at"]?.string)
        )
    }

    static func topic(_ value: JSONValue) -> DiscoverTopic? {
        let label = value["label"]?.string ?? value["name"]?.string ?? value["title"]?.string
        let id = value["id"]?.string ?? label
        guard let id, let label else { return nil }
        return DiscoverTopic(
            id: id,
            label: label,
            postCount: value["postCount"]?.int ?? value["post_count"]?.int,
            summary: value["description"]?.string ?? value["summary"]?.string
        )
    }

    static func post(_ value: JSONValue) -> DiscoverPost? {
        let id = value["id"]?.string ?? value["postId"]?.string
        guard let id else { return nil }
        let author = value["author"].flatMap(person)
        let mediaValue = value["media"]
        let media: DiscoverPostMedia?
        if let mediaValue {
            if let first = mediaValue.array?.first {
                media = mediaItem(first)
            } else {
                media = mediaItem(mediaValue)
            }
        } else {
            media = nil
        }
        return DiscoverPost(
            id: id,
            author: author,
            createdAt: decodeDate(value["createdAt"]?.string ?? value["created_at"]?.string),
            text: emptyToNil(value["text"]?.string ?? value["caption"]?.string),
            kind: DiscoverPostKind(parsing: value["kind"]?.string ?? value["type"]?.string),
            media: media,
            likeCount: value["likeCount"]?.int ?? value["like_count"]?.int,
            replyCount: value["replyCount"]?.int ?? value["reply_count"]?.int,
            audience: value["audience"]?.string
        )
    }

    static func featuredModule(_ value: JSONValue) -> DiscoverFeaturedModule? {
        let name = value["name"]?.string
        let rawID = value["id"]?.string ?? value["moduleId"]?.string
        guard let rawID, let name else { return nil }
        let declared = value["moduleId"]?.string
            ?? value["catalogueId"]?.string
            ?? value["canonicalModuleId"]?.string
        let catalogueID: String?
        if let declared, declared.contains(".") {
            catalogueID = declared
        } else if rawID.contains(".") {
            catalogueID = rawID
        } else {
            catalogueID = nil
        }
        return DiscoverFeaturedModule(id: rawID, name: name, status: value["status"]?.string, catalogueID: catalogueID)
    }

    static func mediaItem(_ value: JSONValue) -> DiscoverPostMedia? {
        let url = value["url"]?.string.flatMap(URL.init(string:))
        let title = value["title"]?.string ?? value["altText"]?.string
        let colour = value["colour"]?.string ?? value["color"]?.string
        if url == nil && title == nil && colour == nil { return nil }
        return DiscoverPostMedia(url: url, altText: value["altText"]?.string, colour: colour, title: title)
    }

    static func searchHit(_ value: JSONValue) -> SearchHit? {
        let entityType = value["entityType"]?.string ?? value["type"]?.string ?? ""
        let id = value["entityId"]?.string ?? value["id"]?.string
        let title = value["title"]?.string
        guard let id, let title else { return nil }
        let meta = value["metadata"]
        let handle = meta?["handle"]?.string
        let excerpt = emptyToNil(value["excerpt"]?.string)
        let person: DiscoverPerson?
        if entityType == "profile" {
            person = DiscoverPerson(
                id: id,
                handle: handle ?? id,
                displayName: title,
                kind: meta?["kind"]?.string,
                bio: excerpt == handle ? nil : excerpt,
                avatarURL: nil,
                followerCount: nil,
                followingCount: nil,
                postCount: nil,
                isFollowing: false,
                followsViewer: false,
                isVerified: false,
                joinedAt: decodeDate(value["createdAt"]?.string)
            )
        } else {
            person = nil
        }
        let post: DiscoverPost?
        if entityType == "post" {
            let author = DiscoverPerson(
                id: value["ownerId"]?.string ?? handle ?? "unknown",
                handle: handle ?? "",
                displayName: meta?["authorDisplayName"]?.string ?? handle ?? "Member",
                kind: nil,
                bio: nil,
                avatarURL: nil,
                followerCount: nil,
                followingCount: nil,
                postCount: nil,
                isFollowing: false,
                followsViewer: false,
                isVerified: false,
                joinedAt: nil
            )
            post = DiscoverPost(
                id: id,
                author: author,
                createdAt: decodeDate(value["createdAt"]?.string),
                text: excerpt,
                kind: DiscoverPostKind(parsing: meta?["kind"]?.string),
                media: nil,
                likeCount: nil,
                replyCount: nil,
                audience: meta?["audience"]?.string
            )
        } else {
            post = nil
        }
        let moduleID: String?
        if entityType == "module" || entityType == "module-release" {
            moduleID = id
        } else {
            moduleID = nil
        }
        return SearchHit(
            id: id,
            entityType: entityType,
            title: title,
            excerpt: excerpt,
            score: value["score"]?.number,
            handle: handle,
            person: person,
            post: post,
            moduleID: moduleID,
            topic: nil
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

extension DiscoverPost {
    /// Bridges Discover preview cards into the canonical SocialPost engagement store.
    func asSocialPost() -> SocialPost {
        let author = author.map {
            SocialAuthor(id: $0.id, handle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL)
        }
        let media: [SocialPostMedia] = {
            guard let media else { return [] }
            return [
                SocialPostMedia(
                    id: "\(id)-media",
                    url: media.url,
                    altText: media.altText,
                    kind: "image",
                    aspectRatio: nil
                )
            ]
        }()
        let kind: SocialPostKind = {
            switch self.kind {
            case .text: return .text
            case .media, .image: return media.isEmpty ? .text : .media
            case .video: return .video
            case .link: return .link
            case .unknown: return .unknown
            }
        }()
        return SocialPost(
            id: id,
            author: author,
            createdAt: createdAt ?? Date(),
            editedAt: nil,
            feed: "discover",
            text: text,
            kind: kind,
            visibility: PostVisibility(parsing: audience),
            audience: audience,
            media: media,
            link: nil,
            module: nil,
            glowColour: nil,
            engagement: PostEngagement(
                liked: false,
                saved: false,
                reposted: false,
                viewerReaction: nil,
                likeCount: likeCount ?? 0,
                replyCount: replyCount ?? 0,
                repostCount: 0,
                quoteCount: 0,
                reactionCount: likeCount ?? 0
            )
        )
    }
}
