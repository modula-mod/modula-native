import Foundation

typealias ProfileID = String
typealias ProfileHandle = String

enum ProfileIdentity: Hashable, Sendable, CustomStringConvertible {
    case me
    case handle(ProfileHandle)
    case id(ProfileID)

    var description: String {
        switch self {
        case .me: "me"
        case .handle(let handle): handle
        case .id(let id): id
        }
    }

    /// Prefer handle for Greenfield GET /v1/profiles/:handle.
    var lookupHandle: ProfileHandle? {
        switch self {
        case .me: nil
        case .handle(let handle): handle
        case .id: nil
        }
    }

    static func resolving(routeUserID: String?) -> ProfileIdentity {
        guard let routeUserID, !routeUserID.isEmpty else { return .me }
        return .handle(routeUserID)
    }
}

enum ProfileVisibility: String, Hashable, Sendable {
    case `public`, followers, teams, `private`

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "followers": self = .followers
        case "teams": self = .teams
        case "private": self = .private
        default: self = .public
        }
    }

    var displayTitle: String {
        switch self {
        case .public: "Public"
        case .followers: "Followers"
        case .teams: "Teams"
        case .private: "Private"
        }
    }
}

struct ProfileLink: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let url: URL?
    let domain: String?
    let visibility: ProfileVisibility
}

struct ProfileLocation: Hashable, Sendable {
    let label: String
    let visibility: ProfileVisibility
}

struct ProfileFocusStatus: Hashable, Sendable {
    let id: String
    let label: String
    let message: String?
}

struct ProfileIdentityClaim: Hashable, Sendable {
    let kind: String?
    let label: String?
    let verified: Bool
}

enum ProfileFollowState: Hashable, Sendable {
    case none
    case following
    /// Reserved — Greenfield profiles do not emit approval state today.
    case requested

    init(isFollowing: Bool) {
        self = isFollowing ? .following : .none
    }

    var title: String {
        switch self {
        case .none: "Follow"
        case .following: "Following"
        case .requested: "Requested"
        }
    }
}

struct ModulaProfile: Identifiable, Hashable, Sendable {
    let id: ProfileID
    let handle: ProfileHandle
    let displayName: String
    let kind: String
    let avatarURL: URL?
    let coverURL: URL?
    let coverColour: String?
    let bio: String
    let pronouns: String?
    let location: ProfileLocation?
    let website: ProfileLink?
    let followerCount: Int
    let followingCount: Int
    let moduleCount: Int
    let postCount: Int
    let joinedAt: Date?
    let focusStatus: ProfileFocusStatus?
    let identityClaims: [ProfileIdentityClaim]
    let links: [ProfileLink]
    let featuredModuleIds: [String]
    var isFollowing: Bool
    var followsViewer: Bool
    let version: Int?
    let visibility: ProfileVisibility?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var routeID: String { handle.isEmpty ? id : handle }
    var isVerified: Bool { identityClaims.contains(where: \.verified) }
    var followState: ProfileFollowState { .init(isFollowing: isFollowing) }
    var shareURL: URL {
        URL(string: "https://modula.digital/profile/\(routeID)")!
    }

    var publicLinks: [ProfileLink] {
        var items = links
        if let website, !items.contains(where: { $0.id == website.id }) {
            items.insert(website, at: 0)
        }
        return items
    }
}

struct ProfilePeoplePage: Sendable, Equatable {
    var items: [ModulaProfile]
    var nextCursor: String?
    var hasMore: Bool
}

struct ProfilePostPage: Sendable, Equatable {
    var items: [SocialPost]
    var nextCursor: String?
    var hasMore: Bool
}

struct ProfileModulePage: Sendable, Equatable {
    var items: [CatalogueProduct]
    var nextCursor: String?
    var hasMore: Bool
}

struct ProfileEditDraft: Equatable, Sendable {
    var displayName: String
    var bio: String
    var visibility: ProfileVisibility
    var expectedVersion: Int?

    static func from(_ profile: ModulaProfile) -> Self {
        Self(
            displayName: profile.displayName,
            bio: profile.bio,
            visibility: profile.visibility ?? .public,
            expectedVersion: profile.version
        )
    }
}

enum ProfileLoadState: Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case loaded
    case failed(String)
    case notFound
    case unavailable
}

struct ProfileSessionState: Equatable {
    var profile: ModulaProfile?
    var loadState: ProfileLoadState = .idle
    var lastError: String?
    var lastRefresh: Date?
    var posts = ProfileCollectionState<SocialPost>()
    var modules = ProfileCollectionState<CatalogueProduct>()
    var followers = ProfileCollectionState<ModulaProfile>()
    var following = ProfileCollectionState<ModulaProfile>()
    var overviewPreviewPosts: [SocialPost] = []
    var scrollOffsets: [ProfileSection: CGFloat] = [:]
}

struct ProfileCollectionState<Item: Equatable>: Equatable {
    var items: [Item] = []
    var nextCursor: String?
    var hasMore = false
    var loadState: ProfileLoadState = .idle
    var lastError: String?
}

