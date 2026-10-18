import Foundation
import Observation

struct ProductUIRecord: Identifiable, Equatable, Sendable {
    var id: String
    var revision: Int
    var data: [String: JSONValue]
    var deleted: Bool
    var createdAt: String = ""
    var updatedAt: String = ""
    var deletedAt: String = ""

    func fieldValue(_ path: String) -> JSONValue? {
        path.split(separator: ".").reduce(JSONValue.object(data) as JSONValue?) { value, key in value?[String(key)] }
    }

    func value(_ path: String) -> String {
        if path == "id" { return id }
        if path == "revision" { return String(revision) }
        if path == "createdAt" { return createdAt }
        if path == "updatedAt" { return updatedAt }
        if path == "deletedAt" { return deletedAt }
        if path == "plainTextProjection" {
            let projection = StructuredDocument.excerpt(from: data[path])
            return projection.isEmpty ? StructuredDocument.excerpt(from: data["document"]) : projection
        }
        if path == "document" { return StructuredDocument.excerpt(from: data[path], limit: 250_000) }
        let value = fieldValue(path)
        if path.hasSuffix("plainTextProjection") { return StructuredDocument.excerpt(from: value) }
        if path.hasSuffix("document") { return StructuredDocument.excerpt(from: value, limit: 250_000) }
        return value?.string ?? value?.number.map { String(Int($0)) } ?? ""
    }

    var searchText: String {
        [value("title"), StructuredDocument.excerpt(from: data["plainTextProjection"], limit: 20_000),
         StructuredDocument.excerpt(from: data["document"], limit: 20_000)].joined(separator: " ")
    }
}

struct ProductUIMediaAttachmentRequest: Equatable, Sendable {
    let recordType: String
    let recordId: String
}

struct ProductUIMediaOpenRequest: Equatable, Sendable {
    let assetId: String
    let filename: String
}

struct ProductUIMediaDetachmentRequest: Equatable, Sendable {
    let recordType: String
    let recordId: String
    let bindingId: String
}

