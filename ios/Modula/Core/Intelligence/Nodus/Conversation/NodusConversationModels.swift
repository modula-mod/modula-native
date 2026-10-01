import Foundation

enum NodusReasoningMode: String, Sendable, Codable, CaseIterable {
    case standard
    case deep

    var displayName: String { self == .deep ? "Think" : "Standard" }
}

enum NodusMessageRole: String, Sendable, Codable {
    case user
    case nodus
}

enum NodusCitationKind: String, Sendable, Codable {
    case knowledge
    case web
}

struct NodusCitation: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let kind: NodusCitationKind
    let title: String
    let sourceName: String
    let collectionName: String?
    let location: String?
    let url: URL?
    let retrievedAt: Date?
    let excerpt: String?

    init(
        id: UUID = UUID(),
        kind: NodusCitationKind,
        title: String,
        sourceName: String,
        collectionName: String? = nil,
        location: String? = nil,
        url: URL? = nil,
        retrievedAt: Date? = nil,
        excerpt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceName = sourceName
        self.collectionName = collectionName
        self.location = location
        self.url = url
        self.retrievedAt = retrievedAt
        self.excerpt = excerpt
    }
}

struct NodusResponseDetails: Sendable, Codable, Equatable {
    let reasoningMode: NodusReasoningMode
    let searchEnabled: Bool
    let searchedWeb: Bool
    let knowledgeChunkCount: Int
    let memoryItemIDs: [UUID]
    let searchResultCount: Int
    let generationDuration: Double?
    let retrievalDuration: Double?
    let searchDuration: Double?
    let inferencePasses: Int
}

struct NodusMessage: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let role: NodusMessageRole
    let text: String
    let createdAt: Date
    let answer: NodusAnswer?
    let requestID: UUID?
    let citations: [NodusCitation]
    let details: NodusResponseDetails?

    init(
        id: UUID = UUID(),
        role: NodusMessageRole,
        text: String,
        createdAt: Date = Date(),
        answer: NodusAnswer? = nil,
        requestID: UUID? = nil,
        citations: [NodusCitation] = [],
        details: NodusResponseDetails? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.answer = answer
        self.requestID = requestID
        self.citations = citations
        self.details = details
    }
}

struct NodusConversation: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    let modelID: String
    let modelStage: NodusModelStage
    var reasoningMode: NodusReasoningMode
    var searchEnabled: Bool
    var attachedKnowledgeCollectionIDs: Set<UUID>
    var memoryEnabled: Bool
    var pinned: Bool
    var messages: [NodusMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelID: String = "nodus-r7-experimental",
        modelStage: NodusModelStage = .experimentalCandidate,
        reasoningMode: NodusReasoningMode = .standard,
        searchEnabled: Bool = false,
        attachedKnowledgeCollectionIDs: Set<UUID> = [],
        memoryEnabled: Bool = true,
        pinned: Bool = false,
        messages: [NodusMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
        self.modelStage = modelStage
        self.reasoningMode = reasoningMode
        self.searchEnabled = searchEnabled
        self.attachedKnowledgeCollectionIDs = attachedKnowledgeCollectionIDs
        self.memoryEnabled = memoryEnabled
        self.pinned = pinned
        self.messages = messages
    }

    var preview: String {
        messages.last?.text.replacingOccurrences(of: "\n", with: " ") ?? "No messages yet"
    }

    static func fallbackTitle(for firstUserMessage: String) -> String {
        let singleLine = firstUserMessage
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "New Chat" }
        let limit = 52
        if singleLine.count <= limit { return singleLine }
        return String(singleLine.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

struct NodusProject: Identifiable, Sendable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var brief: String
    var createdAt: Date
    var updatedAt: Date
    var archived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "briefcase",
        brief: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.brief = brief
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }
}

