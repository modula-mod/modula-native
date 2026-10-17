import CryptoKit
import Foundation

struct DeveloperField: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var kind: String

    static func title() -> DeveloperField { DeveloperField(id: "title", label: "Title", kind: "string") }
}

struct DeveloperModuleDraft: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var moduleId: String
    var publisher: String
    var summary: String
    var template: String
    var version: String
    var homeTitle: String
    var intro: String
    var paragraphs: [String]
    var primaryAction: String
    var fields: [DeveloperField]

    var id: String { moduleId }

    static let templates = ["basic", "records", "dashboard", "document", "intelligence"]

    static func new(name: String, template: String) -> DeveloperModuleDraft {
        let moduleId = suggestedModuleID(name: name)
        return DeveloperModuleDraft(
            name: name,
            moduleId: moduleId,
            publisher: "modula",
            summary: "\(name) created in Modula Developer Studio.",
            template: templates.contains(template) ? template : "basic",
            version: "0.1.0",
            homeTitle: name,
            intro: "Welcome to \(name)",
            paragraphs: ["This module was generated inside Modula. Edits here publish to the same app."],
            primaryAction: template == "records" || template == "document" ? "New" : "Open settings",
            fields: template == "basic" || template == "dashboard" || template == "intelligence"
                ? []
                : [DeveloperField.title(), DeveloperField(id: "notes", label: "Notes", kind: "string")]
        )
    }

    static func suggestedModuleID(name: String) -> String {
        let slug = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        var cleaned = String(slug)
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if cleaned.isEmpty { cleaned = "module" }
        return "digital.modula.\(cleaned)"
    }

    func bumpedVersion() -> String {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        var parts = core.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        parts[2] += 1
        return parts.map(String.init).joined(separator: ".")
    }
}

struct GeneratedModuleProject: Equatable, Sendable {
    var frontend: Data
    var product: Data
    var moduleManifest: Data
    var issues: [String]
    var frontendSha256: String
}

enum ModuleProjectGenerator {
    static let moduleIDPattern = #"^(?=.{3,128}$)[a-z][a-z0-9]*(\.[a-z0-9]+(?:-[a-z0-9]+)*)+$"#
    static let versionPattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$"#

