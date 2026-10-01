import SwiftUI

#if DEBUG
extension NodusChatTint {
    func color(accent: Color) -> Color {
        switch self {
        case .accent: accent
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .green: .green
        case .pink: .pink
        case .red: .red
        }
    }
}

enum NodusLibraryScope: String, CaseIterable, Identifiable {
    case all
    case important
    case favorites
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Chats"
        case .important: "Important"
        case .favorites: "Favorites"
        case .archived: "Archive"
        }
    }
}

struct NodusLibraryBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    @Bindable var model: NodusChatViewModel
    @State private var query = ""
    @State private var scope: NodusLibraryScope = .all
    @State private var selectedProjectID: UUID?
    @State private var selectedFolderID: UUID?
    @State private var naming: LibraryDraft?
    @State private var noteTarget: NodusConversation?
    @State private var noteText = ""
    @State private var moveTarget: NodusConversation?

    var body: some View {
        NavigationStack {
            List {
                newChatRow
                scopePicker
                projectsSection
                foldersSection
                chatsSection
            }
            .searchable(text: $query, prompt: "Search chats")
            .onChange(of: query) { _, value in Task { await model.searchConversations(value) } }
            .navigationTitle(selectedProject?.name ?? "Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("New Project", systemImage: "plus.rectangle.on.folder") { naming = .project }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $naming) { draft in
                NodusLibraryEditor(draft: draft) { name, symbol, brief in
                    Task { await save(draft, name: name, symbol: symbol, brief: brief) }
                }
            }
            .sheet(item: $moveTarget) { conversation in
                NodusMoveChatSheet(library: model.library, conversation: conversation) { projectID, folderID in
                    Task { await model.place(conversation.id, projectID: projectID, folderID: folderID) }
                }
            }
            .alert("Chat note", isPresented: notePresented) {
                TextField("Only on this iPhone", text: $noteText)
                Button("Cancel", role: .cancel) { noteTarget = nil }
                Button("Save") {
                    if let noteTarget {
                        Task { await model.setNote(noteTarget, note: noteText) }
                    }
                    noteTarget = nil
                }
            } message: {
                Text("This note stays on this iPhone and is not sent to Nodus.")
            }
            .accessibilityIdentifier("nodus.conversations")
        }
    }

    private var notePresented: Binding<Bool> {
        Binding(get: { noteTarget != nil }, set: { if !$0 { noteTarget = nil } })
    }

    private var selectedProject: NodusProject? {
        selectedProjectID.flatMap { model.library.project(id: $0) }
    }

    private var visibleFolders: [NodusFolder] {
        model.library.folders(in: selectedProjectID)
    }

    private var visibleChats: [NodusConversation] {
        model.conversations.filter { conversation in
            let placement = model.library.placement(for: conversation.id)
            let archived = placement?.archived == true
            switch scope {
            case .all where archived: return false
            case .archived where !archived: return false
            case .favorites where placement?.favorite != true || archived: return false
            case .important where placement?.important != true || archived: return false
            default: break
            }
            if let selectedProjectID, placement?.projectID != selectedProjectID { return false }
            if let selectedFolderID, placement?.folderID != selectedFolderID { return false }
            return true
        }
    }

    private var newChatRow: some View {
        Button {
            Task {
                await model.newConversation(projectID: selectedProjectID, folderID: selectedFolderID)
                dismiss()
            }
        } label: {
            Label(selectedFolderID == nil ? "New Chat" : "New Chat in Folder", systemImage: "plus.circle.fill")
        }
    }

    private var scopePicker: some View {
        Section {
            Picker("Library", selection: $scope) {
                ForEach(NodusLibraryScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            Text("Swipe sideways to move between Chats, Important, Favorites, and Archive.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .simultaneousGesture(librarySwipe)
    }

    private var librarySwipe: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                guard abs(value.translation.width) > 70, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                let cases = NodusLibraryScope.allCases
                guard let index = cases.firstIndex(of: scope) else { return }
                let next = value.translation.width < 0 ? index + 1 : index - 1
                guard cases.indices.contains(next) else { return }
                withAnimation(.spring(duration: 0.38, bounce: 0.18)) { scope = cases[next] }
            }
    }

    private var projectsSection: some View {
        Section("Projects") {
            Button {
                selectedProjectID = nil
                selectedFolderID = nil
            } label: {
                Label("All chats", systemImage: "tray")
            }
            if model.library.projects.isEmpty {
                Text("Projects keep a brief, folders, and the chats inside them on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.library.projects.filter { scope == .archived ? $0.archived : !$0.archived }) { project in
                Button {
                    selectedProjectID = project.id
                    selectedFolderID = nil
                } label: {
                    HStack {
                        Label(project.name, systemImage: project.symbol)
                        Spacer()
                        if selectedProjectID == project.id {
                            Image(systemName: "checkmark").foregroundStyle(app.appearance.accent.color)
                        }
                    }
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { naming = .editProject(project) }
                    Button(project.archived ? "Restore" : "Archive", systemImage: "archivebox") {
                        Task { await model.setProjectArchived(project, archived: !project.archived) }
                    }
                    Button("Delete Project", systemImage: "trash", role: .destructive) {
                        Task {
                            if selectedProjectID == project.id { selectedProjectID = nil; selectedFolderID = nil }
                            await model.deleteProject(project)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteProject(project) }
                    }
                    Button(project.archived ? "Restore" : "Archive", systemImage: "archivebox") {
                        Task { await model.setProjectArchived(project, archived: !project.archived) }
                    }
                    .tint(.indigo)
                }
            }
        }
    }

    private var foldersSection: some View {
        Section {
            if visibleFolders.isEmpty {
                Text("No folders here yet. A new project also creates Notes, Research, and Drafts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(visibleFolders) { folder in
                Button {
                    selectedFolderID = selectedFolderID == folder.id ? nil : folder.id
                } label: {
                    HStack {
                        Label(folder.name, systemImage: folder.symbol)
                        Spacer()
                        if selectedFolderID == folder.id {
                            Image(systemName: "checkmark").foregroundStyle(app.appearance.accent.color)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task {
                            if selectedFolderID == folder.id { selectedFolderID = nil }
                            await model.deleteFolder(folder)
                        }
                    }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { naming = .editFolder(folder) }
                    Button("Delete Folder", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteFolder(folder) }
                    }
                }
            }
        } header: {
            HStack {
                Text("Folders")
                Spacer()
                Button("Add", systemImage: "folder.badge.plus") { naming = .folder(projectID: selectedProjectID) }
                    .font(.caption.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("New folder")
            }
        }
    }

    private var chatsSection: some View {
        Section(scope.title) {
            if visibleChats.isEmpty {
                Text("No chats in this view.").foregroundStyle(.secondary)
            }
            ForEach(visibleChats) { conversation in
                chatRow(conversation)
            }
        }
    }

    private func chatRow(_ conversation: NodusConversation) -> some View {
        let placement = model.library.placement(for: conversation.id)
        return Button {
            model.select(conversation)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let tint = NodusChatTint(rawValue: placement?.color ?? ""), tint != .accent {
                        Circle().fill(tint.color(accent: app.appearance.accent.color)).frame(width: 8, height: 8)
                    }
                    if placement?.important == true {
                        Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    if placement?.favorite == true {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    Text(conversation.title).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(conversation.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                Text(conversation.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let note = placement?.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let project = model.library.project(for: conversation.id) {
                        Label(project.name, systemImage: project.symbol)
                    }
                    if let folder = model.library.folder(for: conversation.id) {
                        Label(folder.name, systemImage: "folder")
                    }
                    if conversation.pinned { Label("Pinned", systemImage: "pin") }
                    if placement?.forkedFrom != nil { Label("Fork", systemImage: "arrow.triangle.branch") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(placement?.important == true ? "Unmark" : "Important", systemImage: "flag") {
                Task { await model.setImportant(conversation, important: placement?.important != true) }
            }
            .tint(.red)
            Button(placement?.favorite == true ? "Unfavorite" : "Favorite", systemImage: "star") {
                Task { await model.setFavorite(conversation, favorite: placement?.favorite != true) }
            }
            .tint(.yellow)
            Button(conversation.pinned ? "Unpin" : "Pin", systemImage: conversation.pinned ? "pin.slash" : "pin") {
                Task { await model.setPinned(conversation, pinned: !conversation.pinned) }
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.delete(conversation) }
            }
            Button(placement?.archived == true ? "Restore" : "Archive", systemImage: "archivebox") {
                Task { await model.setArchived(conversation, archived: placement?.archived != true) }
            }
            .tint(.indigo)
        }
        .contextMenu {
            Menu("Organise", systemImage: "folder") {
                Button("Fork", systemImage: "arrow.triangle.branch") {
                    Task { await model.fork(conversation); dismiss() }
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    Task { await model.duplicate(conversation); dismiss() }
                }
                Button("Move", systemImage: "folder") { moveTarget = conversation }
                Button("Note", systemImage: "note.text") {
                    noteText = placement?.note ?? ""
                    noteTarget = conversation
                }
            }
            Menu("Marks", systemImage: "flag") {
                Button(placement?.important == true ? "Unmark Important" : "Mark Important", systemImage: "flag") {
                    Task { await model.setImportant(conversation, important: placement?.important != true) }
                }
                Button(placement?.favorite == true ? "Unfavorite" : "Favorite", systemImage: "star") {
                    Task { await model.setFavorite(conversation, favorite: placement?.favorite != true) }
                }
                Button(placement?.archived == true ? "Restore" : "Archive", systemImage: "archivebox") {
                    Task { await model.setArchived(conversation, archived: placement?.archived != true) }
                }
            }
            ShareLink(item: Self.transcript(conversation)) { Label("Export", systemImage: "square.and.arrow.up") }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.delete(conversation) }
            }
        }
    }

    private func save(_ draft: LibraryDraft, name: String, symbol: String, brief: String) async {
        switch draft {
        case .project:
            await model.createProject(name: name, symbol: symbol, brief: brief)
        case .editProject(let project):
            await model.updateProject(project, name: name, symbol: symbol, brief: brief)
        case .folder(let projectID):
            await model.createFolder(name: name, projectID: projectID)
        case .editFolder(let folder):
            await model.renameFolder(folder, name: name)
        }
    }

    private static func transcript(_ conversation: NodusConversation) -> String {
        let lines = conversation.messages.map { "\($0.role == .user ? "You" : "Nodus"): \($0.text)" }
        return ([conversation.title] + lines).joined(separator: "\n\n")
    }
}

private enum LibraryDraft: Identifiable {
    case project
    case editProject(NodusProject)
    case folder(projectID: UUID?)
    case editFolder(NodusFolder)

    var id: String {
        switch self {
        case .project: "new-project"
        case .editProject(let project): "project-\(project.id)"
        case .folder: "new-folder"
        case .editFolder(let folder): "folder-\(folder.id)"
        }
    }

    var title: String {
        switch self {
        case .project: "New Project"
        case .editProject: "Edit Project"
        case .folder: "New Folder"
        case .editFolder: "Rename Folder"
        }
    }

    var showsBrief: Bool {
        switch self {
        case .project, .editProject: true
        case .folder, .editFolder: false
        }
    }
}

private struct NodusLibraryEditor: View {
    let draft: LibraryDraft
    var onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "briefcase"
    @State private var brief = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if draft.showsBrief {
                    TextField("Instructions", text: $brief, axis: .vertical)
                        .lineLimit(3 ... 8)
                    Text("Instructions are included when Nodus answers chats in this project. They stay on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    symbolPicker
                }
            }
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, symbol, brief)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            switch draft {
            case .editProject(let project):
                name = project.name
                symbol = project.symbol
                brief = project.brief
            case .editFolder(let folder):
                name = folder.name
                symbol = folder.symbol
            case .folder:
                symbol = "folder"
            case .project:
                break
            }
        }
    }

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NodusLibrarySnapshot.symbols, id: \.self) { item in
                    Button {
                        symbol = item
                    } label: {
                        Image(systemName: item)
                            .frame(width: 36, height: 36)
                            .background(symbol == item ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                }
            }
        }
    }
}

struct NodusChatSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    @Bindable var model: NodusChatViewModel
    @State private var instructions = ""
    @State private var projectInstructions = ""
    @State private var promptTitle = ""
    @State private var promptBody = ""

    private var conversation: NodusConversation? { model.activeConversation }
    private var placement: NodusChatPlacement? {
        conversation.flatMap { model.library.placement(for: $0.id) }
    }
    private var project: NodusProject? {
        conversation.flatMap { model.library.project(for: $0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This chat") {
                    Toggle("Important", isOn: importantBinding)
                    Toggle("Pinned", isOn: pinnedBinding)
                    TextField("Instructions for this chat", text: $instructions, axis: .vertical)
                        .lineLimit(3 ... 8)
                    Button("Save instructions") {
                        guard let conversation else { return }
                        Task { await model.setInstructions(conversation, instructions: instructions) }
                    }
                    .disabled(conversation == nil)
                    Text("Instructions are sent with the question. Colour, spacing, and timestamps are in Customise.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let project {
                    Section("Project instructions") {
                        TextField(project.name, text: $projectInstructions, axis: .vertical)
                            .lineLimit(3 ... 8)
                        Button("Save project instructions") {
                            Task { await model.updateProject(project, name: project.name, symbol: project.symbol, brief: projectInstructions) }
                        }
                    }
                }
                Section("Reply budget") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.thinkStep.title).font(.body.weight(.semibold))
                            Text(model.thinkStep.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        NodusStudioGlyph(symbol: "brain", size: 32)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.thinkStep.rawValue) },
                            set: { value in Task { await model.setThinkSteps(Int(value.rounded())) } }
                        ),
                        in: 1...5,
                        step: 1
                    )
                    .tint(app.appearance.accent.color)
                    Text("Short, Standard, and Fuller are one draft. Review adds a revision. Deep adds a review and a final pass.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Modes") {
                    Toggle("Search", isOn: searchBinding)
                    Toggle("Memory", isOn: memoryBinding)
                    Text("The Think button on the composer turns Review and Deep on or off. The slider above sets the reply budget. Search sends only the query.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Saved prompts") {
                    let prompts = model.library.prompts(for: project?.id)
                    if prompts.isEmpty {
                        Text("Nothing saved yet. Add prompts from the Marketplace.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(prompts) { prompt in
                        Button {
                            let current = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
                            model.input = current.isEmpty ? prompt.body : current + "\n" + prompt.body
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prompt.title)
                                Text(prompt.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .onAppear {
                instructions = placement?.instructions ?? ""
                projectInstructions = project?.brief ?? ""
            }
            .accessibilityIdentifier("nodus.chat.settings.sheet")
        }
    }

    private var importantBinding: Binding<Bool> {
        Binding(
            get: { placement?.important == true },
            set: { value in
                guard let conversation else { return }
                Task { await model.setImportant(conversation, important: value) }
            }
        )
    }

    private var pinnedBinding: Binding<Bool> {
        Binding(
            get: { conversation?.pinned == true },
            set: { value in
                guard let conversation else { return }
                Task { await model.setPinned(conversation, pinned: value) }
            }
        )
    }

    private var searchBinding: Binding<Bool> {
        Binding(
            get: { conversation?.searchEnabled == true },
            set: { value in Task { await model.setSearchEnabled(value) } }
        )
    }

    private var memoryBinding: Binding<Bool> {
        Binding(
            get: { conversation?.memoryEnabled == true },
            set: { value in Task { await model.setMemoryEnabled(value) } }
        )
    }
}

private struct NodusMoveChatSheet: View {
    let library: NodusLibrarySnapshot
    let conversation: NodusConversation
    var onMove: (UUID?, UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button("No project or folder") {
                    onMove(nil, nil)
                    dismiss()
                }
                ForEach(library.projects.filter { !$0.archived }) { project in
                    Section(project.name) {
                        Button("Project only") {
                            onMove(project.id, nil)
                            dismiss()
                        }
                        ForEach(library.folders(in: project.id)) { folder in
                            Button(folder.name, systemImage: "folder") {
                                onMove(project.id, folder.id)
                                dismiss()
                            }
                        }
                    }
                }
                let loose = library.folders(in: nil)
                if !loose.isEmpty {
                    Section("Folders") {
                        ForEach(loose) { folder in
                            Button(folder.name, systemImage: "folder") {
                                onMove(nil, folder.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \(conversation.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
#endif
