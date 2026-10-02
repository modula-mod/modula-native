import Foundation
import UIKit

@MainActor @objc final class ModulaBridge: NSObject {
    @objc static let shared = ModulaBridge()
    weak var runtime: ModuleRuntimeController?
    var client: GreenfieldClient?
    /// Called only after the shell confirms its own authentication is invalid.
    var authenticationInvalidated: (() -> Void)?
    weak var navigation: NavigationCoordinator?

    @objc func request(_ wire: String, completion: @escaping (String) -> Void) {
        guard wire.utf8.count <= 300_000,
              let data = wire.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == ["version", "moduleID", "surfaceToken", "action", "params"],
              value["version"] as? String == ModuleRuntimeController.bridgeVersion,
              let token = value["surfaceToken"] as? String, let moduleID = value["moduleID"] as? String,
              let action = value["action"] as? String,
              let params = value["params"] as? [String: Any], let runtime else {
            self.runtime?.reject("REQUEST_DENIED")
            completion(Self.reply(error: .requestDenied)); return
        }
        // The session is resolved natively from the surface-bound token; a JS-supplied
        // native session ID or another module's identity resolves to nothing.
        guard let session = runtime.session(forToken: token, moduleID: moduleID) else {
            runtime.reject("REQUEST_DENIED")
            completion(Self.reply(error: .requestDenied)); return
        }
        guard runtime.authorize(session) else {
            runtime.reject("SESSION_EXPIRED")
            completion(Self.reply(error: session.state == .expired ? .sessionExpired : .sessionRevoked)); return
        }
        guard ModuleRuntimeController.supportedCapabilities.contains(action) else {
            runtime.reject("UNSUPPORTED_ACTION"); completion(Self.reply(error: .unsupportedAction)); return
        }
        guard session.grantedCapabilities.contains(action) else {
            runtime.reject("PERMISSION_DENIED")
            if !session.deniedCapabilities.contains(action) { session.deniedCapabilities.append(action) }
            completion(Self.reply(error: .permissionDenied)); return
        }
        if action.hasPrefix("backend.records.") {
            guard let operation = ModuleBackendRequest.parse(action: action, params: params, manifest: session.manifest),
                  let accountID = session.accountID, let client else {
                runtime.reject("INVALID_BACKEND_REQUEST")
                completion(Self.reply(error: .invalidBackendRequest)); return
            }
            Task {
                do {
                    let value = try await client.moduleRequest(method: operation.method, path: operation.path, body: operation.body, expectedAccountID: accountID)
                    guard runtime.authorize(session, renew: false) else { completion(Self.reply(error: .sessionRevoked)); return }
                    completion(Self.reply(data: value.foundation))
                } catch {
                    let code = HostErrorCode(error)
                    if code == .backendUnauthenticated { await self.shellAuthenticationCheck(client) }
                    guard runtime.authorize(session, renew: false) else { completion(Self.reply(error: .sessionRevoked)); return }
                    completion(Self.reply(error: code))
                }
            }
            return
        }
        guard action == "navigation.open" || params.isEmpty else {
            runtime.reject("INVALID_PAYLOAD"); completion(Self.reply(error: .invalidPayload)); return
        }
        switch action {
        case "diagnostics.ready": runtime.ready(session)
        case "diagnostics.dataReady": runtime.dataReady(session)
        case "diagnostics.fail": runtime.fail(session)
        case "haptics.selection": HapticEngine.shared.play(.selection)
        case "navigation.open":
            guard let route = Self.route(params), let navigation else {
                completion(Self.reply(error: .invalidRoute)); return
            }
            navigation.openFromModule(route)
        default:
            runtime.reject("UNSUPPORTED_ACTION")
            completion(Self.reply(error: .unsupportedAction)); return
        }
        completion(Self.reply())
    }

    /// A module 401 may be a module-scoped rejection (installation/permission). The client
    /// refreshes once and keeps its session when that refresh succeeds; only sign the app
    /// out when the shell's own session is actually gone.
    private func shellAuthenticationCheck(_ client: GreenfieldClient) async {
        if await client.hasSession() == false { authenticationInvalidated?() }
    }

