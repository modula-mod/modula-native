import XCTest
@testable import Modula

/// URLProtocol tests for Mosaic #201: deleteData returns 401 STEP_UP_REQUIRED when
/// the session is older than 15 minutes; native steps up once and retries once.
/// No network leaves this process.
final class ModuleUninstallStepUpTests: XCTestCase {
    private let moduleID = "digital.modula.notes"

    override func tearDown() {
        UninstallRouterProtocol.handler = nil
        UninstallRouterProtocol.log = []
        super.tearDown()
    }

    func testStepUpThenSuccessfulRetry() async throws {
        let client = makeClient()
        let lock = NSLock()
        nonisolated(unsafe) var deleteAttempts = 0
        nonisolated(unsafe) var stepUpBody: JSONValue?
        nonisolated(unsafe) var retryBody: JSONValue?
        nonisolated(unsafe) var stepUpHasBearer = false

        UninstallRouterProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                if deleteAttempts == 1 {
                    return Self.failure(401, "STEP_UP_REQUIRED", message: "Recent stronger authentication required")
                }
                retryBody = bodyJSON(request)
                return Self.ok(#"{"ok":true,"data":{"status":"uninstalling"}}"#, status: 202)
            case ("POST", "/v1/auth/step-up/password"):
                stepUpBody = bodyJSON(request)
                stepUpHasBearer = (request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer ")
                return Self.ok(#"{"ok":true,"data":{"stepUp":true,"authenticationStrength":"medium","validForSeconds":600}}"#)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "unused-sign-in-password")
        let flow = ModuleUninstallFlow(client: client)
        let first = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-aaaaaaaa"
        )
        XCTAssertEqual(first, .needsPasswordStepUp)
        XCTAssertEqual(deleteAttempts, 1)

        let second = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "correct-horse", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-aaaaaaaa"
        )
        XCTAssertEqual(second, .succeeded)
        XCTAssertEqual(deleteAttempts, 2)
        XCTAssertTrue(stepUpHasBearer, "Step-up is an authenticated route and must send the current bearer")
        XCTAssertEqual(stepUpBody?["password"]?.string, "correct-horse")
        XCTAssertEqual(stepUpBody?.objectKeys.sorted(), ["password"], "Body must be only {password}")
        XCTAssertEqual(retryBody?["choice"]?.string, "deleteData")
        XCTAssertEqual(retryBody?["confirmDelete"]?.bool, true)
        XCTAssertNil(retryBody?["recentAuth"], "recentAuth is ignored by #201 and must not be sent")
        XCTAssertEqual(retryBody?["idempotencyKey"]?.string, "ios-uninstall-notes-aaaaaaaa")
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/auth/step-up/password") }.count, 1)
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 0)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "STEP_UP_REQUIRED must not sign the user out")
    }

    func testCancelLeavesModuleInstalledAndDoesNotStepUp() async throws {
        let client = makeClient()
        nonisolated(unsafe) var deleteAttempts = 0
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                return Self.failure(401, "STEP_UP_REQUIRED", message: "Recent stronger authentication required")
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let flow = ModuleUninstallFlow(client: client)
        let first = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-bbbbbbbb"
        )
        XCTAssertEqual(first, .needsPasswordStepUp)
        // Cancel is a UI action: no password submit, no second DELETE.
        XCTAssertEqual(deleteAttempts, 1)
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.contains("/v1/auth/step-up/password") }.count, 0)
        XCTAssertTrue(ModuleUninstallOutcome.cancelled.leavesModuleInstalled)
        XCTAssertEqual(ModuleUninstallFlow.cancelledNotice, "The module is still installed. Your password is needed to delete its data.")
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testWrongPasswordShowsInlineErrorAndDoesNotRetryDelete() async throws {
        let client = makeClient()
        nonisolated(unsafe) var deleteAttempts = 0
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                return Self.failure(401, "STEP_UP_REQUIRED")
            case ("POST", "/v1/auth/step-up/password"):
                return Self.failure(
                    400,
                    "VALIDATION_FAILED",
                    message: "That password is not correct",
                    fieldErrors: #"{"password":"That password is not correct"}"#
                )
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let flow = ModuleUninstallFlow(client: client)
        _ = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-cccccccc"
        )
        let second = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "wrong-password", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-cccccccc"
        )
        XCTAssertEqual(second, .passwordRejected("That password is not correct"))
        XCTAssertEqual(deleteAttempts, 1, "A wrong password must not retry deleteData")
        XCTAssertTrue(second.leavesModuleInstalled)
    }

    func testSecondStepUpRequiredRePromptsOnceThenStops() async throws {
        let client = makeClient()
        nonisolated(unsafe) var deleteAttempts = 0
        nonisolated(unsafe) var stepUpAttempts = 0
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                return Self.failure(
                    401,
                    "STEP_UP_REQUIRED",
                    message: "Recent stronger authentication required",
                    details: #"{"action":"delete_module_data","maxAgeSeconds":900}"#
                )
            case ("POST", "/v1/auth/step-up/password"):
                stepUpAttempts += 1
                return Self.ok(#"{"ok":true,"data":{"stepUp":true,"authenticationStrength":"medium","validForSeconds":600}}"#)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let flow = ModuleUninstallFlow(client: client)
        XCTAssertEqual(
            await flow.requestUninstall(moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-dddddddd"),
            .needsPasswordStepUp
        )
        let afterFirstSubmit = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "correct-horse", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-dddddddd", isReprompt: false
        )
        XCTAssertEqual(afterFirstSubmit, .needsPasswordStepUp, "A second STEP_UP_REQUIRED re-prompts the sheet once; it does not loop silently")
        XCTAssertEqual(deleteAttempts, 2)
        XCTAssertEqual(stepUpAttempts, 1)

        let afterReprompt = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "correct-horse", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-dddddddd", isReprompt: true
        )
        guard case .stillRequiresStepUp(let message) = afterReprompt else {
            return XCTFail("expected stillRequiresStepUp after the re-prompt, got \(afterReprompt)")
        }
        XCTAssertEqual(message, ModuleUninstallFlow.stillRequiresStepUpMessage)
        XCTAssertEqual(deleteAttempts, 3, "deleteData is retried once per confirmed password, then stops")
        XCTAssertEqual(stepUpAttempts, 2, "the re-prompt may step up once more; it must not continue after that")
        XCTAssertTrue(afterReprompt.leavesModuleInstalled)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "A repeated STEP_UP_REQUIRED must not invalidate the session")
    }

    func testRateLimitedRespectsRetryAfter() async throws {
        let client = makeClient()
        nonisolated(unsafe) var deleteAttempts = 0
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                return Self.failure(401, "STEP_UP_REQUIRED")
            case ("POST", "/v1/auth/step-up/password"):
                return (
                    429,
                    #"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many attempts. Try again in a few minutes.","retryable":true}}"#,
                    ["Retry-After": "42"]
                )
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let flow = ModuleUninstallFlow(client: client)
        _ = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-eeeeeeee"
        )
        let second = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "correct-horse", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-eeeeeeee"
        )
        XCTAssertEqual(second, .rateLimited(retryAfter: 42, message: "Too many attempts. Try again in a few minutes."))
        XCTAssertEqual(deleteAttempts, 1, "429 must not retry deleteData")
        XCTAssertTrue(second.leavesModuleInstalled)
    }

    func testStepUpRequiredDoesNotRefreshOrSignOut() async throws {
        let client = makeClient()
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                return Self.failure(401, "STEP_UP_REQUIRED")
            case ("POST", "/v1/sessions/refresh"):
                return Self.ok(Self.tokens)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        do {
            try await client.uninstallModule(
                moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-ffffffff"
            )
            XCTFail("expected STEP_UP_REQUIRED")
        } catch {
            XCTAssertNotNil(APIError.requiresStepUp(error), "\(error)")
        }
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 0)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testKeepDataDoesNotSendConfirmDelete() async throws {
        let client = makeClient()
        nonisolated(unsafe) var body: JSONValue?
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                body = bodyJSON(request)
                return Self.ok(#"{"ok":true,"data":{"status":"uninstalling"}}"#, status: 202)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }
        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let outcome = await ModuleUninstallFlow(client: client).requestUninstall(
            moduleID: moduleID, choice: .keepData, confirmDelete: false, idempotencyKey: "ios-uninstall-notes-gggggggg"
        )
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(body?["choice"]?.string, "keepData")
        XCTAssertNil(body?["confirmDelete"])
    }

    func testRetryAfterPrefersHeaderThenRetryAfterSecondsThenLegacyString() throws {
        let url = URL(string: "https://uninstall-stepup.modula.test/v1/auth/step-up/password")!
        func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }

        let allThree = Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many attempts. Try again in a few minutes.","retryable":true,"details":{"retryAfterSeconds":99,"retryAfter":"30 seconds"}}}"#.utf8)
        do {
            _ = try GreenfieldClient.decodePasswordStepUp(allThree, response: response(429, headers: ["Retry-After": "10"]))
            XCTFail("expected rate limit")
        } catch let error as PasswordStepUpFailure {
            XCTAssertEqual(error, .rateLimited(retryAfter: 10, message: "Too many attempts. Try again in a few minutes."))
        }

        do {
            _ = try GreenfieldClient.decodePasswordStepUp(allThree, response: response(429))
            XCTFail("expected rate limit")
        } catch let error as PasswordStepUpFailure {
            XCTAssertEqual(error, .rateLimited(retryAfter: 99, message: "Too many attempts. Try again in a few minutes."))
        }

        let legacyOnly = Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many attempts. Try again in a few minutes.","retryable":true,"details":{"retryAfter":"20 seconds"}}}"#.utf8)
        do {
            _ = try GreenfieldClient.decodePasswordStepUp(legacyOnly, response: response(429))
            XCTFail("expected rate limit")
        } catch let error as PasswordStepUpFailure {
            XCTAssertEqual(error, .rateLimited(retryAfter: 20, message: "Too many attempts. Try again in a few minutes."))
        }

        let none = Data(#"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many attempts. Try again in a few minutes.","retryable":true}}"#.utf8)
        do {
            _ = try GreenfieldClient.decodePasswordStepUp(none, response: response(429))
            XCTFail("expected rate limit")
        } catch let error as PasswordStepUpFailure {
            XCTAssertEqual(error, .rateLimited(retryAfter: nil, message: "Too many attempts. Try again in a few minutes."), "Do not invent a timer when no Retry-After, retryAfterSeconds, or retryAfter is present")
        }

        // HTTP-date Retry-After is ignored; fall through to retryAfterSeconds.
        do {
            _ = try GreenfieldClient.decodePasswordStepUp(allThree, response: response(429, headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"]))
            XCTFail("expected rate limit")
        } catch let error as PasswordStepUpFailure {
            XCTAssertEqual(error, .rateLimited(retryAfter: 99, message: "Too many attempts. Try again in a few minutes."))
        }
    }

    func testPasswordConflictFallsBackToTOTPThenSuccessfulRetry() async throws {
        let client = makeClient()
        let lock = NSLock()
        nonisolated(unsafe) var deleteAttempts = 0
        nonisolated(unsafe) var totpBody: JSONValue?
        nonisolated(unsafe) var totpHasBearer = false

        UninstallRouterProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                if deleteAttempts == 1 {
                    return Self.failure(401, "STEP_UP_REQUIRED", message: "Recent stronger authentication required")
                }
                return Self.ok(#"{"ok":true,"data":{"status":"uninstalling"}}"#, status: 202)
            case ("POST", "/v1/auth/step-up/password"):
                return Self.failure(409, "CONFLICT", message: "This account has no password")
            case ("POST", "/v1/auth/step-up/totp"):
                totpBody = bodyJSON(request)
                totpHasBearer = (request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer ")
                return Self.ok(#"{"ok":true,"data":{"stepUp":true,"authenticationStrength":"strong"}}"#)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "unused-sign-in-password")
        let flow = ModuleUninstallFlow(client: client)
        let first = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-totp0001"
        )
        XCTAssertEqual(first, .needsPasswordStepUp)

        let afterPassword = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "any-password", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-totp0001"
        )
        XCTAssertEqual(afterPassword, .needsTOTP)
        XCTAssertEqual(deleteAttempts, 1, "409 must not retry deleteData")
        XCTAssertTrue(afterPassword.leavesModuleInstalled)

        let afterTOTP = await flow.submitTOTPAndRetryDelete(
            moduleID: moduleID,
            code: "123456",
            confirmDelete: true,
            idempotencyKey: "ios-uninstall-notes-totp0001",
            passwordWasUnavailable: true
        )
        XCTAssertEqual(afterTOTP, .succeeded)
        XCTAssertEqual(deleteAttempts, 2)
        XCTAssertTrue(totpHasBearer, "TOTP step-up is an authenticated route and must send the current bearer")
        XCTAssertEqual(totpBody?["code"]?.string, "123456")
        XCTAssertEqual(totpBody?.objectKeys.sorted(), ["code"], "Body must be only {code}")
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/auth/step-up/totp") }.count, 1)
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 0)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testNeitherPasswordNorTOTPLeadsToSignInAgain() async throws {
        let client = makeClient()
        nonisolated(unsafe) var deleteAttempts = 0
        UninstallRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return Self.ok(Self.tokens)
            case ("GET", "/v1/accounts/me"): return Self.ok(Self.me)
            case ("DELETE", "/v1/modules/digital.modula.notes/install"):
                deleteAttempts += 1
                return Self.failure(401, "STEP_UP_REQUIRED")
            case ("POST", "/v1/auth/step-up/password"):
                return Self.failure(409, "CONFLICT", message: "This account has no password")
            case ("POST", "/v1/auth/step-up/totp"):
                return Self.failure(401, "AUTH_METHOD_UNAVAILABLE", message: "Authenticator is not enabled")
            case ("POST", "/v1/sessions/refresh"):
                return Self.ok(Self.tokens)
            default:
                return Self.failure(404, "NOT_FOUND")
            }
        }

        _ = try await client.signIn(email: "owner@modula.test", password: "pw")
        let flow = ModuleUninstallFlow(client: client)
        _ = await flow.requestUninstall(
            moduleID: moduleID, choice: .deleteData, confirmDelete: true, idempotencyKey: "ios-uninstall-notes-neither01"
        )
        let afterPassword = await flow.submitPasswordAndRetryDelete(
            moduleID: moduleID, password: "any-password", confirmDelete: true, idempotencyKey: "ios-uninstall-notes-neither01"
        )
        XCTAssertEqual(afterPassword, .needsTOTP)

        let afterTOTP = await flow.submitTOTPAndRetryDelete(
            moduleID: moduleID,
            code: "000000",
            confirmDelete: true,
            idempotencyKey: "ios-uninstall-notes-neither01",
            passwordWasUnavailable: true
        )
        XCTAssertEqual(afterTOTP, .needsSignInAgain)
        XCTAssertTrue(afterTOTP.leavesModuleInstalled)
        XCTAssertEqual(deleteAttempts, 1, "Sign-in-again must not retry deleteData")
        XCTAssertEqual(UninstallRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 0, "AUTH_METHOD_UNAVAILABLE must not refresh or end the session")
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    // MARK: - Helpers

    private func makeClient() -> GreenfieldClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UninstallRouterProtocol.self]
        UninstallRouterProtocol.log = []
        UninstallRouterProtocol.handler = nil
        return GreenfieldClient(
            baseURL: URL(string: "https://uninstall-stepup-\(UUID().uuidString.prefix(8)).modula.test")!,
            transport: URLSession(configuration: config)
        )
    }

    private static var tokens: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let access = formatter.string(from: Date().addingTimeInterval(900))
        let refresh = formatter.string(from: Date().addingTimeInterval(86_400))
        return #"{"ok":true,"data":{"accessToken":"access-1","refreshToken":"refresh-1","sessionId":"s","accessExpiresAt":"\#(access)","refreshExpiresAt":"\#(refresh)"}}"#
    }

    private static let me = #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active","email":"owner@modula.test"}}"#

    private static func ok(_ body: String, status: Int = 200) -> (Int, String, [String: String]) {
        (status, body, [:])
    }

    private static func failure(
        _ status: Int,
        _ code: String,
        message: String = "Rejected",
        fieldErrors: String? = nil,
        details: String? = nil,
        headers: [String: String] = [:]
    ) -> (Int, String, [String: String]) {
        let fields = fieldErrors.map { #","fieldErrors":\#($0)"# } ?? ""
        let detail = details.map { #","details":\#($0)"# } ?? ""
        return (status, #"{"ok":false,"error":{"code":"\#(code)","message":"\#(message)"\#(fields)\#(detail)}}"#, headers)
    }

    func testStepUpRequiredDecodesActionAndMaxAgeSeconds() {
        let body = Data(#"{"ok":false,"error":{"code":"STEP_UP_REQUIRED","message":"Recent stronger authentication required","details":{"action":"delete_module_data","maxAgeSeconds":900}}}"#.utf8)
        let error = GreenfieldClient.decodedError(from: body, status: 401)
        let requirement = error.requiresStepUp
        XCTAssertNotNil(requirement)
        XCTAssertEqual(requirement?.action, "delete_module_data")
        XCTAssertEqual(requirement?.maxAgeSeconds, 900)
        XCTAssertEqual(error.code, "STEP_UP_REQUIRED")
        if case .stepUpRequired(let value) = error {
            XCTAssertEqual(value, requirement)
        } else {
            XCTFail("expected stepUpRequired, got \(error)")
        }
    }

    func testStepUpRequiredDecodesWithoutDetailsOnOlderServers() {
        let body = Data(#"{"ok":false,"error":{"code":"STEP_UP_REQUIRED","message":"Recent stronger authentication required"}}"#.utf8)
        let error = GreenfieldClient.decodedError(from: body, status: 401)
        let requirement = error.requiresStepUp
        XCTAssertNotNil(requirement, "Older servers still produce a step-up error")
        XCTAssertNil(requirement?.action)
        XCTAssertNil(requirement?.maxAgeSeconds)
        if case .stepUpRequired(let value) = error {
            XCTAssertEqual(value, StepUpRequirement(action: nil, maxAgeSeconds: nil))
        } else {
            XCTFail("expected stepUpRequired, got \(error)")
        }
    }

}

private final class UninstallRouterProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String, [String: String]))?
    nonisolated(unsafe) static var log: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.log.append("\(request.httpMethod ?? "GET") \(path) \(request.value(forHTTPHeaderField: "Authorization") ?? "-")")
        let (status, body, extra) = Self.handler?(request) ?? (500, "{}", [:])
        var headers = ["Content-Type": "application/json"]
        for (key, value) in extra { headers[key] = value }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func bodyJSON(_ request: URLRequest) -> JSONValue? {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&chunk, maxLength: chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
        }
        data = buffer
    }
    return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

private extension JSONValue {
    var objectKeys: [String] {
        if case .object(let value) = self { return Array(value.keys) }
        return []
    }
}
