import Foundation
import Observation

enum ActivityLoadState: Equatable {
    case idle
    case loading
    case loaded
    case refreshing
    case loadingMore
    case failed(String)
}

struct ActivityModeState: Equatable {
    var events: [ActivityEvent] = []
    var nextCursor: String?
    var unreadCount: Int?
    var loadState: ActivityLoadState = .idle
    var lastRefresh: Date?
    var lastError: String?
    var filter: ActivityFilter?
}

@MainActor @Observable
final class ActivityStore {
    private let repository: GreenfieldActivityRepository
    private(set) var modes: [ActivityMode: ActivityModeState] = [
        .all: ActivityModeState(),
        .mentions: ActivityModeState(),
        .requests: ActivityModeState()
    ]
    private(set) var actionError: String?
    var isOfflineHint = false
    private(set) var dismissedIDs: Set<ActivityEventID> = Set(UserDefaults.standard.stringArray(forKey: "activity.dismissed.v1") ?? [])

    init(client: GreenfieldClient) {
        self.repository = GreenfieldActivityRepository(client: client)
    }

    func state(for mode: ActivityMode) -> ActivityModeState {
        modes[mode] ?? ActivityModeState()
    }

    func summary(for mode: ActivityMode) -> ActivitySummary {
        let events = modes[mode]?.events ?? []
        let requests = modes[.requests]?.events.count
            ?? events.filter(\.kind.isRequest).count
        return .aggregates(from: events, pendingRequests: requests)
    }

    func loadIfNeeded(_ mode: ActivityMode, signedIn: Bool) async {
        guard signedIn else { return }
        let current = state(for: mode)
        guard current.loadState == .idle || current.events.isEmpty else { return }
        await refresh(mode, signedIn: true)
    }

    func refresh(_ mode: ActivityMode, signedIn: Bool) async {
        guard signedIn else {
            modes[mode] = ActivityModeState(loadState: .idle)
            return
        }
        var state = self.state(for: mode)
        #if DEBUG
        if ActivityDebugFixture.isEnabled {
            let events = ActivityDebugFixture.events(mode: mode).filter { state.filter?.matches($0) ?? true }
            state.events = events
            state.nextCursor = nil
            state.unreadCount = events.filter { !$0.isRead }.count
            state.loadState = .loaded
            state.lastRefresh = Date()
            modes[mode] = state
            return
        }
        #endif
        let hasContent = !state.events.isEmpty
        state.loadState = hasContent ? .refreshing : .loading
        state.lastError = nil
        modes[mode] = state
        do {
            let page = try await repository.page(mode: mode, cursor: nil, filter: state.filter)
            state.events = page.events
            state.nextCursor = page.nextCursor
            state.unreadCount = page.unreadCount
            state.loadState = .loaded
            state.lastRefresh = Date()
            state.lastError = nil
            modes[mode] = state
            actionError = nil
            isOfflineHint = false
        } catch let api as APIError {
            if hasContent {
                state.loadState = .loaded
                state.lastError = api.userFacingMessage
                modes[mode] = state
                actionError = api.userFacingMessage
            } else {
                state.loadState = .failed(api.userFacingMessage)
                state.lastError = api.userFacingMessage
                modes[mode] = state
            }
            if api == .unauthenticated { isOfflineHint = false }
        } catch {
            let message = "Unable to load activity."
            if hasContent {
                state.loadState = .loaded
                modes[mode] = state
                actionError = message
            } else {
                state.loadState = .failed(message)
                modes[mode] = state
            }
        }
    }

    func loadMore(_ mode: ActivityMode) async {
        var state = self.state(for: mode)
        guard let cursor = state.nextCursor, state.loadState == .loaded else { return }
        state.loadState = .loadingMore
        modes[mode] = state
        do {
            let page = try await repository.page(mode: mode, cursor: cursor, filter: state.filter)
            let existing = Set(state.events.map(\.id))
            state.events.append(contentsOf: page.events.filter { !existing.contains($0.id) })
            state.nextCursor = page.nextCursor
            state.loadState = .loaded
            modes[mode] = state
        } catch {
            state.loadState = .loaded
            modes[mode] = state
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not load more."
        }
    }

