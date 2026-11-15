import Foundation
import Observation

/// Communities are a shipped GreenField capability. This invariant remains typed so
/// older deep links and the developer diagnostics entry do not need a second route.
enum CommunityFeatureFlags {
    static var isEnabled: Bool { true }

    static func isEnabled(defaults _: UserDefaults, release _: Bool) -> Bool { true }
}

enum CommunityRoute: String, CaseIterable, Codable, Hashable, Identifiable {
    case hub
    case forYou = "for-you"
    case following
    case communities
    case topics
    case creators
    case builders
    case events
    case modulaBuilders = "modula-builders"
    case settings
    case poll
    case event

    var id: String { rawValue }

    var isHub: Bool {
        switch self {
        case .modulaBuilders, .settings, .poll, .event: false
        default: true
        }
    }

    var hubScope: CommunityHubScope? {
        switch self {
        case .hub, .forYou: .forYou
        case .following: .following
        case .communities: .communities
        case .topics: .topics
        case .creators: .creators
        case .builders: .builders
        case .events: .events
        default: nil
        }
    }

    var navigationTitle: String {
        switch self {
        case .settings: "Community Settings"
        case .poll: "Community poll"
        case .event: "Community Event"
        case .modulaBuilders: "Community"
        default: ""
        }
    }
}

enum CommunityHubScope: String, CaseIterable, Hashable, Identifiable, Sendable {
    case forYou, following, communities, topics, creators, builders, events
    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "For You"
        case .following: "Following"
        case .communities: "Communities"
        case .topics: "Topics"
        case .creators: "Creators"
        case .builders: "Builders"
        case .events: "Events"
        }
    }

    var symbol: String {
        switch self {
        case .forYou: "house"
        case .following: "person.2"
        case .communities: "person.3"
        case .topics: "number"
        case .creators: "star"
        case .builders: "cube.box"
        case .events: "calendar"
        }
    }

    var route: CommunityRoute {
        switch self {
        case .forYou: .forYou
        case .following: .following
        case .communities: .communities
        case .topics: .topics
        case .creators: .creators
        case .builders: .builders
        case .events: .events
        }
    }
}

enum CommunityBuildersTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case feed, projects, events, members, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .feed: "house"
        case .projects: "cube.box"
        case .events: "calendar"
        case .members: "person.2"
        case .about: "info.circle"
        }
    }
}

enum CommunityVisibility: String, Hashable, Sendable { case `public`, `private` }
enum CommunityMembershipPolicy: String, Hashable, Sendable { case open, approval }
enum CommunityPostingPolicy: String, Hashable, Sendable { case members, moderators }
enum CommunityMembership: String, Hashable, Sendable { case none, pending, active, banned }
enum CommunityRole: String, Hashable, Sendable { case owner, admin, moderator, member, restricted }

struct CommunityArtwork: Equatable, Sendable {
    let iconURL: URL?
    let coverURL: URL?
}

struct CommunitySummary: Identifiable, Equatable, Sendable {
    let id: String
    let slug: String
    let name: String
    let description: String
    let category: String
    let visibility: CommunityVisibility
    let discoverable: Bool
    let featured: Bool
    let memberCount: Int
    let membership: CommunityMembership
    let viewerRole: CommunityRole?
    let recentActivityAt: Date?
    let artwork: CommunityArtwork
    let version: Int
}

struct CommunityDetails: Identifiable, Equatable, Sendable {
    let summary: CommunitySummary
    let ownerActorID: String
    let membershipPolicy: CommunityMembershipPolicy
    let postingPolicy: CommunityPostingPolicy
    let createdAt: Date?
    let updatedAt: Date?
    var id: String { summary.id }
}

struct CommunityMember: Identifiable, Equatable, Sendable {
    let actorID: String
    let role: CommunityRole
    let joinedAt: Date?
    let profile: ModulaProfile
    var id: String { actorID }
}

struct CommunityPost: Identifiable, Equatable, Sendable {
    let communityID: String
    let moderationState: String
    let featuredAt: Date?
    let post: SocialPost
    var id: String { post.id }
}

