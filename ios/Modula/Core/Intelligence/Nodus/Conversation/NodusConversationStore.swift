import Foundation

private struct NodusConversationSnapshot: Sendable, Codable {
    var schemaVersion = 1
    var conversations: [NodusConversation] = []
}

actor NodusConversationStore {
    private let files: PrivateFileStore
    private let filename: String
    private let libraryFilename: String
    private var state: NodusConversationSnapshot
    private var library: NodusLibrarySnapshot

    init(
        files: PrivateFileStore = PrivateFileStore(domain: .nodusConversations),
        filename: String = "conversations.json",
        libraryFilename: String = "library.json"
    ) {
        self.files = files
        self.filename = filename
        self.libraryFilename = libraryFilename
        if let data = try? files.loadData(filename: filename),
           let decoded = try? Self.decoder.decode(NodusConversationSnapshot.self, from: data) {
            state = decoded
        } else {
            state = NodusConversationSnapshot()
        }
        if let data = try? files.loadData(filename: libraryFilename),
           let decoded = try? Self.decoder.decode(NodusLibrarySnapshot.self, from: data) {
            library = decoded
        } else {
            library = NodusLibrarySnapshot()
        }
    }

    func librarySnapshot() -> NodusLibrarySnapshot { library }

    func all() -> [NodusConversation] {
        state.conversations.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func conversation(id: UUID) -> NodusConversation? {
        state.conversations.first { $0.id == id }
    }

    @discardableResult
    func create(now: Date = Date()) throws -> NodusConversation {
        let conversation = NodusConversation(createdAt: now, updatedAt: now)
        state.conversations.append(conversation)
        try persist()
        return conversation
    }

    func upsert(_ conversation: NodusConversation) throws {
        if let index = state.conversations.firstIndex(where: { $0.id == conversation.id }) {
            state.conversations[index] = conversation
        } else {
            state.conversations.append(conversation)
        }
        try persist()
    }

    @discardableResult
    func append(_ message: NodusMessage, to conversationID: UUID, now: Date = Date()) throws -> NodusConversation? {
        guard let index = state.conversations.firstIndex(where: { $0.id == conversationID }) else { return nil }
        state.conversations[index].messages.append(message)
        state.conversations[index].updatedAt = now
        if message.role == .user,
           state.conversations[index].messages.filter({ $0.role == .user }).count == 1,
           state.conversations[index].title == "New Chat" {
            state.conversations[index].title = NodusConversation.fallbackTitle(for: message.text)
        }
        try persist()
        return state.conversations[index]
    }

    func rename(id: UUID, title: String, now: Date = Date()) throws {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        state.conversations[index].title = String(normalized.prefix(100))
        state.conversations[index].updatedAt = now
        try persist()
    }

    func clear(id: UUID, now: Date = Date()) throws {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[index].messages = []
        state.conversations[index].updatedAt = now
        try persist()
    }

    func delete(id: UUID) throws {
        state.conversations.removeAll { $0.id == id }
        library.placements.removeAll { $0.conversationID == id }
        try persist()
        try persistLibrary()
    }

    @discardableResult
    func createProject(name: String, symbol: String, brief: String = "", now: Date = Date()) throws -> NodusLibrarySnapshot {
        let clean = normalized(name, fallback: "Project")
        let project = NodusProject(name: clean, symbol: symbol, brief: brief, createdAt: now, updatedAt: now)
        library.projects.append(project)
        for folderName in ["Notes", "Research", "Drafts"] {
            library.folders.append(NodusFolder(name: folderName, projectID: project.id, createdAt: now, updatedAt: now))
        }
        try persistLibrary()
        return library
    }

    @discardableResult
    func updateProject(id: UUID, name: String, symbol: String, brief: String, now: Date = Date()) throws -> NodusLibrarySnapshot {
        guard let index = library.projects.firstIndex(where: { $0.id == id }) else { return library }
        library.projects[index].name = normalized(name, fallback: library.projects[index].name)
        library.projects[index].symbol = symbol
        library.projects[index].brief = String(brief.prefix(800))
        library.projects[index].updatedAt = now
        try persistLibrary()
        return library
    }

    @discardableResult
    func setProjectArchived(id: UUID, archived: Bool, now: Date = Date()) throws -> NodusLibrarySnapshot {
        guard let index = library.projects.firstIndex(where: { $0.id == id }) else { return library }
        library.projects[index].archived = archived
        library.projects[index].updatedAt = now
        try persistLibrary()
        return library
    }

    @discardableResult
    func deleteProject(id: UUID) throws -> NodusLibrarySnapshot {
        let folderIDs = Set(library.folders.filter { $0.projectID == id }.map(\.id))
        library.projects.removeAll { $0.id == id }
        library.folders.removeAll { $0.projectID == id }
        for index in library.placements.indices {
            if library.placements[index].projectID == id { library.placements[index].projectID = nil }
            if let folderID = library.placements[index].folderID, folderIDs.contains(folderID) {
                library.placements[index].folderID = nil
            }
        }
        try persistLibrary()
        return library
    }

    @discardableResult
    func createFolder(name: String, symbol: String = "folder", projectID: UUID?, now: Date = Date()) throws -> NodusLibrarySnapshot {
        let folder = NodusFolder(name: normalized(name, fallback: "Folder"), symbol: symbol, projectID: projectID, createdAt: now, updatedAt: now)
        library.folders.append(folder)
        try persistLibrary()
        return library
    }

    @discardableResult
    func renameFolder(id: UUID, name: String, now: Date = Date()) throws -> NodusLibrarySnapshot {
        guard let index = library.folders.firstIndex(where: { $0.id == id }) else { return library }
        library.folders[index].name = normalized(name, fallback: library.folders[index].name)
        library.folders[index].updatedAt = now
        try persistLibrary()
        return library
    }

    @discardableResult
    func deleteFolder(id: UUID) throws -> NodusLibrarySnapshot {
        library.folders.removeAll { $0.id == id }
        for index in library.placements.indices where library.placements[index].folderID == id {
            library.placements[index].folderID = nil
        }
        try persistLibrary()
        return library
    }

    @discardableResult
    func place(conversationID: UUID, projectID: UUID?, folderID: UUID?, now: Date = Date()) throws -> NodusLibrarySnapshot {
        var resolvedProject = projectID
        if let folderID, let folder = library.folder(id: folderID) {
            resolvedProject = folder.projectID
        }
        var placement = library.placement(for: conversationID) ?? NodusChatPlacement(conversationID: conversationID)
        placement.projectID = resolvedProject
        placement.folderID = folderID
        upsertPlacement(placement)
        if let resolvedProject, let projectIndex = library.projects.firstIndex(where: { $0.id == resolvedProject }) {
            library.projects[projectIndex].updatedAt = now
        }
        try persistLibrary()
        return library
    }

    @discardableResult
    func setChatArchived(id: UUID, archived: Bool) throws -> NodusLibrarySnapshot {
        var placement = library.placement(for: id) ?? NodusChatPlacement(conversationID: id)
        placement.archived = archived
        upsertPlacement(placement)
        try persistLibrary()
        return library
    }

    @discardableResult
    func setChatFavorite(id: UUID, favorite: Bool) throws -> NodusLibrarySnapshot {
        var placement = library.placement(for: id) ?? NodusChatPlacement(conversationID: id)
        placement.favorite = favorite
        upsertPlacement(placement)
        try persistLibrary()
        return library
    }

    @discardableResult
    func setChatFlags(id: UUID, important: Bool? = nil, color: String? = nil, instructions: String? = nil, forkedFrom: UUID? = nil, thinkSteps: Int? = nil, persona: String? = nil, skillIDs: String? = nil, messageDensity: String? = nil, showTimes: Bool? = nil, textSize: String? = nil, copy: NodusChatPlacement? = nil) throws -> NodusLibrarySnapshot {
        var placement = library.placement(for: id) ?? NodusChatPlacement(conversationID: id)
        if let copy {
            placement.projectID = copy.projectID
            placement.folderID = copy.folderID
            placement.color = copy.color
            placement.important = copy.important
            placement.instructions = copy.instructions
            placement.thinkSteps = copy.thinkSteps
            placement.persona = copy.persona
            placement.skillIDs = copy.skillIDs
            placement.messageDensity = copy.messageDensity
            placement.showTimes = copy.showTimes
            placement.textSize = copy.textSize
        }
        if let important { placement.important = important }
        if let color { placement.color = color }
        if let instructions { placement.instructions = String(instructions.prefix(800)) }
        if let forkedFrom { placement.forkedFrom = forkedFrom }
        if let thinkSteps { placement.thinkSteps = min(max(thinkSteps, 0), 5) }
        if let persona { placement.persona = String(persona.prefix(400)) }
        if let skillIDs { placement.skillIDs = String(skillIDs.prefix(200)) }
        if let messageDensity { placement.messageDensity = messageDensity == "compact" ? "compact" : "comfortable" }
        if let showTimes { placement.showTimes = showTimes }
        if let textSize {
            placement.textSize = ["small", "regular", "large"].contains(textSize) ? textSize : "regular"
        }
        upsertPlacement(placement)
        try persistLibrary()
        return library
    }

    @discardableResult
    func savePrompt(title: String, body: String, projectID: UUID?, id: UUID? = nil, now: Date = Date()) throws -> NodusLibrarySnapshot {
        let cleanTitle = normalized(title, fallback: "Prompt")
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty else { return library }
        if let id, let index = library.prompts.firstIndex(where: { $0.id == id }) {
            library.prompts[index].title = cleanTitle
            library.prompts[index].body = String(cleanBody.prefix(2_000))
            library.prompts[index].projectID = projectID
        } else {
            library.prompts.append(NodusPrompt(title: cleanTitle, body: String(cleanBody.prefix(2_000)), projectID: projectID, createdAt: now))
        }
        try persistLibrary()
        return library
    }

    @discardableResult
    func deletePrompt(id: UUID) throws -> NodusLibrarySnapshot {
        library.prompts.removeAll { $0.id == id }
        try persistLibrary()
        return library
    }

    @discardableResult
    func setChatNote(id: UUID, note: String) throws -> NodusLibrarySnapshot {
        var placement = library.placement(for: id) ?? NodusChatPlacement(conversationID: id)
        placement.note = String(note.prefix(280))
        upsertPlacement(placement)
        try persistLibrary()
        return library
    }

    func search(_ query: String) -> [NodusConversation] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return all() }
        return all().filter { conversation in
            let haystack = ([conversation.title] + conversation.messages.map(\.text)).joined(separator: " ").lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    private func upsertPlacement(_ placement: NodusChatPlacement) {
        if let index = library.placements.firstIndex(where: { $0.conversationID == placement.conversationID }) {
            library.placements[index] = placement
        } else {
            library.placements.append(placement)
        }
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = clean.isEmpty ? fallback : clean
        return String(chosen.prefix(48))
    }

    private func persist() throws {
        let encoder = Self.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try files.saveData(try encoder.encode(state), filename: filename)
    }

    private func persistLibrary() throws {
        let encoder = Self.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try files.saveData(try encoder.encode(library), filename: libraryFilename)
    }

    private static func terms(in value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}

