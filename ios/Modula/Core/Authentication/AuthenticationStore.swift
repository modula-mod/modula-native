import Foundation
import Observation

@MainActor @Observable
final class AuthenticationStore {
    private let client: GreenfieldClient
    private let pendingStore: PendingSignupStore
    private let now: () -> Date
    private(set) var account: GreenfieldAccount? { didSet { onAccountChange?(account) } }
    var onAccountChange: ((GreenfieldAccount?) -> Void)?
    /// Runs before tokens are revoked (e.g. unregister this device's push token).
    var willSignOut: (@MainActor () async -> Void)?
    private(set) var busy = false
    var error: String?
    #if DEBUG
    var lastDiagnostic: String?
    #endif

    // MARK: Pending sign-up (email verification)

    /// The sign-up waiting for its emailed code, restored from the Keychain on launch.
    private(set) var pendingSignup: PendingSignup?
    /// One-off information for the auth screens (for example: the code expired).
    var pendingNotice: String?
    /// Error from the last verify/resend attempt.
    var signupError: String?
    private(set) var verifying = false
    private(set) var resending = false
    /// Email that was just verified, offered to Sign In so it needn't be retyped.
    private(set) var lastVerifiedEmail: String?

    init(client: GreenfieldClient,
         pendingStore: PendingSignupStore = PendingSignupStore(namespace: "unconfigured"),
         now: @escaping () -> Date = { Date() }) {
        self.client = client
        self.pendingStore = pendingStore
        self.now = now
    }

    var isSignedIn: Bool { account != nil }

