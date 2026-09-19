import Foundation
import Observation

/// Resolves boot / session / first-run / lock before any shell chrome is mounted.
@MainActor @Observable
final class AppGate {
    private(set) var state: AppLaunchState = .booting
    private(set) var pendingDestination: PendingDestination?
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
            return
        }
        pendingDestination = PendingDestination(route: route, capturedAt: Date())
    }

    func takePendingDestination() -> AppRoute? {
        guard state == .ready else { return nil }
        let route = pendingDestination?.route
        pendingDestination = nil
        return route
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
