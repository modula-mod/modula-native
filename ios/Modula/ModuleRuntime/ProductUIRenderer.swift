import SwiftUI

/// Generic Product UI 1.0 renderer. No product-specific module ID branches.
struct ProductUIHostView: View {
    let session: ModuleSession
    let document: ProductUIDocument
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var runtime: ProductUIRuntime

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
        .onAppear {
            runtime.online = app.auth.account != nil
            if let source = app.runtime.productUIRecordSource {
                runtime.recordSource = source
            }
            runtime.refresh()
            if session.state == .loadingModule || session.state == .preparing {
                app.runtime.ready(session)
            }
        }
        .accessibilityIdentifier("module.host.product-ui")
    }
}

struct ProductUIViewCanvas: View {
    let view: JSONValue
    @Bindable var runtime: ProductUIRuntime

    var body: some View {
        let kind = view["kind"]?.string ?? "collection"
        let title = view["title"]?.string ?? runtime.document.productId
        let states = view["states"]
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if runtime.viewState == "loading", let node = states?["loading"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if runtime.viewState == "empty", let node = states?["empty"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if runtime.viewState == "error", let node = states?["error"] {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("product-ui.view.\(kind)")
    }
}

struct ProductUINode: View {
    let node: JSONValue
    @Bindable var runtime: ProductUIRuntime
    var provenance: ProductUIProvenance
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
            HStack(alignment: .center, spacing: ModulaSpacing.sm) { children }.frame(maxWidth: .infinity, alignment: .leading)
        case "grid":
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) { children }
        case "text", "label", "metadata":
            Text(runtime.boundText(node)).font(type == "text" ? .body : .subheadline).foregroundStyle(type == "metadata" ? .secondary : .primary)
        case "badge":
            Text(runtime.boundText(node).isEmpty ? " " : runtime.boundText(node))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(app.appearance.accent.color.opacity(0.14), in: Capsule())
        case "divider":
            Divider()
        case "icon":
            Image(systemName: node["icon"]?.string ?? "square.stack.3d.up").foregroundStyle(app.appearance.accent.color)
        case "image", "media":
            RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 120)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        case "button":
            Button(runtime.boundText(node).isEmpty ? "Continue" : runtime.boundText(node)) {
                if let action = node["action"]?.string { runtime.perform(actionId: action) }
            }
            .buttonStyle(.borderedProminent)
            .tint(app.appearance.accent.color)
            .accessibilityIdentifier("product-ui.button.\(node["action"]?.string ?? "none")")
        case "search":
            TextField(runtime.boundText(node).isEmpty ? "Search" : runtime.boundText(node), text: $runtime.query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: runtime.query) { _, _ in runtime.refresh() }
                .accessibilityIdentifier("product-ui.search")
        case "filter":
            Picker("Filter", selection: $runtime.filter) {
                Text("All").tag("")
                Text("Open").tag("open")
                Text("Done").tag("done")
            }
            .pickerStyle(.segmented)
            .onChange(of: runtime.filter) { _, _ in runtime.refresh() }
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
            recordRow(runtime.bindingRecords(node["binding"]?.string).first)
        case "emptyState":
            ContentUnavailableView(runtime.boundText(node).isEmpty ? "Nothing here yet" : runtime.boundText(node), systemImage: "tray")
        case "errorState":
            ContentUnavailableView(runtime.boundText(node).isEmpty ? "Couldn’t load this screen" : runtime.boundText(node), systemImage: "exclamationmark.triangle")
        case "loadingState":
            ProgressView(runtime.boundText(node).isEmpty ? "Loading…" : runtime.boundText(node))
        case "menu", "tabs", "picker", "sheet":
            children
        case "progress":
            ProgressView(value: 0.4)
        case "richText", "richDocumentEditor":
            ProductUIRichTextEditor(text: bindingDraft("body"), capability: "ui.richText@1")
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
            ProductUINode(node: child, runtime: runtime, provenance: provenance)
        }
    }

    private var field: some View {
        let field = node["field"]
        let id = field?["id"]?.string ?? "field"
        let label = field?["label"]?.string ?? id
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            if field?["type"]?.string == "multilineText" || field?["type"]?.string == "richText" {
                TextEditor(text: bindingDraft(id)).frame(minHeight: field?["type"]?.string == "richText" ? 180 : 88)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            } else {
                TextField(label, text: bindingDraft(id)).textFieldStyle(.roundedBorder)
            }
        }
        .accessibilityIdentifier("product-ui.field.\(id)")
    }

    private var recordList: some View {
        let items = runtime.bindingRecords(node["binding"]?.string)
        return LazyVStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                ContentUnavailableView("No records", systemImage: "tray")
            }
            ForEach(items) { item in
                Button {
                    if let action = node["action"]?.string { runtime.perform(actionId: action, record: item) }
                } label: {
                    recordRow(item)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("product-ui.record.\(item.id)")
            }
        }
    }

    private func recordRow(_ item: ProductUIRecord?) -> some View {
        let title = item?.value("title").isEmpty == false ? item!.value("title") : runtime.boundText(node)
        let status = item?.value("status") ?? ""
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Untitled" : title).font(.headline)
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

struct ProductUIRichTextEditor: View {
    @Binding var text: String
    let capability: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rich document")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("product-ui.richtext.caption")
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .accessibilityIdentifier("product-ui.richtext")
            Text("Host renderer \(capability). Blocks stay plain-text projected until a richer native editor is available.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