    func setFilter(_ filter: ActivityFilter?, mode: ActivityMode, signedIn: Bool) async {
        var state = self.state(for: mode)
        state.filter = filter
        modes[mode] = state
        await refresh(mode, signedIn: signedIn)
    }

    func markRead(_ event: ActivityEvent, mode: ActivityMode) async {
        guard !event.isRead else { return }
        applyLocalRead(event.id, mode: mode, isRead: true)
        #if DEBUG
        if ActivityDebugFixture.isEnabled { return }
        #endif
        do {
            try await repository.markRead(event.id)
        } catch {
            applyLocalRead(event.id, mode: mode, isRead: false)
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not mark as read."
        }
    }

    func markAllRead(mode: ActivityMode) async {
        let before = state(for: mode).events
        applyAllRead(mode: mode)
        #if DEBUG
        if ActivityDebugFixture.isEnabled { HapticEngine.shared.play(.confirmation); return }
        #endif
        do {
            try await repository.markAllRead(mode: mode)
            HapticEngine.shared.play(.confirmation)
        } catch {
            modes[mode]?.events = before
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not mark all as read."
            HapticEngine.shared.play(.failure)
        }
    }

    func accept(_ event: ActivityEvent) async {
        removeLocally(event.id, mode: .requests)
        do {
            try await repository.acceptRequest(event: event)
            HapticEngine.shared.play(.success)
        } catch {
            await refresh(.requests, signedIn: true)
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not accept request."
            HapticEngine.shared.play(.failure)
        }
    }

    func decline(_ event: ActivityEvent) async {
        removeLocally(event.id, mode: .requests)
        do {
            try await repository.declineRequest(event: event)
            HapticEngine.shared.play(.warning)
        } catch {
            await refresh(.requests, signedIn: true)
            actionError = (error as? APIError)?.userFacingMessage ?? "Could not decline request."
            HapticEngine.shared.play(.failure)
        }
    }

    func clearActionError() { actionError = nil }

    func dismiss(_ events: [ActivityEvent], mode: ActivityMode) {
        for event in events { removeLocally(event.id, mode: mode) }
        dismissedIDs.formUnion(events.map(\.id))
        UserDefaults.standard.set(Array(dismissedIDs.prefix(800)), forKey: "activity.dismissed.v1")
    }

    func markRead(_ events: [ActivityEvent], mode: ActivityMode) async {
        for event in events where !event.isRead { await markRead(event, mode: mode) }
    }

    // MARK: - Local mutations

    private func applyLocalRead(_ id: ActivityEventID, mode: ActivityMode, isRead: Bool) {
        guard var state = modes[mode] else { return }
        state.events = state.events.map { event in
            guard event.id == id else { return event }
            return ActivityEvent(
                id: event.id, kind: event.kind, actor: event.actor, actors: event.actors,
                createdAt: event.createdAt, isRead: isRead, subject: event.subject, preview: event.preview,
                destination: event.destination, descriptionText: event.descriptionText,
                groupHint: event.groupHint, requestID: event.requestID
            )
        }
        modes[mode] = state
    }

    private func applyAllRead(mode: ActivityMode) {
        guard var state = modes[mode] else { return }
        state.events = state.events.map {
            ActivityEvent(
                id: $0.id, kind: $0.kind, actor: $0.actor, actors: $0.actors,
                createdAt: $0.createdAt, isRead: true, subject: $0.subject, preview: $0.preview,
                destination: $0.destination, descriptionText: $0.descriptionText,
                groupHint: $0.groupHint, requestID: $0.requestID
            )
        }
        state.unreadCount = 0
        modes[mode] = state
    }

    private func removeLocally(_ id: ActivityEventID, mode: ActivityMode) {
        guard var state = modes[mode] else { return }
        state.events.removeAll { $0.id == id }
        modes[mode] = state
    }
}

