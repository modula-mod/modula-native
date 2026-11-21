import Foundation

/// Retention choice on `DELETE /v1/modules/:id/install`.
/// `keepData` needs no step-up. `deleteData` requires `confirmDelete` and, when the
/// session is older than 15 minutes, server-side step-up (Mosaic #201).
enum ModuleUninstallChoice: String, Sendable, Equatable {
    case keepData
    case deleteData
}

/// Result of `POST /v1/auth/step-up/password`. The session's `recent_authentication_at`
/// is refreshed; no separate step-up token is issued. Retry the original call with the
/// same bearer. `validForSeconds` is the server's hint (currently 600); the delete-data
/// policy window is 15 minutes.
struct PasswordStepUpResult: Codable, Sendable, Equatable {
    var stepUp: Bool
    var authenticationStrength: String?
    var validForSeconds: Int?
}

enum PasswordStepUpFailure: Error, Equatable, Sendable, LocalizedError {
    case validation(String)
    case rateLimited(retryAfter: TimeInterval?, message: String)
    case conflict(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .rateLimited(_, let message), .conflict(let message), .failed(let message):
            return message
        }
    }
}

enum ModuleUninstallOutcome: Equatable, Sendable {
    case succeeded
    case needsPasswordStepUp
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
/// On `401 STEP_UP_REQUIRED` from deleteData, the caller presents a password sheet,
/// then `submitPasswordAndRetryDelete` steps up once and retries deleteData once.
struct ModuleUninstallFlow: Sendable {
    let client: GreenfieldClient

    static let stillRequiresStepUpMessage =
        "Your password was confirmed, but deleting this module’s data still needs a stronger sign-in. The module is still installed."

    static let cancelledNotice =
        "The module is still installed. Your password is needed to delete its data."

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
            if APIError.requiresStepUp(error) {
                return choice == .deleteData ? .needsPasswordStepUp : .failed(Self.message(error))
            }
            return .failed(Self.message(error))
        }
    }

    /// Confirms the password on `POST /v1/auth/step-up/password` (bearer required; body is
    /// only `{password}`), then retries deleteData once. A second `STEP_UP_REQUIRED` stops
    /// with `stillRequiresStepUp` and does not loop. The password is not stored.
    func submitPasswordAndRetryDelete(
        moduleID: String,
        password: String,
        confirmDelete: Bool,
        idempotencyKey: String
    ) async -> ModuleUninstallOutcome {
        do {
            _ = try await client.passwordStepUp(password: password)
        } catch let error as PasswordStepUpFailure {
            switch error {
            case .validation(let message):
                return .passwordRejected(message)
            case .rateLimited(let retryAfter, let message):
                return .rateLimited(retryAfter: retryAfter, message: message)
            case .conflict(let message):
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
            if APIError.requiresStepUp(error) {
                return .stillRequiresStepUp(Self.stillRequiresStepUpMessage)
            }
            return .failed(Self.message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        if APIError.requiresStepUp(error) {
            return "Confirm your password to delete this module’s data."
        }
        if let api = error as? APIError {
            return "Couldn’t remove the module. \(api.userFacingMessage)"
        }
        return "Couldn’t remove the module. Check your connection and try again."
    }
}
