import SwiftUI

/// In-app module authoring. Files are real Product UI artifacts installed by the same ModuleHost.
struct DeveloperStudioView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var projects: [DeveloperModuleDraft] = []
    @State private var draft = DeveloperModuleDraft.new(name: "Tasks", template: "records")
    @State private var editing = false
    @State private var issues: [String] = []
    @State private var status = ""
    @State private var showPreview = false
    @State private var previewDocument: ProductUIDocument?
    @State private var newParagraph = ""
    @State private var newFieldLabel = ""

    var body: some View {
        Form {
            if editing {
                editor
            } else {
                gallery
                creator
            }
        }
        .navigationTitle(editing ? draft.name : "Developer")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if editing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Projects") { editing = false; reload() }
                }
            }
        }
        .onAppear { reload() }
        .accessibilityIdentifier("developer.studio")
    }

    private var gallery: some View {
        Section("Projects") {
            if projects.isEmpty {
                Text("No modules yet. Generate one below. It installs into this app without another Xcode build.")
                    .foregroundStyle(.secondary)
            }
            ForEach(projects) { project in
                Button {
                    draft = project
                    editing = true
                    refreshPreview()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.headline)
                        Text("\(project.moduleId) · \(project.template) · \(project.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("developer.project.\(project.moduleId)")
            }
        }
    }

    private var creator: some View {
        Section("Create module") {
            TextField("Name", text: $draft.name)
                .onChange(of: draft.name) { _, name in
                    draft.moduleId = DeveloperModuleDraft.suggestedModuleID(name: name)
                    draft.homeTitle = name
                    draft.intro = "Welcome to \(name)"
                }
            TextField("Module ID", text: $draft.moduleId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Template", selection: $draft.template) {
                ForEach(DeveloperModuleDraft.templates, id: \.self) { template in
                    Text(template).tag(template)
                }
            }
            TextField("Description", text: $draft.summary, axis: .vertical)
            TextField("Version", text: $draft.version)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Generate module") { generate(install: false) }
                .accessibilityIdentifier("developer.studio.generate")
            if !issues.isEmpty { issueList }
        }
    }

    private var editor: some View {
        Group {
            Section("Module") {
                LabeledContent("ID", value: draft.moduleId)
                LabeledContent("Template", value: draft.template)
                LabeledContent("Version", value: draft.version)
                TextField("Home title", text: $draft.homeTitle)
                TextField("Introduction", text: $draft.intro, axis: .vertical)
                TextField("Description", text: $draft.summary, axis: .vertical)
                TextField("Primary action", text: $draft.primaryAction)
            }
            Section("Copy") {
                ForEach(draft.paragraphs.indices, id: \.self) { index in
                    TextField("Paragraph", text: $draft.paragraphs[index], axis: .vertical)
                }
                .onDelete { draft.paragraphs.remove(atOffsets: $0) }
                TextField("Add a paragraph", text: $newParagraph)
                Button("Add paragraph") {
                    let text = newParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft.paragraphs.append(text)
                    newParagraph = ""
                }
            }
            if ModuleProjectGenerator.usesRecords(draft) {
                Section("Record fields") {
                    ForEach($draft.fields) { $field in
                        TextField("Label", text: $field.label)
                    }
                    .onDelete { draft.fields.remove(atOffsets: $0) }
                    TextField("New field label", text: $newFieldLabel)
                    Button("Add field") { addField() }
                }
            }
            Section("Permissions") {
                ForEach(ModuleProjectGenerator.permissions(draft), id: \.id) { permission in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(permission.id).font(.subheadline.weight(.semibold))
                        Text(permission.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("settings:register does not grant settings:read or settings:write.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Release") {
                Button("Save and validate") { generate(install: false) }
                    .accessibilityIdentifier("developer.studio.validate")
                Button("Install in this app") { generate(install: true) }
                    .accessibilityIdentifier("developer.studio.install")
                Button("Publish update") { publishUpdate() }
                    .accessibilityIdentifier("developer.studio.update")
                Button("Roll back") { rollback() }
                    .accessibilityIdentifier("developer.studio.rollback")
                Button(showPreview ? "Hide native preview" : "Preview on this device") { showPreview.toggle(); refreshPreview() }
                    .accessibilityIdentifier("developer.studio.preview")
                if !status.isEmpty {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                if !issues.isEmpty { issueList }
            }
            if showPreview, let previewDocument {
                Section("Native preview") {
                    Text("This is the actual Product UI renderer, not the web Studio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProductUIHostView(session: previewSession(previewDocument), document: previewDocument)
                        .frame(minHeight: 420)
                        .accessibilityIdentifier("developer.studio.native-preview")
                }
            }
        }
    }

    private var issueList: some View {
        ForEach(issues, id: \.self) { issue in
            Text(issue).font(.caption).foregroundStyle(.red)
        }
    }

    private func reload() {
        projects = DeveloperModuleStore.list()
    }

    private func addField() {
        let label = newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let id = label.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !id.isEmpty else { return }
        draft.fields.append(DeveloperField(id: id, label: label, kind: "string"))
        newFieldLabel = ""
    }

    private func generate(install: Bool) {
        do {
            let generated = try DeveloperModuleStore.save(draft)
            issues = []
            status = "Saved \(draft.moduleId)@\(draft.version) \(generated.frontendSha256.prefix(12))"
            refreshPreview()
            reload()
            if install { Task { await installCurrent() } }
        } catch {
            issues = [error.localizedDescription]
            status = ""
        }
    }

    private func publishUpdate() {
        draft.version = draft.bumpedVersion()
        draft.paragraphs.append("Updated to \(draft.version) without rebuilding Modula.")
        generate(install: true)
    }

    private func installCurrent() async {
        let account = app.auth.account?.accountId ?? app.runtime.accountID ?? "local-dev"
        app.runtime.setAccount(account)
        app.catalogue.accountID = account
        app.catalogue.localDevRoots = [DeveloperModuleStore.devRoot()]
        app.catalogue.mergeLocalDevModules()
        let permissions = ModuleProjectGenerator.permissions(draft).map(\.id)
        let installed = await app.catalogue.installLocalDevelopment(draft.moduleId, permissions: permissions, version: draft.version)
        if installed == true {
            status = "Installed \(draft.version). Open it from Product Hub or the button below."
            app.navigation.open(.module(draft.moduleId, localPath: nil))
        } else {
            issues = [app.catalogue.lifecycleErrors[draft.moduleId] ?? "Install did not activate."]
        }
    }

    private func rollback() {
        let account = app.auth.account?.accountId ?? app.catalogue.accountID ?? "local-dev"
        do {
            let restored = try app.catalogue.activation?.rollback(accountID: account, moduleId: draft.moduleId, reason: "developer-studio")
            status = restored.map { "Restored \($0.version)" } ?? "No previous good release."
        } catch {
            issues = [error.localizedDescription]
        }
    }

    private func refreshPreview() {
        let generated = ModuleProjectGenerator.generate(draft)
        guard generated.issues.isEmpty,
              let document = try? ProductUIDocument.parse(data: generated.frontend, productId: draft.moduleId, version: draft.version) else {
            previewDocument = nil
            return
        }
        previewDocument = document
    }

    private func previewSession(_ document: ProductUIDocument) -> ModuleSession {
        let manifest = ModuleManifest(
            id: draft.moduleId, name: draft.name, version: draft.version, runtime: "declarative",
            entry: "product-ui", permissions: ModuleProjectGenerator.permissions(draft).map(\.id),
            minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: [ModuleProjectGenerator.recordType(draft)]
        )
        let session = ModuleSession(
            manifest: manifest,
            environment: ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)
        )
        session.runtimeKind = .declarativeProductUI
        session.state = .ready
        session.productUI = document
        return session
    }
}