#if DEBUG
/// DEBUG-only screenshot seed for the Activity tab (`--debug-activity-fixture`).
/// Never compiled into Release; never writes to an account or the server.
enum ActivityDebugFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-activity-fixture") }
    /// `--debug-activity-chip moliboos` opens a filter for screenshots.
    static var initialChip: ActivityChip? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--debug-activity-chip"), args.indices.contains(i + 1) else { return nil }
        return ActivityChip(rawValue: args[i + 1])
    }
    /// `--debug-activity-scrolled` scrolls the feed so the top blur is visible in screenshots.
    static var startsScrolled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-activity-scrolled") }

    private static func actor(_ id: String, _ name: String, _ handle: String) -> ActivityActor {
        ActivityActor(id: "fixture-\(id)", handle: handle, displayName: name, avatarURL: nil)
    }

    static func events(mode: ActivityMode, now: Date = Date()) -> [ActivityEvent] {
        let ana = actor("ana", "Ana Ruiz", "ana"), leo = actor("leo", "Leo Park", "leopark")
        let mia = actor("mia", "Mia Chen", "miachen"), sam = actor("sam", "Sam Okafor", "samo")
        let noor = actor("noor", "Noor Haddad", "noor"), kai = actor("kai", "Kai Jensen", "kaij")
        let thumb = { (seed: String) in URL(string: "https://picsum.photos/seed/\(seed)/200/200") }
        func ev(_ id: String, _ kind: ActivityEventKind, _ actors: [ActivityActor], minutes: Double, read: Bool = false,
                text: String? = nil, thumb t: URL? = nil, post: String? = nil, desc: String) -> ActivityEvent {
            ActivityEvent(
                id: "fixture-\(id)", kind: kind, actor: actors.first, actors: actors,
                createdAt: now.addingTimeInterval(-minutes * 60), isRead: read,
                subject: post.map { ActivitySubject(kind: .post, id: $0, title: text) },
                preview: (text != nil || t != nil) ? ActivityPreview(text: text, thumbnailURL: t) : nil,
                destination: post.map { .post($0) } ?? (actors.first.map { .profile($0.id) } ?? .none),
                descriptionText: desc, groupHint: nil, requestID: kind.isRequest ? "fixture-\(id)" : nil
            )
        }
        let all: [ActivityEvent] = [
            ev("l1", .like, [ana], minutes: 3, thumb: thumb("sunset"), post: "fx-p1", desc: "liked your post"),
            ev("l2", .like, [leo], minutes: 6, thumb: thumb("sunset"), post: "fx-p1", desc: "liked your post"),
            ev("l3", .like, [mia], minutes: 9, thumb: thumb("sunset"), post: "fx-p1", desc: "liked your post"),
            ev("l4", .like, [sam], minutes: 14, thumb: thumb("sunset"), post: "fx-p1", desc: "liked your post"),
            ev("m1", .mention, [noor], minutes: 22, text: "@andy this is exactly the module flow I was talking about — can we ship it?", post: "fx-p2", desc: "mentioned you"),
            ev("f1", .follow, [kai], minutes: 48, desc: "started following you"),
            ev("c1", .comment, [mia], minutes: 95, text: "The glass on the new header is so clean. How did you do the blur?", thumb: thumb("glass"), post: "fx-p3", desc: "replied to your post"),
            ev("r1", .repost, [leo], minutes: 180, read: true, thumb: thumb("city"), post: "fx-p4", desc: "reposted your post"),
            ev("md1", .moduleUpdate, [], minutes: 300, read: true, text: "Vault Notes 2.0.2 is ready", desc: "Vault Notes was updated"),
            ev("f2", .follow, [ana], minutes: 60 * 26, read: true, desc: "started following you"),
            ev("f3", .follow, [sam], minutes: 60 * 27, read: true, desc: "started following you"),
            ev("re1", .reaction, [noor], minutes: 60 * 50, read: true, thumb: thumb("forest"), post: "fx-p5", desc: "reacted to your post"),
            ev("c2", .comment, [kai], minutes: 60 * 24 * 9, read: true, text: "Loved this write-up.", post: "fx-p6", desc: "replied to your post"),
            ev("l5", .like, [leo, mia], minutes: 60 * 24 * 12, read: true, thumb: thumb("ocean"), post: "fx-p7", desc: "liked your post"),
        ]
        switch mode {
        case .all: return all
        case .mentions: return all.filter(\.kind.isMention)
        case .requests:
            return [ev("q1", .followRequest, [actor("zoe", "Zoe Adler", "zoe")], minutes: 40, desc: "wants to follow you")]
        }
    }
}
#endif
