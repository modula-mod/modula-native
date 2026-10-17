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
    var viewState: String = "populated"
    var lastError: String?
    var lastAction: String?
    var capabilityResults: [String: String] = [:]
    var online = true
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
                if recordSource == nil {
                    waitingForRecords = true
                    continue
                }
            }
            if source == "record.query" {
                let type = binding["recordType"]?.string ?? session.manifest.collections?.first ?? id
                let items = loadRecords(type: type, query: query)
                records[id] = items
                if items.isEmpty { emptyRecordBindings += 1 }
            } else if source == "record.detail" {
                let type = binding["recordType"]?.string ?? ""
                let param = binding["recordIdParam"]?.string ?? "id"
                let recordId = routeParams[param] ?? ""
                if let item = loadRecords(type: type, query: "").first(where: { $0.id == recordId }) {
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
        case "record.create", "record.update":
            mutate(kind: family, action: action, record: record)
        case "record.delete":
            mutate(kind: family, action: action, record: record)
        case "record.restore":
            mutate(kind: family, action: action, record: record)
        case "record.query":
            refresh()
        case "dismiss":
            open("/")
        case "capability.invoke":
            let capability = action["capability"]?.string ?? ""
            capabilityResults[capability] = ModuleCapabilityBroker.invoke(
                capability, session: session, localOnly: action["localOnly"]?.bool == true
            )
        case "function.invoke", "service.invoke", "extension.invoke", "share", "settings.update":
            lastAction = family
            if !online {
                pendingMutations.append(ProductUIMutation(
                    id: UUID().uuidString, family: family, recordType: action["recordType"]?.string ?? "",
                    recordId: record?.id, expectedRevision: record?.revision, payload: drafts, queuedOffline: true
                ))
            }
        case "module.invoke":
            lastAction = family
            lastError = nil
            pendingMutations.append(ProductUIMutation(
                id: UUID().uuidString,
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
            items = items.filter { $0.value("title").localizedCaseInsensitiveContains(query) }
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

    private func loadRecords(type: String, query: String) -> [ProductUIRecord] {
        if let recordSource { return recordSource(type, query) }
        return records[type] ?? []
    }

    private func mutate(kind: String, action: JSONValue, record: ProductUIRecord?) {
        let type = action["recordType"]?.string ?? session.manifest.collections?.first ?? "item"
        let mutation = ProductUIMutation(
            id: UUID().uuidString, family: kind, recordType: type, recordId: record?.id,
            expectedRevision: record?.revision, payload: drafts, queuedOffline: !online
        )
        pendingMutations.append(mutation)
        if let mutationHandler {
            do {
                let saved = try mutationHandler(mutation)
                upsert(saved, type: type)
            } catch {
                lastError = error.localizedDescription
                viewState = "error"
            }
        } else if kind == "record.create" {
            let created = ProductUIRecord(
                id: mutation.id, revision: 1,
                data: drafts.mapValues { .string($0) }.merging(["title": .string(drafts["title"] ?? "Untitled")]) { _, new in new },
                deleted: false
            )
            upsert(created, type: type)
        } else if kind == "record.delete", let record {
            var items = records[type] ?? bindingRecords(type)
            items.removeAll { $0.id == record.id }
            records[type] = items
        }
        refresh()
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
    var family: String
    var recordType: String
    var recordId: String?
    var expectedRevision: Int?
    var payload: [String: String]
    var queuedOffline: Bool
}