enum ProfilePayloadDecoder {
    static func profile(from value: JSONValue) -> ModulaProfile? {
        let payload = value["profile"] ?? value
        let id = payload["id"]?.string
        guard let id else { return nil }
        let handle = payload["handle"]?.string ?? id
        let display = payload["displayName"]?.string ?? payload["name"]?.string ?? handle
        let claims = (payload["identityClaims"]?.array ?? []).map(claim)
        let links = (payload["links"]?.array ?? []).compactMap(link)
        let website = payload["website"].flatMap(link)
        let locationValue = payload["location"]
        let location: ProfileLocation? = {
            guard let label = locationValue?["label"]?.string, !label.isEmpty else { return nil }
            return ProfileLocation(
                label: label,
                visibility: ProfileVisibility(parsing: locationValue?["visibility"]?.string)
            )
        }()
        let focus = payload["focusStatus"].map {
            ProfileFocusStatus(
                id: $0["id"]?.string ?? "focus",
                label: $0["label"]?.string ?? "Available",
                message: emptyToNil($0["message"]?.string)
            )
        }
        return ModulaProfile(
            id: id,
            handle: handle,
            displayName: display,
            kind: payload["kind"]?.string ?? "person",
            avatarURL: url(payload["avatarUri"]?.string ?? payload["avatarUrl"]?.string ?? payload["avatar"]?.string),
            coverURL: url(payload["coverUri"]?.string ?? payload["coverUrl"]?.string ?? payload["cover"]?.string),
            coverColour: emptyToNil(payload["coverColour"]?.string ?? payload["cover_colour"]?.string),
            bio: payload["bio"]?.string ?? "",
            pronouns: emptyToNil(payload["pronouns"]?.string),
            location: location,
            website: website,
            followerCount: payload["followerCount"]?.int ?? payload["follower_count"]?.int ?? 0,
            followingCount: payload["followingCount"]?.int ?? payload["following_count"]?.int ?? 0,
            moduleCount: payload["moduleCount"]?.int ?? payload["module_count"]?.int ?? 0,
            postCount: payload["postCount"]?.int ?? payload["post_count"]?.int ?? 0,
            joinedAt: SocialPayloadDecoder.decodeDate(payload["joinedAt"]?.string ?? payload["joined_at"]?.string),
            focusStatus: focus,
            identityClaims: claims,
            links: links,
            featuredModuleIds: (payload["featuredModuleIds"]?.array ?? payload["featured_module_ids"]?.array ?? [])
                .compactMap(\.string),
            isFollowing: payload["isFollowing"]?.bool ?? payload["is_following"]?.bool ?? false,
            followsViewer: payload["followsViewer"]?.bool ?? payload["follows_viewer"]?.bool ?? false,
            version: payload["version"]?.int,
            visibility: payload["visibility"]?.string.map { ProfileVisibility(parsing: $0) }
        )
    }

    static func peoplePage(from value: JSONValue) -> ProfilePeoplePage {
        let items = (value["items"]?.array ?? value.array ?? []).compactMap(profile)
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let hasMore = value["hasMore"]?.bool ?? value["has_more"]?.bool ?? (next != nil)
        return ProfilePeoplePage(items: items, nextCursor: next, hasMore: hasMore)
    }

    static func postPage(from value: JSONValue) -> ProfilePostPage {
        let home = SocialPayloadDecoder.homePage(from: value)
        return ProfilePostPage(items: home.items, nextCursor: home.nextCursor, hasMore: home.hasMore)
    }

    private static func link(_ value: JSONValue) -> ProfileLink? {
        let id = value["id"]?.string ?? value["url"]?.string
        guard let id else { return nil }
        return ProfileLink(
            id: id,
            label: value["label"]?.string ?? value["title"]?.string ?? value["domain"]?.string ?? "Link",
            url: url(value["url"]?.string),
            domain: emptyToNil(value["domain"]?.string),
            visibility: ProfileVisibility(parsing: value["visibility"]?.string)
        )
    }

    private static func claim(_ value: JSONValue) -> ProfileIdentityClaim {
        let verified = value["verified"]?.bool == true
            || value["status"]?.string?.lowercased() == "verified"
        return ProfileIdentityClaim(
            kind: emptyToNil(value["kind"]?.string ?? value["type"]?.string),
            label: emptyToNil(value["label"]?.string ?? value["title"]?.string),
            verified: verified
        )
    }

    private static func url(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), !raw.isEmpty else { return nil }
        return url
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ProfileCountFormatter {
    static func compact(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.locale = .current
        if value < 1_000 { return formatter.string(from: NSNumber(value: value)) ?? "\(value)" }
        if value < 1_000_000 {
            let scaled = Double(value) / 1_000
            let text = formatter.string(from: NSNumber(value: scaled)) ?? String(format: "%.1f", scaled)
            return text.replacingOccurrences(of: ".0", with: "") + "K"
        }
        let scaled = Double(value) / 1_000_000
        let text = formatter.string(from: NSNumber(value: scaled)) ?? String(format: "%.1f", scaled)
        return text.replacingOccurrences(of: ".0", with: "") + "M"
    }

    static func accessibility(_ value: Int, noun: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(noun)"
    }
}
