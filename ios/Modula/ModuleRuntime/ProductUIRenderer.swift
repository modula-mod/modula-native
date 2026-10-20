import SwiftUI
import UniformTypeIdentifiers
import QuickLook

/// Generic Product UI 1.0 renderer. No product-specific module ID branches.
struct ProductUIHostView: View {
    let session: ModuleSession
    let document: ProductUIDocument
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var runtime: ProductUIRuntime
    @State private var showsFileImporter = false
    @State private var mediaUploadInProgress = false
    @State private var previewURL: URL?
    @State private var previewFilename = "Attachment"

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
                    Label("Update Modula to continue", systemImage: "arrow.down.app")
                } description: {
                    Text("This screen needs a newer version of Modula.")
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
        .environment(\.font, .system(.body, design: .default))
        .overlay(alignment: .top) {
            if mediaUploadInProgress { ProgressView("Attaching file…").padding(8).background(.regularMaterial, in: Capsule()) }
        }
        .toolbar {
            if runtime.route != "/" {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        runtime.goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("product-ui.back")
                }
            }
            if runtime.currentView?["kind"]?.string == "form",
               let actionId = ProductUILayout.formSubmitAction(in: runtime.currentView, document: runtime.document) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { runtime.perform(actionId: actionId) }
                        .fontWeight(.semibold)
                        .disabled(runtime.serverMutation != nil)
                        .accessibilityIdentifier("product-ui.form.done")
                }
            }
        }
        .navigationBarBackButtonHidden(runtime.route != "/")
        .toolbar(runtime.currentView?["kind"]?.string == "form" ? .hidden : .visible, for: .tabBar)
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
        .task(id: "\(runtime.query)|\(runtime.sort)") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await loadInstalledRecords()
        }
        .onChange(of: runtime.requestedNextPage) { _, key in
            guard let key else { return }
            runtime.requestedNextPage = nil
            Task { await loadNextPage(key) }
        }
        .onChange(of: runtime.filePickToken) { _, token in
            if token > 0 { showsFileImporter = true }
        }
        .onChange(of: runtime.pendingMediaOpen) { _, request in
            guard let request else { return }
            runtime.pendingMediaOpen = nil
            Task { await openMedia(request) }
        }
        .onChange(of: runtime.pendingMediaDetachment) { _, request in
            guard let request else { return }
            runtime.pendingMediaDetachment = nil
            Task { await detachMedia(request) }
        }
        .onChange(of: previewURL) { old, new in
            if new == nil, let old { try? FileManager.default.removeItem(at: old) }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL {
                NavigationStack {
                    ModuleAttachmentPreview(url: previewURL)
                        .navigationTitle(previewFilename)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { self.previewURL = nil }
                            }
                        }
                }
            }
        }
        .confirmationDialog("Unsaved changes", isPresented: Binding(
            get: { runtime.showsUnsavedChanges },
            set: { runtime.showsUnsavedChanges = $0 }
        )) {
            Button("Discard Changes", role: .destructive) { runtime.discardAndLeave() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Save the record before leaving to keep your changes.")
        }
        .onChange(of: runtime.serverMutation?.id) { _, mutationId in
            guard mutationId != nil, let mutation = runtime.serverMutation else { return }
            Task { await performRecordWrite(mutation) }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .text, .audio, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let request = runtime.pendingMediaAttachment {
                    runtime.pendingMediaAttachment = nil
                    Task { await uploadAndBind(url: url, to: request) }
                } else {
                    rememberChosenFile(url)
                }
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

    private func uploadAndBind(url: URL, to request: ProductUIMediaAttachmentRequest) async {
        guard !mediaUploadInProgress,
              let accountID = app.auth.account?.accountId,
              GreenfieldClient.modulePath(session.manifest.id) != nil else { return }
        if let grants = session.cachedRelease?.descriptor?.grantedPermissions {
            let required = [
                "records:module.\(session.manifest.id).\(request.recordType):write",
                "media:module.\(session.manifest.id).\(request.recordType):write",
            ]
            guard required.allSatisfy(grants.contains) else {
                runtime.lastError = "This module does not have permission to attach files to this record."
                return
            }
        }
        mediaUploadInProgress = true
        defer { mediaUploadInProgress = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let count = values.fileSize ?? 0
            guard count > 0, count <= 100_000_000 else {
                runtime.lastError = "Choose a nonempty file smaller than 100 MB."
                return
            }
            try FileManager.default.copyItem(at: url, to: temporary)
            let mime = values.contentType?.preferredMIMEType ?? "application/octet-stream"
            let kind: CreationMedia.Kind = mime.hasPrefix("image/") ? .image :
                mime == "application/pdf" ? .pdf : mime.hasPrefix("audio/") ? .audio : .document
            let prepared = PreparedMedia(
                id: UUID().uuidString, kind: kind, fileURL: temporary, mimeType: mime,
                filename: url.lastPathComponent, altText: "", byteCount: count,
                checksum: nil, width: nil, height: nil, duration: nil, pageCount: nil
            )
            let uploaded = try await app.mediaUploader.upload(
                prepared, progress: { _ in }, sessionCreated: { _, _ in }
            )
            guard app.auth.account?.accountId == accountID else { throw APIError.accountChanged }
            let path = "/v1/modules/\(session.manifest.id)/records/\(request.recordType)/\(request.recordId)/media"
            let _: JSONValue = try await app.client.moduleRequest(
                method: "POST", path: path,
                body: .object(["assetId": .string(uploaded.remoteID), "role": .string("attachment")]),
                expectedAccountID: accountID
            )
            runtime.lastError = nil
            runtime.serverRecords.removeValue(forKey: "\(request.recordType)|media|\(request.recordId)")
            await loadInstalledRecords()
        } catch let error as APIError {
            runtime.lastError = error.userFacingMessage
        } catch {
            runtime.lastError = "The file could not be attached. Try again."
        }
    }

    private func openMedia(_ request: ProductUIMediaOpenRequest) async {
        guard let accountID = app.auth.account?.accountId else { return }
        do {
            let downloaded = try await app.client.downloadModuleAttachment(
                request.assetId, expectedAccountID: accountID
            )
            defer { try? FileManager.default.removeItem(at: downloaded) }
            let suffix = URL(fileURLWithPath: request.filename).pathExtension
            let safeSuffix = suffix.range(of: "^[A-Za-z0-9]{1,12}$", options: .regularExpression) != nil ? suffix : "bin"
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("module-preview-\(UUID().uuidString)")
                .appendingPathExtension(safeSuffix)
            try FileManager.default.copyItem(at: downloaded, to: destination)
            previewFilename = request.filename
            previewURL = destination
            runtime.lastError = nil
        } catch let error as APIError {
            runtime.lastError = error.userFacingMessage
        } catch {
            runtime.lastError = "The attachment could not be opened."
        }
    }

    private func detachMedia(_ request: ProductUIMediaDetachmentRequest) async {
        guard let accountID = app.auth.account?.accountId else { return }
        let path = "/v1/modules/\(session.manifest.id)/records/\(request.recordType)/\(request.recordId)/media/\(request.bindingId)"
        do {
            let _: JSONValue = try await app.client.moduleRequest(
                method: "DELETE", path: path, body: nil, expectedAccountID: accountID
            )
            runtime.serverRecords.removeValue(forKey: "\(request.recordType)|media|\(request.recordId)")
            runtime.lastError = nil
            await loadInstalledRecords()
        } catch let error as APIError {
            runtime.lastError = error.userFacingMessage
        } catch {
            runtime.lastError = "The attachment could not be removed."
        }
    }

    /// Writes the form into the signed-in account's module records, then reloads that account's list.
    private func performRecordWrite(_ mutation: ProductUIMutation) async {
        runtime.serverMutation = nil
        guard let accountID = app.auth.account?.accountId else {
            runtime.lastError = "Sign in to Modula to save."
            return
        }
        guard let action = runtime.document.action(id: mutation.actionId) else {
            runtime.lastError = "This action is not available on this host yet."
            return
        }
        let existing = mutation.recordId.flatMap { id in
            runtime.serverRecords.values.flatMap(\.self).first { $0.id == id }
        }
        let prepared = ProductUIRecords.prepare(
            moduleId: session.manifest.id,
            mutation: mutation,
            action: action,
            fields: ProductUIRecords.fieldNodes(in: runtime.currentView),
            existing: existing
        )
        switch prepared {
        case .failure(let error):
            runtime.lastError = error.message
        case .success(let request):
            do {
                let _: JSONValue = try await app.client.moduleRequest(
                    method: request.method, path: request.path, body: request.body, expectedAccountID: accountID
                )
                runtime.lastError = nil
                runtime.clearSavedDraft()
                runtime.serverRecords = [:]
                runtime.recordSource = nil
                if mutation.family == "record.update" || mutation.family == "record.delete" {
                    runtime.goBack()
                } else if mutation.family == "record.create" {
                    runtime.open("/")
                } else {
                    runtime.refresh()
                }
                await loadInstalledRecords()
            } catch let error as APIError {
                runtime.lastError = error.userFacingMessage
            } catch {
                runtime.lastError = "Couldn’t save this record."
            }
        }
    }

    /// Reads the installed module's records for this account. Capability bindings are not collections.
    private func loadInstalledRecords() async {
        guard let accountID = app.auth.account?.accountId else { return }
        let moduleID = session.manifest.id
        guard GreenfieldClient.modulePath(moduleID) != nil else { return }
        let requestedRoute = runtime.route
        let requestedQuery = runtime.query
        let requestedSort = runtime.sort
        let bindings = runtime.currentView?["bindings"]?.array ?? []
        var pairs: [(String, String)] = []
        for binding in bindings {
            let source = binding["source"]?.string ?? ""
            guard source == "record.query",
                  let type = binding["recordType"]?.string,
                  type.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else { continue }
            let state = binding["query"]?["recordState"]?.string ?? "active"
            if !pairs.contains(where: { $0.0 == type && $0.1 == state }) { pairs.append((type, state)) }
        }
        for type in ProductUILayout.referencedRecordTypes(in: runtime.currentView)
        where type.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil
            && !pairs.contains(where: { $0.0 == type && $0.1 == "active" }) {
            pairs.append((type, "active"))
        }
        var loaded: [String: [ProductUIRecord]] = [:]
        var firstError: Error?
        var detailError: Error?
        var nextCursors: [String: String] = [:]
        for (type, state) in pairs {
            let path = recordQueryPath(type: type, state: state, bindings: bindings)
            do {
                let value: JSONValue = try await app.client.moduleRequest(
                    method: "GET", path: path, body: nil, expectedAccountID: accountID
                )
                loaded["\(type)|\(state)"] = ProductUIRuntime.records(from: value)
                if let cursor = value["nextCursor"]?.string { nextCursors["\(type)|\(state)"] = cursor }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        for binding in bindings where binding["source"]?.string == "record.detail" {
            guard let type = binding["recordType"]?.string,
                  let recordId = runtime.routeParams[binding["recordIdParam"]?.string ?? "id"],
                  !recordId.isEmpty,
                  let encoded = recordId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { continue }
            do {
                let value: JSONValue = try await app.client.moduleRequest(
                    method: "GET", path: "/v1/modules/\(moduleID)/records/\(type)/\(encoded)",
                    body: nil, expectedAccountID: accountID
                )
                if let record = ProductUIRuntime.records(from: value).first {
                    var items = loaded["\(type)|active"] ?? []
                    items.removeAll { $0.id == record.id }
                    items.insert(record, at: 0)
                    loaded["\(type)|active"] = items
                }
            } catch {
                detailError = error
                if firstError == nil { firstError = error }
            }
        }
        for binding in bindings where ["record.revisions", "record.revision"].contains(binding["source"]?.string ?? "") {
            guard let source = binding["source"]?.string,
                  let type = binding["recordType"]?.string,
                  type.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
                  let recordID = runtime.routeParams[binding["recordIdParam"]?.string ?? "id"],
                  let encodedID = recordID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { continue }
            var path = "/v1/modules/\(moduleID)/records/\(type)/\(encodedID)/revisions"
            var key = "\(type)|revisions|\(recordID)"
            if source == "record.revision" {
                guard let revision = runtime.routeParams[binding["revisionParam"]?.string ?? "revision"],
                      let number = Int(revision), number >= 1 else { continue }
                path += "/\(number)"
                key = "\(type)|revision|\(recordID)|\(revision)"
            } else if let limit = binding["query"]?["limit"]?.number, limit >= 1, limit <= 100 {
                path += "?limit=\(Int(limit))"
            }
            do {
                let value: JSONValue = try await app.client.moduleRequest(
                    method: "GET", path: path, body: nil, expectedAccountID: accountID
                )
                loaded[key] = ProductUIRuntime.revisions(from: value)
            } catch {
                detailError = error
                if firstError == nil { firstError = error }
            }
        }
        for binding in bindings where binding["source"]?.string == "record.media" {
            guard let type = binding["recordType"]?.string,
                  type.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
                  let recordID = runtime.routeParams[binding["recordIdParam"]?.string ?? "id"],
                  let encoded = recordID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { continue }
            let key = "\(type)|media|\(recordID)"
            do {
                let value: JSONValue = try await app.client.moduleRequest(
                    method: "GET", path: "/v1/modules/\(moduleID)/records/\(type)/\(encoded)/media",
                    body: nil, expectedAccountID: accountID
                )
                loaded[key] = ProductUIRuntime.media(from: value)
            } catch {
                detailError = error
                if firstError == nil { firstError = error }
            }
        }
        guard runtime.route == requestedRoute, runtime.query == requestedQuery,
              runtime.sort == requestedSort, app.auth.account?.accountId == accountID else { return }
        if let detailError {
            runtime.viewState = (detailError as? APIError)?.code == "FORBIDDEN" ? "permissionDenied" : "error"
            runtime.lastError = (detailError as? APIError)?.userFacingMessage ?? "Couldn’t open this record."
            return
        }
        if let firstError, loaded.isEmpty, !pairs.isEmpty {
            runtime.viewState = (firstError as? APIError)?.code == "FORBIDDEN" ? "permissionDenied" : runtime.online ? "error" : "offline"
            runtime.lastError = (firstError as? APIError)?.userFacingMessage ?? "Couldn’t load this collection. Try again."
            return
        }
        for (key, items) in loaded { runtime.serverRecords[key] = items }
        for (type, state) in pairs {
            let key = "\(type)|\(state)"
            runtime.nextPageCursors[key] = nextCursors[key]
        }
        runtime.recordSource = nil
        runtime.refresh()
    }

    private func recordQueryPath(type: String, state: String, bindings: [JSONValue], cursor: String? = nil) -> String {
        let binding = bindings.first {
            $0["source"]?.string == "record.query" && $0["recordType"]?.string == type
                && ($0["query"]?["recordState"]?.string ?? "active") == state
        }
        let sort = binding?["query"]?["sortParam"]?.string != nil ? runtime.sort : "updatedAt"
        var path = "/v1/modules/\(session.manifest.id)/records/\(type)?limit=100&recordState=\(state)&sort=\(sort)&direction=desc"
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        if let field = binding?["query"]?["membership"]?["field"]?.string,
           let param = binding?["query"]?["membership"]?["param"]?.string,
           let recordID = runtime.routeParams[param],
           let encoded = "\"\(recordID)\"".addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "&contains.\(field)=\(encoded)"
        }
        if binding?["query"]?["filterParam"]?.string == "folderId",
           let recordID = runtime.routeParams["folderId"],
           let encoded = recordID.addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "&folder=\(encoded)"
        }
        if !runtime.query.isEmpty,
           let encoded = runtime.query.addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "&q=\(encoded)"
        }
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "&cursor=\(encoded)"
        }
        return path
    }

    private func loadNextPage(_ key: String) async {
        guard !runtime.loadingNextPage,
              let cursor = runtime.nextPageCursors[key],
              let accountID = app.auth.account?.accountId,
              let separator = key.lastIndex(of: "|") else { return }
        let type = String(key[..<separator])
        let state = String(key[key.index(after: separator)...])
        let route = runtime.route
        let query = runtime.query
        let sort = runtime.sort
        runtime.loadingNextPage = true
        defer { runtime.loadingNextPage = false }
        do {
            let path = recordQueryPath(type: type, state: state,
                                       bindings: runtime.currentView?["bindings"]?.array ?? [], cursor: cursor)
            let value: JSONValue = try await app.client.moduleRequest(
                method: "GET", path: path, body: nil, expectedAccountID: accountID
            )
            guard runtime.route == route, runtime.query == query, runtime.sort == sort,
                  app.auth.account?.accountId == accountID else { return }
            var items = runtime.serverRecords[key] ?? []
            let seen = Set(items.map(\.id))
            items.append(contentsOf: ProductUIRuntime.records(from: value).filter { !seen.contains($0.id) })
            runtime.serverRecords[key] = items
            runtime.nextPageCursors[key] = value["nextCursor"]?.string
            runtime.refresh()
        } catch let error as APIError {
            runtime.lastError = error.userFacingMessage
        } catch {
            runtime.lastError = "More records could not be loaded. Try again."
        }
    }
}

