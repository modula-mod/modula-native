import Foundation
import Observation

struct DraftPublishOutcome: Sendable {
    let draft: GreenfieldPostDraft
    let postID: String
}

actor GreenfieldDraftRepository {
    private let client: GreenfieldClient

    init(client: GreenfieldClient) { self.client = client }

    func allDrafts() async throws -> [GreenfieldPostDraft] {
        var result: [GreenfieldPostDraft] = []
        var cursor: String?
        repeat {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: cursor)]
                .filter { $0.value != nil }
            let path = "/v1/me/drafts?\(components.percentEncodedQuery ?? "limit=50")"
            let value = try await client.authenticatedJSON("GET", path: path)
            result.append(contentsOf: try (value["items"]?.array ?? []).map(Self.decode))
            cursor = value["nextCursor"]?.string
        } while cursor != nil
        return result
    }

    func draft(id: String) async throws -> GreenfieldPostDraft {
        let value = try await client.authenticatedJSON("GET", path: Self.path(id))
        return try Self.decode(value["draft"] ?? value)
    }

    func create(_ draft: PostDraft) async throws -> GreenfieldPostDraft {
        let value = try await client.authenticatedJSON("POST", path: "/v1/me/drafts", body: Self.body(draft, creating: true))
        return try Self.decode(value["draft"] ?? value)
    }

    func update(_ draft: PostDraft) async throws -> GreenfieldPostDraft {
        guard let id = draft.serverID, let version = draft.serverVersion else { throw APIError.invalidResponse }
        var body = Self.bodyObject(draft)
        body["expectedVersion"] = .number(Double(version))
        let value = try await client.authenticatedJSON("PATCH", path: Self.path(id), body: .object(body))
        return try Self.decode(value["draft"] ?? value)
    }

    func delete(id: String, expectedVersion: Int) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE", path: "\(Self.path(id))?expectedVersion=\(expectedVersion)"
        )
    }

    func publish(id: String, expectedVersion: Int) async throws -> DraftPublishOutcome {
        let value = try await client.authenticatedJSON("POST", path: "\(Self.path(id))/publish", body: .object([
            "expectedVersion": .number(Double(expectedVersion)),
        ]))
        guard let postID = value["postId"]?.string else { throw APIError.invalidResponse }
        return DraftPublishOutcome(draft: try Self.decode(value["draft"] ?? value), postID: postID)
    }

    func post(id: String) async throws -> SocialPost {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let value = try await client.authenticatedJSON("GET", path: "/v1/posts/\(escaped)")
        guard let post = SocialPayloadDecoder.post(value["post"] ?? value) else { throw APIError.invalidResponse }
        return post
    }

    nonisolated static func payload(_ draft: PostDraft) -> DraftPayloadIdentity {
        DraftPayloadIdentity(
            text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
            feed: draft.feed,
            audience: AudienceSelection(greenfield: draft.audience).greenfieldValue,
            replyPermission: draft.replyPermission,
            content: content(draft),
            publishToATProto: draft.publishToATProto
        )
    }

    nonisolated static func payload(_ draft: GreenfieldPostDraft) -> DraftPayloadIdentity {
        DraftPayloadIdentity(
            text: draft.text,
            feed: draft.feed,
            audience: draft.audience,
            replyPermission: draft.replyPermission,
            content: draft.content,
            publishToATProto: draft.publishToATProto
        )
    }

    nonisolated private static func body(_ draft: PostDraft, creating: Bool) -> JSONValue {
        var result = bodyObject(draft)
        if creating { result["idempotencyKey"] = .string(draft.idempotencyKey) }
        return .object(result)
    }

    nonisolated private static func bodyObject(_ draft: PostDraft) -> [String: JSONValue] {
        let payload = payload(draft)
        return [
            "text": .string(payload.text),
            "feed": .string(payload.feed),
            "audience": .string(payload.audience),
            "replyPermission": .string(payload.replyPermission),
            "content": .array(payload.content.map { item in
                var object: [String: JSONValue] = [
                    "type": .string(item.type), "attachmentId": .string(item.attachmentID),
                ]
                if let caption = item.caption { object["caption"] = .string(caption) }
                return .object(object)
            }),
            "publishToAtproto": .bool(payload.publishToATProto),
        ]
    }

    nonisolated private static func content(_ draft: PostDraft) -> [GreenfieldDraftContent] {
        draft.media.compactMap { media in
            guard let attachmentID = media.remoteAttachmentID else { return nil }
            let caption = media.altText.trimmingCharacters(in: .whitespacesAndNewlines)
            return GreenfieldDraftContent(
                type: media.kind.greenfieldDraftType,
                attachmentID: attachmentID,
                caption: caption.isEmpty ? nil : String(caption.prefix(1_000))
            )
        }
    }

    nonisolated private static func decode(_ value: JSONValue) throws -> GreenfieldPostDraft {
        guard let id = value["id"]?.string, let text = value["text"]?.string,
              let feed = value["feed"]?.string, let audience = value["audience"]?.string,
              let replyPermission = value["replyPermission"]?.string,
              let state = value["state"]?.string, let version = value["version"]?.int,
              let createdAt = SocialPayloadDecoder.decodeDate(value["createdAt"]?.string),
              let updatedAt = SocialPayloadDecoder.decodeDate(value["updatedAt"]?.string) else {
            throw APIError.invalidResponse
        }
        let content = try (value["content"]?.array ?? []).map { item -> GreenfieldDraftContent in
            guard let type = item["type"]?.string, let attachmentID = item["attachmentId"]?.string else {
                throw APIError.invalidResponse
            }
            return GreenfieldDraftContent(type: type, attachmentID: attachmentID, caption: item["caption"]?.string)
        }
        return GreenfieldPostDraft(
            id: id, idempotencyKey: value["idempotencyKey"]?.string, text: text,
            feed: feed, audience: audience, replyPermission: replyPermission, content: content,
            publishToATProto: value["publishToAtproto"]?.bool ?? false, state: state,
            publishedPostID: value["publishedPostId"]?.string, version: version,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    nonisolated private static func path(_ id: String) -> String {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return "/v1/me/drafts/\(escaped)"
    }
}

struct DraftPayloadIdentity: Equatable, Sendable {
    let text: String
    let feed: String
    let audience: String
    let replyPermission: String
    let content: [GreenfieldDraftContent]
    let publishToATProto: Bool
}

private extension CreationMedia.Kind {
    var greenfieldDraftType: String {
        switch self {
        case .image: "image"
        case .video: "video"
        case .audio: "audio"
        case .pdf: "pdf"
        case .document, .unknown: "document"
        }
    }
}

/// Private local cache plus GreenField synchronization for post drafts. In-Mail and Story
/// drafts remain separate local models because PR #151 does not define contracts for them.
@MainActor @Observable
final class DraftStore {
    private struct DeleteMutation: Codable, Sendable, Equatable {
        var serverID: String
        var expectedVersion: Int
    }
    private struct SyncCache: Codable { var deletes: [DeleteMutation] }

    private let fileStore: PrivateFileStore
    private let mediaStore: DraftMediaStore
    private let defaults: UserDefaults
    private let repository: GreenfieldDraftRepository?
    private var autosaveTasks: [String: Task<Void, Never>] = [:]
    private var pendingWrites: [String: @MainActor () -> Void] = [:]
    private var pendingPosts: [String: PostDraft] = [:]
    private var pendingDeletes: [DeleteMutation] = []
    private var syncingIDs: Set<String> = []
    private let autosaveNanoseconds: UInt64

    let capabilities: DraftBackendCapabilities
    private(set) var accountID: String?
    private(set) var posts: [PostDraft] = []
    private(set) var inMails: [PersistedInMailDraft] = []
    private(set) var stories: [StoryDraft] = []
    private(set) var lastSavedAt: Date?
    private(set) var showSavedIndicator = false
    private(set) var saveError: String?
    private(set) var syncError: String?
    private(set) var isRefreshing = false
    var pendingResumeID: String?

    init(
        client: GreenfieldClient? = nil,
        capabilities: DraftBackendCapabilities = .production,
        fileStore: PrivateFileStore = PrivateFileStore(domain: .drafts),
        mediaStore: DraftMediaStore = DraftMediaStore(),
        autosaveMilliseconds: UInt64 = 600,
        defaults: UserDefaults = .standard
    ) {
        repository = client.map { GreenfieldDraftRepository(client: $0) }
        self.capabilities = capabilities
        self.fileStore = fileStore
        self.mediaStore = mediaStore
        self.autosaveNanoseconds = autosaveMilliseconds * 1_000_000
        self.defaults = defaults
        load()
    }

    var allPreviews: [(id: String, kind: DraftKind, preview: String, lastEdited: Date)] {
        let mapped = posts.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
            + inMails.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
            + stories.map { ($0.id, $0.kind, $0.preview, $0.lastEdited) }
        return mapped.sorted { $0.3 > $1.3 }
    }

    var libraryItems: [DraftLibraryItem] {
        let postItems = posts.map {
            DraftLibraryItem(
                id: $0.id, kind: .post, preview: $0.preview, lastEdited: $0.lastEdited,
                mediaCount: $0.media.count, audienceTitle: AudienceSelection(greenfield: $0.audience).title,
                syncState: $0.syncState
            )
        }
        let mailItems = inMails.map {
            DraftLibraryItem(id: $0.id, kind: .inMail, preview: $0.preview, lastEdited: $0.lastEdited, mediaCount: 0, audienceTitle: nil)
        }
        let storyItems = stories.map {
            DraftLibraryItem(
                id: $0.id, kind: .story, preview: $0.preview, lastEdited: $0.lastEdited,
                mediaCount: max($0.mediaAssetIDs.count, $0.media == nil ? 0 : 1),
                audienceTitle: DraftLibraryItem.audienceTitle(for: $0.visibility)
            )
        }
        return (postItems + mailItems + storyItems).sorted { $0.lastEdited > $1.lastEdited }
    }

    var countsByKind: [DraftKind: Int] { [.post: posts.count, .inMail: inMails.count, .story: stories.count] }
    var draftMediaBytes: Int64 { mediaStore.byteCount(accountID: accountID) }

    func setAccountID(_ id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard accountID != next else { return }
        _ = flush()
        let legacyPosts = accountID == nil ? posts : []
        let legacyMail = accountID == nil ? inMails : []
        let legacyStories = accountID == nil ? stories : []
        accountID = next
        load()
        if next != nil, repository != nil, posts.isEmpty, inMails.isEmpty, stories.isEmpty,
           !legacyPosts.isEmpty || !legacyMail.isEmpty || !legacyStories.isEmpty {
            posts = legacyPosts.map { value in
                var migrated = value
                migrated.accountID = next
                migrated.syncState = .pending
                return migrated
            }
            inMails = legacyMail
            stories = legacyStories
            _ = persist()
        }
        guard next != nil else { return }
        Task { [weak self] in await self?.refresh() }
    }

    func lastAudience() -> AudienceSelection {
        if UserDefaults.standard.object(forKey: ModulaPreferences.Key.creatorDefaultAudience) != nil {
            return ModulaPreferences.creatorDefaultAudience
        }
        guard let accountID, let raw = defaults.string(forKey: Self.audienceKey(accountID)) else { return .everyone }
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
        if let existing = postDraft(id: scoped.id) {
            scoped.feed = existing.feed
            scoped.replyPermission = existing.replyPermission
            scoped.publishToATProto = existing.publishToATProto
            scoped.serverID = existing.serverID
            scoped.serverVersion = existing.serverVersion
            scoped.serverUpdatedAt = existing.serverUpdatedAt
            scoped.publishedPostID = existing.publishedPostID
            scoped.syncConflict = existing.syncConflict
            scoped.syncState = existing.syncState == .conflict ? .conflict : (accountID == nil ? .localOnly : .pending)
        } else {
            scoped.syncState = accountID == nil ? .localOnly : .pending
        }
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
        if let serverID = existing?.serverID, let version = existing?.serverVersion {
            pendingDeletes.removeAll { $0.serverID == serverID }
            pendingDeletes.append(DeleteMutation(serverID: serverID, expectedVersion: version))
        }
        removeLocalPost(id: id, removeMedia: true)
        _ = persist()
        replayDeletesSoon()
        ModulaLog.app.info("draft.discard kind=post count=\(self.posts.count, privacy: .public)")
    }

    func markPublished(id: String) {
        removeLocalPost(id: id, removeMedia: true)
        _ = persist()
    }

    func publish(_ creation: CreationDraft, fallback: PublishingRepository) async throws -> SocialPost {
        upsertCreation(creation, debounce: false)
        guard flush() else { throw DraftSyncError.localSave(saveError ?? "The draft could not be saved locally.") }
        guard let repository, accountID != nil else {
            let post = try await fallback.publish(creation)
            markPublished(id: creation.id)
            return post
        }
        for _ in 0..<3 {
            if await syncPost(id: creation.id), postDraft(id: creation.id)?.syncState == .synced { break }
            if postDraft(id: creation.id)?.syncState == .conflict { break }
            try? await Task.sleep(for: .milliseconds(80))
        }
        guard let local = postDraft(id: creation.id) else { throw APIError.invalidResponse }
        guard local.syncConflict == nil else {
            throw DraftSyncError.conflict
        }
        guard let serverID = local.serverID, let version = local.serverVersion, local.syncState == .synced else {
            throw DraftSyncError.waiting(syncError ?? "The draft is saved locally and will publish after it syncs.")
        }
        let post: SocialPost
        do {
            let outcome = try await repository.publish(id: serverID, expectedVersion: version)
            post = try await repository.post(id: outcome.postID)
        } catch {
            // The publish endpoint is exactly-once. If its response was lost after commit,
            // recover the published identity instead of issuing a second logical publish.
            guard let recovered = try? await repository.draft(id: serverID),
                  recovered.state == "published", let postID = recovered.publishedPostID else {
                throw error
            }
            post = try await repository.post(id: postID)
        }
        removeLocalPost(id: creation.id, removeMedia: true)
        syncError = nil
        _ = persist()
        return post
    }

    func resolveConflictUsingServer(id: String) {
        guard let index = posts.firstIndex(where: { $0.id == id }), let conflict = posts[index].syncConflict else { return }
        posts[index] = localDraft(from: conflict.server, localID: id, preserving: posts[index])
        syncError = nil
        _ = persist()
    }

    func resolveConflictKeepingLocal(id: String) {
        guard let index = posts.firstIndex(where: { $0.id == id }), let conflict = posts[index].syncConflict else { return }
        let serverCopy = localDraft(from: conflict.server, localID: conflict.server.id, preserving: nil)
        var local = posts[index]
        local.serverID = nil
        local.serverVersion = nil
        local.serverUpdatedAt = nil
        local.publishedPostID = nil
        local.idempotencyKey = UUID().uuidString
        local.syncConflict = nil
        local.syncState = .pending
        posts[index] = local
        if !posts.contains(where: { $0.id == serverCopy.id || $0.serverID == serverCopy.serverID }) {
            posts.append(serverCopy)
        }
        syncError = nil
        _ = persist()
        Task { [weak self] in _ = await self?.syncPost(id: id) }
    }

    func refresh() async {
        guard let repository, accountID != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await replayDeletes()
        for id in posts.filter({ $0.syncState == .pending }).map(\.id) { _ = await syncPost(id: id) }
        do {
            let serverDrafts = try await repository.allDrafts()
            let byID = Dictionary(uniqueKeysWithValues: serverDrafts.map { ($0.id, $0) })
            let suppressed = Set(pendingDeletes.map(\.serverID))
            var merged: [PostDraft] = []
            var seen: Set<String> = []
            for local in posts {
                guard let serverID = local.serverID else { merged.append(local); continue }
                seen.insert(serverID)
                guard let server = byID[serverID] else {
                    if local.syncState != .synced { merged.append(local) }
                    continue
                }
                if local.syncState == .conflict {
                    merged.append(local)
                } else if local.syncState == .pending, local.serverVersion != server.version {
                    var conflict = local
                    conflict.syncState = .conflict
                    conflict.syncConflict = DraftSyncConflict(server: server, detectedAt: Date())
                    merged.append(conflict)
                } else if local.syncState == .pending {
                    merged.append(local)
                } else {
                    merged.append(localDraft(from: server, localID: local.id, preserving: local))
                }
            }
            for server in serverDrafts where !seen.contains(server.id) && !suppressed.contains(server.id) {
                merged.append(localDraft(from: server, localID: server.id, preserving: nil))
            }
            posts = merged
            syncError = nil
            _ = persist()
        } catch {
            syncError = (error as? APIError)?.userFacingMessage ?? "Drafts will refresh when the connection recovers."
        }
    }

    // MARK: - In-Mail and Story

    func upsertInMail(_ draft: InMailDraft, id: String = "inmail-primary", debounce: Bool = true) {
        let record = PersistedInMailDraft(id: id, toHandle: draft.toHandle, subject: draft.subject, body: draft.body, lastEdited: Date())
        guard record.hasContent else { return }
        schedule(id: id, debounce: debounce) { [weak self] in self?.writeInMail(record) }
    }

    func inMailDraft(id: String = "inmail-primary") -> PersistedInMailDraft? { inMails.first { $0.id == id } }

    func discardInMail(id: String = "inmail-primary") {
        cancelPending(id: id)
        let previous = inMails
        inMails.removeAll { $0.id == id }
        guard persist() else { inMails = previous; return }
    }

    func upsertStory(_ draft: StoryDraft, debounce: Bool = true) {
        guard draft.hasContent else { return }
        var safe = draft
        safe.mediaAssetIDs = draft.mediaAssetIDs.filter { !$0.hasPrefix("file:") && !$0.hasPrefix("/") }
        schedule(id: draft.id, debounce: debounce) { [weak self] in self?.writeStory(safe) }
    }

    func discardStory(id: String) {
        cancelPending(id: id)
        let previous = stories
        stories.removeAll { $0.id == id }
        guard persist() else { stories = previous; return }
        if let media = previous.first(where: { $0.id == id })?.media { mediaStore.remove(media) }
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
        return persist()
    }

    // MARK: - Synchronization

    @discardableResult
    private func syncPost(id: String) async -> Bool {
        guard let repository, accountID != nil else { return true }
        guard !syncingIDs.contains(id), let snapshot = postDraft(id: id), snapshot.syncState != .conflict else { return false }
        let payload = GreenfieldDraftRepository.payload(snapshot)
        guard !payload.text.isEmpty || !payload.content.isEmpty else { return false }
        syncingIDs.insert(id)
        defer { syncingIDs.remove(id) }
        do {
            let server = snapshot.serverID == nil ? try await repository.create(snapshot) : try await repository.update(snapshot)
            guard let index = posts.firstIndex(where: { $0.id == id }) else {
                // The user discarded this draft while creation was in flight. Remove the
                // just-created server record through the authenticated replay queue.
                pendingDeletes.removeAll { $0.serverID == server.id }
                pendingDeletes.append(DeleteMutation(serverID: server.id, expectedVersion: server.version))
                _ = persist()
                replayDeletesSoon()
                return true
            }
            let currentPayload = GreenfieldDraftRepository.payload(posts[index])
            posts[index].serverID = server.id
            posts[index].serverVersion = server.version
            posts[index].serverUpdatedAt = server.updatedAt
            posts[index].publishedPostID = server.publishedPostID
            posts[index].syncConflict = nil
            posts[index].syncState = currentPayload == payload ? .synced : .pending
            syncError = nil
            _ = persist()
            if currentPayload != payload {
                Task { [weak self] in _ = await self?.syncPost(id: id) }
            }
            return currentPayload == payload
        } catch let api as APIError where Self.isConflict(api) {
            if snapshot.serverID == nil,
               let recovered = (try? await repository.allDrafts())?.first(where: { $0.idempotencyKey == snapshot.idempotencyKey }),
               let index = posts.firstIndex(where: { $0.id == id }) {
                posts[index].serverID = recovered.id
                posts[index].serverVersion = recovered.version
                posts[index].serverUpdatedAt = recovered.updatedAt
                posts[index].syncState = .pending
                _ = persist()
                Task { [weak self] in _ = await self?.syncPost(id: id) }
                return false
            }
            if let serverID = snapshot.serverID, let server = try? await repository.draft(id: serverID),
               let index = posts.firstIndex(where: { $0.id == id }) {
                if server.state == "editing", GreenfieldDraftRepository.payload(server) == payload {
                    posts[index].serverVersion = server.version
                    posts[index].serverUpdatedAt = server.updatedAt
                    posts[index].syncConflict = nil
                    posts[index].syncState = .synced
                    syncError = nil
                    _ = persist()
                    return true
                }
                posts[index].syncState = .conflict
                posts[index].syncConflict = DraftSyncConflict(server: server, detectedAt: Date())
                syncError = "This draft has a newer server revision. Your local edit has been preserved."
                _ = persist()
            } else {
                syncError = api.userFacingMessage
            }
            return false
        } catch {
            if let index = posts.firstIndex(where: { $0.id == id }), posts[index].syncState != .conflict {
                posts[index].syncState = .pending
            }
            syncError = (error as? APIError)?.userFacingMessage ?? "Drafts will sync when the connection recovers."
            _ = persist()
            return false
        }
    }

    private func replayDeletesSoon() {
        guard repository != nil, accountID != nil else { return }
        Task { [weak self] in await self?.replayDeletes() }
    }

    private func replayDeletes() async {
        guard let repository, accountID != nil else { return }
        while let mutation = pendingDeletes.first {
            do {
                try await repository.delete(id: mutation.serverID, expectedVersion: mutation.expectedVersion)
                pendingDeletes.removeFirst()
                syncError = nil
                _ = persist()
            } catch let api as APIError where Self.isNotFound(api) {
                pendingDeletes.removeFirst()
                _ = persist()
            } catch {
                syncError = (error as? APIError)?.userFacingMessage ?? "Draft deletion will retry when the connection recovers."
                _ = persist()
                return
            }
        }
    }

    private func localDraft(from server: GreenfieldPostDraft, localID: String, preserving existing: PostDraft?) -> PostDraft {
        let media = server.content.map { content -> CreationMedia in
            if let cached = existing?.media.first(where: { $0.remoteAttachmentID == content.attachmentID }) { return cached }
            return CreationMedia(
                id: content.attachmentID,
                kind: CreationMedia.Kind(rawValue: content.type) ?? .document,
                filename: "greenfield-\(content.attachmentID)", altText: content.caption ?? "",
                pixelWidth: nil, pixelHeight: nil, byteCount: nil, duration: nil,
                sensitive: false, remoteAttachmentID: content.attachmentID, uploadState: .ready
            )
        }
        let kind: CreationKind = media.count > 1 ? .carousel : {
            switch media.first?.kind {
            case .image: return .photo
            case .video: return .video
            case .audio: return .audio
            default: return .post
            }
        }()
        return PostDraft(
            id: localID, accountID: accountID, creationKind: kind.rawValue, text: server.text,
            mediaReferences: media.map(\.id), media: media,
            audience: server.audience, altTextByMediaID: Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0.altText) }),
            lastEdited: server.updatedAt, state: server.state,
            idempotencyKey: server.idempotencyKey ?? existing?.idempotencyKey ?? UUID().uuidString,
            originPath: existing?.originPath, feed: server.feed, replyPermission: server.replyPermission,
            publishToATProto: server.publishToATProto, serverID: server.id, serverVersion: server.version,
            serverUpdatedAt: server.updatedAt, publishedPostID: server.publishedPostID, syncState: .synced
        )
    }

    // MARK: - Persistence

    private var filename: String {
        if let accountID, !accountID.isEmpty { return "accounts/\(sanitize(accountID))/draft-index.json" }
        return "draft-index.json"
    }

    private var syncFilename: String {
        if let accountID, !accountID.isEmpty { return "accounts/\(sanitize(accountID))/draft-sync.json" }
        return "draft-sync.json"
    }

    private func schedule(id: String, debounce: Bool, work: @escaping @MainActor () -> Void) {
        cancelPending(id: id)
        showSavedIndicator = false
        if !debounce { work(); return }
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
        if let existing = posts.first(where: { $0.id == next.id }) {
            next.feed = existing.feed
            next.replyPermission = existing.replyPermission
            next.publishToATProto = existing.publishToATProto
            next.serverID = existing.serverID
            next.serverVersion = existing.serverVersion
            next.serverUpdatedAt = existing.serverUpdatedAt
            next.publishedPostID = existing.publishedPostID
            next.syncConflict = existing.syncConflict
            next.syncState = existing.syncState == .conflict ? .conflict : (accountID == nil ? .localOnly : .pending)
        }
        if let index = posts.firstIndex(where: { $0.id == next.id }) { posts[index] = next } else { posts.append(next) }
        if persist() { markSaved() }
        if next.syncState == .pending { Task { [weak self] in _ = await self?.syncPost(id: next.id) } }
        ModulaLog.app.info("draft.autosave kind=post count=\(self.posts.count, privacy: .public)")
    }

    private func writeInMail(_ draft: PersistedInMailDraft) {
        var next = draft
        next.lastEdited = Date()
        if let index = inMails.firstIndex(where: { $0.id == next.id }) { inMails[index] = next } else { inMails.append(next) }
        if persist() { markSaved() }
    }

    private func writeStory(_ draft: StoryDraft) {
        var next = draft
        next.lastEdited = Date()
        if let index = stories.firstIndex(where: { $0.id == next.id }) { stories[index] = next } else { stories.append(next) }
        if persist() { markSaved() }
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
        if let data = try? fileStore.loadData(filename: filename),
           let decoded = try? JSONDecoder().decode(DraftIndex.self, from: data) {
            posts = accountID.map { id in decoded.posts.filter { $0.accountID == nil || $0.accountID == id } } ?? decoded.posts
            inMails = decoded.inMails
            stories = decoded.stories
        } else { posts = []; inMails = []; stories = [] }
        if let data = try? fileStore.loadData(filename: syncFilename),
           let decoded = try? JSONDecoder().decode(SyncCache.self, from: data) {
            pendingDeletes = decoded.deletes
        } else { pendingDeletes = [] }
    }

    @discardableResult
    private func persist() -> Bool {
        let index = DraftIndex(posts: posts, inMails: inMails, stories: stories)
        do {
            try fileStore.saveData(try JSONEncoder().encode(index), filename: filename)
            try fileStore.saveData(try JSONEncoder().encode(SyncCache(deletes: pendingDeletes)), filename: syncFilename)
            saveError = nil
            return true
        } catch {
            showSavedIndicator = false
            saveError = "Couldn’t save your draft cache on this iPhone. Free up storage and try again."
            return false
        }
    }

    private func removeLocalPost(id: String, removeMedia: Bool) {
        let existing = posts.first { $0.id == id } ?? pendingPosts[id]
        posts.removeAll { $0.id == id }
        pendingPosts[id] = nil
        if removeMedia, let existing {
            let localMedia = existing.media.filter { $0.filename.hasPrefix("greenfield-") == false }
            mediaStore.remove(ids: localMedia.map(\.id) + existing.mediaReferences, from: localMedia)
        }
        cleanupMedia()
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

    private static func audienceKey(_ accountID: String) -> String { "modula.creation.lastAudience.\(accountID)" }
    private static func isConflict(_ error: APIError) -> Bool {
        if case .rejected(409, _) = error { return true }
        return false
    }
    private static func isNotFound(_ error: APIError) -> Bool {
        if case .rejected(404, _) = error { return true }
        return false
    }
}
