import Foundation

struct RegistrationPayload: Sendable {
    var email: String
    var password: String
    var handle: String
    var displayName: String?
    var inviteCode: String?
    var acceptedTerms: Bool
}

struct RegistrationResult: Sendable, Equatable {
    var accountID: String?
    var status: String?
    /// Greenfield returns `verificationChallengeId`; the code can only be confirmed with it.
    var challengeID: String?
    var verificationRequired: Bool
    var handle: String? = nil
    /// Masked address the code went to (`verificationDelivery.recipient`).
    var recipient: String? = nil
    /// When the emailed code stops working (`verificationExpiresAt`).
    var expiresAt: Date? = nil
}

/// `POST /v1/accounts/resend-verification`. Greenfield at ab0efa4f answers `{resent: true}`
/// only; a newer server may also name the replacement challenge, which is kept if present.
struct ResendVerificationResult: Sendable, Equatable {
    var challengeID: String?
    var expiresAt: Date?
    /// Masked address (`a•••@example.com`). Unknown emails get an identical-looking decoy,
    /// so this never proves an account exists.
    var recipient: String? = nil
}

/// Structured details from a Greenfield failure envelope (`error.retryable`, `error.details`).
/// All optional: servers before modula-latest #190 send none of them.
struct GreenfieldFailureDetails: Sendable, Equatable {
    var retryable: Bool? = nil
    /// Seconds to wait after a 429. Precedence (GreenField #203): `Retry-After`
    /// header, then `details.retryAfterSeconds` (number), then `details.retryAfter`
    /// ("<n> seconds" or a number).
    var retryAfterSeconds: Int? = nil
    /// `details.challengeId` / `expiresAt` / `delivery.recipient` from 403 EMAIL_VERIFICATION_REQUIRED.
    var challengeID: String? = nil
    var expiresAt: Date? = nil
    var recipient: String? = nil
    /// `error.message` from the envelope (for plain-language 400 VALIDATION_FAILED copy).
    var message: String? = nil

    static func parse(_ data: Data, response: HTTPURLResponse? = nil) -> GreenfieldFailureDetails? {
        let headerSeconds = retryAfterHeaderSeconds(response)
        let root = try? JSONDecoder().decode(JSONValue.self, from: data)
        let error = root?["error"]
        let details = error?["details"]
        var bodySeconds: Int?
        if let number = details?["retryAfterSeconds"]?.number {
            bodySeconds = Int(number)
        }
        var legacySeconds: Int?
        if let text = details?["retryAfter"]?.string {
            legacySeconds = Int(text.split(separator: " ").first ?? "")
        } else if let number = details?["retryAfter"]?.number {
            legacySeconds = Int(number)
        }
        let seconds = headerSeconds ?? bodySeconds ?? legacySeconds
        let parsed = GreenfieldFailureDetails(
            retryable: error?["retryable"]?.bool,
            retryAfterSeconds: seconds.flatMap { $0 >= 0 ? $0 : nil },
            challengeID: details?["challengeId"]?.string,
            expiresAt: GreenfieldTimestamp.parse(details?["expiresAt"]?.string),
            recipient: details?["delivery"]?["recipient"]?.string,
            message: error?["message"]?.string
        )
        if error == nil, headerSeconds == nil { return nil }
        return parsed
    }

    /// `Retry-After` as a delta-seconds integer. HTTP-date values are ignored.
    static func retryAfterHeaderSeconds(_ response: HTTPURLResponse?) -> Int? {
        guard let raw = response?.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let seconds = Int(raw), seconds >= 0 else { return nil }
        return seconds
    }
}