    static func validate(_ draft: DeveloperModuleDraft) -> [String] {
        var issues: [String] = []
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Module name is required.")
        }
        if draft.moduleId.range(of: moduleIDPattern, options: .regularExpression) == nil {
            issues.append("Module ID must be reverse-DNS, for example digital.modula.tasks.")
        }
        if draft.version.range(of: versionPattern, options: .regularExpression) == nil {
            issues.append("Version must be SemVer, for example 0.1.0.")
        }
        if !DeveloperModuleDraft.templates.contains(draft.template) {
            issues.append("Unknown template \(draft.template).")
        }
        let fieldIDs = draft.fields.map(\.id)
        if Set(fieldIDs).count != fieldIDs.count {
            issues.append("Record fields need unique identifiers.")
        }
        for field in draft.fields where field.id.range(of: #"^[a-z][A-Za-z0-9]*$"#, options: .regularExpression) == nil {
            issues.append("Field \(field.id) must start with a lowercase letter and contain no spaces.")
        }
        return issues
    }

    static func generate(_ draft: DeveloperModuleDraft) -> GeneratedModuleProject {
        let issues = validate(draft)
        guard issues.isEmpty else {
            return GeneratedModuleProject(frontend: Data(), product: Data(), moduleManifest: Data(), issues: issues, frontendSha256: "")
        }
        let frontendObject = frontend(draft)
        let frontend = jsonData(frontendObject)
        let digest = SHA256.hash(data: frontend).map { String(format: "%02x", $0) }.joined()
        let product = jsonData(product(draft, frontendSha256: digest))
        let moduleManifest = jsonData(moduleDocument(draft, frontendSha256: digest))
        return GeneratedModuleProject(frontend: frontend, product: product, moduleManifest: moduleManifest, issues: [], frontendSha256: digest)
    }

    private static func frontend(_ draft: DeveloperModuleDraft) -> [String: Any] {
        var document: [String: Any] = [
            "$schema": "https://modula.digital/schemas/product-standard/1.0/frontend.schema.json",
            "schema": "modula.frontend.1.0",
            "frontendSchemaVersion": "1.0.0",
            "mpsVersion": "1.0",
            "productId": draft.moduleId,
            "releaseVersion": draft.version,
            "mode": "declarative",
            "entry": "home",
            "hostRuntime": ["versionRange": ">=1.0.0 <2.0.0"],
            "routes": routes(draft),
            "views": views(draft),
            "navigation": navigation(draft),
            "actions": actions(draft),
            "settings": ["viewId": "settings"],
            "platformRequirements": ["platforms": ["ios", "android", "web"]],
            "accessibility": accessibility(),
        ]
        if let capabilities = capabilities(draft) {
            document["capabilities"] = capabilities
        }
        return document
    }

    private static func routes(_ draft: DeveloperModuleDraft) -> [[String: Any]] {
        var routes: [[String: Any]] = [["path": "/", "viewId": "home"]]
        switch draft.template {
        case "records", "document":
            let collection = collectionSlug(draft)
            let param = "\(recordType(draft))Id"
            routes.append(["path": "/new", "viewId": "editor", "presentation": "sheet"])
            routes.append(["path": "/\(collection)/:\(param)", "viewId": "detail"])
            routes.append(["path": "/\(collection)/:\(param)/edit", "viewId": "editor", "presentation": "sheet"])
            routes.append(["path": "/history", "viewId": "history"])
        case "intelligence":
            routes.append(["path": "/task", "viewId": "task"])
        default:
            break
        }
        routes.append(["path": "/settings", "viewId": "settings"])
        return routes
    }

    private static func views(_ draft: DeveloperModuleDraft) -> [[String: Any]] {
        var views = [homeView(draft), settingsView(draft)]
        switch draft.template {
        case "records", "document":
            views.append(detailView(draft))
            views.append(editorView(draft))
            views.append(historyView(draft))
        case "intelligence":
            views.append(intelligenceView(draft))
        default:
            break
        }
        return views
    }

    private static func homeView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        var children: [[String: Any]] = [
            ["type": "text", "text": draft.intro],
            ["type": "label", "text": draft.summary],
        ]
        for paragraph in draft.paragraphs where !paragraph.isEmpty {
            children.append(["type": "text", "text": paragraph])
        }
        switch draft.template {
        case "records", "document":
            children.append([
                "type": "toolbar",
                "accessibility": ["label": "\(draft.name) actions"],
                "children": [
                    ["type": "search", "text": "Search \(collectionSlug(draft))", "binding": "items"],
                    ["type": "button", "text": draft.primaryAction, "action": "createOpen"],
                ],
            ])
            children.append([
                "type": "recordList",
                "binding": "items",
                "action": "openRecord",
                "accessibility": ["label": draft.name, "role": "list"],
            ])
        case "dashboard":
            children.append(["type": "metadata", "text": "Records come from the host. This module does not invent analytics."])
            children.append(["type": "badge", "text": draft.version])
            children.append(["type": "button", "text": draft.primaryAction, "action": "openSettings"])
        case "intelligence":
            children.append(["type": "metadata", "text": "Local tasks stay on device. Unavailable providers return CAPABILITY_UNAVAILABLE."])
            children.append(["type": "button", "text": draft.primaryAction, "action": "openTask"])
        default:
            children.append(["type": "button", "text": draft.primaryAction, "action": "openSettings"])
        }
        var view: [String: Any] = [
            "id": "home",
            "kind": draft.template == "records" || draft.template == "document" ? "collection" : "dashboard",
            "title": draft.homeTitle,
            "root": [
                "type": "section",
                "accessibility": ["label": "\(draft.name) home"],
                "children": children,
            ],
            "states": states(draft.name),
        ]
        if draft.template == "records" || draft.template == "document" {
            view["bindings"] = [[
                "id": "items",
                "source": "record.query",
                "recordType": recordType(draft),
                "query": [
                    "filterParam": "filter",
                    "limit": 100,
                    "recordState": "active",
                    "searchParam": "q",
                    "sortParam": "sort",
                ],
            ]]
        }
        return view
    }

    private static func settingsView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        [
            "id": "settings",
            "kind": "settings",
            "title": "\(draft.name) settings",
            "bindings": [["id": "preferences", "source": "settings", "settingsKey": "\(draft.moduleId).preferences"]],
            "root": [
                "type": "section",
                "accessibility": ["label": "\(draft.name) settings", "role": "form"],
                "children": [
                    ["type": "field", "binding": "preferences", "field": ["id": "compactHome", "type": "boolean", "label": "Compact home"]],
                    ["type": "button", "text": "Save", "action": "saveSettings"],
                ],
            ],
            "states": states("settings"),
        ]
    }

    private static func detailView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        let type = recordType(draft)
        var rows: [[String: Any]] = draft.fields.map { field in
            ["type": "metadata", "text": field.label, "binding": "item", "valuePath": field.id]
        }
        rows.append(["type": "button", "text": "Edit", "action": "editOpen"])
        return [
            "id": "detail",
            "kind": "detail",
            "title": draft.name,
            "bindings": [["id": "item", "source": "record.detail", "recordType": type, "recordIdParam": "\(type)Id"]],
            "root": ["type": "section", "children": rows],
            "states": states(draft.name),
        ]
    }

    private static func editorView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        let fields: [[String: Any]] = draft.fields.map { field in
            ["type": "field", "binding": "itemForm", "field": ["id": field.id, "type": field.kind, "label": field.label]]
        }
        return [
            "id": "editor",
            "kind": "form",
            "title": "Edit \(draft.name)",
            "bindings": [["id": "itemForm", "source": "record.detail", "recordType": recordType(draft), "recordIdParam": "\(recordType(draft))Id"]],
            "root": [
                "type": "section",
                "children": fields + [["type": "button", "text": "Save", "action": "createRecord"]],
            ],
            "states": states(draft.name),
        ]
    }

    private static func historyView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        [
            "id": "history",
            "kind": "collection",
            "title": "History",
            "bindings": [["id": "history", "source": "record.query", "recordType": recordType(draft), "query": ["recordState": "deleted", "limit": 100]]],
            "root": [
                "type": "section",
                "children": [[
                    "type": "recordList",
                    "binding": "history",
                    "action": "restoreRecord",
                    "accessibility": ["label": "History", "role": "list"],
                ]],
            ],
            "states": states("history"),
        ]
    }

    private static func intelligenceView(_ draft: DeveloperModuleDraft) -> [String: Any] {
        [
            "id": "task",
            "kind": "form",
            "title": "Local task",
            "root": [
                "type": "section",
                "children": [
                    ["type": "text", "text": "This request is localOnly. Modula does not invent a model answer."],
                    ["type": "button", "text": "Run on device", "action": "runLocal"],
                ],
            ],
            "states": states(draft.name),
        ]
    }

    private static func actions(_ draft: DeveloperModuleDraft) -> [[String: Any]] {
        var actions: [[String: Any]] = [
            ["id": "openSettings", "family": "route.open", "label": "Open settings", "route": "/settings"],
            ["id": "saveSettings", "family": "settings.update", "label": "Save settings", "settingsKey": "\(draft.moduleId).preferences"],
            ["id": "dismiss", "family": "dismiss", "label": "Dismiss"],
        ]
        switch draft.template {
        case "records", "document":
            let type = recordType(draft)
            let collection = collectionSlug(draft)
            actions.append(["id": "createOpen", "family": "route.open", "label": draft.primaryAction, "route": "/new"])
            actions.append(["id": "openRecord", "family": "route.open", "label": "Open", "route": "/\(collection)/:\(type)Id"])
            actions.append(["id": "editOpen", "family": "route.open", "label": "Edit", "route": "/\(collection)/:\(type)Id/edit"])
            actions.append(["id": "createRecord", "family": "record.create", "label": "Save", "recordType": type, "inputBinding": "itemForm"])
            actions.append(["id": "updateRecord", "family": "record.update", "label": "Save changes", "recordType": type, "recordIdBinding": "item", "inputBinding": "itemForm"])
            actions.append(["id": "deleteRecord", "family": "record.delete", "label": "Delete", "recordType": type, "recordIdBinding": "item", "confirm": true])
            actions.append(["id": "restoreRecord", "family": "record.restore", "label": "Restore", "recordType": type, "recordIdBinding": "history"])
        case "intelligence":
            actions.append(["id": "openTask", "family": "route.open", "label": draft.primaryAction, "route": "/task"])
            actions.append([
                "id": "runLocal",
                "family": "capability.invoke",
                "label": "Run on device",
                "capability": "intelligence.local@1",
                "localOnly": true,
            ])
        default:
            break
        }
        return actions
    }

    private static func navigation(_ draft: DeveloperModuleDraft) -> [String: Any] {
        [
            "rootView": "home",
            "backBehavior": "host",
            "tabs": [
                ["id": "home", "label": "Home", "viewId": "home", "icon": "system.house"],
                ["id": "settings", "label": "Settings", "viewId": "settings", "icon": "system.gear"],
            ],
        ]
    }

    private static func capabilities(_ draft: DeveloperModuleDraft) -> [String: Any]? {
        switch draft.template {
        case "records":
            return ["required": [], "optional": ["ui.search@1"]]
        case "document":
            return ["required": [], "optional": ["ui.richText@1", "ui.search@1"]]
        case "intelligence":
            // Deployed GreenField accepts ui/audio/camera/media/file/share/map/game capabilities.
            // intelligence.local is a host broker id, not a publishable frontend capability yet.
            return nil
        default:
            return nil
        }
    }

    private static func product(_ draft: DeveloperModuleDraft, frontendSha256: String) -> [String: Any] {
        let records = usesRecords(draft)
        var document: [String: Any] = [:]
        document["$schema"] = "https://modula.digital/schemas/product-standard/1.0/product.schema.json"
        document["schema"] = "modula.product.1.0"
        document["productStandard"] = "1.0"
        document["identity"] = [
            "id": draft.moduleId,
            "kind": "module",
            "version": draft.version,
            "displayName": draft.name,
            "description": draft.summary,
            "status": "development",
            "visibility": "private",
        ] as [String: Any]
        document["publisher"] = ["id": draft.publisher, "displayName": draft.publisher]
        document["source"] = [
            "repository": "\(draft.publisher)/\(collectionSlug(draft))",
            "commit": "0000000000000000000000000000000000000000",
            "manifestPath": "modula.product.json",
            "provider": "github",
        ]
        document["licence"] = ["spdx": "MIT", "evidence": ["LICENSE"], "declaredByPublisher": true] as [String: Any]
        document["release"] = [
            "channel": "development",
            "notes": "Generated in the Modula app. Not a public registry release.",
            "builder": "modula-native-developer-studio",
            "provenance": ["frontendSha256": frontendSha256],
        ] as [String: Any]
        document["security"] = [
            "baseline": "mps-1.0",
            "rawUserBearerForwarding": "forbidden",
            "crossProductDatabaseAccess": "forbidden",
            "arbitraryRemoteCode": "forbidden-by-default",
        ]
        document["compatibility"] = [
            "productStandard": "^1.0.0",
            "greenfieldProtocol": "greenfield.v1",
            "host": ">=1.0.0 <2.0.0",
            "platforms": ["ios", "android", "web"],
        ] as [String: Any]
        document["marketplace"] = ["category": "productivity"]
        document["telemetry"] = ["destinationClass": "none", "optOut": "not-applicable", "purpose": "none"]
        document["frontend"] = [
            "mode": "declarative",
            "artifact": [
                "path": "frontend/frontend.manifest.json",
                "mediaType": "application/vnd.modula.frontend+json",
                "sha256": frontendSha256,
                "schemaVersion": "1.0.0",
                "entryView": "home",
            ],
        ] as [String: Any]
        if records {
            document["backend"] = [
                "mode": "greenfield-records",
                "records": [["id": recordType(draft), "schemaVersion": "1.0.0", "title": draft.name]],
            ]
            document["storage"] = ["mode": "greenfield-records"]
        } else {
            document["backend"] = ["mode": "none"]
        }
        document["permissions"] = permissions(draft).map { ["id": $0.id, "reason": $0.reason] }
        document["capabilities"] = ["provides": [], "requires": [], "requests": []] as [String: Any]
        document["privacy"] = [
            "dataAccessed": [records ? "account records" : "module settings"],
            "dataCreated": [records ? draft.name : "module settings"],
            "dataTransmitted": ["none-by-default"],
            "retention": "until uninstall",
            "deletion": "removed with the module",
            "analytics": "none",
            "telemetry": "none",
        ] as [String: Any]
        document["accessibility"] = accessibility()
        return document
    }

    private static func moduleDocument(_ draft: DeveloperModuleDraft, frontendSha256: String) -> [String: Any] {
        [
            "manifestVersion": 2,
            "moduleId": draft.moduleId,
            "name": draft.name,
            "description": draft.summary,
            "version": draft.version,
            "publisher": ["publisherId": draft.publisher, "displayName": draft.publisher],
            "frontend": [
                "path": "frontend/frontend.manifest.json",
                "mediaType": "application/vnd.modula.frontend+json",
                "sha256": frontendSha256,
                "schema": "modula.frontend.1.0",
            ],
        ]
    }

    static func permissions(_ draft: DeveloperModuleDraft) -> [(id: String, reason: String)] {
        var items = [
            ("settings:register", "Register a settings surface. This does not allow reading or writing settings values."),
            ("settings:read", "Read settings saved for this module."),
            ("settings:write", "Save settings edited in this module."),
        ]
        if usesRecords(draft) {
            let type = recordType(draft)
            items.insert(("records:module.\(draft.moduleId).\(type):read", "Read \(draft.name) records for this account."), at: 0)
            items.insert(("records:module.\(draft.moduleId).\(type):write", "Create and update \(draft.name) records."), at: 1)
        }
        return items.map { (id: $0.0, reason: $0.1) }
    }

    static func usesRecords(_ draft: DeveloperModuleDraft) -> Bool {
        draft.template == "records" || draft.template == "document"
    }

    static func collectionSlug(_ draft: DeveloperModuleDraft) -> String {
        draft.moduleId.split(separator: ".").last.map(String.init) ?? "items"
    }

    static func recordType(_ draft: DeveloperModuleDraft) -> String {
        var slug = collectionSlug(draft).replacingOccurrences(of: "-", with: "")
        if slug.hasSuffix("s"), slug.count > 1 { slug.removeLast() }
        if slug.isEmpty || slug.range(of: #"^[a-z][A-Za-z0-9]*$"#, options: .regularExpression) == nil {
            slug = "item"
        }
        return slug
    }

    private static func states(_ name: String) -> [String: Any] {
        [
            "loading": ["type": "loadingState", "text": "Loading \(name)", "accessibility": ["role": "status"]],
            "empty": ["type": "emptyState", "text": "\(name) is empty", "accessibility": ["role": "status"]],
            "error": ["type": "errorState", "text": "\(name) could not be loaded", "accessibility": ["role": "status"]],
            "permissionDenied": ["type": "errorState", "text": "Permission denied", "accessibility": ["role": "status"]],
        ]
    }

    private static func accessibility() -> [String: Any] {
        [
            "declaration": "host-baseline-with-product-semantics",
            "screenReader": true,
            "scalableText": true,
            "keyboardNavigation": true,
            "reduceMotion": true,
        ]
    }

    private static func jsonData(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

enum DeveloperModuleStore {
    static func devRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Modula/DevModules", isDirectory: true)
    }

    static func projectRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Modula/DeveloperStudio", isDirectory: true)
    }

    static func list() -> [DeveloperModuleDraft] {
        let root = projectRoot()
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(DeveloperModuleDraft.self, from: data)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    static func save(_ draft: DeveloperModuleDraft) throws -> GeneratedModuleProject {
        let generated = ModuleProjectGenerator.generate(draft)
        guard generated.issues.isEmpty else {
            throw DeveloperModuleError.invalid(generated.issues)
        }
        let parsed = try ProductUIDocument.parse(data: generated.frontend, productId: draft.moduleId, version: draft.version)
        guard parsed.entry == "home" else { throw DeveloperModuleError.invalid(["Generated frontend is missing its home screen."]) }
        let folder = devRoot().appendingPathComponent("\(draft.moduleId)/\(draft.version)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try generated.frontend.write(to: folder.appendingPathComponent("frontend.manifest.json"), options: .atomic)
        try generated.product.write(to: folder.appendingPathComponent("modula.product.json"), options: .atomic)
        try generated.moduleManifest.write(to: folder.appendingPathComponent("modula.module.json"), options: .atomic)
        let projects = projectRoot()
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(draft)
        try encoded.write(to: projects.appendingPathComponent("\(draft.moduleId).json"), options: .atomic)
        return generated
    }
}

enum DeveloperModuleError: Error, LocalizedError {
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .invalid(let issues): issues.joined(separator: " ")
        }
    }
}
