import Foundation
import Observation

struct ProductUIRecord: Identifiable, Equatable, Sendable {
    var id: String
    var revision: Int
    var data: [String: JSONValue]
    var deleted: Bool

    func value(_ path: String) -> String {
        if path == "id" { return id }
        if path == "revision" { return String(revision) }
        return data[path]?.string ?? data[path]?.number.map { String(Int($0)) } ?? ""
    }
}

/// Host-owned records/actions for a declarative Product UI surface.
/// Offline reads come from the last verified cache; mutations queue with stable IDs.
@MainActor @Observable
final class ProductUIRuntime {
    let document: ProductUIDocument
    let session: ModuleSession
    var route: String
    var query: String = ""
    var sort: String = "updatedAt"
    var filter: String = ""
    var records: [String: [ProductUIRecord]] = [:]
    var selected: [String: ProductUIRecord] = [:]
    var drafts: [String: String] = [:]
    var pendingMutations: [ProductUIMutation] = []
    /// The account-backed write the host should send. Nil while idle.
    var serverMutation: ProductUIMutation?
    /// Records fetched for this account, keyed by `type|recordState`.
    var serverRecords: [String: [ProductUIRecord]] = [:]
    var viewState: String = "populated"
    var lastError: String?
    var lastAction: String?
    var capabilityResults: [String: String] = [:]
    var online = true
    /// Increments when the frontend asks the host to choose a file.
    var filePickToken = 0
    /// Module function the host should run with the current form.
    var pendingFunction: String?
    var recordSource: ((String, String) -> [ProductUIRecord])?
    var mutationHandler: ((ProductUIMutation) throws -> ProductUIRecord)?

    init(document: ProductUIDocument, session: ModuleSession, initialPath: String?) {
        self.document = document
        self.session = session
        self.route = initialPath?.isEmpty == false ? initialPath! : "/"
    }

    var currentView: JSONValue? {
        document.view(id: document.viewId(forRoute: route) ?? document.entry)
    }

    var routeParams: [String: String] { document.routeParameters(route) }

    func open(_ path: String) {
        route = path.hasPrefix("/") ? path : "/\(path)"
        lastAction = "route.open"
        refresh()
    }

    func refresh() {
        guard let view = currentView else {
            viewState = "error"
            lastError = "This screen is not in the verified frontend."
            return
        }
        let bindings = view["bindings"]?.array ?? []
        var recordBindings = 0
        var emptyRecordBindings = 0
        var waitingForRecords = false
        for binding in bindings {
            guard let id = binding["id"]?.string else { continue }
            let source = binding["source"]?.string ?? ""
            if source == "record.query" || source == "record.detail" {
                recordBindings += 1
                let type = binding["recordType"]?.string
                    ?? (source == "record.query" ? session.manifest.collections?.first : nil)
                    ?? id
                let state = binding["query"]?["recordState"]?.string ?? "active"
                let hasCached = recordSource != nil
                    || serverRecords["\(type)|\(state)"] != nil
                    || serverRecords["\(type)|active"] != nil
                    || serverRecords["\(type)|deleted"] != nil
                if !hasCached {
                    waitingForRecords = true
                    continue
                }
            }
            if source == "record.query" {
                let type = binding["recordType"]?.string ?? session.manifest.collections?.first ?? id
                let state = binding["query"]?["recordState"]?.string ?? "active"
                let items = ProductUIRecords.visibleRecords(loadRecords(type: type, state: state, query: query), binding: binding)
                records[id] = items
                if items.isEmpty { emptyRecordBindings += 1 }
            } else if source == "record.detail" {
                let type = binding["recordType"]?.string ?? ""
                let param = binding["recordIdParam"]?.string ?? "id"
                let recordId = routeParams[param] ?? ""
                let item = loadRecords(type: type, state: "active", query: "").first(where: { $0.id == recordId })
                    ?? loadRecords(type: type, state: "deleted", query: "").first(where: { $0.id == recordId })
                if let item {
                    selected[id] = item
                    records[id] = [item]
                } else {
                    records[id] = []
                    selected[id] = nil
                    emptyRecordBindings += 1
                }
            }
        }
        if waitingForRecords {
            viewState = "loading"
        } else if recordBindings > 0, emptyRecordBindings == recordBindings, view["kind"]?.string == "collection" {
            viewState = "empty"
        } else {
            viewState = "populated"
        }
        if !waitingForRecords { seedFormDrafts() }
    }

