import XCTest
@testable import Modula

/// Records every request (method, path, headers, body) and answers from a handler. No network.
private final class PendingSignupRouter: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let authorization: String?
        let cookie: String?
        let body: [String: String]
    }

    nonisolated(unsafe) static var handler: (@Sendable (String, String, [String: String]) -> (Int, String))?
    nonisolated(unsafe) static var log: [Recorded] = []
    /// Extra response headers (e.g. Retry-After) merged into every mocked reply.
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let body = Self.decodeBody(request)
        Self.log.append(Recorded(
            method: method, path: path,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            cookie: request.value(forHTTPHeaderField: "Cookie"),
            body: body
        ))
        let (status, json) = Self.handler?(method, path, body) ?? (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
        var headers = ["Content-Type": "application/json"]
        for (field, value) in Self.responseHeaders { headers[field] = value }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func decodeBody(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues { "\($0)" }
    }
}

/// Canned bodies the (nonisolated, @Sendable) router reads.
private final class Responses: @unchecked Sendable {
    var register = ""
    var tokens = ""
    var me = ""
    var resend = ""
}

private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class AuthPendingSignupTests: XCTestCase {
    private var host = ""
    private var namespace = ""
    private let password = "correct-horse-battery-9"
    private let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    private let responses = Responses()

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString.prefix(8).lowercased()
        host = "pending-\(id).modula.test"
        namespace = "https://\(host)"
        PendingSignupRouter.log = []
        PendingSignupRouter.handler = nil
        PendingSignupRouter.responseHeaders = [:]
    }

    override func tearDown() {
        PendingSignupStore(namespace: namespace).clear()
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains(host) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        PendingSignupRouter.handler = nil
        PendingSignupRouter.responseHeaders = [:]
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStore() -> AuthenticationStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PendingSignupRouter.self]
        // A real cookie jar with a cookie for this host: requests must still carry none.
        config.httpCookieStorage = HTTPCookieStorage.shared
        let client = GreenfieldClient(baseURL: URL(string: namespace)!, transport: URLSession(configuration: config))
        let clock = self.clock
        return AuthenticationStore(client: client, pendingStore: PendingSignupStore(namespace: namespace), now: { clock.now })
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func registerResponse(challenge: String = "chal-1", expiresIn: TimeInterval = 3_600) -> String {
        #"{"ok":true,"data":{"accountId":"acct-a","primaryHandle":"newbie","status":"pendingVerification","verificationChallengeId":"\#(challenge)","verificationExpiresAt":"\#(iso(clock.now.addingTimeInterval(expiresIn)))","verificationDelivery":{"channel":"email","recipient":"n•••@example.com"}}}"#
    }

    private func tokens() -> String {
        let access = iso(Date().addingTimeInterval(900))
        let refresh = iso(Date().addingTimeInterval(86_400))
        return #"{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","sessionId":"sess-b","accessExpiresAt":"\#(access)","refreshExpiresAt":"\#(refresh)"}}"#
    }

    private let meB = #"{"ok":true,"data":{"accountId":"acct-b","primaryHandle":"existing","status":"active"}}"#

    private func payload(_ email: String = "  Newbie@Example.com ") -> RegistrationPayload {
        RegistrationPayload(email: email, password: password, handle: "newbie", displayName: "New Bie", inviteCode: nil, acceptedTerms: true)
    }

    private func registerPending(_ store: AuthenticationStore, expiresIn: TimeInterval = 3_600) async throws {
        responses.register = registerResponse(expiresIn: expiresIn)
        let r = responses
        PendingSignupRouter.handler = { method, path, _ in
            if method == "POST", path == "/v1/accounts/register" { return (201, r.register) }
            return (404, "{}")
        }
        _ = try await store.register(payload: payload())
    }

    // MARK: Persistence

    func testPendingStatePersistsInKeychainWithoutPassword() async throws {
        let store = makeStore()
        try await registerPending(store)

        let pending = try XCTUnwrap(store.pendingSignup)
        XCTAssertEqual(pending.email, "newbie@example.com")
        XCTAssertEqual(pending.accountID, "acct-a")
        XCTAssertEqual(pending.challengeID, "chal-1", "reads Greenfield's verificationChallengeId")
        XCTAssertEqual(pending.expiresAt.timeIntervalSince1970, clock.now.addingTimeInterval(3_600).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load(), pending, "round-trips through the Keychain")

        let raw = try XCTUnwrap(PendingSignupStore(namespace: namespace).storedData())
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.contains(password), "the password is never stored")
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any]).keys
        XCTAssertFalse(keys.contains { $0.lowercased().contains("password") || $0.lowercased().contains("token") })

        let register = try XCTUnwrap(PendingSignupRouter.log.first { $0.path == "/v1/accounts/register" })
        XCTAssertNil(register.authorization, "register sends no bearer")
    }

    func testColdLaunchResumesAtCodeStepAndVerifiesWithChallenge() async throws {
        try await registerPending(makeStore())

        // App killed: a brand-new store/client restores from the Keychain.
        let relaunched = makeStore()
        XCTAssertNil(relaunched.pendingSignup)
        let restored = try XCTUnwrap(relaunched.restorePendingSignup())
        XCTAssertEqual(restored.challengeID, "chal-1")

        // The code arrives late (well within its lifetime).
        clock.now = clock.now.addingTimeInterval(45 * 60)
        PendingSignupRouter.log = []
        PendingSignupRouter.handler = { method, path, body in
            guard method == "POST", path == "/v1/accounts/verify-email" else { return (404, "{}") }
            return body["challengeId"] == "chal-1" && body["code"] == "123456"
                ? (200, #"{"ok":true,"data":{"verified":true,"account":{"accountId":"acct-a"}}}"#)
                : (401, #"{"ok":false,"error":{"code":"CHALLENGE_INVALID"}}"#)
        }
        let ok = await relaunched.verifyPendingCode("123 456")
        XCTAssertTrue(ok)
        let verify = try XCTUnwrap(PendingSignupRouter.log.first)
        XCTAssertNil(verify.authorization, "verify sends no bearer")
        XCTAssertNil(relaunched.pendingSignup)
        XCTAssertNil(PendingSignupStore(namespace: namespace).load(), "verified sign-up is cleared")
        XCTAssertEqual(relaunched.lastVerifiedEmail, "newbie@example.com")
    }

    func testExpiredPendingStateIsClearedWithNotice() async throws {
        try await registerPending(makeStore(), expiresIn: 600)
        clock.now = clock.now.addingTimeInterval(601)

        let relaunched = makeStore()
        XCTAssertNil(relaunched.restorePendingSignup())
        XCTAssertNil(relaunched.pendingSignup)
        XCTAssertNil(PendingSignupStore(namespace: namespace).load())
        let notice = try XCTUnwrap(relaunched.pendingNotice)
        XCTAssertTrue(notice.contains("expired"))
        XCTAssertTrue(notice.contains("newbie@example.com"))
    }

    func testPendingLifetimeIsCappedAtTwentyFourHours() {
        let start = clock.now
        XCTAssertEqual(PendingSignupStore.expiry(server: start.addingTimeInterval(72 * 3_600), from: start),
                       start.addingTimeInterval(24 * 3_600))
        XCTAssertEqual(PendingSignupStore.expiry(server: nil, from: start), start.addingTimeInterval(24 * 3_600))
        XCTAssertEqual(PendingSignupStore.expiry(server: start.addingTimeInterval(600), from: start), start.addingTimeInterval(600))
    }

    // MARK: Sign-in while pending

    func testSignInToAnotherAccountClearsPendingAndSendsNoPendingCredential() async throws {
        let store = makeStore()
        try await registerPending(store)
        HTTPCookieStorage.shared.setCookie(HTTPCookie(properties: [
            .domain: host, .path: "/", .name: "pending", .value: "chal-1", .secure: "TRUE"
        ])!)

        PendingSignupRouter.log = []
        responses.tokens = tokens()
        responses.me = meB
        let r = responses
        PendingSignupRouter.handler = { method, path, _ in
            switch (method, path) {
            case ("POST", "/v1/sessions"): return (200, r.tokens)
            case ("GET", "/v1/accounts/me"): return (200, r.me)
            default: return (404, "{}")
            }
        }
        let ok = await store.signIn(email: "existing@example.com", password: "other-account-pw")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.account?.accountId, "acct-b")
        XCTAssertNil(store.pendingSignup)
        XCTAssertNil(PendingSignupStore(namespace: namespace).load())

        let session = try XCTUnwrap(PendingSignupRouter.log.first { $0.path == "/v1/sessions" })
        XCTAssertNil(session.authorization, "sign-in carries no bearer")
        XCTAssertNil(session.cookie, "sign-in carries no cookie")
        XCTAssertEqual(Set(session.body.keys), ["email", "password"])
        XCTAssertFalse(session.body.values.contains { $0.contains("chal-1") || $0.contains("newbie") })
        await store.signOut() // clears the session Keychain entry this test created
    }

    func testSignInToUnverifiedAccountExplainsVerificationAndKeepsPending() async throws {
        let store = makeStore()
        try await registerPending(store)
        PendingSignupRouter.handler = { method, path, _ in
            method == "POST" && path == "/v1/sessions"
                ? (401, #"{"ok":false,"error":{"code":"INVALID_CREDENTIALS"}}"#) : (404, "{}")
        }
        let ok = await store.signIn(email: "NEWBIE@example.com", password: password)
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.pendingSignup, "same email keeps the pending sign-up")
        XCTAssertTrue(store.signInNeedsVerification(email: "newbie@example.com"))
        XCTAssertEqual(store.error, "Finish verifying newbie@example.com first. Enter the code we emailed you.")
    }

    func testUseDifferentAccountClearsPendingState() async throws {
        let store = makeStore()
        try await registerPending(store)
        XCTAssertNotNil(PendingSignupStore(namespace: namespace).load())
        store.abandonPendingSignup()
        XCTAssertNil(store.pendingSignup)
        XCTAssertNil(PendingSignupStore(namespace: namespace).load())
        XCTAssertNil(makeStore().restorePendingSignup())
    }

    // MARK: Resend

    func testResendRespectsCooldownAndNeverPretendsSupersededCodeWorks() async throws {
        let store = makeStore()
        try await registerPending(store)
        responses.resend = #"{"ok":true,"data":{"resent":true}}"#
        let r = responses
        PendingSignupRouter.handler = { method, path, body in
            guard method == "POST", path == "/v1/accounts/resend-verification",
                  body["email"] == "newbie@example.com" else { return (404, "{}") }
            return (200, r.resend)
        }

        // Inside the cooldown: no request at all.
        clock.now = clock.now.addingTimeInterval(30)
        XCTAssertEqual(store.resendWait(), 30, accuracy: 0.5)
        let early = await store.resendPendingCode()
        XCTAssertFalse(early)
        let resendCalls = PendingSignupRouter.log.filter { $0.path == "/v1/accounts/resend-verification" }.count
        XCTAssertEqual(resendCalls, 0)

        // After the cooldown, Greenfield ab0efa4f answers {resent:true} with no new challenge.
        clock.now = clock.now.addingTimeInterval(31)
        let sent = await store.resendPendingCode()
        XCTAssertTrue(sent)
        XCTAssertNil(store.pendingSignup?.challengeID, "the superseded challenge isn't kept as if valid")
        XCTAssertEqual(store.pendingNotice, AuthenticationStore.resendUnconfirmableNotice)
        XCTAssertEqual(store.resendWait(), PendingSignupStore.resendCooldown, accuracy: 0.5)
        XCTAssertNil(PendingSignupRouter.log.last?.authorization, "resend sends no bearer")

        // Forge's fix returns the new challenge: it is stored and used.
        clock.now = clock.now.addingTimeInterval(61)
        responses.resend = #"{"ok":true,"data":{"resent":true,"challengeId":"chal-2","expiresAt":"\#(iso(clock.now.addingTimeInterval(1_800)))","delivery":{"channel":"email","recipient":"n•••@example.com"}},"meta":{"requestId":"r","serverTime":"\#(iso(clock.now))"}}"#
        _ = await store.resendPendingCode()
        XCTAssertEqual(store.pendingSignup?.challengeID, "chal-2", "#190 resend replaces the stored challenge")
        XCTAssertEqual(store.pendingSignup?.recipient, "n•••@example.com")
        let notice = try XCTUnwrap(store.pendingNotice)
        XCTAssertTrue(notice.hasPrefix("If n•••@example.com has a sign-up waiting"), "never claims the account exists")
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load()?.challengeID, "chal-2")
        XCTAssertEqual(store.pendingSignup?.expiresAt.timeIntervalSince1970 ?? 0,
                       clock.now.addingTimeInterval(1_800).timeIntervalSince1970, accuracy: 1)

        // Verification-send limit (5 per 10 min, retryable:false, no details): wait ~10 minutes.
        clock.now = clock.now.addingTimeInterval(61)
        PendingSignupRouter.handler = { _, _, _ in (429, #"{"ok":false,"error":{"code":"RATE_LIMITED","message":"x","retryable":false},"meta":{"requestId":"r"}}"#) }
        let limited = await store.resendPendingCode()
        XCTAssertFalse(limited)
        XCTAssertEqual(store.resendWait(), PendingSignupStore.rateLimitedCooldown, accuracy: 0.5)
        XCTAssertEqual(store.signupError, "Too many codes requested. Try again in about 10 minutes.")
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load()?.resendWait(at: clock.now) ?? 0,
                       PendingSignupStore.rateLimitedCooldown, accuracy: 0.5)
    }

    // MARK: Wrong codes, errors, reset contract

    func testFiveWrongCodesLockTheChallengeWithClearMessage() async throws {
        let store = makeStore()
        try await registerPending(store)
        PendingSignupRouter.handler = { _, _, _ in (401, #"{"ok":false,"error":{"code":"CHALLENGE_INVALID"}}"#) }
        for attempt in 1...PendingSignupStore.attemptLimit {
            let ok = await store.verifyPendingCode("000000")
            XCTAssertFalse(ok)
            XCTAssertEqual(store.pendingSignup?.failedAttempts, attempt)
        }
        XCTAssertEqual(store.signupError, AuthenticationStore.lockedMessage)
        PendingSignupRouter.log = []
        let blocked = await store.verifyPendingCode("111111")
        XCTAssertFalse(blocked)
        XCTAssertTrue(PendingSignupRouter.log.isEmpty, "a locked code isn't retried against the server")
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load()?.failedAttempts, PendingSignupStore.attemptLimit)
    }

    func testRegisterErrorsArePlainLanguage() {
        let conflict = AuthenticationStore.signupMessage(.rejected(409, "CONFLICT"))
        XCTAssertEqual(conflict, AuthenticationStore.checkEmailMessage)
        XCTAssertFalse(Self.revealsExistingAccount(conflict))
        XCTAssertEqual(AuthenticationStore.signupMessage(.rejected(409, "EMAIL_TAKEN")), AuthenticationStore.checkEmailMessage)
        XCTAssertEqual(AuthenticationStore.signupMessage(.rejected(409, "HANDLE_TAKEN")), "That username is taken. Pick another one.")
        XCTAssertEqual(AuthenticationStore.signupMessage(.rejected(429, "RATE_LIMITED")), AuthenticationStore.rateLimitedRegisterMessage)
        XCTAssertTrue(AuthenticationStore.signupMessage(.rejected(400, "VALIDATION_FAILED")).contains("10 characters"))
        XCTAssertTrue(AuthenticationStore.verificationMessage(.rejected(401, "CHALLENGE_EXPIRED")).contains("expired"))
        XCTAssertTrue(AuthenticationStore.verificationMessage(.rejected(401, "CHALLENGE_INVALID")).contains("didn’t work")
                      || AuthenticationStore.verificationMessage(.rejected(401, "CHALLENGE_INVALID")).contains("didn't work"))
    }

    /// Phrases that would tell the person this email already has an account.
    private static func revealsExistingAccount(_ text: String) -> Bool {
        let lowered = text.lowercased()
        for phrase in ["already registered", "already in use", "this email is already", "email is already registered"] {
            if lowered.contains(phrase) { return true }
        }
        return false
    }

    // MARK: GreenField #196 — 202 check-your-email, decoy, legacy 409

    func testRegister202GoesToCodeEntryWithoutRequiringAccountId() async throws {
        let store = makeStore()
        let expires = iso(clock.now.addingTimeInterval(3_600))
        // #190 / #196 shape: 202, verificationChallengeId, verificationExpiresAt, email;
        // accountId omitted (a decoy may lack it or send a fake one).
        PendingSignupRouter.handler = { method, path, _ in
            guard method == "POST", path == "/v1/accounts/register" else { return (404, "{}") }
            return (202, #"{"ok":true,"data":{"verificationChallengeId":"chal-202","verificationExpiresAt":"\#(expires)","email":"newbie@example.com","verificationDelivery":{"channel":"email","recipient":"n•••@example.com"}}}"#)
        }
        let result = try await store.register(payload: payload())
        XCTAssertEqual(result.challengeID, "chal-202")
        XCTAssertNil(result.accountID, "accountId is optional on a 202 / decoy")
        XCTAssertTrue(result.verificationRequired)
        let pending = try XCTUnwrap(store.pendingSignup)
        XCTAssertEqual(pending.email, "newbie@example.com")
        XCTAssertNil(pending.accountID)
        XCTAssertEqual(pending.challengeID, "chal-202")
        XCTAssertEqual(pending.recipient, "n•••@example.com")
        XCTAssertEqual(pending.expiresAt.timeIntervalSince1970, clock.now.addingTimeInterval(3_600).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load(), pending)
        let raw = String(decoding: try XCTUnwrap(PendingSignupStore(namespace: namespace).storedData()), as: UTF8.self)
        XCTAssertFalse(raw.contains(password))
        XCTAssertNil(PendingSignupRouter.log.first?.authorization, "register sends no bearer")
    }

    func testDecoyChallengeWrongCodeIsInvalidAndLocksAfterFive() async throws {
        let store = makeStore()
        let expires = iso(clock.now.addingTimeInterval(3_600))
        PendingSignupRouter.handler = { method, path, _ in
            guard method == "POST", path == "/v1/accounts/register" else { return (404, "{}") }
            // Decoy may carry a fake accountId; it must never verify.
            return (202, #"{"ok":true,"data":{"accountId":"acct-decoy","verificationChallengeId":"chal-decoy","verificationExpiresAt":"\#(expires)","email":"taken@example.com"}}"#)
        }
        _ = try await store.register(payload: payload("taken@example.com"))
        XCTAssertEqual(store.pendingSignup?.accountID, "acct-decoy")
        XCTAssertEqual(store.pendingSignup?.challengeID, "chal-decoy")

        PendingSignupRouter.log = []
        PendingSignupRouter.handler = { method, path, _ in
            guard method == "POST", path == "/v1/accounts/verify-email" else { return (404, "{}") }
            return (401, #"{"ok":false,"error":{"code":"CHALLENGE_INVALID"}}"#)
        }
        for attempt in 1...PendingSignupStore.attemptLimit {
            let ok = await store.verifyPendingCode("000000")
            XCTAssertFalse(ok)
            XCTAssertEqual(store.pendingSignup?.failedAttempts, attempt)
            if attempt < PendingSignupStore.attemptLimit {
                let message = try XCTUnwrap(store.signupError)
                XCTAssertTrue(message.contains("didn’t work") || message.contains("didn't work"), message)
                XCTAssertTrue(message.contains("tries left"), message)
                XCTAssertFalse(Self.revealsExistingAccount(message))
            }
        }
        XCTAssertEqual(store.signupError, AuthenticationStore.lockedMessage)
        XCTAssertNotNil(store.pendingSignup, "lockout must not clear or loop the pending sign-up")
        XCTAssertTrue(PendingSignupRouter.log.allSatisfy { $0.body["challengeId"] == "chal-decoy" })
        PendingSignupRouter.log = []
        let blocked = await store.verifyPendingCode("111111")
        XCTAssertFalse(blocked)
        XCTAssertTrue(PendingSignupRouter.log.isEmpty, "a locked decoy isn’t retried against the server")
        XCTAssertEqual(store.signupError, AuthenticationStore.lockedMessage)
    }

    func testLegacy409DoesNotRevealExistingAccountAndOpensCheckEmailPath() async throws {
        let store = makeStore()
        PendingSignupRouter.handler = { method, path, _ in
            method == "POST" && path == "/v1/accounts/register"
                ? (409, #"{"ok":false,"error":{"code":"EMAIL_TAKEN"}}"#)
                : (404, "{}")
        }
        let result = try await store.register(payload: payload("  Taken@Example.com "))
        XCTAssertTrue(result.verificationRequired)
        let pending = try XCTUnwrap(store.pendingSignup)
        XCTAssertEqual(pending.email, "taken@example.com")
        XCTAssertNil(pending.accountID)
        XCTAssertNil(pending.challengeID)
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load()?.email, "taken@example.com")
        XCTAssertNil(store.signupError)
        XCTAssertFalse(Self.revealsExistingAccount(AuthenticationStore.signupMessage(.rejected(409, "EMAIL_TAKEN"))))
        XCTAssertFalse(Self.revealsExistingAccount(AuthenticationStore.signupMessage(.rejected(409, "CONFLICT"))))
        XCTAssertFalse(Self.revealsExistingAccount(AuthenticationStore.checkEmailMessage))

        // CONFLICT (legacy generic 409) also opens the check-email path.
        PendingSignupStore(namespace: namespace).clear()
        let other = makeStore()
        PendingSignupRouter.handler = { method, path, _ in
            method == "POST" && path == "/v1/accounts/register"
                ? (409, #"{"ok":false,"error":{"code":"CONFLICT"}}"#)
                : (404, "{}")
        }
        _ = try await other.register(payload: payload("legacy@example.com"))
        XCTAssertEqual(other.pendingSignup?.email, "legacy@example.com")
        XCTAssertNil(other.signupError)

        // HANDLE_TAKEN stays on the form: the username is taken, not the email.
        let handleStore = makeStore()
        PendingSignupRouter.handler = { _, path, _ in
            path == "/v1/accounts/register"
                ? (409, #"{"ok":false,"error":{"code":"HANDLE_TAKEN"}}"#)
                : (404, "{}")
        }
        do {
            _ = try await handleStore.register(payload: payload("fresh@example.com"))
            XCTFail("HANDLE_TAKEN should still surface as an error")
        } catch let api as APIError {
            XCTAssertEqual(api, .rejected(409, "HANDLE_TAKEN"))
            XCTAssertEqual(AuthenticationStore.signupMessage(api), "That username is taken. Pick another one.")
        }
        XCTAssertNil(handleStore.pendingSignup)
    }

    func testVerifyEmailLinksRouteToSignInAndForgotPassword() {
        XCTAssertEqual(VerifyEmailView.AlternateActions.signInTitle, "Sign in")
        XCTAssertEqual(VerifyEmailView.AlternateActions.forgotPasswordTitle, "Forgot password")
        XCTAssertEqual(VerifyEmailView.AlternateActions.signInRoute, .auth(.login))
        XCTAssertEqual(VerifyEmailView.AlternateActions.forgotPasswordRoute, .auth(.forgotPassword))
        XCTAssertTrue(AuthRoute.allCases.contains(.login))
        XCTAssertTrue(AuthRoute.allCases.contains(.forgotPassword))
        let copy = VerifyEmailView.AlternateActions.existingAccountCopy
        XCTAssertTrue(copy.contains("already have an account"), copy)
        XCTAssertTrue(copy.contains("sign in"), copy)
        XCTAssertTrue(copy.contains("reset"), copy)
        XCTAssertFalse(Self.revealsExistingAccount(copy))
    }

    func testRegisterRateLimitedSurfacesAndStoresNothing() async {
        let store = makeStore()
        PendingSignupRouter.handler = { _, _, _ in (429, #"{"ok":false,"error":{"code":"RATE_LIMITED"}}"#) }
        do {
            _ = try await store.register(payload: payload())
            XCTFail("expected RATE_LIMITED")
        } catch {
            XCTAssertEqual(error as? APIError, .rejected(429, "RATE_LIMITED"))
        }
        XCTAssertNil(store.pendingSignup)
        XCTAssertNil(PendingSignupStore(namespace: namespace).load())
    }

    func testResetPasswordSendsNewPasswordField() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PendingSignupRouter.self]
        let client = GreenfieldClient(baseURL: URL(string: namespace)!, transport: URLSession(configuration: config))
        PendingSignupRouter.handler = { method, path, body in
            method == "POST" && path == "/v1/accounts/reset-password" && body["newPassword"] == "new-password-10" && body["token"] == "t"
                ? (200, #"{"ok":true,"data":{"reset":true}}"#) : (400, #"{"ok":false,"error":{"code":"VALIDATION_FAILED"}}"#)
        }
        try await client.resetPassword(token: "t", newPassword: "new-password-10")
        let request = try XCTUnwrap(PendingSignupRouter.log.last)
        XCTAssertNil(request.body["password"])
        XCTAssertNil(request.authorization)
    }

    // MARK: modula-latest #190 contract

    func testEmailVerificationRequiredOnSignInResumesAtCodeStep() async throws {
        let store = makeStore()
        let expires = iso(clock.now.addingTimeInterval(3_600))
        PendingSignupRouter.handler = { method, path, _ in
            guard method == "POST", path == "/v1/sessions" else { return (404, "{}") }
            return (403, #"{"ok":false,"error":{"code":"EMAIL_VERIFICATION_REQUIRED","message":"Verify your email","retryable":false,"details":{"challengeId":"chal-login","expiresAt":"\#(expires)","delivery":{"channel":"email","recipient":"p•••@example.com"}}},"meta":{"requestId":"r","serverTime":"\#(expires)"}}"#)
        }
        let ok = await store.signIn(email: "Pending@Example.com", password: password)
        XCTAssertFalse(ok)
        XCTAssertNil(store.account, "403 carries no tokens")
        XCTAssertTrue(store.resumeVerificationRequested)
        let pending = try XCTUnwrap(store.pendingSignup)
        XCTAssertEqual(pending.email, "pending@example.com")
        XCTAssertEqual(pending.challengeID, "chal-login")
        XCTAssertEqual(pending.recipient, "p•••@example.com")
        XCTAssertEqual(pending.expiresAt.timeIntervalSince1970, clock.now.addingTimeInterval(3_600).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load(), pending)
        XCTAssertEqual(store.error, "Your email isn’t verified yet. We sent a fresh code to p•••@example.com.")
        XCTAssertNil(PendingSignupRouter.log.first?.authorization, "sign-in sends no bearer")
        let raw = String(decoding: try XCTUnwrap(PendingSignupStore(namespace: namespace).storedData()), as: UTF8.self)
        XCTAssertFalse(raw.contains(password))

        // The fresh challenge is what verify uses.
        PendingSignupRouter.handler = { _, path, body in
            path == "/v1/accounts/verify-email" && body["challengeId"] == "chal-login" && body["code"] == "654321"
                ? (200, #"{"ok":true,"data":{"verified":true}}"#) : (401, #"{"ok":false,"error":{"code":"CHALLENGE_INVALID"}}"#)
        }
        let verified = await store.verifyPendingCode("654321")
        XCTAssertTrue(verified)
    }

    func testPerRouteRateLimitCountsDownRetryAfterThenReenables() async throws {
        let store = makeStore()
        PendingSignupRouter.handler = { _, _, _ in
            (429, #"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Rate limit exceeded; retry after 37 seconds","retryable":true,"details":{"retryAfter":"37 seconds","limit":10}},"meta":{"requestId":"r"}}"#)
        }
        let ok = await store.signIn(email: "someone@example.com", password: "whatever-pw")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "Too many attempts. Try again in 37 seconds.")
        XCTAssertEqual(store.rateLimitWait(), 37, accuracy: 0.5)
        clock.now = clock.now.addingTimeInterval(20)
        XCTAssertEqual(store.rateLimitWait(), 17, accuracy: 0.5)
        clock.now = clock.now.addingTimeInterval(18)
        XCTAssertEqual(store.rateLimitWait(), 0, "re-enabled after retryAfter")

        // Create Account on the per-route limit too.
        do {
            _ = try await store.register(payload: payload())
            XCTFail("expected 429")
        } catch {
            XCTAssertEqual(store.rateLimitNotice, "Too many attempts. Try again in 37 seconds.")
        }
    }

    func testDecodesWithAndWithoutPR190Fields() async throws {
        // Failure details.
        XCTAssertNil(GreenfieldFailureDetails.parse(Data(#"{"ok":true,"data":{}}"#.utf8)))
        let legacy = try XCTUnwrap(GreenfieldFailureDetails.parse(Data(#"{"ok":false,"error":{"code":"RATE_LIMITED"}}"#.utf8)))
        XCTAssertEqual(legacy, GreenfieldFailureDetails())
        XCTAssertEqual(AuthenticationStore.rateLimitWait(legacy), PendingSignupStore.rateLimitedCooldown)
        let route = try XCTUnwrap(GreenfieldFailureDetails.parse(Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","retryable":true,"details":{"retryAfter":"12 seconds"}}}"#.utf8)))
        XCTAssertEqual(route.retryAfterSeconds, 12)
        XCTAssertEqual(AuthenticationStore.rateLimitWait(route), 12)
        let numeric = try XCTUnwrap(GreenfieldFailureDetails.parse(Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","retryable":true,"details":{"retryAfter":5}}}"#.utf8)))
        XCTAssertEqual(numeric.retryAfterSeconds, 5)

        // Resend success, before and after #190.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PendingSignupRouter.self]
        let client = GreenfieldClient(baseURL: URL(string: namespace)!, transport: URLSession(configuration: config))
        responses.resend = #"{"ok":true,"data":{"resent":true}}"#
        let r = responses
        PendingSignupRouter.handler = { _, _, _ in (200, r.resend) }
        let before = try await client.resendVerification(email: "a@example.com")
        XCTAssertEqual(before, ResendVerificationResult(challengeID: nil, expiresAt: nil, recipient: nil))
        let expires = clock.now.addingTimeInterval(900)
        responses.resend = #"{"ok":true,"data":{"resent":true,"challengeId":"c-190","expiresAt":"\#(iso(expires))","delivery":{"channel":"email","recipient":"a•••@example.com"}},"meta":{"requestId":"r","serverTime":"\#(iso(clock.now))"}}"#
        let after = try await client.resendVerification(email: "a@example.com")
        XCTAssertEqual(after.challengeID, "c-190")
        XCTAssertEqual(after.recipient, "a•••@example.com")
        XCTAssertEqual(after.expiresAt?.timeIntervalSince1970 ?? 0, expires.timeIntervalSince1970, accuracy: 1)

        // Register: masked recipient from verificationDelivery.
        responses.register = registerResponse()
        PendingSignupRouter.handler = { _, _, _ in (201, r.register) }
        let registered = try await client.register(payload: payload())
        XCTAssertEqual(registered.challengeID, "chal-1")
        XCTAssertEqual(registered.recipient, "n•••@example.com")
    }

    // MARK: GreenField #203 — Retry-After, 400 copy, revoke 404, reuse keeps pending

    func testSignIn429PrefersRetryAfterHeaderThenBodyFallbacks() async throws {
        let store = makeStore()

        // Header wins over a conflicting body.
        PendingSignupRouter.responseHeaders = ["Retry-After": "30"]
        PendingSignupRouter.handler = { _, path, _ in
            path == "/v1/sessions"
                ? (429, #"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many sign-in attempts. Try again later.","retryable":true,"details":{"retryAfterSeconds":99,"retryAfter":"12 seconds"}}}"#)
                : (404, "{}")
        }
        let first = await store.signIn(email: "someone@example.com", password: "whatever-pw")
        XCTAssertFalse(first)
        XCTAssertEqual(store.error, "Too many attempts. Try again in 30 seconds.")
        XCTAssertEqual(store.rateLimitWait(), 30, accuracy: 0.5)

        // No header: details.retryAfterSeconds (number) wins over the legacy string.
        PendingSignupRouter.responseHeaders = [:]
        clock.now = clock.now.addingTimeInterval(60)
        PendingSignupRouter.handler = { _, path, _ in
            path == "/v1/sessions"
                ? (429, #"{"ok":false,"error":{"code":"RATE_LIMITED","retryable":true,"details":{"retryAfterSeconds":45,"retryAfter":"12 seconds"}}}"#)
                : (404, "{}")
        }
        _ = await store.signIn(email: "someone@example.com", password: "whatever-pw")
        XCTAssertEqual(store.error, "Too many attempts. Try again in 45 seconds.")
        XCTAssertEqual(store.rateLimitWait(), 45, accuracy: 0.5)

        // No header, no retryAfterSeconds: legacy `details.retryAfter` string.
        clock.now = clock.now.addingTimeInterval(60)
        PendingSignupRouter.handler = { _, path, _ in
            path == "/v1/sessions"
                ? (429, #"{"ok":false,"error":{"code":"RATE_LIMITED","retryable":true,"details":{"retryAfter":"16 seconds"}}}"#)
                : (404, "{}")
        }
        _ = await store.signIn(email: "someone@example.com", password: "whatever-pw")
        XCTAssertEqual(store.error, "Too many attempts. Try again in 16 seconds.")
        XCTAssertEqual(store.rateLimitWait(), 16, accuracy: 0.5)

        // Parser unit: header > seconds > string.
        let header = HTTPURLResponse(
            url: URL(string: "https://example.com/v1/sessions")!,
            statusCode: 429, httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "7"]
        )!
        let parsed = GreenfieldFailureDetails.parse(
            Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","retryable":true,"details":{"retryAfterSeconds":99,"retryAfter":"12 seconds"}}}"#.utf8),
            response: header
        )
        XCTAssertEqual(parsed?.retryAfterSeconds, 7)
        let bodyOnly = GreenfieldFailureDetails.parse(
            Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","details":{"retryAfterSeconds":11,"retryAfter":"3 seconds"}}}"#.utf8)
        )
        XCTAssertEqual(bodyOnly?.retryAfterSeconds, 11)
    }

    func testValidationFailedShowsPlainLanguageServerMessage() async throws {
        let store = makeStore()
        PendingSignupRouter.handler = { _, path, body in
            if path == "/v1/sessions" {
                XCTAssertFalse(body.isEmpty, "sign-in must send a JSON body")
                return (400, #"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"Email required","retryable":false}}"#)
            }
            return (404, "{}")
        }
        let ok = await store.signIn(email: "not-an-email", password: "whatever-pw")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "Email required")

        PendingSignupRouter.handler = { _, path, body in
            if path == "/v1/accounts/register" {
                XCTAssertFalse(body.isEmpty)
                return (400, #"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"Email required"}}"#)
            }
            return (404, "{}")
        }
        do {
            _ = try await store.register(payload: payload())
            XCTFail("expected VALIDATION_FAILED")
        } catch let api as APIError {
            XCTAssertEqual(api, .rejected(400, "VALIDATION_FAILED"))
            XCTAssertEqual(
                AuthenticationStore.signupMessage(api, details: GreenfieldFailureDetails.parse(Data(#"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"Email required"}}"#.utf8))),
                "Email required"
            )
        }
        XCTAssertEqual(
            AuthenticationStore.validationMessage(
                details: GreenfieldFailureDetails.parse(Data(#"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"Email required"}}"#.utf8))
            ),
            "Email required"
        )
        XCTAssertEqual(AuthenticationStore.signupMessage(.rejected(400, "VALIDATION_FAILED"), details: GreenfieldFailureDetails(message: "Email required")), "Email required")
    }

    func testSessionInvalidatedKeepsPendingSignupAndShowsNeutralNotice() async throws {
        let store = makeStore()
        responses.tokens = tokens()
        responses.me = meB
        let r = responses
        PendingSignupRouter.handler = { method, path, _ in
            switch (method, path) {
            case ("POST", "/v1/sessions"): return (200, r.tokens)
            case ("GET", "/v1/accounts/me"): return (200, r.me)
            default: return (404, "{}")
            }
        }
        XCTAssertTrue(await store.signIn(email: "existing@example.com", password: "other-account-pw"))
        XCTAssertNotNil(store.account)

        let pending = PendingSignup(
            email: "newbie@example.com",
            handle: "newbie",
            accountID: "acct-a",
            challengeID: "chal-1",
            createdAt: clock.now,
            expiresAt: clock.now.addingTimeInterval(3_600),
            lastCodeSentAt: clock.now,
            resendAvailableAt: clock.now
        )
        try PendingSignupStore(namespace: namespace).save(pending)
        XCTAssertEqual(store.restorePendingSignup()?.email, "newbie@example.com")

        store.sessionInvalidated()
        XCTAssertNil(store.account)
        XCTAssertEqual(store.error, "Your session ended. Sign in again to continue.")
        XCTAssertEqual(store.pendingSignup?.email, "newbie@example.com")
        XCTAssertEqual(PendingSignupStore(namespace: namespace).load()?.email, "newbie@example.com")
        await store.signOut()
    }

    func testForgotPasswordDoesNotSendAnEmptyBody() async {
        let store = makeStore()
        PendingSignupRouter.log = []
        PendingSignupRouter.handler = { _, _, _ in (200, #"{"ok":true,"data":{"requested":true}}"#) }
        let sent = await store.requestPasswordReset(email: "   ")
        XCTAssertFalse(sent)
        XCTAssertEqual(store.error, "Email required")
        XCTAssertTrue(PendingSignupRouter.log.isEmpty, "a blank email must not hit the network")
    }
}