struct CommunitySettings: Equatable, Sendable {
    let communityID: String
    let canManage: Bool
    let membershipPolicy: CommunityMembershipPolicy
    let postingPolicy: CommunityPostingPolicy
    let inviteLinksEnabled: Bool
    let allowAttachments: Bool
    let reactionsEnabled: Bool
    let featuredPostsEnabled: Bool
    let blockedWords: [String]?
    let notifyMentions: Bool
    let weeklyDigest: Bool
    let eventReminders: Bool
    let version: Int
    let updatedAt: Date?
}

enum CommunityEventResponse: String, Hashable, Sendable { case going, interested }

struct CommunityEventLocation: Equatable, Sendable {
    let type: String
    let name: String?
    let onlineURL: URL?
}

struct CommunityEvent: Identifiable, Equatable, Sendable {
    let id: String
    let communityID: String
    let creatorActorID: String
    let title: String
    let description: String
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let location: CommunityEventLocation
    let coverURL: URL?
    let capacity: Int?
    let status: String
    let goingCount: Int
    let interestedCount: Int
    let viewerResponse: CommunityEventResponse?
    let version: Int
}

struct CommunityPollOption: Identifiable, Equatable, Sendable {
    let id: String
    let position: Int
    let text: String
    let voteCount: Int?
}

struct CommunityPoll: Identifiable, Equatable, Sendable {
    let id: String
    let communityID: String
    let creatorActorID: String
    let question: String
    let options: [CommunityPollOption]
    let closesAt: Date
    let allowVoteChanges: Bool
    let resultsVisibility: String
    let status: String
    let closed: Bool
    let viewerOptionID: String?
    let totalVotes: Int?
    let version: Int
}

struct CommunityPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool
}

enum CommunityLoadState: Equatable {
    case idle, loading, loaded, empty
    case offline(String), unauthorized(String), failed(String)

    var isLoading: Bool { self == .loading }
    var message: String? {
        switch self {
        case .offline(let value), .unauthorized(let value), .failed(let value): value
        default: nil
        }
    }
}

struct CommunityCapabilities: Equatable, Sendable {
    let canPost: Bool
    let canModerate: Bool
    let canManage: Bool
    let canVoteAndRSVP: Bool

    static func derive(from community: CommunityDetails?, settings: CommunitySettings?) -> Self {
        guard let community else { return .init(canPost: false, canModerate: false, canManage: false, canVoteAndRSVP: false) }
        let summary = community.summary
        let active = summary.membership == .active && summary.viewerRole != .restricted
        let elevatedRoles: Set<CommunityRole> = [.owner, .admin, .moderator]
        let elevated = summary.viewerRole.map(elevatedRoles.contains) ?? false
        let managementRoles: Set<CommunityRole> = [.owner, .admin]
        let canPost = active && (community.postingPolicy == .members || elevated)
        return .init(
            canPost: canPost,
            canModerate: active && elevated,
            canManage: active && (settings?.canManage == true || summary.viewerRole.map(managementRoles.contains) == true),
            canVoteAndRSVP: active
        )
    }
}

struct CommunitySettingsDraft: Equatable, Sendable {
    var name: String
    var description: String
    var visibility: CommunityVisibility
    var membershipPolicy: CommunityMembershipPolicy
    var postingPolicy: CommunityPostingPolicy
    var inviteLinksEnabled: Bool
    var allowAttachments: Bool
    var reactionsEnabled: Bool
    var featuredPostsEnabled: Bool
    var notifyMentions: Bool
    var weeklyDigest: Bool
    var eventReminders: Bool
    var blockedWords: String

    init(community: CommunityDetails, settings: CommunitySettings) {
        name = community.summary.name
        description = community.summary.description
        visibility = community.summary.visibility
        membershipPolicy = settings.membershipPolicy
        postingPolicy = settings.postingPolicy
        inviteLinksEnabled = settings.inviteLinksEnabled
        allowAttachments = settings.allowAttachments
        reactionsEnabled = settings.reactionsEnabled
        featuredPostsEnabled = settings.featuredPostsEnabled
        notifyMentions = settings.notifyMentions
        weeklyDigest = settings.weeklyDigest
        eventReminders = settings.eventReminders
        blockedWords = (settings.blockedWords ?? []).joined(separator: ", ")
    }

