import Foundation
import Observation

/// Private local drafts. Diagnostics may log counts and kind — never bodies.
@MainActor @Observable
final class DraftStore {
    private let fileStore: PrivateFileStore
    private let mediaStore: DraftMediaStore
    private let defaults: UserDefaults
    private var autosaveTasks: [String: Task<Void, Never>] = [:]
    private var pendingWrites: [String: @MainActor () -> Void] = [:]
    private var pendingPosts: [String: PostDraft] = [:]
    private let autosaveNanoseconds: UInt64

    private(set) var accountID: String?
    private(set) var posts: [PostDraft] = []
    private(set) var inMails: [PersistedInMailDraft] = []
    private(set) var stories: [StoryDraft] = []
    private(set) var lastSavedAt: Date?
    /// Subtle composer indicator — not a giant banner.
    private(set) var showSavedIndicator = false
    private(set) var saveError: String?
    /// Set by Drafts library before opening Creation Studio.
    var pendingResumeID: String?

    init(
        fileStore: PrivateFileStore = PrivateFileStore(domain: .drafts),
        mediaStore: DraftMediaStore = DraftMediaStore(),
        autosaveMilliseconds: UInt64 = 600,
        defaults: UserDefaults = .standard
    ) {
        self.fileStore = fileStore
        self.mediaStore = mediaStore
        self.autosaveNanoseconds = autosaveMilliseconds * 1_000_000
        self.defaults = defaults
        load()
    }

    var allPreviews: [(id: String, kind: DraftKind, preview: String, lastEdited: Date)] {
        let mapped =
            posts.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
            + inMails.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
            + stories.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
        return mapped.sorted { $0.3 > $1.3 }
    }

    var countsByKind: [DraftKind: Int] {
        [.post: posts.count, .inMail: inMails.count, .story: stories.count]
    }

    var draftMediaBytes: Int64 {
        mediaStore.byteCount(accountID: accountID)
    }

    func setAccountID(_ id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard accountID != next else { return }
        flush()
        accountID = next
        load()
    }

    func lastAudience() -> AudienceSelection {
        guard let accountID, let raw = defaults.string(forKey: Self.audienceKey(accountID)) else {
            return .everyone
        }
        return AudienceSelection(greenfield: raw)
    }

    func rememberAudience(_ audience: AudienceSelection) {
        guard let accountID else { return }
        defaults.set(audience.greenfieldValue, forKey: Self.audienceKey(accountID))
    }

    // MARK: - Post / Creation

    func upsertPost(_ draft: PostDraft, debounce: Bool = true) {
        var scoped = draft
        scoped.accountID = scoped.accountID ?? accountID
        guard scoped.hasContent else { return }
        pendingPosts[scoped.id] = scoped
        schedule(id: scoped.id, debounce: debounce) { [weak self] in
            self?.writePost(scoped)
            self?.pendingPosts[scoped.id] = nil
        }
    }

    func upsertCreation(_ draft: CreationDraft, debounce: Bool = true) {
        guard draft.state != .published, draft.state != .discarded else { return }
        upsertPost(PostDraft(draft), debounce: debounce)
    }

    func postDraft(id: String = "post-primary") -> PostDraft? {
        pendingPosts[id] ?? posts.first { $0.id == id }
    }

    func latestPostDraft() -> PostDraft? {
        if let pending = pendingPosts.values.max(by: { $0.lastEdited < $1.lastEdited }) { return pending }
        return posts.max(by: { $0.lastEdited < $1.lastEdited })
    }

    func creationDraft(id: String) -> CreationDraft? {
        postDraft(id: id)?.asCreationDraft(fallbackAccount: accountID ?? "")
    }

    func discardPost(id: String = "post-primary") {
        cancelPending(id: id)
        let existing = posts.first { $0.id == id } ?? pendingPosts[id]
        posts.removeAll { $0.id == id }
        pendingPosts[id] = nil
        guard persist() else {
            if let existing { posts.append(existing) }
            return
        }
        if let existing {
            mediaStore.remove(ids: existing.media.map(\.id) + existing.mediaReferences, from: existing.media)
        }
        cleanupMedia()
        ModulaLog.app.info("draft.discard kind=post count=\(self.posts.count, privacy: .public)")
    }

    func markPublished(id: String) {
        discardPost(id: id)
    }

    // MARK: - In-Mail

    func upsertInMail(_ draft: InMailDraft, id: String = "inmail-primary", debounce: Bool = true) {
        let record = PersistedInMailDraft(
            id: id,
            toHandle: draft.toHandle,
            subject: draft.subject,
            body: draft.body,
            lastEdited: Date()
        )
        guard record.hasContent else { return }
        schedule(id: id, debounce: debounce) { [weak self] in
            self?.writeInMail(record)
        }
    }

    func inMailDraft(id: String = "inmail-primary") -> PersistedInMailDraft? {
        inMails.first { $0.id == id }
    }

    func discardInMail(id: String = "inmail-primary") {
        cancelPending(id: id)
        let previous = inMails
        inMails.removeAll { $0.id == id }
        guard persist() else { inMails = previous; return }
        ModulaLog.app.info("draft.discard kind=inMail count=\(self.inMails.count, privacy: .public)")
    }