    static func records(from value: JSONValue) -> [ProductUIRecord] {
        (value["items"]?.array ?? []).compactMap { item in
            let id = item["record_id"]?.string ?? item["recordId"]?.string ?? item["id"]?.string
            guard let id, !id.isEmpty else { return nil }
            let revision = Int(item["revision"]?.number ?? 1)
            let data: [String: JSONValue]
            if case .object(let object) = item["data"] { data = object } else { data = [:] }
            return ProductUIRecord(id: id, revision: max(revision, 1), data: data, deleted: false)
        }
    }

    func perform(actionId: String, record: ProductUIRecord? = nil) {
        guard session.isValid else { return }
        lastError = nil
        lastAction = actionId
        guard let action = document.action(id: actionId) else {
            lastError = "Unknown action \(actionId)."
            viewState = "error"
            return
        }
        if let capability = action["capability"]?.string,
           !session.grantedCapabilities.contains(capability)
            && !ModuleCapabilityBroker.hostSupports(capability) {
            if document.optionalCapabilities.contains(capability) {
                capabilityResults[capability] = "CAPABILITY_UNAVAILABLE"
                lastError = "\(capability) is unavailable on this device."
                return
            }
            viewState = "capabilityUnavailable"
            lastError = "This screen needs \(capability), which this host does not provide."
            return
        }
        let family = action["family"]?.string ?? ""
        let target = record ?? boundRecord(action)
        switch family {
        case "route.open":
            var path = action["route"]?.string ?? "/"
            if let record {
                path = path.replacingOccurrences(of: ":noteId", with: record.id)
                    .replacingOccurrences(of: ":taskId", with: record.id)
                    .replacingOccurrences(of: ":itemId", with: record.id)
                    .replacingOccurrences(of: ":folderId", with: record.id)
                    .replacingOccurrences(of: ":tagId", with: record.id)
                    .replacingOccurrences(of: ":revisionId", with: record.id)
                for (key, value) in routeParams {
                    path = path.replacingOccurrences(of: ":\(key)", with: value)
                }
                let type = action["recordType"]?.string
                if let type, path.contains(":\(type)Id") {
                    path = path.replacingOccurrences(of: ":\(type)Id", with: record.id)
                }
            } else {
                for (key, value) in routeParams {
                    path = path.replacingOccurrences(of: ":\(key)", with: value)
                }
            }
            open(path)
        case "record.create", "record.update", "record.delete", "record.restore", "record.purge":
            mutate(kind: family, action: action, actionId: actionId, record: target)
        case "record.query":
            refresh()
        case "dismiss":
            open("/")
        case "capability.invoke":
            let capability = action["capability"]?.string ?? ""
            let result = ModuleCapabilityBroker.invoke(
                capability, session: session, localOnly: action["localOnly"]?.bool == true
            )
            capabilityResults[capability] = result
            if ModuleCapabilityBroker.canonical(capability) == "mediaPicker", result == "ok" {
                filePickToken += 1
            } else if result != "ok" {
                lastError = "\(capability) is unavailable on this device."
            }
        case "function.invoke":
            if !online {
                pendingMutations.append(ProductUIMutation(
                    id: UUID().uuidString, actionId: actionId, family: family, recordType: action["recordType"]?.string ?? "",
                    recordId: record?.id, expectedRevision: record?.revision, payload: drafts, queuedOffline: true
                ))
            } else {
                pendingFunction = action["functionId"]?.string ?? actionId
            }
        case "service.invoke", "extension.invoke", "share", "settings.update":
            lastAction = family
            if !online {
                pendingMutations.append(ProductUIMutation(
                    id: UUID().uuidString, actionId: actionId, family: family, recordType: action["recordType"]?.string ?? "",
                    recordId: record?.id, expectedRevision: record?.revision, payload: drafts, queuedOffline: true
                ))
            }
        case "module.invoke":
            lastAction = family
            lastError = nil
            pendingMutations.append(ProductUIMutation(
                id: UUID().uuidString,
                actionId: actionId,
                family: family,
                recordType: action["targetModuleId"]?.string ?? "",
                recordId: action["targetActionId"]?.string,
                expectedRevision: nil,
                payload: drafts,
                queuedOffline: !online
            ))
        default:
            lastError = "Unsupported action family \(family)."
        }
    }

