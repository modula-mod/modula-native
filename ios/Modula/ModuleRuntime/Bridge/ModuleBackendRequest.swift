import Foundation
import CoreFoundation

/// Closed record API vocabulary. JavaScript never supplies a URL, header or account.
struct ModuleBackendRequest {
    let method: String
    let path: String
    let body: JSONValue?

    static func parse(action: String, params: [String: Any], manifest: ModuleManifest) -> Self? {
        guard let collection = params["collection"] as? String,
              manifest.collections?.contains(collection) == true,
              ModulaBridge.validID(collection), ModulaBridge.validID(manifest.id) else { return nil }
        let base = "/v1/modules/\(manifest.id)/records/\(collection)"
        func exact(_ keys: Set<String>) -> Bool { Set(params.keys) == keys }
        func recordPath() -> String? {
            guard let id = params["recordID"] as? String, ModulaBridge.validID(id) else { return nil }
            return "\(base)/\(id)"
        }
        func data() -> JSONValue? {
            guard let value = params["data"] as? [String: Any],
                  let bytes = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: bytes)
        }
        func revision() -> JSONValue? {
            guard let number = params["expectedRevision"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 1,
                  number.doubleValue <= 9_007_199_254_740_991,
                  number.doubleValue.rounded() == number.doubleValue else { return nil }
            return .number(number.doubleValue)
        }
        switch action {
        case "backend.records.list":
            guard exact(["collection"]) || exact(["collection", "cursor"]) else { return nil }
            var path = "\(base)?limit=50&recordState=active&sort=updatedAt&direction=desc"
            if let cursor = params["cursor"] {
                guard let cursor = cursor as? String, cursor.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil else { return nil }
                path += "&cursor=\(cursor)"
            }
            return Self(method: "GET", path: path, body: nil)
        case "backend.records.get":
            guard exact(["collection", "recordID"]), let path = recordPath() else { return nil }
            return Self(method: "GET", path: path, body: nil)
        case "backend.records.create":
            guard exact(["collection", "data"]), let data = data() else { return nil }
            return Self(method: "POST", path: base, body: .object(["data": data]))
        case "backend.records.update":
            guard exact(["collection", "recordID", "data", "expectedRevision"]), let path = recordPath(),
                  let data = data(), let revision = revision() else { return nil }
            return Self(method: "PATCH", path: path, body: .object(["data": data, "expectedRevision": revision]))
        case "backend.records.delete":
            guard exact(["collection", "recordID", "expectedRevision"]), let path = recordPath(), let revision = revision() else { return nil }
            return Self(method: "DELETE", path: path, body: .object(["expectedRevision": revision]))
        default: return nil
        }
    }
}
