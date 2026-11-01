import Foundation

protocol ActivityRepository: Sendable {
    func page(mode: ActivityMode, cursor: String?, filter: ActivityFilter?) async throws -> ActivityPage
    func markRead(_ id: ActivityEventID) async throws
    func markAllRead(mode: ActivityMode?) async throws
    func acceptRequest(event: ActivityEvent) async throws
    func declineRequest(event: ActivityEvent) async throws
}

/// Greenfield-backed Activity repository.
///
/// Contract (public probe + auth inventory, VPS source pending):
/// - `GET /v1/notifications` — authenticated timeline (All / Mentions)
/// - `GET /v1/profiles/me/follow-requests` — authenticated Requests mode (cursor page)
/// - `POST /v1/notifications/:id/read`
/// - `POST /v1/notifications/read-all`
/// - Accept: `POST /v1/follow-requests/:requestId/accept`
/// - Decline: `POST /v1/follow-requests/:requestId/reject`
///   (falls back to the actor follow routes only when a payload carries no request id)
///
/// Public `GET /v1/activity` is a static demo seed and is **not** used for signed-in acceptance.
actor GreenfieldActivityRepository: ActivityRepository {
    private let client: GreenfieldClient
    private var cache: [ActivityMode: ActivityPage] = [:]

    init(client: GreenfieldClient) {
        self.client = client
    }

    func cachedPage(mode: ActivityMode) -> ActivityPage? { cache[mode] }

    func page(mode: ActivityMode, cursor: String?, filter: ActivityFilter?) async throws -> ActivityPage {
        let page: ActivityPage
        switch mode {
        case .requests:
            page = try await loadRequests(cursor: cursor)
        case .mentions:
            page = try await loadNotifications(mode: "mentions", cursor: cursor)
        case .all:
            page = try await loadNotifications(mode: nil, cursor: cursor)
        }
        let filtered: ActivityPage
        if let filter {
            filtered = ActivityPage(
                events: page.events.filter(filter.matches),
                nextCursor: page.nextCursor,
                unreadCount: page.unreadCount
            )
        } else {
            filtered = page
        }
        if cursor == nil { cache[mode] = filtered }
        return filtered
    }

    func markRead(_ id: ActivityEventID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/notifications/\(Self.pathEscaped(id))/read",
            body: .object([:])
        )
        mutateCache { event in
            guard event.id == id else { return event }
            return ActivityEvent(
                id: event.id, kind: event.kind, actor: event.actor, actors: event.actors,
                createdAt: event.createdAt, isRead: true, subject: event.subject, preview: event.preview,
                destination: event.destination, descriptionText: event.descriptionText,
                groupHint: event.groupHint, requestID: event.requestID
            )
        }
    }

    func markAllRead(mode: ActivityMode?) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/notifications/read-all",
            body: mode.map { .object(["mode": .string($0.rawValue)]) } ?? .object([:])
        )
        mutateCache { event in
            ActivityEvent(
                id: event.id, kind: event.kind, actor: event.actor, actors: event.actors,
                createdAt: event.createdAt, isRead: true, subject: event.subject, preview: event.preview,
                destination: event.destination, descriptionText: event.descriptionText,
                groupHint: event.groupHint, requestID: event.requestID
            )
        }
    }

    func acceptRequest(event: ActivityEvent) async throws {
        if let requestID = event.requestID, !requestID.isEmpty {
            let _: JSONValue = try await client.authenticatedJSON(
                "POST",
                path: "/v1/follow-requests/\(Self.pathEscaped(requestID))/accept",
                body: .object([:])
            )
            removeFromCache(id: event.id, mode: .requests)
            return
        }
        guard let actorID = event.actor?.id ?? event.actors.first?.id else {
            throw APIError.invalidResponse
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/profiles/\(Self.pathEscaped(actorID))/follow",
            body: .object([:])
        )
        removeFromCache(id: event.id, mode: .requests)
    }

    func declineRequest(event: ActivityEvent) async throws {
        if let requestID = event.requestID, !requestID.isEmpty {
            let _: JSONValue = try await client.authenticatedJSON(
                "POST",
                path: "/v1/follow-requests/\(Self.pathEscaped(requestID))/reject",
                body: .object([:])
            )
            removeFromCache(id: event.id, mode: .requests)
            return
        }
        guard let actorID = event.actor?.id ?? event.actors.first?.id else {
            throw APIError.invalidResponse
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/profiles/\(Self.pathEscaped(actorID))/follow",
            body: nil
        )
        removeFromCache(id: event.id, mode: .requests)
    }

    // MARK: - Private

    private func loadNotifications(mode: String?, cursor: String?) async throws -> ActivityPage {
        var path = "/v1/notifications?limit=30"
        if let mode { path += "&mode=\(mode)" }
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.authenticatedJSON("GET", path: path)
        return ActivityPayloadDecoder.page(from: value, defaultKindHint: mode == "mentions" ? .mention : nil)
    }

    private func loadRequests(cursor: String?) async throws -> ActivityPage {
        var path = "/v1/profiles/me/follow-requests?limit=30"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.authenticatedJSON("GET", path: path)
        return ActivityPayloadDecoder.page(from: value, defaultKindHint: .followRequest)
    }

    private func mutateCache(_ transform: (ActivityEvent) -> ActivityEvent) {
        for mode in ActivityMode.allCases {
            guard let page = cache[mode] else { continue }
            cache[mode] = ActivityPage(
                events: page.events.map(transform),
                nextCursor: page.nextCursor,
                unreadCount: page.unreadCount
            )
        }
    }

    private func removeFromCache(id: ActivityEventID, mode: ActivityMode) {
        guard let page = cache[mode] else { return }
        cache[mode] = ActivityPage(
            events: page.events.filter { $0.id != id },
            nextCursor: page.nextCursor,
            unreadCount: page.unreadCount
        )
    }

    nonisolated private static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

