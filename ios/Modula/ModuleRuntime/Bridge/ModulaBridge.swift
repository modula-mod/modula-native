import Foundation
import UIKit

@MainActor @objc final class ModulaBridge: NSObject {
    @objc static let shared = ModulaBridge()
    weak var runtime: ModuleRuntimeController?
    weak var navigation: NavigationCoordinator?

    @objc func request(_ wire: String, completion: @escaping (String) -> Void) {
        guard wire.utf8.count <= 300_000,
              let data = wire.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["version"] as? String == ModuleRuntimeController.bridgeVersion,
              let id = value["sessionID"] as? String, let runtime,
              let session = runtime.sessions[id], session.isValid,
              let action = value["action"] as? String,
              session.manifest.permissions.contains(action),
              let params = value["params"] as? [String: Any] else {
            completion(Self.reply(error: "REQUEST_DENIED")); return
        }
        switch action {
        case "diagnostics.ready": runtime.ready(session)
        case "diagnostics.fail": runtime.fail(session)
        case "haptics.selection": UISelectionFeedbackGenerator().selectionChanged()
        case "navigation.open":
            guard let route = Self.route(params), let navigation else {
                completion(Self.reply(error: "INVALID_ROUTE")); return
            }
            navigation.open(route)
        default:
            completion(Self.reply(error: "UNSUPPORTED_ACTION")); return
        }
        completion(Self.reply())
    }

    static func route(_ params: [String: Any]) -> AppRoute? {
        guard let route = params["route"] as? String else { return nil }
        switch route {
        case "home": return .home
        case "settings": return .settings
        case "productHub": return .productHub
        case "profile":
            guard let id = params["userId"] as? String, validID(id) else { return nil }
            return .profile(id)
        case "post":
            guard let id = params["postId"] as? String, validID(id) else { return nil }
            return .post(id)
        default: return nil
        }
    }
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 120 && value.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    }
    static func reply(data: Any = NSNull(), error: String? = nil) -> String {
        let result: [String: Any] = error.map { ["ok": false, "error": ["code": $0, "message": $0]] } ?? ["ok": true, "data": data]
        guard let bytes = try? JSONSerialization.data(withJSONObject: result), let wire = String(data: bytes, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"ENCODING_FAILED\",\"message\":\"Encoding failed\"}}"
        }
        return wire
    }
}