    func bindingRecords(_ id: String?) -> [ProductUIRecord] {
        guard let id else { return [] }
        var items = records[id] ?? []
        if !query.isEmpty {
            items = items.filter { record in
                record.data.values.contains { $0.string?.localizedCaseInsensitiveContains(query) == true }
            }
        }
        if filter == "done" || filter == "complete" {
            items = items.filter { ["done", "complete", "completed"].contains($0.value("status")) }
        } else if filter == "open" {
            items = items.filter { $0.value("status") != "done" && $0.value("status") != "complete" }
        }
        switch sort {
        case "title": items.sort { $0.value("title") < $1.value("title") }
        case "createdAt": items.sort { $0.value("createdAt") > $1.value("createdAt") }
        default: break
        }
        return items
    }

    func boundText(_ node: JSONValue) -> String {
        if let literal = node["text"]?.string { return literal }
        if let title = node["title"]?.string { return title }
        if let binding = node["binding"]?.string, let path = node["valuePath"]?.string {
            if let selected = selected[binding] { return selected.value(path) }
            return bindingRecords(binding).first?.value(path) ?? ""
        }
        return ""
    }

    private func loadRecords(type: String, state: String = "active", query: String) -> [ProductUIRecord] {
        if let recordSource { return recordSource(type, query) }
        return serverRecords["\(type)|\(state)"] ?? []
    }

    private func boundRecord(_ action: JSONValue) -> ProductUIRecord? {
        guard let bindingId = action["recordIdBinding"]?.string else { return nil }
        if let selected = selected[bindingId] { return selected }
        let declared = currentView?["bindings"]?.array?.first {
            $0["id"]?.string == bindingId && $0["source"]?.string == "record.detail"
        }
        let type = action["recordType"]?.string ?? declared?["recordType"]?.string ?? ""
        let param = declared?["recordIdParam"]?.string ?? "id"
        let recordId = routeParams[param] ?? ""
        guard !recordId.isEmpty else { return nil }
        return loadRecords(type: type, state: "active", query: "").first { $0.id == recordId }
            ?? loadRecords(type: type, state: "deleted", query: "").first { $0.id == recordId }
    }

    /// Fills a form from the open record. Field ids come from the module, not from this host.
    private func seedFormDrafts() {
        guard currentView?["kind"]?.string == "form" else { return }
        let record = currentView?["bindings"]?.array?.compactMap { binding -> ProductUIRecord? in
            guard binding["source"]?.string == "record.detail", let id = binding["id"]?.string else { return nil }
            return selected[id]
        }.first
        guard let record else { return }
        for field in ProductUIRecords.fieldNodes(in: currentView) {
            guard let id = field["id"]?.string, drafts[id] == nil else { continue }
            switch field["type"]?.string ?? "text" {
            case "boolean":
                if case .bool(let value) = record.data[id] { drafts[id] = value ? "true" : "false" }
            case "richText":
                let body = record.value("plainTextProjection")
                if !body.isEmpty { drafts[id] = body }
            case "tags":
                if case .array(let items) = record.data[id] {
                    let joined = items.compactMap(\.string).joined(separator: ", ")
                    if !joined.isEmpty { drafts[id] = joined }
                }
            case "recordReference":
                if case .object(let object) = record.data[id],
                   let recordId = object["record"]?["recordId"]?.string {
                    drafts[id] = recordId
                } else {
                    let text = record.value(id)
                    if !text.isEmpty { drafts[id] = text }
                }
            default:
                let text = record.value(id)
                if !text.isEmpty { drafts[id] = text }
            }
        }
    }