    static func route(_ params: [String: Any]) -> AppRoute? {
        guard let route = params["route"] as? String else { return nil }
        let expected: Set<String> = route == "profile" ? ["route", "userId"] : route == "post" ? ["route", "postId"] : ["route"]
        guard Set(params.keys) == expected else { return nil }
        switch route {
        case "home": return .home(.following)
        case "settings": return .settings(.root)
        case "productHub": return .productHub(.featured)
        case "profile":
            guard let id = params["userId"] as? String, validID(id) else { return nil }
            return .profile(id, .overview)
        case "post":
            guard let id = params["postId"] as? String, validID(id) else { return nil }
            return .post(id, .root)
        default: return nil
        }
    }
    nonisolated static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 120 && value.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    }
    static func reply(data: Any = NSNull(), error: HostErrorCode? = nil) -> String {
        let result: [String: Any] = error.map {
            ["ok": false, "error": ["code": $0.rawValue, "message": $0.message]]
        } ?? ["ok": true, "data": data]
        guard let bytes = try? JSONSerialization.data(withJSONObject: result), let wire = String(data: bytes, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"ENCODING_FAILED\",\"message\":\"The host couldn’t encode the reply.\"}}"
        }
        return wire
    }
}

/// Stable host error codes (packages/module-contracts/schemas/host-reply.schema.json).
/// Messages are fixed host text; backend/transport text never reaches JavaScript.
enum HostErrorCode: String, Sendable {
    case requestDenied = "REQUEST_DENIED", permissionDenied = "PERMISSION_DENIED"
    case sessionExpired = "SESSION_EXPIRED", sessionRevoked = "SESSION_REVOKED"
    case invalidBackendRequest = "INVALID_BACKEND_REQUEST", invalidPayload = "INVALID_PAYLOAD"
    case invalidRoute = "INVALID_ROUTE", unsupportedAction = "UNSUPPORTED_ACTION"
    case backendUnauthenticated = "BACKEND_UNAUTHENTICATED", backendForbidden = "BACKEND_FORBIDDEN"
    case backendNotFound = "BACKEND_NOT_FOUND", backendConflict = "BACKEND_CONFLICT"
    case backendValidationFailed = "BACKEND_VALIDATION_FAILED", backendRateLimited = "BACKEND_RATE_LIMITED"
    case backendUnavailable = "BACKEND_UNAVAILABLE", backendRequestFailed = "BACKEND_REQUEST_FAILED"
    case networkUnavailable = "NETWORK_UNAVAILABLE", encodingFailed = "ENCODING_FAILED"

    /// Maps transport/backend failures to a code.
    init(_ error: Error) {
        if case APIError.unauthenticated = error { self = .backendUnauthenticated; return }
        if case APIError.accountChanged = error { self = .sessionRevoked; return }
        if case APIError.rejected(let status, _) = error {
            switch status {
            case 401: self = .backendUnauthenticated
            case 403: self = .backendForbidden
            case 404: self = .backendNotFound
            case 409, 412: self = .backendConflict
            case 400, 422: self = .backendValidationFailed
            case 429: self = .backendRateLimited
            case 500...599: self = .backendUnavailable
            default: self = .backendRequestFailed
            }
            return
        }
        if error is URLError { self = .networkUnavailable; return }
        self = .backendRequestFailed
    }

    var message: String {
        switch self {
        case .requestDenied: "The host rejected this request."
        case .permissionDenied: "This module doesn’t have permission for that."
        case .sessionExpired: "The module session expired."
        case .sessionRevoked: "The module session ended."
        case .invalidBackendRequest: "The module backend request is invalid."
        case .invalidPayload: "The request payload is invalid."
        case .invalidRoute: "That destination isn’t available."
        case .unsupportedAction: "This action isn’t supported."
        case .backendUnauthenticated: "Your session couldn’t be confirmed."
        case .backendForbidden: "This module isn’t allowed to do that."
        case .backendNotFound: "That item no longer exists."
        case .backendConflict: "This item changed elsewhere. Reload and try again."
        case .backendValidationFailed: "The server rejected this change."
        case .backendRateLimited: "Too many requests. Try again shortly."
        case .backendUnavailable: "The service is unavailable. Try again later."
        case .backendRequestFailed: "The request failed."
        case .networkUnavailable: "You appear to be offline."
        case .encodingFailed: "The host couldn’t encode the reply."
        }
    }
}