struct NodusFolder: Identifiable, Sendable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var projectID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "folder",
        projectID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.projectID = projectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct NodusChatPlacement: Sendable, Codable, Equatable {
    var conversationID: UUID
    var projectID: UUID?
    var folderID: UUID?
    var archived: Bool
    var favorite: Bool
    var important: Bool
    var note: String
    var instructions: String
    var color: String
    var forkedFrom: UUID?
    var thinkSteps: Int
    var persona: String
    var skillIDs: String
    var messageDensity: String
    var showTimes: Bool
    var textSize: String

    init(
        conversationID: UUID,
        projectID: UUID? = nil,
        folderID: UUID? = nil,
        archived: Bool = false,
        favorite: Bool = false,
        important: Bool = false,
        note: String = "",
        instructions: String = "",
        color: String = "",
        forkedFrom: UUID? = nil,
        thinkSteps: Int = 0,
        persona: String = "",
        skillIDs: String = "",
        messageDensity: String = "comfortable",
        showTimes: Bool = false,
        textSize: String = "regular"
    ) {
        self.conversationID = conversationID
        self.projectID = projectID
        self.folderID = folderID
        self.archived = archived
        self.favorite = favorite
        self.important = important
        self.note = note
        self.instructions = instructions
        self.color = color
        self.forkedFrom = forkedFrom
        self.thinkSteps = thinkSteps
        self.persona = persona
        self.skillIDs = skillIDs
        self.messageDensity = messageDensity
        self.showTimes = showTimes
        self.textSize = textSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        important = try container.decodeIfPresent(Bool.self, forKey: .important) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? ""
        forkedFrom = try container.decodeIfPresent(UUID.self, forKey: .forkedFrom)
        thinkSteps = try container.decodeIfPresent(Int.self, forKey: .thinkSteps) ?? 0
        persona = try container.decodeIfPresent(String.self, forKey: .persona) ?? ""
        skillIDs = try container.decodeIfPresent(String.self, forKey: .skillIDs) ?? ""
        messageDensity = try container.decodeIfPresent(String.self, forKey: .messageDensity) ?? "comfortable"
        showTimes = try container.decodeIfPresent(Bool.self, forKey: .showTimes) ?? false
        textSize = try container.decodeIfPresent(String.self, forKey: .textSize) ?? "regular"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(archived, forKey: .archived)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(important, forKey: .important)
        try container.encode(note, forKey: .note)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(forkedFrom, forKey: .forkedFrom)
        try container.encode(thinkSteps, forKey: .thinkSteps)
        try container.encode(persona, forKey: .persona)
        try container.encode(skillIDs, forKey: .skillIDs)
        try container.encode(messageDensity, forKey: .messageDensity)
        try container.encode(showTimes, forKey: .showTimes)
        try container.encode(textSize, forKey: .textSize)
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID, projectID, folderID, archived, favorite, important, note, instructions, color, forkedFrom, thinkSteps, persona, skillIDs, messageDensity, showTimes, textSize
    }
}

struct NodusPrompt: Identifiable, Sendable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var symbol: String
    var projectID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        symbol: String = "text.quote",
        projectID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.symbol = symbol
        self.projectID = projectID
        self.createdAt = createdAt
    }
}

enum NodusChatTint: String, CaseIterable, Identifiable {
    case accent
    case blue
    case purple
    case orange
    case green
    case pink
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent: "Teal"
        case .blue: "Blue"
        case .purple: "Purple"
        case .orange: "Orange"
        case .green: "Green"
        case .pink: "Pink"
        case .red: "Red"
        }
    }
}

enum NodusSkill: String, CaseIterable, Identifiable, Sendable {
    case concise
    case lists
    case questions
    case sources
    case uncertainty
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise: "Concise"
        case .lists: "Lists"
        case .questions: "One question"
        case .sources: "Name sources"
        case .uncertainty: "Mark uncertainty"
        case .local: "Stay local"
        }
    }

    var symbol: String {
        switch self {
        case .concise: "text.alignleft"
        case .lists: "list.bullet"
        case .questions: "questionmark.bubble"
        case .sources: "quote.opening"
        case .uncertainty: "exclamationmark.circle"
        case .local: "iphone"
        }
    }

    var instruction: String {
        switch self {
        case .concise: "Prefer a short answer."
        case .lists: "Use a list when there are several parts."
        case .questions: "If something important is missing, ask one question."
        case .sources: "When Knowledge or Search is used, name the source."
        case .uncertainty: "Say when a claim is not supported by this chat."
        case .local: "Do not suggest uploading this chat."
        }
    }

    static func enabled(in stored: String) -> [NodusSkill] {
        let ids = Set(stored.split(separator: ",").map(String.init))
        return allCases.filter { ids.contains($0.rawValue) }
    }

    static func stored(from skills: [NodusSkill]) -> String {
        skills.map(\.rawValue).joined(separator: ",")
    }
}