    private func mutate(kind: String, action: JSONValue, actionId: String, record: ProductUIRecord?) {
        let type = action["recordType"]?.string ?? session.manifest.collections?.first ?? "item"
        let mutation = ProductUIMutation(
            id: UUID().uuidString, actionId: actionId, family: kind, recordType: type, recordId: record?.id,
            expectedRevision: record?.revision, payload: drafts, queuedOffline: !online
        )
        if let mutationHandler {
            pendingMutations.append(mutation)
            do {
                let saved = try mutationHandler(mutation)
                upsert(saved, type: type)
            } catch {
                lastError = error.localizedDescription
                viewState = "error"
            }
            refresh()
            return
        }
        if !online {
            pendingMutations.append(mutation)
            lastError = "You're offline. Reconnect to save this to your account."
            return
        }
        guard serverMutation == nil else { return }
        if kind != "record.create", record == nil {
            lastError = "Open the note again, then try."
            return
        }
        serverMutation = mutation
    }

    private func upsert(_ record: ProductUIRecord, type: String) {
        var items = records[type] ?? []
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            items[index] = record
        } else {
            items.insert(record, at: 0)
        }
        records[type] = items
        selected[type] = record
    }
}

struct ProductUIMutation: Equatable, Identifiable, Sendable {
    var id: String
    var actionId: String
    var family: String
    var recordType: String
    var recordId: String?
    var expectedRevision: Int?
    var payload: [String: String]
    var queuedOffline: Bool
}

struct ProductUIWriteRequest: Equatable, Sendable {
    var method: String
    var path: String
    var body: JSONValue
}

struct ProductUIWriteError: Error, Equatable, Sendable {
    let message: String
}

