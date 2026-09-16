import Foundation

enum DraftKind: String, Codable, Sendable, Hashable, CaseIterable {
    case post
    case inMail
    case story
}

protocol DraftRecord: Identifiable, Sendable {
    var id: String { get }
    var kind: DraftKind { get }
    var lastEdited: Date { get }
    var preview: String { get }
}

/// N4D-local post draft. Creation-domain fields (media/poll/audience) land in N4F.
struct PostDraft: Codable, Equatable, Hashable, DraftRecord {
    var id: String
    var kind: DraftKind { .post }
    var accountID: String?
    var text: String
    var mediaReferences: [String]
    var lastEdited: Date
    var originPath: String?

    init(
        id: String,
        accountID: String? = nil,
        text: String,
        mediaReferences: [String] = [],
        lastEdited: Date,
        originPath: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.text = text
        self.mediaReferences = mediaReferences
        self.lastEdited = lastEdited
        self.originPath = originPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        text = try c.decode(String.self, forKey: .text)
        mediaReferences = try c.decodeIfPresent([String].self, forKey: .mediaReferences) ?? []
        lastEdited = try c.decode(Date.self, forKey: .lastEdited)
        originPath = try c.decodeIfPresent(String.self, forKey: .originPath)
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return mediaReferences.isEmpty ? "Empty post draft" : "Media draft" }
        return String(trimmed.prefix(80))
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaReferences.isEmpty
    }
}

struct PersistedInMailDraft: Codable, Equatable, Hashable, DraftRecord {
    var id: String
    var kind: DraftKind { .inMail }
    var toHandle: String
    var subject: String
    var body: String
    var lastEdited: Date

    var preview: String {
        let subjectTrim = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subjectTrim.isEmpty { return String(subjectTrim.prefix(80)) }
        let bodyTrim = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return bodyTrim.isEmpty ? "Empty In-Mail draft" : String(bodyTrim.prefix(80))
    }

    var hasContent: Bool {
        !toHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func asComposerDraft() -> InMailDraft {
        InMailDraft(toHandle: toHandle, subject: subject, body: body)
    }
}

struct StoryDraft: Codable, Equatable, Hashable, DraftRecord {
    var id: String
    var kind: DraftKind { .story }
    /// Stable app-owned media identifiers only — never ephemeral picker URLs.
    var mediaAssetIDs: [String]
    var caption: String
    var lastEdited: Date

    var preview: String {
        let captionTrim = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !captionTrim.isEmpty { return String(captionTrim.prefix(80)) }
        return mediaAssetIDs.isEmpty ? "Empty story draft" : "Story media draft"
    }

    var hasContent: Bool {
        !mediaAssetIDs.isEmpty || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DraftIndex: Codable, Sendable, Equatable {
    var posts: [PostDraft]
    var inMails: [PersistedInMailDraft]
    var stories: [StoryDraft]
}

enum DraftBackendCapabilities: Sendable, Equatable {
    // Server drafts remain OPEN; local persistence is the N4D/N4F path.
}
