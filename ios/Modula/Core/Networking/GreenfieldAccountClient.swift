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
    /// When the emailed code stops working (`verificationExpiresAt`).
    var expiresAt: Date? = nil
}

/// `POST /v1/accounts/resend-verification`. Greenfield at ab0efa4f answers `{resent: true}`
/// only; a newer server may also name the replacement challenge, which is kept if present.
struct ResendVerificationResult: Sendable, Equatable {
    var challengeID: String?
    var expiresAt: Date?
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
            expiresAt: GreenfieldTimestamp.parse(value["verificationExpiresAt"]?.string ?? value["expiresAt"]?.string)
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

    func revokeSession(id: String) async throws {
        let path = "/v1/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"
        let _: JSONValue = try await authenticatedJSON("DELETE", path: path)
    }

    func revokeOtherSessions() async throws {
        let _: JSONValue = try await authenticatedJSON("DELETE", path: "/v1/accounts/me/sessions")
    }
}
