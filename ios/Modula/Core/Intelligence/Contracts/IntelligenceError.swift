import Foundation

/// Typed intelligence failures. Callers must branch on `code`, never free-form messages.
enum IntelligenceError: Error, Sendable, Equatable {
    case noEligibleProvider
    case localProviderUnavailable
    case remoteExecutionForbidden
    case capabilityUnsupported
    case providerUnavailable(providerID: String)
    case providerNotFound(providerID: String)
    case duplicateProvider(providerID: String)
    case toolNotFound(toolID: String)
    case toolArgumentsInvalid(toolID: String, detail: String)
    case toolPermissionDenied(toolID: String, permission: String)
    case toolNotAuthorizedForRequest(toolID: String)
    case duplicateTool(toolID: String)
    case invalidRequest(detail: String)
    case contextLimitExceeded
    case unsupportedLanguage
    case safetyRefusal
    case requestCancelled
    case providerFailure(providerID: String, detail: String)

    var code: String {
        switch self {
        case .noEligibleProvider: "NO_ELIGIBLE_PROVIDER"
        case .localProviderUnavailable: "LOCAL_PROVIDER_UNAVAILABLE"
        case .remoteExecutionForbidden: "REMOTE_EXECUTION_FORBIDDEN"
        case .capabilityUnsupported: "CAPABILITY_UNSUPPORTED"
        case .providerUnavailable: "PROVIDER_UNAVAILABLE"
        case .providerNotFound: "PROVIDER_NOT_FOUND"
        case .duplicateProvider: "DUPLICATE_PROVIDER"
        case .toolNotFound: "TOOL_NOT_FOUND"
        case .toolArgumentsInvalid: "TOOL_ARGUMENTS_INVALID"
        case .toolPermissionDenied: "TOOL_PERMISSION_DENIED"
        case .toolNotAuthorizedForRequest: "TOOL_NOT_AUTHORIZED"
        case .duplicateTool: "DUPLICATE_TOOL"
        case .invalidRequest: "INVALID_REQUEST"
        case .contextLimitExceeded: "CONTEXT_LIMIT_EXCEEDED"
        case .unsupportedLanguage: "UNSUPPORTED_LANGUAGE"
        case .safetyRefusal: "SAFETY_REFUSAL"
        case .requestCancelled: "REQUEST_CANCELLED"
        case .providerFailure: "PROVIDER_FAILURE"
        }
    }
}

extension IntelligenceError: LocalizedError {
    var errorDescription: String? { code }
}