enum NodusPersonaPreset: String, CaseIterable, Identifiable, Sendable {
    case plain
    case brief
    case careful
    case teacher
    case editor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .brief: "Brief"
        case .careful: "Careful"
        case .teacher: "Teacher"
        case .editor: "Editor"
        }
    }

    var symbol: String {
        switch self {
        case .plain: "circle"
        case .brief: "text.alignleft"
        case .careful: "checkmark.shield"
        case .teacher: "graduationcap"
        case .editor: "pencil.line"
        }
    }

    var instruction: String {
        switch self {
        case .plain: ""
        case .brief: "Answer in a few short sentences."
        case .careful: "Say when you are unsure. Do not invent facts."
        case .teacher: "Explain in plain steps, and define words that might be unfamiliar."
        case .editor: "Improve the writing. Do not add facts that were not given."
        }
    }
}

struct NodusLibrarySnapshot: Sendable, Codable, Equatable {
    var schemaVersion = 1
    var projects: [NodusProject] = []
    var folders: [NodusFolder] = []
    var placements: [NodusChatPlacement] = []
    var prompts: [NodusPrompt] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projects = try container.decodeIfPresent([NodusProject].self, forKey: .projects) ?? []
        folders = try container.decodeIfPresent([NodusFolder].self, forKey: .folders) ?? []
        placements = try container.decodeIfPresent([NodusChatPlacement].self, forKey: .placements) ?? []
        prompts = try container.decodeIfPresent([NodusPrompt].self, forKey: .prompts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(projects, forKey: .projects)
        try container.encode(folders, forKey: .folders)
        try container.encode(placements, forKey: .placements)
        try container.encode(prompts, forKey: .prompts)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, folders, placements, prompts
    }

    func placement(for conversationID: UUID) -> NodusChatPlacement? {
        placements.first { $0.conversationID == conversationID }
    }

    func project(id: UUID) -> NodusProject? {
        projects.first { $0.id == id }
    }

    func folder(id: UUID) -> NodusFolder? {
        folders.first { $0.id == id }
    }

    func project(for conversationID: UUID) -> NodusProject? {
        guard let projectID = placement(for: conversationID)?.projectID else { return nil }
        return project(id: projectID)
    }

    func folder(for conversationID: UUID) -> NodusFolder? {
        guard let folderID = placement(for: conversationID)?.folderID else { return nil }
        return folder(id: folderID)
    }

    func projectBrief(for conversationID: UUID) -> String? {
        guard let project = project(for: conversationID), !project.archived else { return nil }
        let brief = project.brief.trimmingCharacters(in: .whitespacesAndNewlines)
        return brief.isEmpty ? nil : brief
    }

    func instructions(for conversationID: UUID) -> String? {
        var parts: [String] = []
        if let brief = projectBrief(for: conversationID) {
            parts.append("Project instructions:\n\(brief)")
        }
        let placement = placement(for: conversationID)
        let chat = placement?.instructions.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !chat.isEmpty {
            parts.append("Chat instructions:\n\(chat)")
        }
        let persona = placement?.persona.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !persona.isEmpty {
            parts.append("Persona, written for this chat on this iPhone:\n\(persona)")
        }
        let skills = NodusSkill.enabled(in: placement?.skillIDs ?? "")
        if !skills.isEmpty {
            let lines = skills.map { "- \($0.title): \($0.instruction)" }.joined(separator: "\n")
            parts.append("Skills turned on for this chat:\n\(lines)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func prompts(for projectID: UUID?) -> [NodusPrompt] {
        prompts.filter { $0.projectID == nil || $0.projectID == projectID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func folders(in projectID: UUID?) -> [NodusFolder] {
        folders.filter { $0.projectID == projectID }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static let symbols = ["briefcase", "folder", "book.closed", "hammer", "leaf", "star", "lightbulb", "shippingbox", "person.2", "tray.full"]
}