enum ActivityPayloadDecoder {
    static func page(from value: JSONValue, defaultKindHint: ActivityEventKind? = nil) -> ActivityPage {
        let items: [JSONValue]
        let nextCursor: String?
        let unread: Int?

        if case .array(let array) = value {
            items = array
            nextCursor = nil
            unread = nil
        } else {
            if case .array(let array) = value["items"] { items = array }
            else if case .array(let array) = value["notifications"] { items = array }
            else if case .array(let array) = value["requests"] { items = array }
            else if case .array(let array) = value["events"] { items = array }
            else { items = [] }
            nextCursor = value["nextCursor"]?.string ?? value["next_cursor"]?.string ?? value["cursor"]?.string
            if case .number(let n) = value["unreadCount"] { unread = Int(n) }
            else if case .number(let n) = value["unread_count"] { unread = Int(n) }
            else { unread = nil }
        }

        let events = items.compactMap { decodeEvent($0, defaultKindHint: defaultKindHint) }
        return ActivityPage(events: events, nextCursor: nextCursor, unreadCount: unread)
    }

    static func decodeEvent(_ value: JSONValue, defaultKindHint: ActivityEventKind? = nil) -> ActivityEvent? {
        let id = value["id"]?.string
            ?? value["notificationId"]?.string
            ?? value["requestId"]?.string
            ?? value["request_id"]?.string
        guard let id else { return nil }

        let typeRaw = value["type"]?.string
            ?? value["kind"]?.string
            ?? value["eventType"]?.string
            ?? defaultKindHint?.rawValue
            ?? "unknown"
        let kind = ActivityEventKind(parsing: typeRaw)

        let actors = decodeActors(value)
        let actor = actors.first
        let createdAt = decodeDate(
            value["createdAt"]?.string
                ?? value["created_at"]?.string
                ?? value["timestamp"]?.string
                ?? value["occurredAt"]?.string
        ) ?? Date()

        let isRead: Bool = {
            if case .bool(let v) = value["isRead"] { return v }
            if case .bool(let v) = value["read"] { return v }
            if case .bool(let v) = value["is_read"] { return v }
            if value["readAt"]?.string != nil { return true }
            return false
        }()

        let description = value["description"]?.string
            ?? value["body"]?.string
            ?? value["message"]?.string
            ?? value["title"]?.string
            ?? defaultDescription(for: kind)

        let previewText = value["preview"]?.string
            ?? value["excerpt"]?.string
            ?? value["previewText"]?.string
        let thumb = (value["thumbnailUrl"]?.string ?? value["mediaUrl"]?.string ?? value["preview"]?["url"]?.string)
            .flatMap(URL.init(string:))
        let preview = (previewText != nil || thumb != nil) ? ActivityPreview(text: previewText, thumbnailURL: thumb) : nil

        let subject = decodeSubject(value)
        let destination = decodeDestination(kind: kind, value: value, subject: subject, actor: actor)
        let requestID = value["requestId"]?.string ?? value["request_id"]?.string ?? (kind.isRequest ? id : nil)

        return ActivityEvent(
            id: id,
            kind: kind,
            actor: actor,
            actors: actors,
            createdAt: createdAt,
            isRead: isRead,
            subject: subject,
            preview: preview,
            destination: destination,
            descriptionText: description,
            groupHint: value["group"]?.string,
            requestID: requestID
        )
    }