    #if DEBUG
    /// UI-test session with no tokens and no production authority.
    func adoptUITestLocalModuleSession() {
        let arguments = ProcessInfo.processInfo.arguments
        var accountId = "uitest-local-modules"
        if let index = arguments.firstIndex(of: "--uitest-local-account"),
           arguments.indices.contains(arguments.index(after: index)) {
            let candidate = arguments[arguments.index(after: index)]
            let allowed = candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            if allowed, (8...80).contains(candidate.count) { accountId = candidate }
        }
        account = GreenfieldAccount(
            accountId: accountId,
            primaryHandle: "modules",
            status: "active",
            displayName: "Module Fixture"
        )
    }
    #endif

    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            account = try await client.restore()
            error = nil
            #if DEBUG
            lastDiagnostic = nil
            #endif
        } catch {
            account = nil
            self.error = "Session could not be restored. Sign in again."
            #if DEBUG
            lastDiagnostic = (error as? APIError)?.diagnosticDescription ?? String(describing: error)
            #endif
        }
    }

    /// Re-reads `/v1/accounts/me` after an account change (for example a new username).
    func refreshAccount() async {
        if let fresh = try? await client.restore() { account = fresh }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard !busy else { return false }
        // Signing in to another account abandons the pending sign-up: it never blocks or
        // rides along with a normal sign-in. (Same email: keep it until sign-in succeeds,
        // because an unverified account can't sign in yet.)
        if let pending = pendingSignup, pending.email != PendingSignup.normalizedEmail(email) {
            abandonPendingSignup()
        }
        busy = true; error = nil
        defer { busy = false }
        let host = await client.apiOriginHost
        do {
            account = try await client.signIn(email: email, password: password)
            abandonPendingSignup()
            lastVerifiedEmail = nil
            #if DEBUG
            lastDiagnostic = nil
            #endif
            return true
        } catch let api as APIError {
            if let pending = pendingSignup, pending.email == PendingSignup.normalizedEmail(email),
               case .rejected(_, let code) = api,
               code == "INVALID_CREDENTIALS" || code == "EMAIL_NOT_VERIFIED" || code == "VERIFICATION_REQUIRED" {
                // Greenfield answers INVALID_CREDENTIALS for an unverified account even with the
                // right password (authentication/service.ts), so point at the real next step.
                self.error = "Finish verifying \(pending.email) first. Enter the code we emailed you."
            } else {
                self.error = Self.userFacing(api, host: host)
            }
            #if DEBUG
            lastDiagnostic = api.diagnosticDescription + (host.map { " · \($0)" } ?? "")
            #endif
            return false
        } catch {
            self.error = "Unable to sign in. Check your connection and try again."
            #if DEBUG
            lastDiagnostic = String(describing: error)
            #endif
            return false
        }
    }

    private static func userFacing(_ api: APIError, host: String?) -> String {
        if case .rejected(_, "INVALID_CREDENTIALS") = api {
            return invalidCredentialsMessage
        }
        return api.userFacingMessage
    }

    /// Greenfield gives an unverified account the same answer as a wrong password.
    static let invalidCredentialsMessage = "Email or password is incorrect. If you just created this account, verify your email first."

    /// Whether a failed sign-in for `email` should continue at the enter-code step.
    func signInNeedsVerification(email: String) -> Bool {
        guard let pending = pendingSignup else { return false }
        return pending.email == PendingSignup.normalizedEmail(email)
    }

    // MARK: Sign-up and verification

    /// Re-reads the pending sign-up (launch, foreground). An expired one is cleared with a notice.
    @discardableResult
    func restorePendingSignup() -> PendingSignup? {
        guard let stored = pendingStore.load() else {
            pendingSignup = nil
            return nil
        }
        if stored.isExpired(at: now()) {
            expire(stored)
            return nil
        }
        pendingSignup = stored
        return stored
    }

    /// Creates the account. When Greenfield requires email verification the pending state is
    /// saved (never the password) so the code step survives the app closing.
    func register(payload: RegistrationPayload) async throws -> RegistrationResult {
        let result = try await client.register(payload: payload)
        guard result.verificationRequired else {
            abandonPendingSignup()
            return result
        }
        let started = now()
        let pending = PendingSignup(
            email: PendingSignup.normalizedEmail(payload.email),
            handle: result.handle ?? payload.handle,
            accountID: result.accountID,
            challengeID: result.challengeID,
            createdAt: started,
            expiresAt: PendingSignupStore.expiry(server: result.expiresAt, from: started),
            lastCodeSentAt: started,
            resendAvailableAt: started.addingTimeInterval(PendingSignupStore.resendCooldown)
        )
        pendingNotice = nil
        signupError = nil
        persist(pending)
        return result
    }

    /// Starts (or restarts) verification for an email typed on the verify screen, by asking for
    /// a new code. Used when nothing is pending on this device (expired, or another device).
    func requestCode(for email: String) async -> Bool {
        let normalized = PendingSignup.normalizedEmail(email)
        guard !resending, !normalized.isEmpty else { return false }
        if let pending = pendingSignup, pending.email == normalized { return await resendPendingCode() }
        resending = true; signupError = nil
        defer { resending = false }
        let started = now()
        do {
            let result = try await client.resendVerification(email: normalized)
            pendingNotice = result.challengeID == nil ? Self.resendUnconfirmableNotice : nil
            persist(PendingSignup(
                email: normalized,
                handle: nil,
                accountID: nil,
                challengeID: result.challengeID,
                createdAt: started,
                expiresAt: PendingSignupStore.expiry(server: result.expiresAt, from: started),
                lastCodeSentAt: started,
                resendAvailableAt: started.addingTimeInterval(PendingSignupStore.resendCooldown)
            ))
            return true
        } catch let api as APIError {
            signupError = Self.verificationMessage(api)
            return false
        } catch {
            signupError = Self.offlineMessage
            return false
        }
    }

    /// Seconds until "Resend code" is available again (0 when it is).
    func resendWait() -> TimeInterval {
        pendingSignup?.resendWait(at: now()) ?? 0
    }

    func resendPendingCode() async -> Bool {
        guard !resending, var pending = pendingSignup else { return false }
        let started = now()
        guard pending.resendWait(at: started) == 0 else { return false }
        resending = true; signupError = nil
        defer { resending = false }
        do {
            let result = try await client.resendVerification(email: pending.email)
            // Greenfield supersedes the previous code on resend. At ab0efa4f it does not return
            // the replacement challenge, so the old id is dropped rather than kept as if valid.
            pending.challengeID = result.challengeID
            pending.lastCodeSentAt = started
            pending.resendAvailableAt = started.addingTimeInterval(PendingSignupStore.resendCooldown)
            pending.expiresAt = PendingSignupStore.expiry(server: result.expiresAt, from: started)
            pending.failedAttempts = 0
            // Don't present a resend as usable when the server didn't name the new code.
            pendingNotice = result.challengeID == nil ? Self.resendUnconfirmableNotice : nil
            persist(pending)
            return true
        } catch let api as APIError {
            if case .rejected(_, let code) = api, code == "RATE_LIMITED" || code == "TOO_MANY_REQUESTS" {
                pending.resendAvailableAt = started.addingTimeInterval(PendingSignupStore.rateLimitedCooldown)
                persist(pending)
                signupError = "Too many codes requested. You can ask for another in 10 minutes."
            } else {
                signupError = Self.verificationMessage(api)
            }
            return false
        } catch {
            signupError = Self.offlineMessage
            return false
        }
    }

    func verifyPendingCode(_ code: String) async -> Bool {
        let trimmed = code.filter { !$0.isWhitespace }
        guard !verifying, var pending = pendingSignup, !trimmed.isEmpty else { return false }
        if pending.isExpired(at: now()) {
            expire(pending)
            return false
        }
        guard !pending.isLocked else {
            signupError = Self.lockedMessage
            return false
        }
        verifying = true; signupError = nil
        defer { verifying = false }
        do {
            try await client.verifyEmail(challengeID: pending.challengeID, code: trimmed, token: nil)
            lastVerifiedEmail = pending.email
            abandonPendingSignup()
            return true
        } catch let api as APIError {
            if pending.challengeID == nil, case .rejected(_, "CHALLENGE_INVALID") = api {
                signupError = Self.resendUnconfirmableNotice
            } else if case .rejected(_, "CHALLENGE_INVALID") = api {
                pending.failedAttempts += 1
                persist(pending)
                signupError = pending.isLocked
                    ? Self.lockedMessage
                    : Self.verificationMessage(api) + " \(PendingSignupStore.attemptLimit - pending.failedAttempts) tries left."
            } else {
                signupError = Self.verificationMessage(api)
            }
            return false
        } catch {
            signupError = Self.offlineMessage
            return false
        }
    }

    /// "Use a different account", or any sign-in to another account: forget the pending
    /// sign-up on this device. Nothing server-side needs revoking (no session exists yet).
    func abandonPendingSignup() {
        pendingStore.clear()
        pendingSignup = nil
        signupError = nil
    }

    private func expire(_ pending: PendingSignup) {
        pendingStore.clear()
        pendingSignup = nil
        signupError = nil
        pendingNotice = "The code for \(pending.email) expired. Request a new code to finish creating your account, or sign in with another account."
    }

    private func persist(_ pending: PendingSignup) {
        pendingSignup = pending
        do { try pendingStore.save(pending) } catch {
            // Still usable in memory for this launch; say plainly that it won't survive a restart.
            pendingNotice = "This device couldn’t save your sign-up securely. Keep Modula open until you’ve entered the code."
        }
    }

    static let offlineMessage = "We couldn’t reach Modula. Check your connection and try again."
    static let lockedMessage = "Too many wrong codes. That code is now locked: tap Resend code to get a new one."
    /// Greenfield at ab0efa4f supersedes the old code on resend without returning the new
    /// challenge id, so the app has nothing to confirm the new code against. Said plainly.
    static let resendUnconfirmableNotice = "A new code was sent, but this version of Modula can’t confirm resent codes yet, and your earlier code no longer works. Contact support to finish verifying, or sign in with another account."
    static let rateLimitedRegisterMessage = "Too many attempts from this network. Wait 10 minutes, then try again."

    /// Plain-language copy for Greenfield's sign-up errors.
    static func signupMessage(_ api: APIError) -> String {
        switch api {
        case .rejected(_, "CONFLICT"):
            return "That email or username is already in use. Sign in instead, or pick another username."
        case .rejected(_, "VALIDATION_FAILED"):
            return "Check your details: a valid email, a display name of 2 to 80 characters and a password of at least 10 characters."
        case .rejected(_, "FORBIDDEN"):
            return "New accounts aren’t open right now."
        case .rejected(_, "RATE_LIMITED"), .rejected(_, "TOO_MANY_REQUESTS"), .rejected(429, _):
            return rateLimitedRegisterMessage
        default:
            return api.userFacingMessage
        }
    }

    /// Plain-language copy for Greenfield's verification (challenge) errors.
    static func verificationMessage(_ api: APIError) -> String {
        switch api {
        case .rejected(_, "CHALLENGE_INVALID"):
            return "That code didn’t work. Check the latest email from Modula and try again."
        case .rejected(_, "CHALLENGE_EXPIRED"):
            return "That code has expired. Tap Resend code to get a new one."
        case .rejected(_, "CHALLENGE_REPLAYED"):
            return "That code was already used. If your email is verified, sign in."
        default:
            return api.userFacingMessage
        }
    }

    func signOut() async {
        guard !busy else { return }
        await willSignOut?()
        busy = true; account = nil
        defer { busy = false }
        do {
            try await client.signOut()
            error = nil
        } catch {
            self.error = "Signed out locally. Server revocation could not be confirmed."
        }
    }

    /// The server ended the session (revoked, or refresh rejected). Tokens are already
    /// cleared by the client; drop the account so the app returns to Sign In.
    func sessionInvalidated() {
        guard account != nil else { return }
        account = nil
        error = "Your session ended. Sign in again to continue."
    }

    func requestPasswordReset(email: String) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await client.requestPasswordReset(email: email)
            return true
        } catch let api as APIError {
            self.error = api.userFacingMessage
            return false
        } catch {
            self.error = "Unable to request a password reset right now."
            return false
        }
    }
}
