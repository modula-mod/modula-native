import Foundation

/// Launch gate above NavigationCoordinator, Root Shell, and ModuleHost.
/// The shell must not exist until this state is `ready`.
enum AppLaunchState: Equatable, Sendable {
    case booting
    case signedOut
    case firstRun
    case locked
    case ready
    case failed(String)

    var allowsShell: Bool {
        if case .ready = self { return true }
        return false
    }

    var accessibilityLabel: String {
        switch self {
        case .booting: "Starting Modula"
        case .signedOut: "Signed out"
        case .firstRun: "Finish setting up your account"
        case .locked: "Modula is locked"
        case .ready: "Modula is ready"
        case .failed: "Modula could not start"
        }
    }
}

/// Device-only marketing flag. Never implies an authenticated session.
struct OnboardingSeenStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key = "modula.native.onboarding.seen.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeenOnboarding: Bool {
        defaults.bool(forKey: key)
    }

    func markSeen() {
        defaults.set(true, forKey: key)
    }
}

/// Account-scoped first-run completion. Device-local until Greenfield exposes a verified contract.
struct FirstRunCompletionStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let prefix = "modula.native.firstRun.completed.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isComplete(accountID: String) -> Bool {
        guard !accountID.isEmpty else { return false }
        return defaults.bool(forKey: prefix + accountID)
    }

    func markComplete(accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.set(true, forKey: prefix + accountID)
    }

    func clear(accountID: String) {
        defaults.removeObject(forKey: prefix + accountID)
    }
}

/// Deep links and shortcuts wait here until the gate is ready.
struct PendingDestination: Equatable, Sendable {
    let route: AppRoute
    let capturedAt: Date
}

enum SignOutRetentionPolicy {
    /// Device appearance stays. It is not an account secret.
    static let retainAppearance = true
    /// Marketing onboarding is not re-shown after a later sign-out.
    static let retainOnboardingSeen = true
    /// Local drafts remain until the user discards them. Sign-out warns.
    static let retainLocalDrafts = true
    /// On-device collections remain. They are not Greenfield account data.
    static let retainLocalCollections = true
    /// App Lock PIN is account-session protection and is reset on sign-out.
    static let resetAppLock = true
}
