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

struct PostDraft: Codable, Equatable, Hashable, DraftRecord {
    var id: String
    var kind: DraftKind { .post }
    var accountID: String?
    var creationKind: String
    var text: String
    var mediaReferences: [String]
    var media: [CreationMedia]
    var linkURL: String?
    var linkTitle: String?
    var linkDescription: String?
    var poll: PollDraft?
    var audience: String
    var mentions: [MentionDraft]
    var topics: [String]
    var altTextByMediaID: [String: String]
    var lastEdited: Date
    var state: String
    var idempotencyKey: String
    var originPath: String?

    init(
        id: String,
        accountID: String? = nil,
        creationKind: String = CreationKind.post.rawValue,
        text: String,
        mediaReferences: [String],
        media: [CreationMedia] = [],
        linkURL: String? = nil,
        linkTitle: String? = nil,
        linkDescription: String? = nil,
        poll: PollDraft? = nil,
        audience: String = AudienceSelection.everyone.rawValue,
        mentions: [MentionDraft] = [],
        topics: [String] = [],
        altTextByMediaID: [String: String] = [:],
        lastEdited: Date,
        state: String = CreationState.editing.rawValue,
        idempotencyKey: String = UUID().uuidString,
        originPath: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.creationKind = creationKind
        self.text = text
        self.mediaReferences = mediaReferences
        self.media = media
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.linkDescription = linkDescription
        self.poll = poll
        self.audience = audience
        self.mentions = mentions
        self.topics = topics
        self.altTextByMediaID = altTextByMediaID
        self.lastEdited = lastEdited
        self.state = state
        self.idempotencyKey = idempotencyKey
        self.originPath = originPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        creationKind = try c.decodeIfPresent(String.self, forKey: .creationKind) ?? CreationKind.post.rawValue
        text = try c.decode(String.self, forKey: .text)
        mediaReferences = try c.decodeIfPresent([String].self, forKey: .mediaReferences) ?? []
        media = try c.decodeIfPresent([CreationMedia].self, forKey: .media) ?? []
        linkURL = try c.decodeIfPresent(String.self, forKey: .linkURL)
        linkTitle = try c.decodeIfPresent(String.self, forKey: .linkTitle)
        linkDescription = try c.decodeIfPresent(String.self, forKey: .linkDescription)
        poll = try c.decodeIfPresent(PollDraft.self, forKey: .poll)
        audience = try c.decodeIfPresent(String.self, forKey: .audience) ?? AudienceSelection.everyone.rawValue
        mentions = try c.decodeIfPresent([MentionDraft].self, forKey: .mentions) ?? []
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        altTextByMediaID = try c.decodeIfPresent([String: String].self, forKey: .altTextByMediaID) ?? [:]
        lastEdited = try c.decode(Date.self, forKey: .lastEdited)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? CreationState.editing.rawValue
        idempotencyKey = try c.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? UUID().uuidString
        originPath = try c.decodeIfPresent(String.self, forKey: .originPath)
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return mediaReferences.isEmpty && media.isEmpty ? "Empty post draft" : "Media draft" }
        return String(trimmed.prefix(80))
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaReferences.isEmpty
            || !media.isEmpty
            || !(linkURL?.isEmpty ?? true)
            || !(poll?.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func asCreationDraft(fallbackAccount: String) -> CreationDraft {
        var accessibility = MediaAccessibilityMetadata.empty
        accessibility.altTextByMediaID = altTextByMediaID
        for item in media where item.hasAltText {
            accessibility.altTextByMediaID[item.id] = item.altText
        }
        let link: LinkDraft? = {
            guard let linkURL, !linkURL.isEmpty else { return nil }
            return LinkDraft(
                urlString: linkURL,
                title: linkTitle,
                description: linkDescription,
                domain: URL(string: linkURL)?.host,
                imageURLString: nil,
                previewFromServer: false
            )
        }()
        return CreationDraft(
            id: id,
            accountID: accountID ?? fallbackAccount,
            kind: CreationKind(rawValue: creationKind) ?? .post,
            text: text,
            media: media,
            link: link,
            poll: poll,
            audience: AudienceSelection(greenfield: audience),
            mentions: mentions,
            topics: topics,
            location: nil,
            accessibility: accessibility,
            state: CreationState(rawValue: state) ?? .editing,
            lastEdited: lastEdited,
            idempotencyKey: idempotencyKey,
            publishError: nil,
            originPath: originPath
        )
    }

    init(_ draft: CreationDraft) {
        self.init(
            id: draft.id,
            accountID: draft.accountID,
            creationKind: draft.kind.rawValue,
            text: draft.text,
            mediaReferences: draft.media.map(\.id),
            media: draft.media,
            linkURL: draft.link?.urlString,
            linkTitle: draft.link?.title,
            linkDescription: draft.link?.description,
            poll: draft.poll,
            audience: draft.audience.greenfieldValue,
            mentions: draft.mentions,
            topics: draft.topics,
            altTextByMediaID: draft.accessibility.altTextByMediaID,
            lastEdited: draft.lastEdited,
            state: draft.state.rawValue,
            idempotencyKey: draft.idempotencyKey,
            originPath: draft.originPath
        )
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
    var media: CreationMedia? = nil
    var visibility: String? = nil

    var preview: String {
        let captionTrim = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !captionTrim.isEmpty { return String(captionTrim.prefix(80)) }
        return mediaAssetIDs.isEmpty ? "Empty story draft" : "Story media draft"
    }

    var hasContent: Bool {
        media != nil || !mediaAssetIDs.isEmpty || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
