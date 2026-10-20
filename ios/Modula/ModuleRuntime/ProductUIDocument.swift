import Foundation
import CryptoKit

/// Host-owned parse of `application/vnd.modula.frontend+json`.
/// The bytes are treated as data, never evaluated as JavaScript.
struct ProductUIDocument: Equatable, Sendable {
    static let mediaType = "application/vnd.modula.frontend+json"
    static let schema = "modula.frontend.1.0"
    static let maxBytes = 1_048_576
    static let supportedRuntimes: Set<String> = ["declarative", "product-ui"]
    static let supportedHostVersions = ["0.1.0", "1.0.0", "1.1.0"]

    static let forbiddenKeys: Set<String> = [
        "script", "rawjs", "rawhtml", "html", "jsx", "tsx", "css", "style",
        "remotebundle", "remoteentry", "customcomponentname", "webview",
        "unsafewebview", "networkurl", "eval",
    ]

    static let baselineComponents: Set<String> = [
        "section", "text", "label", "metadata", "badge", "image", "icon", "divider",
        "stack", "row", "grid", "scroll", "recordList", "recordRow", "field", "button",
        "menu", "search", "filter", "sort", "tabs", "picker", "toolbar", "sheet",
        "emptyState", "errorState", "loadingState", "media", "progress",
    ]

    static let advancedComponents: [String: String] = [
        "richText": "ui.richText@1",
        "richDocumentEditor": "ui.richText@1",
        "editorToolbar": "ui.richText.commands@1",
        "propertyEditor": "ui.propertyEditor@1",
        "referencePicker": "ui.referencePicker@1",
        "attachmentGallery": "ui.attachments@1",
        "revisionBrowser": "ui.revisions@1",
        "graph": "ui.graph@1",
        "recordTable": "ui.recordTable@1",
        "recordBoard": "ui.recordBoard@1",
        "commandMenu": "ui.commandMenu@1",
    ]

    let productId: String
    let releaseVersion: String
    let entry: String
    let hostRuntimeRange: String
    let sha256: String
    let raw: JSONValue
    let requiredCapabilities: [String]
    let optionalCapabilities: [String]

    var routes: [JSONValue] { raw["routes"]?.array ?? [] }
    var views: [JSONValue] { raw["views"]?.array ?? [] }
    var actions: [JSONValue] { raw["actions"]?.array ?? [] }

    func view(id: String) -> JSONValue? {
        views.first { $0["id"]?.string == id }
    }

    func action(id: String) -> JSONValue? {
        actions.first { $0["id"]?.string == id }
    }

    func route(path: String) -> JSONValue? {
        routes.first { $0["path"]?.string == path }
    }

    func viewId(forRoute path: String) -> String? {
        if let exact = route(path: path)?["viewId"]?.string { return exact }
        return matchParameterizedRoute(path)?["viewId"]?.string ?? entry
    }

    func matchParameterizedRoute(_ path: String) -> JSONValue? {
        let incoming = path.split(separator: "/").map(String.init)
        for route in routes {
            guard let pattern = route["path"]?.string else { continue }
            let parts = pattern.split(separator: "/").map(String.init)
            guard parts.count == incoming.count else { continue }
            var ok = true
            for (expected, actual) in zip(parts, incoming) {
                if expected.hasPrefix(":") { continue }
                if expected != actual { ok = false; break }
            }
            if ok { return route }
        }
        return nil
    }

    func routeParameters(_ path: String) -> [String: String] {
        guard let route = matchParameterizedRoute(path) ?? route(path: path),
              let pattern = route["path"]?.string else { return [:] }
        var params: [String: String] = [:]
        let expected = pattern.split(separator: "/").map(String.init)
        let actual = path.split(separator: "/").map(String.init)
        guard expected.count == actual.count else { return [:] }
        for (exp, act) in zip(expected, actual) where exp.hasPrefix(":") {
            params[String(exp.dropFirst())] = act
        }
        return params
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case oversized
        case invalidJSON
        case forbiddenField(String)
        case identityMismatch
        case missingEntry
        case unsupportedSchema
        case missingAccessibility

        var errorDescription: String? {
            switch self {
            case .oversized: "The module frontend is larger than the 1 MiB Product UI limit."
            case .invalidJSON: "The module frontend is not valid JSON."
            case .forbiddenField(let key): "The module frontend contains forbidden field \(key)."
            case .identityMismatch: "The module frontend identity does not match the verified release."
            case .missingEntry: "The module frontend is missing its entry view."
            case .unsupportedSchema: "This module frontend uses an unsupported Product UI schema."
            case .missingAccessibility: "The module frontend is missing the host accessibility baseline."
            }
        }
    }

    static func parse(data: Data, productId: String, version: String) throws -> ProductUIDocument {
        guard data.count <= maxBytes else { throw ParseError.oversized }
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let raw: JSONValue
        do {
            raw = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        if let forbidden = firstForbidden(in: raw, path: "") { throw ParseError.forbiddenField(forbidden) }
        guard raw["schema"]?.string == schema,
              raw["frontendSchemaVersion"]?.string == "1.0.0" else { throw ParseError.unsupportedSchema }
        guard raw["productId"]?.string == productId, raw["releaseVersion"]?.string == version else {
            throw ParseError.identityMismatch
        }
        guard let entry = raw["entry"]?.string, !entry.isEmpty else { throw ParseError.missingEntry }
        let a11y = raw["accessibility"]
        guard a11y?["declaration"]?.string == "host-baseline-with-product-semantics",
              a11y?["screenReader"]?.bool == true,
              a11y?["scalableText"]?.bool == true,
              a11y?["keyboardNavigation"]?.bool == true,
              a11y?["reduceMotion"]?.bool == true else { throw ParseError.missingAccessibility }
        let required = (raw["capabilities"]?["required"]?.array ?? []).compactMap(\.string)
        let optional = (raw["capabilities"]?["optional"]?.array ?? []).compactMap(\.string)
        return ProductUIDocument(
            productId: productId,
            releaseVersion: version,
            entry: entry,
            hostRuntimeRange: raw["hostRuntime"]?["versionRange"]?.string ?? ">=1.0.0",
            sha256: sha256,
            raw: raw,
            requiredCapabilities: required,
            optionalCapabilities: optional
        )
    }

    private static func firstForbidden(in value: JSONValue, path: String) -> String? {
        switch value {
        case .object(let object):
            for key in object.keys {
                let lowered = key.lowercased()
                if forbiddenKeys.contains(lowered) { return path.isEmpty ? key : "\(path).\(key)" }
                if let found = firstForbidden(in: object[key]!, path: path.isEmpty ? key : "\(path).\(key)") {
                    return found
                }
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                if let found = firstForbidden(in: item, path: "\(path)[\(index)]") { return found }
            }
        default:
            break
        }
        return nil
    }
}

enum ModuleRuntimeKind: String, Sendable {
    case bundledReactNative
    case declarativeProductUI
}

enum ProductUIProvenance: String, Sendable {
    case native
    case fallback
    case emulated
    case unavailable
}
