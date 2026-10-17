import SwiftUI
import UniformTypeIdentifiers

/// Generic Product UI 1.0 renderer. No product-specific module ID branches.
struct ProductUIHostView: View {
    let session: ModuleSession
    let document: ProductUIDocument
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var runtime: ProductUIRuntime
    @State private var showsFileImporter = false

    init(session: ModuleSession, document: ProductUIDocument) {
        self.session = session
        self.document = document
        _runtime = State(initialValue: ProductUIRuntime(
            document: document, session: session, initialPath: session.initialLocalPath
        ))
    }

    var body: some View {
        let palette = ModulaPalette.resolve(app.appearance, scheme: scheme)
        Group {
            if runtime.viewState == "capabilityUnavailable" {
                ContentUnavailableView {
                    Label("Capability unavailable", systemImage: "cpu")
                } description: {
                    Text(runtime.lastError ?? "This host cannot render a required Product UI capability.")
                }
                .accessibilityIdentifier("module.host.capabilityUnavailable")
            } else if let view = runtime.currentView {
                ProductUIViewCanvas(view: view, runtime: runtime)
            } else {
                ContentUnavailableView("This screen is missing", systemImage: "rectangle.badge.xmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
        .task(id: runtime.route) {
            #if DEBUG
            runtime.online = app.auth.account != nil && !ModulaAppNetworkIsolation.isActive
            #else
            runtime.online = app.auth.account != nil
            #endif
            if let source = app.runtime.productUIRecordSource {
                runtime.recordSource = source
            }
            runtime.refresh()
            if session.state == .loadingModule || session.state == .preparing {
                app.runtime.ready(session)
            }
            await loadInstalledRecords()
        }
        .onChange(of: runtime.filePickToken) { _, token in
            if token > 0 { showsFileImporter = true }
        }
        .onChange(of: runtime.pendingFunction) { _, functionId in
            guard let functionId else { return }
            Task { await runModuleFunction(functionId) }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .text, .audio, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                rememberChosenFile(url)
            case .failure(let error):
                runtime.lastError = error.localizedDescription
            }
        }
        .accessibilityIdentifier("module.host.product-ui")
    }

    private func rememberChosenFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let name = url.lastPathComponent
        let safe = name.unicodeScalars.map { scalar -> Character in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
            return allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let assetId = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        runtime.drafts["assetId"] = assetId.isEmpty ? UUID().uuidString : String(assetId.prefix(180))
        runtime.drafts["name"] = name
        runtime.drafts["mimeType"] = values?.contentType?.preferredMIMEType ?? "application/octet-stream"
        runtime.drafts["size"] = String(values?.fileSize ?? 0)
        let mime = runtime.drafts["mimeType"] ?? ""
        runtime.drafts["kind"] = mime.hasPrefix("image/") ? "image" : mime == "application/pdf" ? "pdf" : mime.hasPrefix("audio/") ? "audio" : "file"
        runtime.lastError = nil
    }

    private func runModuleFunction(_ functionId: String) async {
        runtime.pendingFunction = nil
        guard let accountID = app.auth.account?.accountId, GreenfieldClient.modulePath(session.manifest.id) != nil else { return }
        guard functionId.contains("attach") else {
            runtime.lastError = "This module action isn’t available on this host yet."
            return
        }
        let noteId = runtime.drafts["noteId"] ?? ""
        let assetId = runtime.drafts["assetId"] ?? ""
        guard !noteId.isEmpty, !assetId.isEmpty else {
            runtime.lastError = "Choose a note and a file first."
            return
        }
        let data: [String: JSONValue] = [
            "noteId": .string(noteId),
            "assetId": .string(assetId),
            "name": .string(runtime.drafts["name"] ?? assetId),
            "mimeType": .string(runtime.drafts["mimeType"] ?? "application/octet-stream"),
            "size": .number(Double(runtime.drafts["size"] ?? "0") ?? 0),
            "kind": .string(runtime.drafts["kind"] ?? "file"),
            "createdAt": .string(ISO8601DateFormatter().string(from: Date())),
        ]
        do {
            let _: JSONValue = try await app.client.moduleRequest(
                method: "POST",
                path: "/v1/modules/\(session.manifest.id)/records/attachment",
                body: .object(["data": .object(data)]),
                expectedAccountID: accountID
            )
            runtime.lastError = nil
            runtime.recordSource = nil
            await loadInstalledRecords()
        } catch {
            runtime.lastError = "Couldn’t attach the file. Check that this installation can write media."
        }
    }

    /// Reads the installed module's records so the verified frontend can show them.
    /// Capability bindings are not collections and do not count as an empty vault.
    private func loadInstalledRecords() async {
        guard runtime.recordSource == nil, let accountID = app.auth.account?.accountId else { return }
        let moduleID = session.manifest.id
        guard GreenfieldClient.modulePath(moduleID) != nil else { return }
        let bindings = runtime.currentView?["bindings"]?.array ?? []
        var byType: [String: [ProductUIRecord]] = [:]
        var types = bindings.compactMap { binding -> String? in
            guard binding["source"]?.string == "record.query" || binding["source"]?.string == "record.detail" else { return nil }
            return binding["recordType"]?.string
        }
        types.append(contentsOf: ProductUILayout.referencedRecordTypes(in: runtime.currentView))
        for type in types {
            guard type.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
                  byType[type] == nil else { continue }
            let path = "/v1/modules/\(moduleID)/records/\(type)?limit=50&recordState=active&sort=updatedAt&direction=desc"
            guard let value = try? await app.client.moduleRequest(
                method: "GET", path: path, body: nil, expectedAccountID: accountID
            ) else { continue }
            byType[type] = ProductUIRuntime.records(from: value)
        }
        guard !byType.isEmpty else {
            runtime.recordSource = { _, _ in [] }
            runtime.refresh()
            return
        }
        runtime.recordSource = { type, _ in byType[type] ?? [] }
        runtime.refresh()
        for (type, items) in byType { runtime.records[type] = items }
    }
}

struct ProductUIViewCanvas: View {
    let view: JSONValue
    @Bindable var runtime: ProductUIRuntime

    var body: some View {
        let kind = view["kind"]?.string ?? "collection"
        let declaredTitle = view["title"]?.string
        let states = view["states"]
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                if let declaredTitle, !declaredTitle.isEmpty, declaredTitle != runtime.document.productId {
                    Text(declaredTitle).font(.headline).accessibilityAddTraits(.isHeader)
                }
                if runtime.viewState == "error", let node = states?["error"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if runtime.viewState == "permissionDenied", let node = states?["permissionDenied"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if let root = view["root"] {
                    ProductUINode(node: root, runtime: runtime, provenance: .native)
                }
                if let error = runtime.lastError, runtime.viewState != "error" {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(ModulaLayout.contentInset)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("product-ui.view.\(kind)")
    }
}

struct ProductUINode: View {
    let node: JSONValue
    @Bindable var runtime: ProductUIRuntime
    var provenance: ProductUIProvenance
    /// The record this row is drawing. Nil for screen-level nodes.
    var record: ProductUIRecord? = nil
    /// Buttons inside a scrolling toolbar stay compact so the form keeps the screen width.
    var compact = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let type = node["type"]?.string ?? "section"
        if let required = node["capability"]?.string,
           !ModuleCapabilityBroker.hostSupports(required),
           !runtime.document.optionalCapabilities.contains(required) {
            unavailable(required)
        } else if let required = node["capability"]?.string,
                  !ModuleCapabilityBroker.hostSupports(required) {
            fallback(for: type, capability: required)
        } else {
            content(type)
        }
    }

    @ViewBuilder
    private func content(_ type: String) -> some View {
        switch type {
        case "section", "stack", "scroll":
            VStack(alignment: .leading, spacing: ModulaSpacing.sm) { children }
        case "row", "toolbar":
            let scrolls = ProductUILayout.scrollsHorizontally(
                childCount: node["children"]?.array?.count ?? 0,
                declared: node["layout"]?["scroll"]?.string
            )
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: ModulaSpacing.sm) { scrollingChildren }
                }
            } else {
                HStack(alignment: .center, spacing: ModulaSpacing.sm) { children }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "grid":
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) { children }
        case "text", "label", "metadata":
            let copy = displayText(node)
            if !copy.isEmpty {
                let quiet = ProductUILayout.isQuietCopy(copy)
                let path = node["valuePath"]?.string
                Text(copy)
                    .font(path == "title" ? .body.weight(.semibold) : quiet || type != "text" ? .footnote : .subheadline)
                    .foregroundStyle(path == "title" ? .primary : .secondary)
                    .lineLimit(path == "title" ? 2 : quiet ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "badge":
            let copy = displayText(node)
            if ProductUILayout.showsBadge(copy) {
                Text(copy)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(app.appearance.accent.color.opacity(0.14), in: Capsule())
            }
        case "divider":
            Divider()
        case "icon":
            Image(systemName: node["icon"]?.string ?? "square.stack.3d.up").foregroundStyle(app.appearance.accent.color)
        case "image", "media":
            RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 120)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        case "button":
            actionButton
        case "search":
            TextField(runtime.boundText(node).isEmpty ? "Search" : runtime.boundText(node), text: $runtime.query)
                .textFieldStyle(.roundedBorder)
                .layoutPriority(1)
                .onChange(of: runtime.query) { _, _ in runtime.refresh() }
                .accessibilityIdentifier("product-ui.search")
        case "filter":
            EmptyView()
        case "sort":
            Picker("Sort", selection: $runtime.sort) {
                Text("Updated").tag("updatedAt")
                Text("Title").tag("title")
                Text("Created").tag("createdAt")
            }
            .onChange(of: runtime.sort) { _, _ in runtime.refresh() }
        case "field":
            field
        case "recordList":
            recordList
        case "recordRow":
            VStack(alignment: .leading, spacing: 4) { children }
        case "emptyState":
            VStack(spacing: 12) {
                Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                Text(runtime.boundText(node).isEmpty ? "Nothing here yet" : runtime.boundText(node))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                children
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        case "errorState":
            let copy = displayText(node)
            if !copy.isEmpty {
                Label(copy, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "loadingState":
            ProgressView(runtime.boundText(node).isEmpty ? "Loading…" : runtime.boundText(node))
        case "menu", "tabs", "picker", "sheet":
            children
        case "progress":
            ProgressView(value: 0.4)
        case "richText", "richDocumentEditor":
            StructuredDocumentEditor(
                text: bindingDraft(node["fieldId"]?.string ?? node["binding"]?.string ?? node["field"]?["id"]?.string ?? "document"),
                capability: "ui.richText@1",
                externalCommand: runtime.lastAction
            )
        case "editorToolbar":
            ProductUIEditorToolbar { command in runtime.lastAction = command }
        case "graph":
            ProductUIGraphFallback(records: runtime.bindingRecords(node["binding"]?.string))
        case "revisionBrowser", "attachmentGallery", "propertyEditor", "referencePicker",
             "recordTable", "recordBoard", "commandMenu":
            fallback(for: type, capability: ProductUIDocument.advancedComponents[type] ?? "ui.\(type)@1")
        default:
            if ProductUIDocument.advancedComponents[type] != nil {
                fallback(for: type, capability: ProductUIDocument.advancedComponents[type]!)
            } else {
                children
            }
        }
    }

    @ViewBuilder private var children: some View {
        ForEach(Array((node["children"]?.array ?? []).enumerated()), id: \.offset) { _, child in
            ProductUINode(node: child, runtime: runtime, provenance: provenance, record: record, compact: compact)
        }
    }

    @ViewBuilder private var scrollingChildren: some View {
        ForEach(Array((node["children"]?.array ?? []).enumerated()), id: \.offset) { _, child in
            ProductUINode(node: child, runtime: runtime, provenance: provenance, record: record, compact: true)
        }
    }

    @ViewBuilder private var actionButton: some View {
        let button = Button(runtime.boundText(node).isEmpty ? "Continue" : runtime.boundText(node)) {
            if let action = node["action"]?.string { runtime.perform(actionId: action) }
        }
        .tint(app.appearance.accent.color)
        .accessibilityIdentifier("product-ui.button.\(node["action"]?.string ?? "none")")
        if compact {
            button.buttonStyle(.bordered).controlSize(.small)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private func displayText(_ node: JSONValue) -> String {
        if let record, let path = node["valuePath"]?.string {
            return ProductUILayout.present(record.value(path), path: path)
        }
        return runtime.boundText(node)
    }

    private var field: some View {
        let field = node["field"]
        let id = field?["id"]?.string ?? "field"
        let label = field?["label"]?.string ?? id
        let kind = field?["type"]?.string ?? "text"
        return VStack(alignment: .leading, spacing: 6) {
            if kind != "boolean" {
                Text(label).font(.subheadline.weight(.semibold))
            }
            if kind == "richText" {
                StructuredDocumentEditor(text: bindingDraft(id), capability: field?["capability"]?.string ?? "ui.richText@1", externalCommand: runtime.lastAction)
                    .frame(minHeight: 160)
            } else if kind == "multilineText" {
                TextEditor(text: bindingDraft(id)).frame(minHeight: 88)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            } else if kind == "boolean" {
                Toggle(isOn: Binding(
                    get: { ["true", "yes", "1"].contains(runtime.drafts[id]?.lowercased() ?? "") },
                    set: { runtime.drafts[id] = $0 ? "true" : "false" }
                )) {
                    Text(label).font(.subheadline.weight(.semibold))
                }
            } else if kind == "recordReference" {
                let type = field?["recordType"]?.string ?? ""
                let choices = runtime.records[type] ?? []
                Picker(label, selection: bindingDraft(id)) {
                    Text("Choose").tag("")
                    ForEach(choices) { choice in
                        Text(choice.value("title").isEmpty ? choice.id : choice.value("title")).tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
            } else if kind == "singleSelect" {
                Picker(label, selection: bindingDraft(id)) {
                    Text("Not set").tag("")
                    ForEach(Array((field?["options"]?.array ?? []).enumerated()), id: \.offset) { _, option in
                        Text(option["label"]?.string ?? option["value"]?.string ?? "")
                            .tag(option["value"]?.string ?? "")
                    }
                }
                .pickerStyle(.menu)
            } else {
                TextField(field?["placeholder"]?.string ?? "", text: bindingDraft(id))
                    .textFieldStyle(.roundedBorder)
            }
            if let help = field?["helpText"]?.string, !help.isEmpty {
                Text(help).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("product-ui.field.\(id)")
    }

    private var recordList: some View {
        let items = runtime.bindingRecords(node["binding"]?.string)
        return LazyVStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                if runtime.viewState == "loading", let loading = runtime.currentView?["states"]?["loading"] {
                    ProductUINode(node: loading, runtime: runtime, provenance: provenance)
                } else if let empty = runtime.currentView?["states"]?["empty"] {
                    ProductUINode(node: empty, runtime: runtime, provenance: provenance)
                } else {
                    ContentUnavailableView("No records", systemImage: "tray")
                }
            }
            ForEach(items) { item in
                Button {
                    if let action = node["action"]?.string { runtime.perform(actionId: action, record: item) }
                } label: {
                    noteCard(item)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("product-ui.record.\(item.id)")
            }
        }
    }

    private func noteCard(_ item: ProductUIRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let template = node["children"]?.array?.first {
                    ProductUINode(node: template, runtime: runtime, provenance: provenance, record: item)
                } else {
                    Text(item.value("title").isEmpty ? "Untitled" : item.value("title"))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    let preview = item.value("plainTextProjection")
                    if !preview.isEmpty {
                        Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bindingDraft(_ id: String) -> Binding<String> {
        Binding(
            get: { runtime.drafts[id] ?? "" },
            set: { runtime.drafts[id] = $0 }
        )
    }

    private func unavailable(_ capability: String) -> some View {
        Label("Required \(capability) is unavailable", systemImage: "exclamationmark.octagon")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("product-ui.unavailable.\(capability)")
    }

    private func fallback(for type: String, capability: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(type) uses a host fallback", systemImage: "square.dashed")
                .font(.subheadline.weight(.semibold))
            Text("Declared capability \(capability) is not fully native on this host. The fallback stays generic.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            children
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("product-ui.fallback.\(type)")
    }
}


enum ProductUILayout {
    /// A short toolbar stays in the row. A long one scrolls so it cannot widen the screen.
    static func scrollsHorizontally(childCount: Int, declared: String?) -> Bool {
        declared == "horizontal" || childCount > 3
    }

    /// Contract notes are part of the frontend file. They stay available, quieter than the note.
    static func isQuietCopy(_ text: String) -> Bool {
        text.count > 90
    }

    static func showsBadge(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && value != "false" && value != "0" && value != "null"
    }

    static func referencedRecordTypes(in view: JSONValue?) -> [String] {
        guard let view else { return [] }
        var types: [String] = []
        func walk(_ node: JSONValue) {
            if let type = node["field"]?["recordType"]?.string { types.append(type) }
            node["children"]?.array?.forEach(walk)
        }
        walk(view)
        return Array(Set(types))
    }

    static func present(_ value: String, path: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard path == "updatedAt" || path == "createdAt" || path.hasSuffix("At") else { return trimmed }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed)
        return date?.formatted(.relative(presentation: .named)) ?? trimmed
    }
}

struct ProductUIEditorToolbar: View {
    var onCommand: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(["bold", "italic", "heading", "list", "link"], id: \.self) { command in
                Button(command.capitalized) { onCommand("ui.richText.commands@1.\(command)") }
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityIdentifier("product-ui.editor-toolbar")
    }
}

struct ProductUIGraphFallback: View {
    let records: [ProductUIRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Graph").font(.headline)
            Text("\(records.count) linked records. The native graph canvas is a declared fallback list.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(records.prefix(12)) { item in
                Text(item.value("title").isEmpty ? item.id : item.value("title"))
            }
        }
        .accessibilityIdentifier("product-ui.graph")
    }
}