enum GreenfieldTimestamp {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct GreenfieldSessionInfo: Sendable, Identifiable, Equatable {
    var id: String
    var current: Bool
    var platform: String?
    var userAgent: String?
    var lastActive: String?
    var location: String?
}

struct PasswordResetConfirmPayload: Sendable {
    var token: String
    var newPassword: String
}

extension GreenfieldClient {
    func register(payload: RegistrationPayload) async throws -> RegistrationResult {
        var body: [String: JSONValue] = [
            "email": .string(payload.email),
            "password": .string(payload.password),
            "handle": .string(payload.handle),
            "acceptedTerms": .bool(payload.acceptedTerms)
        ]
        if let displayName = payload.displayName, !displayName.isEmpty {
            body["displayName"] = .string(displayName)
        }
        if let inviteCode = payload.inviteCode, !inviteCode.isEmpty {
            body["inviteCode"] = .string(inviteCode)
        }
        let value: JSONValue = try await publicJSON("POST", path: "/v1/accounts/register", body: .object(body))
        return RegistrationResult(
            accountID: value["accountId"]?.string ?? value["account_id"]?.string,
            status: value["status"]?.string,
            challengeID: value["verificationChallengeId"]?.string
                ?? value["challengeId"]?.string ?? value["challenge_id"]?.string,
            verificationRequired: value["verificationRequired"]?.bool
                ?? (value["status"]?.string != "active"),
            handle: value["primaryHandle"]?.string,
            recipient: value["verificationDelivery"]?["recipient"]?.string,
            expiresAt: GreenfieldTimestamp.parse(value["verificationExpiresAt"]?.string)
        )
    }

    func verifyEmail(challengeID: String?, code: String?, token: String?) async throws {
        var body: [String: JSONValue] = [:]
        if let token, !token.isEmpty { body["token"] = .string(token) }
        if let challengeID, !challengeID.isEmpty { body["challengeId"] = .string(challengeID) }
        if let code, !code.isEmpty { body["code"] = .string(code) }
        let _: JSONValue = try await publicJSON("POST", path: "/v1/accounts/verify-email", body: .object(body))
    }

    @discardableResult
    func resendVerification(email: String) async throws -> ResendVerificationResult {
        let value: JSONValue = try await publicJSON("POST", path: "/v1/accounts/resend-verification", body: .object([
            "email": .string(email)
        ]))
        return ResendVerificationResult(
            challengeID: value["verificationChallengeId"]?.string ?? value["challengeId"]?.string,
            expiresAt: GreenfieldTimestamp.parse(value["verificationExpiresAt"]?.string ?? value["expiresAt"]?.string),
            recipient: value["delivery"]?["recipient"]?.string
        )
    }

    func resetPassword(token: String, newPassword: String) async throws {
        let _: JSONValue = try await publicJSON("POST", path: "/v1/accounts/reset-password", body: .object([
            "token": .string(token),
            // Greenfield reads `newPassword` (register-routes.ts reset-password handler).
            "newPassword": .string(newPassword)
        ]))
    }

    func listSessions() async throws -> [GreenfieldSessionInfo] {
        let value: JSONValue = try await authenticatedJSON("GET", path: "/v1/accounts/me/sessions")
        let items = value.array ?? value["items"]?.array ?? value["sessions"]?.array ?? []
        return items.compactMap { item in
            guard let id = item["sessionId"]?.string ?? item["id"]?.string else { return nil }
            return GreenfieldSessionInfo(
                id: id,
                current: item["current"]?.bool ?? item["isCurrent"]?.bool ?? false,
                platform: item["platform"]?.string,
                userAgent: item["userAgent"]?.string ?? item["user_agent"]?.string,
                lastActive: item["lastActiveAt"]?.string ?? item["last_active_at"]?.string ?? item["updatedAt"]?.string,
                location: item["location"]?.string ?? item["approxLocation"]?.string
            )
        }
    }

    /// 404 `NOT_FOUND` ("Session not found"), including a session owned by someone else
    /// (GreenField #203), is treated as already gone.
    func revokeSession(id: String) async throws {
        let path = "/v1/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"
        do {
            let _: JSONValue = try await authenticatedJSON("DELETE", path: path)
        } catch let api as APIError where Self.isSessionAlreadyGone(api) {
            return
        }
    }

    static func isSessionAlreadyGone(_ api: APIError) -> Bool {
        if case .rejected(let status, let code) = api {
            return status == 404 || code == "NOT_FOUND"
        }
        return false
    }

    func revokeOtherSessions() async throws {
        let _: JSONValue = try await authenticatedJSON("DELETE", path: "/v1/accounts/me/sessions")
    }
}