    private static func decodeActors(_ value: JSONValue) -> [ActivityActor] {
        var result: [ActivityActor] = []
        if let single = value["actor"], let actor = decodeActor(single) {
            result.append(actor)
        }
        if case .array(let array) = value["actors"] {
            result.append(contentsOf: array.compactMap(decodeActor))
        }
        if let from = value["from"] ?? value["requester"] ?? value["account"] ?? value["profile"],
           let actor = decodeActor(from) {
            if !result.contains(where: { $0.id == actor.id }) { result.append(actor) }
        }
        return result
    }

    private static func decodeActor(_ value: JSONValue) -> ActivityActor? {
        let id = value["id"]?.string ?? value["accountId"]?.string ?? value["userId"]?.string
        guard let id else { return nil }
        let display = value["displayName"]?.string
            ?? value["name"]?.string
            ?? value["handle"]?.string
            ?? "Member"
        let handle = value["handle"]?.string ?? value["primaryHandle"]?.string
        let avatar = (value["avatarUrl"]?.string ?? value["avatar"]?.string).flatMap(URL.init(string:))
        return ActivityActor(id: id, handle: handle, displayName: display, avatarURL: avatar)
    }

    private static func decodeSubject(_ value: JSONValue) -> ActivitySubject? {
        if let postId = value["postId"]?.string ?? value["post_id"]?.string ?? value["subject"]?["postId"]?.string {
            let title = value["preview"]?.string ?? value["subject"]?["title"]?.string
            return ActivitySubject(kind: .post, id: postId, title: title)
        }
        if let moduleId = value["moduleId"]?.string ?? value["module_id"]?.string {
            return ActivitySubject(kind: .module, id: moduleId, title: value["preview"]?.string)
        }
        if let profileId = value["profileId"]?.string ?? value["targetAccountId"]?.string {
            return ActivitySubject(kind: .profile, id: profileId, title: nil)
        }
        if let subject = value["subject"], let id = subject["id"]?.string {
            let kind = ActivitySubjectKind(rawValue: subject["kind"]?.string ?? subject["type"]?.string ?? "system") ?? .system
            return ActivitySubject(kind: kind, id: id, title: subject["title"]?.string)
        }
        return nil
    }

    private static func decodeDestination(
        kind: ActivityEventKind,
        value: JSONValue,
        subject: ActivitySubject?,
        actor: ActivityActor?
    ) -> ActivityDestination {
        if kind.isRequest { return .activityRequests }
        if let subject {
            switch subject.kind {
            case .post, .comment: return .post(subject.id)
            case .profile: return .profile(subject.id)
            case .module: return .module(subject.id)
            case .request: return .activityRequests
            case .team, .system: break
            }
        }
        if let postId = value["postId"]?.string { return .post(postId) }
        if let moduleId = value["moduleId"]?.string { return .module(moduleId) }
        if kind == .follow || kind == .followAccepted, let actor {
            return .profile(actor.id)
        }
        if let actor, kind == .mention { return .profile(actor.id) }
        return .none
    }

    private static func decodeDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func defaultDescription(for kind: ActivityEventKind) -> String {
        switch kind {
        case .like: "liked your post"
        case .reaction: "reacted to your post"
        case .comment: "commented on your post"
        case .mention: "mentioned you"
        case .repost: "reposted your post"
        case .share: "shared your post"
        case .follow: "started following you"
        case .followRequest: "wants to follow you"
        case .followAccepted: "accepted your follow request"
        case .teamInvite: "invited you to a team"
        case .moduleEvent, .moduleUpdate: "updated a module"
        case .moliboo: "sent a Moliboo moment"
        case .system: "sent a system notice"
        case .unknown: "sent activity"
        }
    }
}