    // MARK: - Story

    func upsertStory(_ draft: StoryDraft, debounce: Bool = true) {
        guard draft.hasContent else { return }
        // Reject ephemeral file URLs.
        var safe = draft
        safe.mediaAssetIDs = draft.mediaAssetIDs.filter { !$0.hasPrefix("file:") && !$0.hasPrefix("/") }
        schedule(id: draft.id, debounce: debounce) { [weak self] in
            self?.writeStory(safe)
        }
    }

    func discardStory(id: String) {
        cancelPending(id: id)
        let previous = stories
        stories.removeAll { $0.id == id }
        guard persist() else { stories = previous; return }
        if let media = previous.first(where: { $0.id == id })?.media { mediaStore.remove(media) }
        ModulaLog.app.info("draft.discard kind=story count=\(self.stories.count, privacy: .public)")
    }

    func discard(kind: DraftKind, id: String) {
        switch kind {
        case .post: discardPost(id: id)
        case .inMail: discardInMail(id: id)
        case .story: discardStory(id: id)
        }
    }

    @discardableResult
    func flush() -> Bool {
        for task in autosaveTasks.values { task.cancel() }
        autosaveTasks.removeAll()
        let writes = Array(pendingWrites.values)
        pendingWrites.removeAll()
        for write in writes { write() }
        pendingPosts.removeAll()
        // Retry any earlier failed write, even when debounce has already fired.
        return persist()
    }

    // MARK: - Persistence

    private var filename: String {
        if let accountID, !accountID.isEmpty {
            return "accounts/\(sanitize(accountID))/draft-index.json"
        }
        return "draft-index.json"
    }

    private func schedule(id: String, debounce: Bool, work: @escaping @MainActor () -> Void) {
        cancelPending(id: id)
        showSavedIndicator = false
        if !debounce {
            work()
            return
        }
        pendingWrites[id] = work
        autosaveTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autosaveNanoseconds)
            guard !Task.isCancelled else { return }
            work()
            pendingWrites[id] = nil
            autosaveTasks[id] = nil
        }
    }

    private func cancelPending(id: String) {
        autosaveTasks.removeValue(forKey: id)?.cancel()
        pendingWrites[id] = nil
    }

    private func writePost(_ draft: PostDraft) {
        var next = draft
        next.lastEdited = Date()
        if next.accountID == nil { next.accountID = accountID }
        if let index = posts.firstIndex(where: { $0.id == next.id }) {
            posts[index] = next
        } else {
            posts.append(next)
        }
        if persist() { markSaved() }
        ModulaLog.app.info("draft.autosave kind=post count=\(self.posts.count, privacy: .public)")
    }

    private func writeInMail(_ draft: PersistedInMailDraft) {
        var next = draft
        next.lastEdited = Date()
        if let index = inMails.firstIndex(where: { $0.id == next.id }) {
            inMails[index] = next
        } else {
            inMails.append(next)
        }
        if persist() { markSaved() }
        ModulaLog.app.info("draft.autosave kind=inMail count=\(self.inMails.count, privacy: .public)")
    }

    private func writeStory(_ draft: StoryDraft) {
        var next = draft
        next.lastEdited = Date()
        if let index = stories.firstIndex(where: { $0.id == next.id }) {
            stories[index] = next
        } else {
            stories.append(next)
        }
        if persist() { markSaved() }
        ModulaLog.app.info("draft.autosave kind=story count=\(self.stories.count, privacy: .public)")
    }

    private func markSaved() {
        lastSavedAt = Date()
        showSavedIndicator = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            showSavedIndicator = false
        }
    }

    private func load() {
        guard let data = try? fileStore.loadData(filename: filename),
              let decoded = try? JSONDecoder().decode(DraftIndex.self, from: data) else {
            posts = []; inMails = []; stories = []
            return
        }
        if let accountID {
            posts = decoded.posts.filter { $0.accountID == nil || $0.accountID == accountID }
        } else {
            posts = decoded.posts
        }
        inMails = decoded.inMails
        stories = decoded.stories
        ModulaLog.app.info(
            "draft.load post=\(self.posts.count, privacy: .public) inMail=\(self.inMails.count, privacy: .public) story=\(self.stories.count, privacy: .public)"
        )
    }

    @discardableResult
    private func persist() -> Bool {
        let index = DraftIndex(posts: posts, inMails: inMails, stories: stories)
        do {
            let data = try JSONEncoder().encode(index)
            try fileStore.saveData(data, filename: filename)
            saveError = nil
            return true
        } catch {
            showSavedIndicator = false
            saveError = "Couldn’t save your draft on this iPhone. Free up storage and try again."
            return false
        }
    }

    private func cleanupMedia() {
        guard let accountID else { return }
        let referenced = Set((posts + Array(pendingPosts.values)).flatMap { $0.media.map(\.id) + $0.mediaReferences }
            + stories.flatMap { $0.mediaAssetIDs + ($0.media.map { [$0.id] } ?? []) })
        mediaStore.cleanupOrphans(referenced: referenced, accountID: accountID)
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(filtered)
        return result.isEmpty ? "_unknown" : result
    }

    private static func audienceKey(_ accountID: String) -> String {
        "modula.creation.lastAudience.\(accountID)"
    }
}
