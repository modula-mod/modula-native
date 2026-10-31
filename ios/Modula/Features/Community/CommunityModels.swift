import Foundation

/// Community shell gate. Release builds are always off, including when a debug
/// default was copied onto a device. Debug defaults on so the shell can be reviewed.
enum CommunityFeatureFlags {
    static let storageKey = "dev.community.shell"

    static var isEnabled: Bool { isEnabled(defaults: .standard, release: isReleaseBuild) }

    static var isReleaseBuild: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    static func isEnabled(defaults: UserDefaults, release: Bool) -> Bool {
        if release { return false }
        guard defaults.object(forKey: storageKey) != nil else { return true }
        return defaults.bool(forKey: storageKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        guard !isReleaseBuild else { return }
        defaults.set(enabled, forKey: storageKey)
    }
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

/// Hub variants from the community comps. One chip row, not a second tab bar.
enum CommunityHubScope: String, CaseIterable, Identifiable, Sendable {
    case forYou
    case following
    case communities
    case topics
    case creators
    case builders
    case events

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

enum CommunityBuildersTab: String, CaseIterable, Identifiable, Sendable {
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

/// Device-only preferences. Nothing here is a member count, a post, or a server write.
struct CommunityLocalSettings: Codable, Equatable, Sendable {
    var displayName: String = ""
    var summary: String = ""
    var isPrivate = false
    var joinApproval = false
    var inviteLinks = false
    var adminsOnlyPosting = false
    var allowAttachments = true
    var reactions = true
    var featuredPosts = false
    var notifyMentions = true
    var weeklyDigest = false
    var eventReminders = false
    var interestedOnDevice = false
    var blockedWords: String = ""

    static let storageKey = "community.local.settings"

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    var shownName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CommunityCopy.buildersTitle : trimmed
    }
}

enum CommunityCopy {
    static let title = "Community"
    static let subtitle = "Creators, builders and explorers. Together on Modula."
    static let comingSoon = "Coming soon"
    static let preview = "Preview · off in Release"
    static let noRoutes = "Greenfield has no communities routes, so this is not a live member list, post, or event."
    static let searchPrompt = "Search people, posts, topics"
    static let searchFootnote = "Communities aren’t searchable yet. Search still covers people, posts and topics."
    static let buildersTitle = "Modula Builders"
    static let buildersStatus = "Preview shell · not a live community"
    static let settingsFootnote = "Saved on this device only. There is no community settings endpoint."
    static let pollFootnote = "Community polls aren’t a feed. If a post you name has a comment poll, voting uses that poll."
    static let eventFootnote = "No community event is scheduled. Interest stays on this device."
    static let eventShareText = "Community events aren’t available on Modula yet."
    static let analyticsUnavailable = "Analytics aren’t available yet."
    static let postsEmpty = "No community posts to show."
    static let membersEmpty = "No member list. Communities aren’t on the server."
    static let savedOnDevice = "Saved on this device"

    static var catalogued: [String] {
        [title, subtitle, comingSoon, preview, noRoutes, searchPrompt, searchFootnote, buildersTitle, buildersStatus, settingsFootnote, pollFootnote, eventFootnote, eventShareText, analyticsUnavailable, postsEmpty, membersEmpty, savedOnDevice]
    }
}

/// `PUT /v1/comments/:commentId/poll/vote` — the only poll route in the HTTP atlas.
enum CommentPollVote {
    static func path(commentID: String) -> String {
        let escaped = commentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? commentID
        return "/v1/comments/\(escaped)/poll/vote"
    }

    static func body(optionIndex: Int?) -> JSONValue {
        .object(["optionIndex": optionIndex.map { .number(Double($0)) } ?? .null])
    }
}

enum CommunityPollListing {
    static func rows(in comments: [SocialComment]) -> [CommunityPollRow] {
        comments.compactMap { comment in
            guard let poll = comment.media.compactMap(\.poll).first else { return nil }
            return CommunityPollRow(comment: comment, poll: poll)
        }
    }

    static func acceptsPostID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 160
            && trimmed.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    }
}

struct CommunityPollRow: Identifiable, Equatable, Sendable {
    var comment: SocialComment
    var poll: CommentPoll
    var id: String { comment.id }
}