enum ProductUIRecords {
    /// Turns a form mutation into the account-scoped records request. The host never invents a saved note.
    static func prepare(moduleId: String, mutation: ProductUIMutation, action: JSONValue, fields: [JSONValue], existing: ProductUIRecord?) -> Result<ProductUIWriteRequest, ProductUIWriteError> {
        guard let modulePath = GreenfieldClient.modulePath(moduleId),
              mutation.recordType.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            return .failure(ProductUIWriteError(message: "This note could not be saved."))
        }
        let collection = mutation.recordType
        let base = "/v1/modules/\(modulePath)/records/\(collection)"
        let mutationId = mutation.id.replacingOccurrences(of: "[^A-Za-z0-9._:-]", with: "-", options: .regularExpression)
        switch mutation.family {
        case "record.create":
            let data = recordData(moduleId: moduleId, mutation: mutation, action: action, fields: fields, existing: nil, includeDefaults: true)
            if let message = missingRequiredFields(data, fields: fields, creating: true) {
                return .failure(ProductUIWriteError(message: message))
            }
            return .success(ProductUIWriteRequest(method: "POST", path: base, body: .object([
                "mutationId": .string(mutationId),
                "data": .object(data),
            ])))
        case "record.update":
            guard let recordId = mutation.recordId, let revision = mutation.expectedRevision, revision >= 1 else {
                return .failure(ProductUIWriteError(message: "Open the note again, then save."))
            }
            let data = recordData(moduleId: moduleId, mutation: mutation, action: action, fields: fields, existing: existing, includeDefaults: false)
            if let message = missingRequiredFields(data, fields: fields, creating: false) {
                return .failure(ProductUIWriteError(message: message))
            }
            return .success(ProductUIWriteRequest(method: "PATCH", path: "\(base)/\(recordId)", body: .object([
                "mutationId": .string(mutationId),
                "expectedRevision": .number(Double(revision)),
                "data": .object(data),
            ])))
        case "record.delete", "record.restore", "record.purge":
            guard let recordId = mutation.recordId, let revision = mutation.expectedRevision, revision >= 1 else {
                return .failure(ProductUIWriteError(message: "Open the note again, then try."))
            }
            let path = mutation.family == "record.restore" ? "\(base)/\(recordId)/restore"
                : mutation.family == "record.purge" ? "\(base)/\(recordId)/permanent" : "\(base)/\(recordId)"
            let method = mutation.family == "record.restore" ? "POST" : "DELETE"
            var body: [String: JSONValue] = [
                "mutationId": .string(mutationId),
                "expectedRevision": .number(Double(revision)),
            ]
            if mutation.family == "record.purge" { body["confirm"] = .bool(true) }
            return .success(ProductUIWriteRequest(method: method, path: path, body: .object(body)))
        default:
            return .failure(ProductUIWriteError(message: "This action is not available on this host yet."))
        }
    }

    static func visibleRecords(_ items: [ProductUIRecord], binding: JSONValue) -> [ProductUIRecord] {
        let query = binding["query"]
        if let param = query?["filterParam"]?.string, ["references", "relatedTo", "folderId", "tagId"].contains(param) {
            return []
        }
        guard let filters = query?["filters"], case .object(let object) = filters else { return items }
        return items.filter { record in
            object.allSatisfy { key, expected in matches(record, field: key, expected: expected) }
        }
    }

    static func fieldNodes(in view: JSONValue?) -> [JSONValue] {
        guard let view else { return [] }
        var fields: [JSONValue] = []
        func walk(_ node: JSONValue) {
            if let field = node["field"] { fields.append(field) }
            node["children"]?.array?.forEach(walk)
        }
        if let root = view["root"] { walk(root) } else { walk(view) }
        return fields
    }

    private static func matches(_ record: ProductUIRecord, field: String, expected: JSONValue) -> Bool {
        switch expected {
        case .bool(let value):
            if case .bool(let stored) = record.data[field] { return stored == value }
            if record.data[field] == nil { return value == false }
            return false
        case .string(let value):
            return record.value(field) == value
        default:
            return true
        }
    }

    private static func missingRequiredFields(_ data: [String: JSONValue], fields: [JSONValue], creating: Bool) -> String? {
        for field in fields {
            guard field["required"]?.bool == true, let id = field["id"]?.string else { continue }
            if !creating && data[id] == nil { continue }
            if isFilled(data[id]) { continue }
            let label = (field["label"]?.string ?? id).lowercased()
            return "Add a \(label) before saving."
        }
        return nil
    }

    private static func isFilled(_ value: JSONValue?) -> Bool {
        switch value {
        case nil: return false
        case .string(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let items): return !items.isEmpty
        default: return true
        }
    }

    private static func recordData(moduleId: String, mutation: ProductUIMutation, action: JSONValue, fields: [JSONValue], existing: ProductUIRecord?, includeDefaults: Bool) -> [String: JSONValue] {
        var data: [String: JSONValue] = [:]
        if includeDefaults, case .object(let defaults) = action["input"]?["defaults"] {
            data = defaults
        }
        let fieldsById = Dictionary(uniqueKeysWithValues: fields.compactMap { field -> (String, JSONValue)? in
            guard let id = field["id"]?.string else { return nil }
            return (id, field)
        })
        for (id, draft) in mutation.payload {
            guard let field = fieldsById[id] else { continue }
            if let value = coerced(field, draft: draft, moduleId: moduleId) {
                data[id] = value
            } else {
                data.removeValue(forKey: id)
            }
        }
        if let transforms = action["input"]?["transforms"]?.array {
            for transform in transforms where transform["transform"]?.string == "richText.plainText@1" {
                let source = transform["source"]?.string ?? "document"
                let target = transform["target"]?.string ?? "plainTextProjection"
                let text = mutation.payload[source]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? existing?.value("plainTextProjection")
                    ?? ""
                data[target] = .string(text)
            }
        }
        if let title = data["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            data["title"] = .string(title)
        }
        return data
    }

    private static func coerced(_ field: JSONValue, draft: String, moduleId: String) -> JSONValue? {
        let kind = field["type"]?.string ?? "text"
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case "boolean":
            return .bool(["true", "yes", "1"].contains(draft.lowercased()))
        case "tags":
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .array(parts.map { .string(String($0)) })
        case "richText", "json":
            if kind == "json", let data = trimmed.data(using: .utf8),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data),
               case .object = value {
                return value
            }
            let blocks: [JSONValue] = trimmed.isEmpty ? [] : [.object([
                "id": .string("block-1"),
                "type": .string("paragraph"),
                "text": .string(trimmed),
                "marks": .array([]),
            ])]
            return .object(["schemaVersion": .string("1.0.0"), "blocks": .array(blocks)])
        case "number":
            guard let number = Double(trimmed) else { return nil }
            return .number(number)
        case "recordReference":
            guard !trimmed.isEmpty, let recordType = field["recordType"]?.string else { return nil }
            return .object(["record": .object([
                "moduleId": .string(moduleId),
                "recordType": .string(recordType),
                "recordId": .string(trimmed),
            ])])
        default:
            return trimmed.isEmpty ? nil : .string(trimmed)
        }
    }
}
