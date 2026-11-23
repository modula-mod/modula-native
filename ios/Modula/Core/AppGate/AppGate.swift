import Foundation
import Observation

/// Resolves boot / session / first-run / lock before any shell chrome is mounted.
@MainActor @Observable
final class AppGate {
    private(set) var state: AppLaunchState = .booting
    private(set) var pendingDestination: PendingDestination? = AppGate.restorePending()
    private(set) var lastFailure: String?

    let onboarding = OnboardingSeenStore()
    let firstRun = FirstRunCompletionStore()

    var signedOutSurface: SignedOutSurface {
        onboarding.hasSeenOnboarding ? .authentication : .onboarding
    }

    enum SignedOutSurface: Equatable {
        case onboarding
        case authentication
    }

    func beginBoot() {
        state = .booting
        lastFailure = nil
    }

    func fail(_ message: String) {
        lastFailure = message
        state = .failed(message)
    }

    /// Apply the canonical launch machine. Never reports `.ready` for a signed-out user.
    func apply(
        signedIn: Bool,
        accountID: String?,
        appLockEnabled: Bool,
        appLockRequiresUnlock: Bool
    ) {
        if !signedIn {
            state = .signedOut
            return
        }
        if let accountID, !firstRun.isComplete(accountID: accountID) {
            state = .firstRun
            return
        }
        if appLockEnabled && appLockRequiresUnlock {
            state = .locked
            return
        }
        state = .ready
    }

    func markOnboardingSeen() {
        onboarding.markSeen()
        if state == .signedOut {
            state = .signedOut
        }
    }

    func completeFirstRun(accountID: String) {
        firstRun.markComplete(accountID: accountID)
    }

    func enqueue(_ route: AppRoute) {
        if route.isPreAuthSurface {
            pendingDestination = nil
            Self.persist(nil)
            return
        }
        let pending = PendingDestination(route: route, capturedAt: Date())
        pendingDestination = pending
        Self.persist(pending)
    }

    func takePendingDestination() -> AppRoute? {
        guard state == .ready else { return nil }
        let route = pendingDestination?.route
        pendingDestination = nil
        Self.persist(nil)
        return route
    }

    // MARK: Pending link survives sign-in (and an app relaunch during sign-in)

    /// A followed link waits this long for sign-in, then is dropped rather than surprising the user later.
    nonisolated static let pendingLifetime: TimeInterval = 30 * 60
    nonisolated private static let pendingRouteKey = "gate.pendingRoute.v1"
    nonisolated private static let pendingAtKey = "gate.pendingRouteAt.v1"

    nonisolated static func persist(_ pending: PendingDestination?, defaults: UserDefaults = .standard) {
        guard let pending else {
            defaults.removeObject(forKey: pendingRouteKey)
            defaults.removeObject(forKey: pendingAtKey)
            return
        }
        defaults.set(RouteSerializer.serialize(pending.route), forKey: pendingRouteKey)
        defaults.set(pending.capturedAt.timeIntervalSince1970, forKey: pendingAtKey)
    }

    nonisolated static func restorePending(defaults: UserDefaults = .standard, now: Date = Date()) -> PendingDestination? {
        guard let value = defaults.string(forKey: pendingRouteKey),
              let route = RouteParser.parse(value),
              !route.isPreAuthSurface else {
            persist(nil, defaults: defaults)
            return nil
        }
        let captured = Date(timeIntervalSince1970: defaults.double(forKey: pendingAtKey))
        guard now.timeIntervalSince(captured) < pendingLifetime, captured <= now else {
            persist(nil, defaults: defaults)
            return nil
        }
        return PendingDestination(route: route, capturedAt: captured)
    }
}

extension AppRoute {
    /// Auth and onboarding destinations may be shown while signed out.
    var isPreAuthSurface: Bool {
        if case .auth = self { return true }
        return false
    }

    /// Destinations that must never appear before the gate is ready.
    var requiresAuthenticatedShell: Bool {
        switch self {
        case .auth, .boot: false
        default: true
        }
    }
}
