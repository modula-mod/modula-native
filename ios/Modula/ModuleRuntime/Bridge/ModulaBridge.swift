import Foundation
import UIKit

@MainActor @objc final class ModulaBridge: NSObject {
    @objc static let shared = ModulaBridge()
    weak var runtime: ModuleRuntimeController?
    var client: GreenfieldClient?
    var authenticationInvalidated: (() -> Void)?
    weak var navigation: NavigationCoordinator?

    @objc func request(_ wire: String, completion: @escaping (String) -> Void) {
        guard wire.utf8.count <= 300_000,
              let data = wire.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == ["version", "moduleID", "sessionID", "action", "params"],
              value["version"] as? String == ModuleRuntimeController.bridgeVersion,
              let id = value["sessionID"] as? String, let runtime,
              let session = runtime.sessions[id], runtime.authorize(session),
              value["moduleID"] as? String == session.manifest.id,
              let action = value["action"] as? String,
              session.manifest.permissions.contains(action),
              let params = value["params"] as? [String: Any] else {
            self.runtime?.reject("REQUEST_DENIED")
            completion(Self.reply(error: "REQUEST_DENIED")); return
        }
        if action.hasPrefix("backend.records.") {
            guard let operation = ModuleBackendRequest.parse(action: action, params: params, manifest: session.manifest),
                  let accountID = session.accountID, let client else {
                runtime.reject("INVALID_BACKEND_REQUEST")
                completion(Self.reply(error: "INVALID_BACKEND_REQUEST", message: "The module backend request is invalid.")); return
            }
            Task {
                do {
                    let value = try await client.moduleRequest(method: operation.method, path: operation.path, body: operation.body, expectedAccountID: accountID)
                    guard runtime.authorize(session) else { completion(Self.reply(error: "SESSION_REVOKED", message: "The module session ended.")); return }
                    completion(Self.reply(data: value.foundation))
                } catch {
                    if case APIError.unauthenticated = error { authenticationInvalidated?() }
                    if case APIError.rejected(401, _) = error { authenticationInvalidated?() }
                    guard runtime.authorize(session) else { completion(Self.reply(error: "SESSION_REVOKED", message: "The module session ended.")); return }
                    let message = (error as? APIError)?.localizedDescription ?? "Greenfield connection unavailable."
                    completion(Self.reply(error: "BACKEND_REQUEST_FAILED", message: message))
                }
            }
            return
        }
        guard action == "navigation.open" || params.isEmpty else {
            runtime.reject("INVALID_PAYLOAD"); completion(Self.reply(error: "INVALID_PAYLOAD")); return
        }
        switch action {
        case "diagnostics.ready": runtime.ready(session)
        case "diagnostics.dataReady": runtime.dataReady(session)
        case "diagnostics.fail": runtime.fail(session)
        case "haptics.selection": HapticEngine.shared.play(.selection)
        case "navigation.open":
            guard let route = Self.route(params), let navigation else {
                completion(Self.reply(error: "INVALID_ROUTE")); return
            }
            navigation.openFromModule(route)
        default:
            runtime.reject("UNSUPPORTED_ACTION")
            completion(Self.reply(error: "UNSUPPORTED_ACTION")); return
        }
        completion(Self.reply())
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
    static func reply(data: Any = NSNull(), error: String? = nil, message: String? = nil) -> String {
        let result: [String: Any] = error.map {
            ["ok": false, "error": ["code": $0, "message": message ?? $0]]
        } ?? ["ok": true, "data": data]
        guard let bytes = try? JSONSerialization.data(withJSONObject: result), let wire = String(data: bytes, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"ENCODING_FAILED\",\"message\":\"Encoding failed\"}}"
        }
        return wire
    }
}