    var normalizedBlockedWords: [String] {
        Array(Set(blockedWords.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }
}

enum CommunityCopy {
    static let title = "Community"
    static let subtitle = "Creators, builders and explorers. Together on Modula."
    static let searchPrompt = "Search communities"
    static let buildersTitle = "Modula Builders"
    static let postsEmpty = "No community posts yet."
    static let membersEmpty = "No members to show."
    static let pollsEmpty = "No community polls yet."
    static let eventsEmpty = "No community events scheduled."
}

/// Comment polls remain a social-post feature and use a different contract from
/// GreenField Community polls. PostRepository consumes this helper directly.
enum CommentPollVote {
    static func path(commentID: String) -> String {
        let escaped = commentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? commentID
        return "/v1/comments/\(escaped)/poll/vote"
    }

    static func body(optionIndex: Int?) -> JSONValue {
        .object(["optionIndex": optionIndex.map { .number(Double($0)) } ?? .null])
    }
}

enum CommunityAPI {
    static func community(_ id: String) -> String { "/v1/communities/\(path(id))" }
    static func join(_ id: String) -> String { "\(community(id))/join" }
    static func leave(_ id: String) -> String { "\(community(id))/leave" }
    static func members(_ id: String, cursor: String? = nil) -> String { page("\(community(id))/members", cursor: cursor) }
    static func postCollection(_ id: String) -> String { "\(community(id))/posts" }
    static func posts(_ id: String, cursor: String? = nil) -> String { page(postCollection(id), cursor: cursor) }
    static func settings(_ id: String) -> String { "\(community(id))/settings" }
    static func pollCollection(_ id: String) -> String { "\(community(id))/polls" }
    static func polls(_ id: String, cursor: String? = nil) -> String { page(pollCollection(id), cursor: cursor) }
    static func vote(_ communityID: String, pollID: String) -> String { "\(pollCollection(communityID))/\(path(pollID))/vote" }
    static func eventCollection(_ id: String) -> String { "\(community(id))/events" }
    static func events(_ id: String, cursor: String? = nil) -> String { page(eventCollection(id), cursor: cursor) }
    static func response(_ communityID: String, eventID: String) -> String { "\(eventCollection(communityID))/\(path(eventID))/response" }

    static func list(query: String? = nil, membership: String? = nil, cursor: String? = nil) -> String {
        queryPath("/v1/communities", items: [
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "membership", value: membership),
            URLQueryItem(name: "cursor", value: cursor),
        ])
    }

    private static func page(_ base: String, cursor: String?) -> String {
        queryPath(base, items: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "cursor", value: cursor)])
    }

    private static func queryPath(_ base: String, items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items.filter { $0.value != nil }
        guard let query = components.percentEncodedQuery, !query.isEmpty else { return base }
        return "\(base)?\(query)"
    }

    private static func path(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

actor GreenfieldCommunityRepository {
    private let client: GreenfieldClient

    init(client: GreenfieldClient) { self.client = client }

    func list(query: String?, membership: String?, cursor: String?) async throws -> CommunityPage<CommunitySummary> {
        let value = try await client.json("GET", path: CommunityAPI.list(query: query, membership: membership, cursor: cursor))
        return try CommunityPayloadDecoder.page(value, decode: CommunityPayloadDecoder.summary)
    }

    func community(_ id: String) async throws -> CommunityDetails {
        let value = try await client.json("GET", path: CommunityAPI.community(id))
        return try CommunityPayloadDecoder.details(value["community"] ?? value)
    }

    func join(_ id: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON("POST", path: CommunityAPI.join(id), body: .object([:]))
    }

    func leave(_ id: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON("POST", path: CommunityAPI.leave(id), body: .object([:]))
    }

    func members(_ id: String, cursor: String?) async throws -> CommunityPage<CommunityMember> {
        let value = try await client.json("GET", path: CommunityAPI.members(id, cursor: cursor))
        return try CommunityPayloadDecoder.page(value, decode: CommunityPayloadDecoder.member)
    }

    func posts(_ id: String, cursor: String?) async throws -> CommunityPage<CommunityPost> {
        let value = try await client.json("GET", path: CommunityAPI.posts(id, cursor: cursor))
        return try CommunityPayloadDecoder.page(value, decode: CommunityPayloadDecoder.post)
    }

    func polls(_ id: String, cursor: String?) async throws -> CommunityPage<CommunityPoll> {
        let value = try await client.json("GET", path: CommunityAPI.polls(id, cursor: cursor))
        return try CommunityPayloadDecoder.page(value, decode: CommunityPayloadDecoder.poll)
    }

    func events(_ id: String, cursor: String?) async throws -> CommunityPage<CommunityEvent> {
        let value = try await client.json("GET", path: CommunityAPI.events(id, cursor: cursor))
        return try CommunityPayloadDecoder.page(value, decode: CommunityPayloadDecoder.event)
    }

    func settings(_ id: String) async throws -> CommunitySettings {
        let value = try await client.authenticatedJSON("GET", path: CommunityAPI.settings(id))
        return try CommunityPayloadDecoder.settings(value["settings"] ?? value)
    }

    func createPost(_ id: String, text: String, idempotencyKey: String) async throws -> CommunityPost {
        let value = try await client.authenticatedJSON("POST", path: CommunityAPI.postCollection(id), body: .object([
            "text": .string(text), "idempotencyKey": .string(idempotencyKey),
        ]))
        return try CommunityPayloadDecoder.post(value["item"] ?? value)
    }

    func vote(communityID: String, pollID: String, optionID: String) async throws -> CommunityPoll {
        let value = try await client.authenticatedJSON("PUT", path: CommunityAPI.vote(communityID, pollID: pollID), body: .object([
            "optionId": .string(optionID),
        ]))
        return try CommunityPayloadDecoder.poll(value["poll"] ?? value)
    }

    func respond(communityID: String, eventID: String, response: CommunityEventResponse?) async throws -> CommunityEvent {
        let value = try await client.authenticatedJSON("PUT", path: CommunityAPI.response(communityID, eventID: eventID), body: .object([
            "response": response.map { .string($0.rawValue) } ?? .null,
        ]))
        return try CommunityPayloadDecoder.event(value["event"] ?? value)
    }

    func updateCommunity(_ community: CommunityDetails, draft: CommunitySettingsDraft) async throws -> CommunityDetails {
        let value = try await client.authenticatedJSON("PATCH", path: CommunityAPI.community(community.id), body: .object([
            "expectedVersion": .number(Double(community.summary.version)),
            "name": .string(draft.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "description": .string(draft.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "visibility": .string(draft.visibility.rawValue),
        ]))
        return try CommunityPayloadDecoder.details(value["community"] ?? value)
    }

    func updateSettings(_ id: String, draft: CommunitySettingsDraft, expectedVersion: Int?, canManage: Bool) async throws -> CommunitySettings {
        var body: [String: JSONValue] = [
            "notifyMentions": .bool(draft.notifyMentions),
            "weeklyDigest": .bool(draft.weeklyDigest),
            "eventReminders": .bool(draft.eventReminders),
        ]
        if canManage {
            guard let expectedVersion else { throw APIError.invalidResponse }
            body.merge([
                "expectedVersion": .number(Double(expectedVersion)),
                "membershipPolicy": .string(draft.membershipPolicy.rawValue),
                "postingPolicy": .string(draft.postingPolicy.rawValue),
                "inviteLinksEnabled": .bool(draft.inviteLinksEnabled),
                "allowAttachments": .bool(draft.allowAttachments),
                "reactionsEnabled": .bool(draft.reactionsEnabled),
                "featuredPostsEnabled": .bool(draft.featuredPostsEnabled),
                "blockedWords": .array(draft.normalizedBlockedWords.map(JSONValue.string)),
            ]) { _, new in new }
        }
        let value = try await client.authenticatedJSON("PATCH", path: CommunityAPI.settings(id), body: .object(body))
        return try CommunityPayloadDecoder.settings(value["settings"] ?? value)
    }
}

enum CommunityPayloadDecoder {
    static func page<Item: Sendable>(_ value: JSONValue, decode: (JSONValue) throws -> Item) throws -> CommunityPage<Item> {
        let items = try (value["items"]?.array ?? []).map(decode)
        return CommunityPage(
            items: items,
            nextCursor: value["nextCursor"]?.string,
            hasMore: value["hasMore"]?.bool ?? (value["nextCursor"]?.string != nil)
        )
    }

    static func summary(_ value: JSONValue) throws -> CommunitySummary {
        guard let id = value["id"]?.string,
              let slug = value["slug"]?.string,
              let name = value["name"]?.string,
              let visibility = value["visibility"]?.string.flatMap(CommunityVisibility.init(rawValue:)),
              let membership = value["membership"]?.string.flatMap(CommunityMembership.init(rawValue:)),
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        let artwork = value["artwork"]
        return CommunitySummary(
            id: id, slug: slug, name: name, description: value["description"]?.string ?? "",
            category: value["category"]?.string ?? "Community", visibility: visibility,
            discoverable: value["discoverable"]?.bool ?? false, featured: value["featured"]?.bool ?? false,
            memberCount: value["memberCount"]?.int ?? 0, membership: membership,
            viewerRole: value["viewerRole"]?.string.flatMap(CommunityRole.init(rawValue:)),
            recentActivityAt: date(value["recentActivityAt"]?.string),
            artwork: CommunityArtwork(
                iconURL: artwork?["iconUrl"]?.string.flatMap(URL.init(string:)),
                coverURL: artwork?["coverUrl"]?.string.flatMap(URL.init(string:))
            ), version: version
        )
    }

    static func details(_ value: JSONValue) throws -> CommunityDetails {
        guard let owner = value["ownerActorId"]?.string,
              let membership = value["membershipPolicy"]?.string.flatMap(CommunityMembershipPolicy.init(rawValue:)),
              let posting = value["postingPolicy"]?.string.flatMap(CommunityPostingPolicy.init(rawValue:)) else {
            throw APIError.invalidResponse
        }
        return CommunityDetails(
            summary: try summary(value), ownerActorID: owner, membershipPolicy: membership, postingPolicy: posting,
            createdAt: date(value["createdAt"]?.string), updatedAt: date(value["updatedAt"]?.string)
        )
    }

    static func member(_ value: JSONValue) throws -> CommunityMember {
        guard let actorID = value["actorId"]?.string,
              let role = value["role"]?.string.flatMap(CommunityRole.init(rawValue:)),
              let profileValue = value["profile"],
              let profile = ProfilePayloadDecoder.profile(from: profileValue) else { throw APIError.invalidResponse }
        return CommunityMember(actorID: actorID, role: role, joinedAt: date(value["joinedAt"]?.string), profile: profile)
    }

    static func post(_ value: JSONValue) throws -> CommunityPost {
        guard let communityID = value["communityId"]?.string,
              let postValue = value["post"],
              let post = SocialPayloadDecoder.post(postValue) else { throw APIError.invalidResponse }
        return CommunityPost(
            communityID: communityID, moderationState: value["moderationState"]?.string ?? "visible",
            featuredAt: date(value["featuredAt"]?.string), post: post
        )
    }

    static func settings(_ value: JSONValue) throws -> CommunitySettings {
        guard let communityID = value["communityId"]?.string,
              let membership = value["membershipPolicy"]?.string.flatMap(CommunityMembershipPolicy.init(rawValue:)),
              let posting = value["postingPolicy"]?.string.flatMap(CommunityPostingPolicy.init(rawValue:)),
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        let notifications = value["notificationPreferences"]
        return CommunitySettings(
            communityID: communityID, canManage: value["canManage"]?.bool ?? false,
            membershipPolicy: membership, postingPolicy: posting,
            inviteLinksEnabled: value["inviteLinksEnabled"]?.bool ?? false,
            allowAttachments: value["allowAttachments"]?.bool ?? false,
            reactionsEnabled: value["reactionsEnabled"]?.bool ?? false,
            featuredPostsEnabled: value["featuredPostsEnabled"]?.bool ?? false,
            blockedWords: value["blockedWords"]?.array?.compactMap(\.string),
            notifyMentions: notifications?["notifyMentions"]?.bool ?? true,
            weeklyDigest: notifications?["weeklyDigest"]?.bool ?? false,
            eventReminders: notifications?["eventReminders"]?.bool ?? true,
            version: version, updatedAt: date(value["updatedAt"]?.string)
        )
    }

    static func event(_ value: JSONValue) throws -> CommunityEvent {
        guard let id = value["id"]?.string,
              let communityID = value["communityId"]?.string,
              let creator = value["creatorActorId"]?.string,
              let title = value["title"]?.string,
              let startsAt = date(value["startsAt"]?.string),
              let endsAt = date(value["endsAt"]?.string),
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        let location = value["location"]
        return CommunityEvent(
            id: id, communityID: communityID, creatorActorID: creator, title: title,
            description: value["description"]?.string ?? "", startsAt: startsAt, endsAt: endsAt,
            timezone: value["timezone"]?.string ?? TimeZone.current.identifier,
            location: CommunityEventLocation(
                type: location?["type"]?.string ?? "tba", name: location?["name"]?.string,
                onlineURL: location?["onlineUrl"]?.string.flatMap(URL.init(string:))
            ),
            coverURL: value["coverUrl"]?.string.flatMap(URL.init(string:)), capacity: value["capacity"]?.int,
            status: value["status"]?.string ?? "scheduled", goingCount: value["goingCount"]?.int ?? 0,
            interestedCount: value["interestedCount"]?.int ?? 0,
            viewerResponse: value["viewerResponse"]?.string.flatMap(CommunityEventResponse.init(rawValue:)),
            version: version
        )
    }

    static func poll(_ value: JSONValue) throws -> CommunityPoll {
        guard let id = value["id"]?.string,
              let communityID = value["communityId"]?.string,
              let creator = value["creatorActorId"]?.string,
              let question = value["question"]?.string,
              let closesAt = date(value["closesAt"]?.string),
              let version = value["version"]?.int else { throw APIError.invalidResponse }
        let options = try (value["options"]?.array ?? []).map { item -> CommunityPollOption in
            guard let id = item["id"]?.string, let text = item["text"]?.string else { throw APIError.invalidResponse }
            return CommunityPollOption(id: id, position: item["position"]?.int ?? 0, text: text, voteCount: item["voteCount"]?.int)
        }
        return CommunityPoll(
            id: id, communityID: communityID, creatorActorID: creator, question: question, options: options,
            closesAt: closesAt, allowVoteChanges: value["allowVoteChanges"]?.bool ?? true,
            resultsVisibility: value["resultsVisibility"]?.string ?? "afterVote",
            status: value["status"]?.string ?? "open", closed: value["closed"]?.bool ?? false,
            viewerOptionID: value["viewerOptionId"]?.string, totalVotes: value["totalVotes"]?.int, version: version
        )
    }

    private static func date(_ value: String?) -> Date? {
        SocialPayloadDecoder.decodeDate(value)
    }
}

@MainActor @Observable
final class CommunityStore {
    private let repository: GreenfieldCommunityRepository
    private(set) var communities: [CommunitySummary] = []
    private(set) var directoryState: CommunityLoadState = .idle
    private(set) var directoryNextCursor: String?
    private(set) var selectedCommunity: CommunityDetails?
    private(set) var contentState: CommunityLoadState = .idle
    private(set) var members: [CommunityMember] = []
    private(set) var posts: [CommunityPost] = []
    private(set) var polls: [CommunityPoll] = []
    private(set) var events: [CommunityEvent] = []
    private(set) var settings: CommunitySettings?
    private(set) var membersNextCursor: String?
    private(set) var postsNextCursor: String?
    private(set) var pollsNextCursor: String?
    private(set) var eventsNextCursor: String?
    private(set) var actionInProgress = false
    private(set) var actionError: String?
    private var selectedID: String?

    init(client: GreenfieldClient) { repository = GreenfieldCommunityRepository(client: client) }

    var capabilities: CommunityCapabilities { .derive(from: selectedCommunity, settings: settings) }

    func select(_ community: CommunitySummary) {
        guard selectedID != community.id else { return }
        selectedID = community.id
        selectedCommunity = nil
        members = []; posts = []; polls = []; events = []; settings = nil
        contentState = .idle
    }

    func loadDirectory(query: String? = nil, membership: String? = nil, reset: Bool = true) async {
        if directoryState == .loading { return }
        let cursor = reset ? nil : directoryNextCursor
        if !reset && cursor == nil { return }
        directoryState = .loading
        do {
            let page = try await repository.list(query: query, membership: membership, cursor: cursor)
            if reset {
                communities = page.items
            } else {
                let existing = Set(communities.map(\.id))
                communities.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            directoryNextCursor = page.nextCursor
            directoryState = communities.isEmpty ? .empty : .loaded
        } catch {
            directoryState = Self.loadState(for: error, hasCached: !communities.isEmpty, fallback: "Couldn’t load communities.")
        }
    }

    func loadBuildersIfNeeded(signedIn: Bool) async {
        if selectedID == nil {
            await loadDirectory(query: CommunityCopy.buildersTitle)
            guard let builders = communities.first(where: {
                $0.name.caseInsensitiveCompare(CommunityCopy.buildersTitle) == .orderedSame || $0.slug == "modula-builders"
            }) ?? communities.first else {
                contentState = directoryState == .empty ? .empty : directoryState
                return
            }
            select(builders)
        }
        if contentState == .idle || selectedCommunity == nil {
            await refreshSelected(signedIn: signedIn)
        }
    }

    func refreshSelected(signedIn: Bool) async {
        guard let id = selectedID ?? selectedCommunity?.id else { contentState = .empty; return }
        contentState = .loading
        actionError = nil
        do {
            selectedCommunity = try await repository.community(id)
            let memberPage = try await repository.members(id, cursor: nil)
            members = memberPage.items; membersNextCursor = memberPage.nextCursor
            let postPage = try await repository.posts(id, cursor: nil)
            posts = postPage.items; postsNextCursor = postPage.nextCursor
            let pollPage = try await repository.polls(id, cursor: nil)
            polls = pollPage.items; pollsNextCursor = pollPage.nextCursor
            let eventPage = try await repository.events(id, cursor: nil)
            events = eventPage.items; eventsNextCursor = eventPage.nextCursor
            if signedIn, selectedCommunity?.summary.membership == .active {
                settings = try await repository.settings(id)
            } else {
                settings = nil
            }
            contentState = .loaded
        } catch {
            contentState = Self.loadState(
                for: error, hasCached: selectedCommunity != nil || !posts.isEmpty || !members.isEmpty,
                fallback: "Couldn’t load this community."
            )
        }
    }

    func loadMoreMembers() async { await loadMore(kind: .members) }
    func loadMorePosts() async { await loadMore(kind: .posts) }
    func loadMorePolls() async { await loadMore(kind: .polls) }
    func loadMoreEvents() async { await loadMore(kind: .events) }

    func join(signedIn: Bool) async {
        guard signedIn, let id = selectedID else { actionError = "Sign in to join this community."; return }
        await perform {
            try await repository.join(id)
            await refreshSelected(signedIn: true)
        }
    }

    func leave() async {
        guard let id = selectedID else { return }
        await perform {
            try await repository.leave(id)
            await refreshSelected(signedIn: true)
        }
    }

    func createPost(text: String, idempotencyKey: String) async -> Bool {
        guard let id = selectedID, capabilities.canPost else {
            actionError = "Your community role does not allow posting."
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var succeeded = false
        await perform {
            let item = try await repository.createPost(id, text: trimmed, idempotencyKey: idempotencyKey)
            posts.removeAll { $0.id == item.id }
            posts.insert(item, at: 0)
            succeeded = true
        }
        return succeeded
    }

    func vote(pollID: String, optionID: String) async {
        guard let id = selectedID, capabilities.canVoteAndRSVP else {
            actionError = "Join this community before voting."
            return
        }
        await perform {
            let updated = try await repository.vote(communityID: id, pollID: pollID, optionID: optionID)
            if let index = polls.firstIndex(where: { $0.id == updated.id }) { polls[index] = updated }
        }
    }

    func respond(eventID: String, response: CommunityEventResponse?) async {
        guard let id = selectedID, capabilities.canVoteAndRSVP else {
            actionError = "Join this community before responding."
            return
        }
        await perform {
            let updated = try await repository.respond(communityID: id, eventID: eventID, response: response)
            if let index = events.firstIndex(where: { $0.id == updated.id }) { events[index] = updated }
        }
    }

    func saveSettings(_ draft: CommunitySettingsDraft) async -> Bool {
        guard let current = selectedCommunity, let currentSettings = settings else { return false }
        let canManage = capabilities.canManage
        var succeeded = false
        await perform {
            if canManage {
                selectedCommunity = try await repository.updateCommunity(current, draft: draft)
                let synchronized = try await repository.settings(current.id)
                settings = try await repository.updateSettings(
                    current.id, draft: draft, expectedVersion: synchronized.version, canManage: true
                )
                selectedCommunity = try await repository.community(current.id)
            } else {
                settings = try await repository.updateSettings(
                    current.id, draft: draft, expectedVersion: currentSettings.version, canManage: false
                )
            }
            succeeded = true
        }
        return succeeded
    }

    func clearActionError() { actionError = nil }

    func resetForAccountChange() {
        selectedCommunity = nil
        settings = nil
        members = []; posts = []; polls = []; events = []
        communities = []
        selectedID = nil
        directoryNextCursor = nil
        membersNextCursor = nil; postsNextCursor = nil; pollsNextCursor = nil; eventsNextCursor = nil
        directoryState = .idle; contentState = .idle
        actionError = nil
    }

    private enum PageKind { case members, posts, polls, events }

    private func loadMore(kind: PageKind) async {
        guard let id = selectedID else { return }
        do {
            switch kind {
            case .members:
                guard let cursor = membersNextCursor else { return }
                let page = try await repository.members(id, cursor: cursor)
                let existing = Set(members.map(\.id)); members.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                membersNextCursor = page.nextCursor
            case .posts:
                guard let cursor = postsNextCursor else { return }
                let page = try await repository.posts(id, cursor: cursor)
                let existing = Set(posts.map(\.id)); posts.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                postsNextCursor = page.nextCursor
            case .polls:
                guard let cursor = pollsNextCursor else { return }
                let page = try await repository.polls(id, cursor: cursor)
                let existing = Set(polls.map(\.id)); polls.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                pollsNextCursor = page.nextCursor
            case .events:
                guard let cursor = eventsNextCursor else { return }
                let page = try await repository.events(id, cursor: cursor)
                let existing = Set(events.map(\.id)); events.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                eventsNextCursor = page.nextCursor
            }
        } catch {
            actionError = Self.actionMessage(error, fallback: "Couldn’t load more community content.")
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !actionInProgress else { return }
        actionInProgress = true
        actionError = nil
        defer { actionInProgress = false }
        do { try await operation() }
        catch { actionError = Self.actionMessage(error, fallback: "Couldn’t update this community.") }
    }

    private static func loadState(for error: Error, hasCached: Bool, fallback: String) -> CommunityLoadState {
        if let api = error as? APIError {
            switch api {
            case .unauthenticated, .rejected(401, _), .rejected(403, _): return .unauthorized(api.userFacingMessage)
            case .unconfigured: return .offline(api.userFacingMessage)
            case .rejected(let status, _) where status >= 500:
                return hasCached ? .offline("Offline · showing the last loaded community data.") : .offline(api.userFacingMessage)
            default: return .failed(api.userFacingMessage)
            }
        }
        if error is URLError {
            return hasCached ? .offline("Offline · showing the last loaded community data.") : .offline("You appear to be offline.")
        }
        return .failed(fallback)
    }

    private static func actionMessage(_ error: Error, fallback: String) -> String {
        guard let api = error as? APIError else { return fallback }
        if case .rejected(403, _) = api { return "Your community role does not allow this action." }
        if case .rejected(409, _) = api { return "This community changed. Refresh it and try again." }
        return api.userFacingMessage
    }
}
