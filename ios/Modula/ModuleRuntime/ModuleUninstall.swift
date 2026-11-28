import Foundation

/// Retention choice on `DELETE /v1/modules/:id/install`.
/// `keepData` needs no step-up. `deleteData` requires `confirmDelete` and, when the
/// session is older than 15 minutes, server-side step-up (Mosaic #201).
enum ModuleUninstallChoice: String, Sendable, Equatable {
    case keepData
    case deleteData
}

/// Result of `POST /v1/auth/step-up/password` or `POST /v1/auth/step-up/totp`.
/// The session's `recent_authentication_at` is refreshed; no separate step-up
/// token is issued. Retry the original call with the same bearer.
/// `validForSeconds` is present on password step-up (currently 600); TOTP
/// success is `{stepUp:true, authenticationStrength:"strong"}`. The delete-data
/// policy window is 15 minutes.
struct PasswordStepUpResult: Codable, Sendable, Equatable {
    var stepUp: Bool
    var authenticationStrength: String?
    var validForSeconds: Int?
}

/// Credential used to refresh `recent_authentication_at` before retrying deleteData.
enum ModuleStepUpCredential: Sendable, Equatable {
    case password(String)
    /// `passwordUnavailable` is true when password step-up already returned 409
    /// CONFLICT (no active password). A subsequent TOTP `AUTH_METHOD_UNAVAILABLE`
    /// then means the account has neither method and must sign in again.
    case totp(code: String, passwordUnavailable: Bool)
}

enum PasswordStepUpFailure: Error, Equatable, Sendable, LocalizedError {
    case validation(String)
    case rateLimited(retryAfter: TimeInterval?, message: String)
    case conflict(String)
    case methodUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .rateLimited(_, let message), .conflict(let message),
             .methodUnavailable(let message), .failed(let message):
            return message
        }
    }
}

enum ModuleUninstallOutcome: Equatable, Sendable {
    case succeeded
    case needsPasswordStepUp
    case needsTOTP
    case needsSignInAgain
    case cancelled
    case passwordRejected(String)
    case rateLimited(retryAfter: TimeInterval?, message: String)
    case unavailable(String)
    case stillRequiresStepUp(String)
    case failed(String)

    /// The module stays installed for every outcome except `succeeded`.
    var leavesModuleInstalled: Bool { self != .succeeded }
}

/// Generic uninstall orchestration (no module-specific cases).
/// On `401 STEP_UP_REQUIRED` from deleteData, the caller presents a step-up sheet,
/// then `submitStepUpAndRetryDelete` steps up once and retries deleteData once.
/// A 409 from password step-up falls back to `POST /v1/auth/step-up/totp`.
/// If the account has neither a password nor TOTP, the outcome is `needsSignInAgain`.
struct ModuleUninstallFlow: Sendable {
    let client: GreenfieldClient

    static let stillRequiresStepUpMessage =
        "Your identity was confirmed, but deleting this module’s data still needs a stronger sign-in. The module is still installed."

    static let cancelledNotice =
        "The module is still installed. Your password is needed to delete its data."

    static let signInAgainNotice =
        "This account has no password or authenticator app for this confirmation. The module is still installed. Sign in again to continue."

    static let totpUnavailableMessage =
        "This account has no authenticator app set up."

    func requestUninstall(
        moduleID: String,
        choice: ModuleUninstallChoice,
        confirmDelete: Bool,
        idempotencyKey: String
    ) async -> ModuleUninstallOutcome {
        do {
            try await client.uninstallModule(
                moduleID,
                choice: choice,
                confirmDelete: confirmDelete,
                idempotencyKey: idempotencyKey
            )
            return .succeeded
        } catch {
            if APIError.requiresStepUp(error) != nil {
                return choice == .deleteData ? .needsPasswordStepUp : .failed(Self.message(error))
            }
            return .failed(Self.message(error))
        }
    }

    static let repromptMessage = "Please confirm your password again."
    static let totpRepromptMessage = "Please enter your authenticator code again."

    /// Confirms the password on `POST /v1/auth/step-up/password` (bearer required; body is
    /// only `{password}`), then retries deleteData once. A 409 CONFLICT means the
    /// account has no password: the sheet should offer TOTP. If that retry still
    /// returns `STEP_UP_REQUIRED`, the outcome is `needsPasswordStepUp` so the sheet
    /// can re-prompt once (`isReprompt: false`). A failure after that re-prompt
    /// (`isReprompt: true`) stops with `stillRequiresStepUp`. The password is not stored.
    func submitPasswordAndRetryDelete(
        moduleID: String,
        password: String,
        confirmDelete: Bool,
        idempotencyKey: String,
        isReprompt: Bool = false
    ) async -> ModuleUninstallOutcome {
        await submitStepUpAndRetryDelete(
            moduleID: moduleID,
            credential: .password(password),
            confirmDelete: confirmDelete,
            idempotencyKey: idempotencyKey,
            isReprompt: isReprompt
        )
    }

    /// Confirms a TOTP code on `POST /v1/auth/step-up/totp` (bearer required; body is
    /// only `{code}`), then retries deleteData once. The code is not stored.
    func submitTOTPAndRetryDelete(
        moduleID: String,
        code: String,
        confirmDelete: Bool,
        idempotencyKey: String,
        isReprompt: Bool = false,
        passwordWasUnavailable: Bool = false
    ) async -> ModuleUninstallOutcome {
        await submitStepUpAndRetryDelete(
            moduleID: moduleID,
            credential: .totp(code: code, passwordUnavailable: passwordWasUnavailable),
            confirmDelete: confirmDelete,
            idempotencyKey: idempotencyKey,
            isReprompt: isReprompt
        )
    }

    func submitStepUpAndRetryDelete(
        moduleID: String,
        credential: ModuleStepUpCredential,
        confirmDelete: Bool,
        idempotencyKey: String,
        isReprompt: Bool = false
    ) async -> ModuleUninstallOutcome {
        do {
            switch credential {
            case .password(let password):
                _ = try await client.passwordStepUp(password: password)
            case .totp(let code, _):
                _ = try await client.totpStepUp(code: code)
            }
        } catch let error as PasswordStepUpFailure {
            switch error {
            case .validation(let message):
                return .passwordRejected(message)
            case .rateLimited(let retryAfter, let message):
                return .rateLimited(retryAfter: retryAfter, message: message)
            case .conflict:
                // Mosaic #207: no password (or password not active) → offer TOTP.
                return .needsTOTP
            case .methodUnavailable(let message):
                if case .totp(_, true) = credential {
                    return .needsSignInAgain
                }
                return .unavailable(message)
            case .failed(let message):
                return .failed(message)
            }
        } catch {
            return .failed(Self.message(error))
        }

        do {
            try await client.uninstallModule(
                moduleID,
                choice: .deleteData,
                confirmDelete: confirmDelete,
                idempotencyKey: idempotencyKey
            )
            return .succeeded
        } catch {
            if APIError.requiresStepUp(error) != nil {
                // Re-prompt the sheet once. Do not silently retry. After that re-prompt,
                // stop with the still-installed error.
                return isReprompt
                    ? .stillRequiresStepUp(Self.stillRequiresStepUpMessage)
                    : .needsPasswordStepUp
            }
            return .failed(Self.message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        if APIError.requiresStepUp(error) != nil {
            return "Confirm your password to delete this module’s data."
        }
        if let api = error as? APIError {
            return "Couldn’t remove the module. \(api.userFacingMessage)"
        }
        return "Couldn’t remove the module. Check your connection and try again."
    }
}
