import Foundation

/// A sign-up that is waiting for its emailed code. It survives backgrounding, the app being
/// killed and cold launch so the person resumes at "Enter the code".
///
/// It deliberately holds no password and no session credential: Greenfield issues no session
/// until the email is verified and the person signs in, so there is nothing that could leak
/// into a later sign-in request.
struct PendingSignup: Codable, Sendable, Equatable {
    /// Normalised (trimmed, lowercased) email the code was sent to.
    var email: String
    var handle: String?
    var accountID: String?
    /// Greenfield `verificationChallengeId` for the emailed code. It names the challenge; it
    /// does not authenticate anything on its own.
    var challengeID: String?
    /// Masked address the latest code went to (`a•••@example.com`), when the server says.
    var recipient: String? = nil
    var createdAt: Date
    var expiresAt: Date
    var lastCodeSentAt: Date
    /// Earliest moment "Resend code" may ask for another code.
    var resendAvailableAt: Date
    /// Wrong codes entered against the current challenge. Greenfield locks a challenge after
    /// `PendingSignupStore.attemptLimit` failures (ChallengeService `attempt_limit: 5`).
    var failedAttempts: Int = 0

    var isLocked: Bool { failedAttempts >= PendingSignupStore.attemptLimit }

    func isExpired(at now: Date) -> Bool { now >= expiresAt }

    func resendWait(at now: Date) -> TimeInterval { max(0, resendAvailableAt.timeIntervalSince(now)) }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Keychain-backed storage for the single pending sign-up, scoped to the API origin like the
/// session tokens (`KeychainStore`, after-first-unlock, this device only).
struct PendingSignupStore: Sendable {
    /// Client-side spacing between resend requests. Greenfield allows 5 codes per 10 minutes
    /// per account/email/IP (`ChallengeService.consumeRateLimit`), so 60 s keeps well inside it.
    static let resendCooldown: TimeInterval = 60
    /// After Greenfield answers RATE_LIMITED, wait out its 10-minute window.
    static let rateLimitedCooldown: TimeInterval = 10 * 60
    /// Longest a pending sign-up is kept: Greenfield caps a challenge at 24 h
    /// (`ChallengeService.createWithDb`). Also used if the server omits `verificationExpiresAt`.
    static let maximumLifetime: TimeInterval = 24 * 60 * 60
    static let attemptLimit = 5

    /// Server expiry, never later than 24 h from `start`.
    static func expiry(server: Date?, from start: Date) -> Date {
        let cap = start.addingTimeInterval(maximumLifetime)
        guard let server else { return cap }
        return min(server, cap)
    }

    private let keychain: KeychainStore

    init(namespace: String) {
        keychain = KeychainStore(namespace: namespace + "|pending-signup")
    }

    init(baseURL: URL?) {
        self.init(namespace: baseURL?.absoluteString ?? "unconfigured")
    }

    func load() -> PendingSignup? {
        guard let data = try? keychain.load() else { return nil }
        guard let pending = try? JSONDecoder().decode(PendingSignup.self, from: data) else {
            // Unreadable (older shape or corruption): drop it rather than strand the person.
            clear()
            return nil
        }
        return pending
    }

    func save(_ pending: PendingSignup) throws {
        try keychain.save(JSONEncoder().encode(pending))
    }

    func clear() {
        try? keychain.clear()
    }

    /// Raw stored bytes, for tests that prove what is (and is not) persisted.
    func storedData() -> Data? {
        try? keychain.load()
    }
}