private struct ModuleAttachmentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
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
                if kind != "detail", kind != "form", let declaredTitle, !declaredTitle.isEmpty,
                   declaredTitle != runtime.document.productId,
                   declaredTitle != runtime.session.manifest.name {
                    Text(declaredTitle)
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }
                if runtime.viewState == "error", let node = states?["error"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if runtime.viewState == "permissionDenied", let node = states?["permissionDenied"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if runtime.viewState == "offline", let node = states?["offline"] {
                    ProductUINode(node: node, runtime: runtime, provenance: .native)
                } else if let root = view["root"] {
                    ProductUINode(node: root, runtime: runtime, provenance: .native)
                }
                if let error = runtime.lastError, runtime.viewState != "error" {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(ModulaLayout.contentInset)
            .padding(.bottom, ModulaSpacing.lg + 96)
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
    @State private var showsConfirmation = false
    @State private var pendingRowAction: String?
    @State private var pendingRowRecord: ProductUIRecord?
    @FocusState private var searchFocused: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

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
        case "section":
            if node["collapsible"]?.bool == true {
                DisclosureGroup(node["text"]?.string ?? "More") { children }
                    .font(.subheadline)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: ModulaSpacing.sm) { children }
            }
        case "stack", "scroll":
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
            if let structured = boundStructuredDocument(node) {
                StructuredDocumentReader(value: structured, omitOpeningHeading: record?.value("title") ?? runtime.selected[node["binding"]?.string ?? ""]?.value("title"))
            } else {
                let copy = displayText(node)
                if !copy.isEmpty {
                let path = node["valuePath"]?.string
                let heading = node["accessibility"]?["role"]?.string == "header"
                Text(copy)
                    .font(path == "title" ? (compact ? .body.weight(.semibold) : .title2.weight(.semibold)) : heading ? .headline : type != "text" ? .caption : path == "plainTextProjection" ? .subheadline : .body)
                    .foregroundStyle(path == "title" || heading || type == "text" && path != "plainTextProjection" ? .primary : .secondary)
                    .lineLimit(path == "title" ? 2 : path == "plainTextProjection" ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                }
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(runtime.boundText(node).isEmpty ? "Search" : runtime.boundText(node), text: $runtime.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .layoutPriority(1)
                    .accessibilityIdentifier("product-ui.search")
                if !runtime.query.isEmpty {
                    Button {
                        runtime.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("product-ui.search.clear")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
            .onAppear {
                if runtime.currentView?["id"]?.string == "search" { searchFocused = true }
            }
            .onChange(of: runtime.query) { _, _ in runtime.refresh() }
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
            if !copy.isEmpty, !ProductUILayout.isContractCopy(copy) {
                Label(copy, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "loadingState":
            ProgressView(runtime.boundText(node).isEmpty ? "Loading…" : runtime.boundText(node))
        case "menu":
            Menu {
                children
            } label: {
                Label(node["label"]?.string ?? "More", systemImage: "ellipsis.circle")
            }
        case "tabs", "picker", "sheet":
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
        let actionId = node["action"]?.string
        let action = actionId.flatMap { runtime.document.action(id: $0) }
        let target = record ?? action?["recordIdBinding"]?.string.flatMap { runtime.selected[$0] }
        let isActiveToggle = action?["family"]?.string == "record.toggle"
            && action?["recordField"]?.string.flatMap { target?.data[$0]?.bool } == true
        let defaultLabel = runtime.boundText(node).isEmpty ? "Continue" : runtime.boundText(node)
        let label = isActiveToggle ? action?["activeLabel"]?.string ?? defaultLabel : defaultLabel
        let route = action?["route"]?.string ?? ""
        let isPrimaryRoute = ["new", "create", "edit"].contains(route.split(separator: "/").last.map(String.init) ?? "")
        let isSecondaryNavigation = action?["family"]?.string == "route.open" && !isPrimaryRoute
        let symbol = node["icon"]?.string ?? action?["icon"]?.string
        let systemSymbol = symbol.flatMap { $0.hasPrefix("system.") ? String($0.dropFirst("system.".count)) : nil }
        let button = Button {
            guard let actionId else { return }
            if runtime.document.action(id: actionId)?["confirm"]?.bool == true {
                showsConfirmation = true
            } else {
                runtime.perform(actionId: actionId, record: record)
            }
        } label: {
            if let systemSymbol { Label(label, systemImage: systemSymbol) }
            else { Text(label) }
        }
        .tint(app.appearance.accent.color)
        .confirmationDialog("Confirm \(label)?", isPresented: $showsConfirmation) {
            Button(label, role: .destructive) {
                if let actionId { runtime.perform(actionId: actionId, record: record) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("product-ui.button.\(node["action"]?.string ?? "none")")
        if compact {
            button.buttonStyle(.bordered).controlSize(.small)
        } else if isSecondaryNavigation {
            button.buttonStyle(.bordered).frame(minHeight: 44)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private func displayText(_ node: JSONValue) -> String {
        if let record, let path = node["valuePath"]?.string {
            let value = ProductUILayout.present(record.value(path), path: path)
            return path == "plainTextProjection"
                ? ProductUILayout.preview(value, title: record.value("title"))
                : value
        }
        let text = runtime.boundText(node)
        return node["valuePath"]?.string.map { ProductUILayout.present(text, path: $0) } ?? text
    }

    private func boundStructuredDocument(_ node: JSONValue) -> JSONValue? {
        guard node["type"]?.string == "text",
              let binding = node["binding"]?.string,
              let path = node["valuePath"]?.string else { return nil }
        let source = record ?? runtime.selected[binding] ?? runtime.bindingRecords(binding).first
        guard let value = source?.fieldValue(path), value["blocks"]?.array != nil,
              value["schemaVersion"]?.string != nil else { return nil }
        return value
    }

    private var field: some View {
        let field = node["field"]
        let id = field?["id"]?.string ?? "field"
        let label = field?["label"]?.string ?? id
        let kind = field?["type"]?.string ?? "text"
        let presentation = field?["presentation"]?.string ?? "standard"
        return VStack(alignment: .leading, spacing: 6) {
            if kind != "boolean" && presentation == "standard" {
                Text(label).font(.subheadline.weight(.semibold))
            }
            if kind == "richText" {
                StructuredDocumentEditor(text: bindingDraft(id), capability: field?["capability"]?.string ?? "ui.richText@1", externalCommand: runtime.lastAction, focusedPresentation: presentation == "documentBody", placeholder: field?["placeholder"]?.string ?? "Start writing")
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
                let choices = runtime.availableRecords(type: type)
                Picker(label, selection: bindingDraft(id)) {
                    Text("Choose").tag("")
                    ForEach(choices) { choice in
                        Text(choice.value("name").isEmpty ? (choice.value("title").isEmpty ? choice.id : choice.value("title")) : choice.value("name")).tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
            } else if kind == "tags", let type = field?["recordType"]?.string {
                let choices = runtime.availableRecords(type: type)
                Menu {
                    ForEach(choices) { choice in
                        Button {
                            var ids = runtime.drafts[id]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                            if ids.contains(choice.id) { ids.removeAll { $0 == choice.id } }
                            else { ids.append(choice.id) }
                            runtime.drafts[id] = ids.joined(separator: ",")
                        } label: {
                            Label(choice.value("name").isEmpty ? choice.id : choice.value("name"),
                                  systemImage: (runtime.drafts[id] ?? "").split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == choice.id } ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    Text((runtime.drafts[id] ?? "").isEmpty ? "Choose tags" : "\((runtime.drafts[id] ?? "").split(separator: ",").count) selected")
                }
            } else if kind == "singleSelect" {
                Picker(label, selection: bindingDraft(id)) {
                    Text("Not set").tag("")
                    ForEach(Array((field?["options"]?.array ?? []).enumerated()), id: \.offset) { _, option in
                        Text(option["label"]?.string ?? option["value"]?.string ?? "")
                            .tag(option["value"]?.string ?? "")
                    }
                }
                .pickerStyle(.menu)
            } else if presentation == "documentTitle" && kind == "text" {
                TextField(field?["placeholder"]?.string ?? "Untitled", text: bindingDraft(id))
                    .font(.system(.title, design: .default, weight: .semibold))
                    .textFieldStyle(.plain)
                    .accessibilityLabel(label)
            } else {
                TextField(field?["placeholder"]?.string ?? "", text: bindingDraft(id))
                    .textFieldStyle(.roundedBorder)
            }
            if let help = field?["helpText"]?.string, !help.isEmpty, !ProductUILayout.isContractCopy(help) {
                Text(help).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ProductUIFieldIdentifier(id: id, enabled: kind != "richText"))
    }

    private var recordList: some View {
        let items = runtime.bindingRecords(node["binding"]?.string)
        let palette = ModulaPalette.resolve(app.appearance, scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                if let bindingID = node["binding"]?.string,
                          runtime.currentView?["bindings"]?.array?.contains(where: {
                              $0["id"]?.string == bindingID && $0["source"]?.string == "record.media"
                          }) == true {
                    Text("No attachments yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if runtime.viewState == "loading", let loading = runtime.currentView?["states"]?["loading"] {
                    ProductUINode(node: loading, runtime: runtime, provenance: provenance)
                } else if let empty = runtime.currentView?["states"]?["empty"] {
                    ProductUINode(node: empty, runtime: runtime, provenance: provenance)
                } else {
                    ContentUnavailableView("No records", systemImage: "tray")
                }
            }
            if !items.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 4) {
                            if let action = node["action"]?.string {
                                Button { runtime.perform(actionId: action, record: item) } label: {
                                    recordCard(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("product-ui.record.\(item.id)")
                            } else {
                                recordCard(item)
                                    .accessibilityIdentifier("product-ui.record.\(item.id)")
                            }
                            if let actions = node["actions"]?.array, !actions.isEmpty {
                                Menu {
                                    ForEach(actions.compactMap(\.string), id: \.self) { actionId in
                                        let action = runtime.document.action(id: actionId)
                                        let field = action?["recordField"]?.string
                                        let toggled = action?["family"]?.string == "record.toggle"
                                            && field.flatMap { item.data[$0]?.bool } == true
                                        let label = toggled ? action?["activeLabel"]?.string ?? actionId
                                            : action?["label"]?.string ?? actionId
                                        Button(label, role: action?["family"]?.string == "record.purge" ? .destructive : nil) {
                                            if action?["confirm"]?.bool == true {
                                                pendingRowAction = actionId
                                                pendingRowRecord = item
                                            } else {
                                                runtime.perform(actionId: actionId, record: item)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .accessibilityLabel("Record actions")
                                }
                                .accessibilityIdentifier("product-ui.record-actions.\(item.id)")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(palette.separator)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let bindingID = node["binding"]?.string,
               let binding = runtime.currentView?["bindings"]?.array?.first(where: { $0["id"]?.string == bindingID }),
               binding["source"]?.string == "record.query",
               let type = binding["recordType"]?.string {
                let state = binding["query"]?["recordState"]?.string ?? "active"
                let key = "\(type)|\(state)"
                if runtime.nextPageCursors[key] != nil {
                    Button("Load more") { runtime.requestedNextPage = key }
                        .disabled(runtime.loadingNextPage)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("product-ui.record-list.load-more")
                }
            }
        }
        .confirmationDialog("Confirm \(runtime.document.action(id: pendingRowAction ?? "")?["label"]?.string ?? "this action")?", isPresented: Binding(
            get: { pendingRowAction != nil },
            set: { if !$0 { pendingRowAction = nil; pendingRowRecord = nil } }
        )) {
            if let actionId = pendingRowAction, let row = pendingRowRecord {
                Button(runtime.document.action(id: actionId)?["label"]?.string ?? "Confirm", role: .destructive) {
                    runtime.perform(actionId: actionId, record: row)
                    pendingRowAction = nil
                    pendingRowRecord = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRowAction = nil
                pendingRowRecord = nil
            }
        }
    }

    private func recordCard(_ item: ProductUIRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol = recordSymbol {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(app.appearance.accent.color)
                    .frame(width: 26)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let template = node["children"]?.array?.first {
                    ProductUINode(node: template, runtime: runtime, provenance: provenance, record: item, compact: true)
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
            if node["action"]?.string != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var recordSymbol: String? {
        guard let bindingID = node["binding"]?.string,
              let binding = runtime.currentView?["bindings"]?.array?.first(where: { $0["id"]?.string == bindingID }) else { return nil }
        switch binding["recordType"]?.string {
        case "folder": return "folder"
        case "tag": return "number"
        default: return nil
        }
    }

    private func bindingDraft(_ id: String) -> Binding<String> {
        Binding(
            get: { runtime.drafts[id] ?? "" },
            set: { runtime.drafts[id] = $0 }
        )
    }

    private func unavailable(_ capability: String) -> some View {
        Label("This feature is unavailable on this device", systemImage: "exclamationmark.octagon")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("product-ui.unavailable.\(capability)")
    }

    private func fallback(for type: String, capability: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Limited view", systemImage: "square.dashed")
                .font(.subheadline.weight(.semibold))
            Text("Some controls are unavailable on this device.")
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
    static func formSubmitAction(in view: JSONValue?, document: ProductUIDocument) -> String? {
        guard let root = view?["root"] else { return nil }
        func find(_ node: JSONValue) -> String? {
            if let id = node["action"]?.string,
               let family = document.action(id: id)?["family"]?.string,
               family == "record.create" || family == "record.update" { return id }
            for child in node["children"]?.array ?? [] {
                if let id = find(child) { return id }
            }
            return nil
        }
        return find(root)
    }

    /// A short toolbar stays in the row. A long one scrolls so it cannot widen the screen.
    static func scrollsHorizontally(childCount: Int, declared: String?) -> Bool {
        declared == "horizontal" || childCount > 3
    }

    /// Contract notes are part of the frontend file. They stay available, quieter than the note.
    static func isQuietCopy(_ text: String) -> Bool {
        text.count > 90
    }

    /// Spec notes belong in the module contract, not on the note someone is reading.
    static func isContractCopy(_ text: String) -> Bool {
        let lower = text.lowercased()
        return isQuietCopy(text) || lower.contains("capability") || lower.contains("generic ") || lower.contains("ui.")
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

    static func preview(_ value: String, title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, value.hasPrefix(title) else { return value }
        let remainder = value.dropFirst(title.count)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return value }
        return String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
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
            Text("\(records.count) linked items")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(records.prefix(12)) { item in
                Text(item.value("title").isEmpty ? item.id : item.value("title"))
            }
        }
        .accessibilityIdentifier("product-ui.graph")
    }
}

private struct ProductUIFieldIdentifier: ViewModifier {
    let id: String
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.accessibilityIdentifier("product-ui.field.\(id)")
        } else {
            content
        }
    }
}
