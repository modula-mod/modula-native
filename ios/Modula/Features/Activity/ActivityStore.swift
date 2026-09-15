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
