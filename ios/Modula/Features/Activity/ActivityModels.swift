import Foundation

typealias ActivityEventID = String

enum ActivityEventKind: String, Codable, Hashable, Sendable, CaseIterable {
    case reaction
    case like
    case comment
    case mention
    case repost
    case share
    case follow
    case followRequest
    case followAccepted
    case teamInvite
    case moduleEvent
    case moduleUpdate
    case system
    case unknown

    init(parsing raw: String) {
        let key = raw
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch key {
        case "reaction", "reacted": self = .reaction
        case "like", "liked": self = .like
        case "comment", "reply", "replied": self = .comment
        case "mention", "mentioned": self = .mention
        case "repost", "reposted": self = .repost
        case "share", "shared": self = .share
        case "follow", "followed", "startedfollowing": self = .follow
        case "followrequest", "follow_request", "connectionrequest", "request": self = .followRequest
        case "followaccepted", "follow_accepted", "accepted": self = .followAccepted
        case "teaminvite", "team_invite": self = .teamInvite
        case "moduleevent", "module_event": self = .moduleEvent
        case "moduleupdate", "module_update": self = .moduleUpdate
        case "system": self = .system
        default: self = .unknown
        }
    }

    var isMention: Bool { self == .mention || self == .comment }
    var isRequest: Bool { self == .followRequest || self == .teamInvite }
}

struct ActivityActor: Identifiable, Hashable, Sendable {
    let id: String
    let handle: String?
    let displayName: String
    let avatarURL: URL?

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var accessibilityName: String { displayName }
}

enum ActivitySubjectKind: String, Hashable, Sendable {
    case post, comment, profile, module, team, request, system
}

struct ActivitySubject: Hashable, Sendable {
    let kind: ActivitySubjectKind
    let id: String
    let title: String?
}

struct ActivityPreview: Hashable, Sendable {
    let text: String?
    let thumbnailURL: URL?
}

enum ActivityDestination: Hashable, Sendable {
    case post(String)
    case profile(String)
    case module(String)
    case activityRequests
    case notification(String)
    case none

    var route: AppRoute? {
        switch self {
        case .post(let id): .post(id, .root)
        case .profile(let id): .profile(id, .overview)
        case .module(let id): .productHub(.module(id, .overview))
        case .activityRequests: .activity(.requests)
        case .notification(let id): .notification(id)
        case .none: nil
        }
    }
}

struct ActivityEvent: Identifiable, Hashable, Sendable {
    let id: ActivityEventID
    let kind: ActivityEventKind
    let actor: ActivityActor?
    let actors: [ActivityActor]
    let createdAt: Date
    let isRead: Bool
    let subject: ActivitySubject?
    let preview: ActivityPreview?
    let destination: ActivityDestination
    let descriptionText: String
    let groupHint: String?
    let requestID: String?

    var primaryActors: [ActivityActor] {
        if !actors.isEmpty { return actors }
        if let actor { return [actor] }
        return []
    }

    var voiceOverSummary: String {
        let names = primaryActors.map(\.accessibilityName)
        let who: String
        switch names.count {
        case 0: who = "Someone"
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names[0]) and \(names.count - 1) others"
        }
        let read = isRead ? "Read" : "Unread"
        return "\(who). \(descriptionText). \(read)."
    }
}

struct ActivityPage: Sendable, Equatable {
    let events: [ActivityEvent]
    let nextCursor: String?
    let unreadCount: Int?
}

enum ActivityFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case unread
    case following
    case mentions
    case reactions
    case comments
    case requests
    case people
    case posts
    case modules
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .unread: "Unread"
        case .following: "Following"
        case .mentions: "Mentions"
        case .reactions: "Reactions"
        case .comments: "Comments"
        case .requests: "Requests"
        case .people: "People"
        case .posts: "Posts"
        case .modules: "Modules"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .unread: "envelope.badge"
        case .following: "person.2"
        case .mentions: "at"
        case .reactions: "heart"
        case .comments: "bubble.left"
        case .requests: "person.badge.plus"
        case .people: "person"
        case .posts: "text.alignleft"
        case .modules: "shippingbox"
        case .system: "gearshape"
        }
    }

    func matches(_ event: ActivityEvent) -> Bool {
        switch self {
        case .unread: !event.isRead
        case .following: [.follow, .followRequest, .followAccepted].contains(event.kind)
        case .mentions: event.kind.isMention
        case .reactions: event.kind == .like || event.kind == .reaction
        case .comments: event.kind == .comment
        case .requests: event.kind.isRequest
        case .people: [.follow, .followRequest, .followAccepted, .mention, .like, .reaction, .comment].contains(event.kind)
        case .posts: [.like, .reaction, .comment, .mention, .repost, .share].contains(event.kind)
        case .modules: [.moduleEvent, .moduleUpdate].contains(event.kind)
        case .system: event.kind == .system || event.kind == .unknown
        }
    }
}

enum ActivitySummarySource: Hashable, Sendable {
    case aggregates
    case ai
}

struct ActivitySummary: Hashable, Sendable {
    let source: ActivitySummarySource
    let unreadCount: Int
    let mentionCount: Int
    let requestCount: Int
    let reactionCount: Int
    let commentCount: Int
    let highlights: [String]
    let mostActiveNames: [String]
    let generatedAt: Date

    static func aggregates(from events: [ActivityEvent], pendingRequests: Int) -> ActivitySummary {
        let unread = events.filter { !$0.isRead }.count
        let mentions = events.filter(\.kind.isMention).count
        let reactions = events.filter { $0.kind == .like || $0.kind == .reaction }.count
        let comments = events.filter { $0.kind == .comment }.count
        var counts: [String: Int] = [:]
        for event in events {
            for actor in event.primaryActors {
                counts[actor.displayName, default: 0] += 1
            }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(2).map(\.key)
        var highlights: [String] = []
        if unread > 0 { highlights.append(String(localized: "\(unread) unread")) }
        if mentions > 0 { highlights.append("\(mentions) mentions") }
        if pendingRequests > 0 { highlights.append("\(pendingRequests) pending requests") }
        if let first = events.first(where: { $0.preview?.text?.isEmpty == false })?.preview?.text {
            highlights.append("Recent: “\(first)”")
        }
        return ActivitySummary(
            source: .aggregates,
            unreadCount: unread,
            mentionCount: mentions,
            requestCount: pendingRequests,
            reactionCount: reactions,
            commentCount: comments,
            highlights: highlights,
            mostActiveNames: Array(top),
            generatedAt: Date()
        )
    }
}

enum ActivityTimelineSection: String, CaseIterable, Identifiable, Sendable {
    /// `yesterday` is kept as the case name for callers; it now covers the last 7 days ("This week").
    case today, yesterday, earlier
    var id: Self { self }
    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "This week"
        case .earlier: "Earlier"
        }
    }

    static func section(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> Self {
        if calendar.isDateInToday(date) { return .today }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo { return .yesterday }
        return .earlier
    }
}