/// Host-owned records/actions for a declarative Product UI surface.
/// Offline reads come from the last verified cache; mutations queue with stable IDs.
@MainActor @Observable
final class ProductUIRuntime {
    let document: ProductUIDocument
    let session: ModuleSession
    var route: String
    private(set) var routeHistory: [String] = []
    var query: String = ""
    var sort: String = "updatedAt"
    var filter: String = ""
    var records: [String: [ProductUIRecord]] = [:]
    var selected: [String: ProductUIRecord] = [:]
    var drafts: [String: String] = [:]
    private var draftRoute: String?
    private var originalDrafts: [String: String] = [:]
    private var seededDraftRoute: String?
    var showsUnsavedChanges = false
    private var pendingNavigation: String?
    var pendingMutations: [ProductUIMutation] = []
    /// The account-backed write the host should send. Nil while idle.
    var serverMutation: ProductUIMutation?
    /// Records fetched for this account, keyed by `type|recordState`.
    var serverRecords: [String: [ProductUIRecord]] = [:]
    var nextPageCursors: [String: String] = [:]
    var requestedNextPage: String?
    var loadingNextPage = false
    var viewState: String = "populated"
    var lastError: String?
    var lastAction: String?
    var capabilityResults: [String: String] = [:]
    var online = true
    /// Increments when the frontend asks the host to choose a file.
    var filePickToken = 0
    var pendingMediaAttachment: ProductUIMediaAttachmentRequest?
    var pendingMediaOpen: ProductUIMediaOpenRequest?
    var pendingMediaDetachment: ProductUIMediaDetachmentRequest?
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
        let next = path.hasPrefix("/") ? path : "/\(path)"
        if next != route, hasUnsavedDraft {
            pendingNavigation = next
            showsUnsavedChanges = true
            return
        }
        if next != route { routeHistory.append(route) }
        route = next
        query = ""
        lastAction = "route.open"
        refresh()
    }

    func goBack() {
        if hasUnsavedDraft {
            pendingNavigation = routeHistory.last ?? "/"
            showsUnsavedChanges = true
            return
        }
        route = routeHistory.popLast() ?? "/"
        query = ""
        lastAction = "route.back"
        refresh()
    }

    var hasUnsavedDraft: Bool {
        draftRoute == route && currentView?["kind"]?.string == "form" && drafts != originalDrafts
    }

    func discardAndLeave() {
        guard let destination = pendingNavigation else { return }
        let wasBack = routeHistory.last == destination
        clearSavedDraft()
        pendingNavigation = nil
        showsUnsavedChanges = false
        if wasBack { route = routeHistory.popLast() ?? "/" }
        else {
            if destination != route { routeHistory.append(route) }
            route = destination
        }
        query = ""
        refresh()
    }

    func clearSavedDraft() {
        drafts = [:]
        originalDrafts = [:]
        draftRoute = nil
        seededDraftRoute = nil
    }

    func refresh() {
        guard let view = currentView else {
            viewState = "error"
            lastError = "This screen is not in the verified frontend."
            return
        }
        if view["kind"]?.string == "form", draftRoute != route {
            drafts = [:]
            originalDrafts = [:]
            draftRoute = route
            seededDraftRoute = nil
        } else if view["kind"]?.string != "form", draftRoute != nil {
            clearSavedDraft()
        }
        let bindings = view["bindings"]?.array ?? []
        var recordBindings = 0
        var emptyRecordBindings = 0
        var waitingForRecords = false
        for binding in bindings {
            guard let id = binding["id"]?.string else { continue }
            let source = binding["source"]?.string ?? ""
            if ["record.query", "record.detail", "record.revisions", "record.revision", "record.media"].contains(source) {
                recordBindings += 1
                let type = binding["recordType"]?.string
                    ?? (source == "record.query" ? session.manifest.collections?.first : nil)
                    ?? id
                let state = binding["query"]?["recordState"]?.string ?? "active"
                let recordID = routeParams[binding["recordIdParam"]?.string ?? "id"] ?? ""
                let revision = routeParams[binding["revisionParam"]?.string ?? "revision"] ?? ""
                let hasCached: Bool
                switch source {
                case "record.revisions": hasCached = serverRecords["\(type)|revisions|\(recordID)"] != nil
                case "record.revision": hasCached = serverRecords["\(type)|revision|\(recordID)|\(revision)"] != nil
                case "record.media": hasCached = serverRecords["\(type)|media|\(recordID)"] != nil
                default: hasCached = recordSource != nil
                    || serverRecords["\(type)|\(state)"] != nil
                    || serverRecords["\(type)|active"] != nil
                    || serverRecords["\(type)|deleted"] != nil
                }
                if !hasCached {
                    waitingForRecords = true
                    continue
                }
            }
            if source == "record.query" {
                let type = binding["recordType"]?.string ?? session.manifest.collections?.first ?? id
                let state = binding["query"]?["recordState"]?.string ?? "active"
                let items = ProductUIRecords.visibleRecords(loadRecords(type: type, state: state, query: query), binding: binding, routeParams: routeParams)
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
            } else if source == "record.revisions" || source == "record.revision" {
                let type = binding["recordType"]?.string ?? ""
                let recordID = routeParams[binding["recordIdParam"]?.string ?? "id"] ?? ""
                let revision = routeParams[binding["revisionParam"]?.string ?? "revision"] ?? ""
                let key = source == "record.revisions" ? "\(type)|revisions|\(recordID)" : "\(type)|revision|\(recordID)|\(revision)"
                let items = serverRecords[key] ?? []
                records[id] = items
                if source == "record.revision" { selected[id] = items.first }
                if items.isEmpty { emptyRecordBindings += 1 }
            } else if source == "record.media" {
                let type = binding["recordType"]?.string ?? ""
                let recordID = routeParams[binding["recordIdParam"]?.string ?? "id"] ?? ""
                let items = serverRecords["\(type)|media|\(recordID)"] ?? []
                records[id] = items
                if items.isEmpty { emptyRecordBindings += 1 }
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
        let items = value["items"]?.array ?? (value["record_id"]?.string != nil || value["recordId"]?.string != nil ? [value] : [])
        return items.compactMap { item in
            let id = item["record_id"]?.string ?? item["recordId"]?.string ?? item["id"]?.string
            guard let id, !id.isEmpty else { return nil }
            let revision = Int(item["revision"]?.number ?? 1)
            let data: [String: JSONValue]
            if case .object(let object) = item["data"] { data = object } else { data = [:] }
            return ProductUIRecord(
                id: id, revision: max(revision, 1), data: data,
                deleted: (item["deleted_at"]?.string ?? item["deletedAt"]?.string) != nil,
                createdAt: item["created_at"]?.string ?? item["createdAt"]?.string ?? "",
                updatedAt: item["updated_at"]?.string ?? item["updatedAt"]?.string ?? "",
                deletedAt: item["deleted_at"]?.string ?? item["deletedAt"]?.string ?? ""
            )
        }
    }

    static func revisions(from value: JSONValue) -> [ProductUIRecord] {
        let items = value["revisions"]?.array ?? (value["revision"]?.number != nil ? [value] : [])
        return items.compactMap { item in
            guard let number = item["revision"]?.number, number >= 1 else { return nil }
            var data: [String: JSONValue] = [:]
            if case .object(let snapshot) = item["data"] { data["snapshot"] = .object(snapshot) }
            data["changeSource"] = item["operation"] ?? .string("")
            data["changedAt"] = item["changedAt"] ?? .string("")
            return ProductUIRecord(
                id: String(Int(number)), revision: Int(number), data: data,
                deleted: item["deleted"]?.bool == true,
                createdAt: item["changedAt"]?.string ?? "",
                updatedAt: item["changedAt"]?.string ?? ""
            )
        }
    }

    static func media(from value: JSONValue) -> [ProductUIRecord] {
        (value["bindings"]?.array ?? []).compactMap { item in
            guard let id = item["bindingId"]?.string, !id.isEmpty,
                  case .object(let data) = item else { return nil }
            return ProductUIRecord(
                id: id, revision: 1, data: data, deleted: false,
                createdAt: item["createdAt"]?.string ?? "",
                updatedAt: item["createdAt"]?.string ?? ""
            )
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
                lastError = "This feature is unavailable on this device."
                return
            }
            viewState = "capabilityUnavailable"
            lastError = "This screen needs a newer version of Modula."
            return
        }
        let family = action["family"]?.string ?? ""
        let target = record ?? boundRecord(action)
        switch family {
        case "route.open":
            var path = action["route"]?.string ?? "/"
            let recordParam = action["recordParam"]?.string
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
            for (key, value) in routeParams where record == nil || key != recordParam {
                path = path.replacingOccurrences(of: ":\(key)", with: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            }
            if let record {
                let encodedID = record.id.addingPercentEncoding(withAllowedCharacters: allowed) ?? record.id
                if let recordParam {
                    path = path.replacingOccurrences(of: ":\(recordParam)", with: encodedID)
                } else {
                    let unresolved = path.split(separator: "/").filter { $0.hasPrefix(":") }
                    if unresolved.count == 1 {
                        path = path.replacingOccurrences(of: String(unresolved[0]), with: encodedID)
                    }
                }
                let type = action["recordType"]?.string
                if let type, path.contains(":\(type)Id") {
                    path = path.replacingOccurrences(of: ":\(type)Id", with: encodedID)
                }
            }
            open(path)
        case "record.create", "record.update", "record.toggle", "record.delete", "record.restore", "record.purge":
            mutate(kind: family, action: action, actionId: actionId, record: target)
        case "record.query":
            refresh()
        case "dismiss":
            goBack()
        case "capability.invoke":
            let capability = action["capability"]?.string ?? ""
            let result = ModuleCapabilityBroker.invoke(
                capability, session: session, localOnly: action["localOnly"]?.bool == true
            )
            capabilityResults[capability] = result
            if ModuleCapabilityBroker.canonical(capability) == "mediaPicker", result == "ok" {
                filePickToken += 1
            } else if result != "ok" {
                lastError = "This feature is unavailable on this device."
            }
        case "media.attach":
            guard online else {
                lastError = "Reconnect to attach a file. Your record is unchanged."
                return
            }
            guard let record = target,
                  let recordType = action["recordType"]?.string,
                  recordType.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
                lastError = "Open the record again, then attach the file."
                return
            }
            pendingMediaAttachment = ProductUIMediaAttachmentRequest(recordType: recordType, recordId: record.id)
            filePickToken += 1
        case "media.open":
            guard let target, let assetId = target.data["assetId"]?.string else {
                lastError = "This file is unavailable."
                return
            }
            pendingMediaOpen = ProductUIMediaOpenRequest(
                assetId: assetId, filename: target.data["filename"]?.string ?? "Attachment"
            )
        case "media.detach":
            guard let target,
                  let recordType = action["recordType"]?.string,
                  let owner = boundRecord(action),
                  action["confirm"]?.bool == true else {
                lastError = "Open the record again, then remove the attachment."
                return
            }
            pendingMediaDetachment = ProductUIMediaDetachmentRequest(
                recordType: recordType, recordId: owner.id, bindingId: target.id
            )
        case "function.invoke":
            lastError = "This module function is not available on this host."
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
                record.searchText.localizedCaseInsensitiveContains(query)
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

    func availableRecords(type: String) -> [ProductUIRecord] {
        serverRecords["\(type)|active"] ?? records[type] ?? []
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
                if let document = record.data[id],
                   JSONSerialization.isValidJSONObject(document.foundation),
                   let data = try? JSONSerialization.data(withJSONObject: document.foundation, options: [.sortedKeys]),
                   let encoded = String(data: data, encoding: .utf8) {
                    drafts[id] = encoded
                } else if let legacy = record.data[id]?.string, !legacy.isEmpty {
                    drafts[id] = legacy
                } else if record.data[id] == nil {
                    let projection = record.value("plainTextProjection")
                    if !projection.isEmpty { drafts[id] = projection }
                }
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
        if seededDraftRoute != route {
            originalDrafts = drafts
            seededDraftRoute = route
        }
    }

    private func mutate(kind: String, action: JSONValue, actionId: String, record: ProductUIRecord?) {
        let type = action["recordType"]?.string ?? session.manifest.collections?.first ?? "item"
        var payload = drafts
        if let sourceParam = action["sourceRevisionParam"]?.string,
           let sourceRevision = routeParams[sourceParam] {
            payload["sourceRevision"] = sourceRevision
        }
        let mutation = ProductUIMutation(
            id: UUID().uuidString, actionId: actionId, family: kind, recordType: type, recordId: record?.id,
            expectedRevision: record?.revision, payload: payload, queuedOffline: !online
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
            lastError = "Open the record again, then try."
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
    /// Turns a form mutation into the account-scoped records request. The host never invents a saved record.
    static func prepare(moduleId: String, mutation: ProductUIMutation, action: JSONValue, fields: [JSONValue], existing: ProductUIRecord?) -> Result<ProductUIWriteRequest, ProductUIWriteError> {
        guard let modulePath = GreenfieldClient.modulePath(moduleId),
              mutation.recordType.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            return .failure(ProductUIWriteError(message: "This record could not be saved."))
        }
        let collection = mutation.recordType
        let base = "/v1/modules/\(modulePath)/records/\(collection)"
        let mutationId = mutation.id.replacingOccurrences(of: "[^A-Za-z0-9._:-]", with: "-", options: .regularExpression)
        switch mutation.family {
        case "record.create":
            if let error = invalidDocumentDraft(mutation, fields: fields) { return .failure(error) }
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
                return .failure(ProductUIWriteError(message: "Open the record again, then save."))
            }
            if let error = invalidDocumentDraft(mutation, fields: fields) { return .failure(error) }
            let data = recordData(moduleId: moduleId, mutation: mutation, action: action, fields: fields, existing: existing, includeDefaults: false)
            if let message = missingRequiredFields(data, fields: fields, creating: false) {
                return .failure(ProductUIWriteError(message: message))
            }
            return .success(ProductUIWriteRequest(method: "PATCH", path: "\(base)/\(recordId)", body: .object([
                "mutationId": .string(mutationId),
                "expectedRevision": .number(Double(revision)),
                "data": .object(data),
            ])))
        case "record.toggle":
            guard let recordId = mutation.recordId, let revision = mutation.expectedRevision, revision >= 1,
                  let field = action["recordField"]?.string,
                  field.range(of: "^[A-Za-z][A-Za-z0-9_]{0,79}$", options: .regularExpression) != nil,
                  let current = existing?.data[field]?.bool else {
                return .failure(ProductUIWriteError(message: "Open the record again, then try."))
            }
            return .success(ProductUIWriteRequest(method: "PATCH", path: "\(base)/\(recordId)", body: .object([
                "mutationId": .string(mutationId),
                "expectedRevision": .number(Double(revision)),
                "data": .object([field: .bool(!current)]),
            ])))
        case "record.delete", "record.restore", "record.purge":
            guard let recordId = mutation.recordId, let revision = mutation.expectedRevision, revision >= 1 else {
                return .failure(ProductUIWriteError(message: "Open the record again, then try."))
            }
            let path = mutation.family == "record.restore" ? "\(base)/\(recordId)/restore"
                : mutation.family == "record.purge" ? "\(base)/\(recordId)/permanent" : "\(base)/\(recordId)"
            let method = mutation.family == "record.restore" ? "POST" : "DELETE"
            var body: [String: JSONValue] = [
                "mutationId": .string(mutationId),
                "expectedRevision": .number(Double(revision)),
            ]
            if mutation.family == "record.purge" { body["confirm"] = .bool(true) }
            if mutation.family == "record.restore" {
                let sourceRevision = mutation.payload["sourceRevision"].flatMap(Int.init) ?? revision
                guard sourceRevision >= 1 else {
                    return .failure(ProductUIWriteError(message: "Choose a valid revision to restore."))
                }
                body["sourceRevision"] = .number(Double(sourceRevision))
            }
            return .success(ProductUIWriteRequest(method: method, path: path, body: .object(body)))
        default:
            return .failure(ProductUIWriteError(message: "This action is not available on this host yet."))
        }
    }

    static func visibleRecords(_ items: [ProductUIRecord], binding: JSONValue, routeParams: [String: String] = [:]) -> [ProductUIRecord] {
        let query = binding["query"]
        if let param = query?["filterParam"]?.string, ["references", "relatedTo"].contains(param) {
            return []
        }
        let filters: [String: JSONValue]
        if case .object(let object) = query?["filters"] { filters = object } else { filters = [:] }
        return items.filter { record in
            guard filters.allSatisfy({ key, expected in matches(record, field: key, expected: expected) }) else { return false }
            if let field = query?["membership"]?["field"]?.string,
               let param = query?["membership"]?["param"]?.string,
               let id = routeParams[param],
               record.data[field]?.array?.contains(where: { $0.string == id || $0["record"]?["recordId"]?.string == id }) != true {
                return false
            }
            guard let param = query?["filterParam"]?.string else { return true }
            if param == "folderId", let id = routeParams["folderId"] {
                return record.data["folderId"]?.string == id
                    || record.data["folderId"]?["record"]?["recordId"]?.string == id
            }
            return true
        }
    }

    private static func invalidDocumentDraft(_ mutation: ProductUIMutation, fields: [JSONValue]) -> ProductUIWriteError? {
        for field in fields where field["type"]?.string == "richText" {
            guard let id = field["id"]?.string, let raw = mutation.payload[id] else { continue }
            if (try? StructuredDocument.parse(raw)) == nil {
                return ProductUIWriteError(message: "This document could not be read. Your draft is unchanged.")
            }
        }
        return nil
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
            // Older records may contain a string reference. Keep it untouched while
            // editing another field; converting it to a new structured reference
            // would require a target that may no longer exist.
            if field["type"]?.string == "recordReference",
               existing?.data[id]?.string == draft { continue }
            if let value = coerced(field, draft: draft, moduleId: moduleId) {
                data[id] = value
            } else {
                data.removeValue(forKey: id)
            }
        }
        if let transforms = action["input"]?["transforms"]?.array {
            for transform in transforms {
                let source = transform["source"]?.string ?? "document"
                let target = transform["target"]?.string ?? "plainTextProjection"
                switch transform["transform"]?.string {
                case "richText.plainText@1":
                    let text = data[source].map { StructuredDocument.excerpt(from: $0, limit: 250_000) }
                        ?? existing?.value(target)
                        ?? ""
                    data[target] = .string(text)
                case "text.slug@1":
                    if let text = data[source]?.string ?? mutation.payload[source] {
                        data[target] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased().replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression))
                    }
                default: break
                }
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
            if kind == "richText", let document = try? StructuredDocument.parse(trimmed),
               let data = document.serialize().data(using: .utf8),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                return value
            }
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
