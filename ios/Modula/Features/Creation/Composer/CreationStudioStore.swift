import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit
import AVFoundation
import CoreTransferable
import ImageIO
import PDFKit

@MainActor @Observable
final class CreationStudioStore {
    var draft: CreationDraft
    var capabilities: CreationCapabilities
    var restoreCandidate: CreationDraft?
    var showRestorePrompt = false
    var showExitPrompt = false
    var publishError: String?
    var preparingMedia = false
    var uploadFraction: Double?
    var altTextMediaID: String?
    var pasteLinkSuggestion: URL?
    var mentionSuggestions: [ModulaComposerMention] = []
    var hashtagSuggestions: [String] = []
    /// Local link/poll staging UI (text paths when structured kinds are off).
    var showsLocalLinkEditor = false
    var showsLocalPollEditor = false
    var composerTip: String?

    private let drafts: DraftStore
    private let mediaStore: DraftMediaStore
    private let publisher: PublishingRepository
    private let uploader: MediaUploading
    private let client: GreenfieldClient?
    private var started = false
    private var mentionTask: Task<Void, Never>?
    private var hashtagTask: Task<Void, Never>?

    init(
        kind: CreationKind,
        accountID: String,
        originPath: String?,
        drafts: DraftStore,
        mediaStore: DraftMediaStore,
        publisher: PublishingRepository,
        uploader: MediaUploading,
        capabilities: CreationCapabilities,
        client: GreenfieldClient? = nil
    ) {
        self.drafts = drafts
        self.mediaStore = mediaStore
        self.publisher = publisher
        self.uploader = uploader
        self.capabilities = capabilities
        self.client = client
        let audience = drafts.lastAudience()
        self.draft = CreationDraft.fresh(kind: kind, accountID: accountID, audience: audience, originPath: originPath)
    }

    var validation: CreationValidation? {
        CreationValidator.problem(for: draft, capabilities: capabilities)
    }

    var canPublish: Bool { validation == nil && !draft.isPublishing && !preparingMedia }

    var publishHint: String? { validation?.accessibilityHint }

    var kindUnavailable: Bool {
        !capabilities.canPublish(draft.kind) && draft.kind != .post
    }

    var unavailableCopy: String {
        capabilities.unavailableReason[draft.kind] ?? "This creation type isn’t available yet."
    }

    func start() {
        guard !started else { return }
        started = true
        if let resume = drafts.pendingResumeID, let existing = drafts.creationDraft(id: resume), existing.hasContent {
            drafts.pendingResumeID = nil
            draft = existing
            draft.state = .editing
            return
        }
        drafts.pendingResumeID = nil
        if let latest = drafts.latestPostDraft(), latest.hasContent {
            let candidate = latest.asCreationDraft(fallbackAccount: draft.accountID)
            if candidate.kind == draft.kind || draft.kind == .post {
                restoreCandidate = candidate
                showRestorePrompt = true
            }
        }
    }

    func continueDraft() {
        if let restoreCandidate {
            draft = restoreCandidate
            draft.state = .editing
        }
        restoreCandidate = nil
        showRestorePrompt = false
    }

    func startNew() {
        if let restoreCandidate {
            drafts.discardPost(id: restoreCandidate.id)
        }
        restoreCandidate = nil
        showRestorePrompt = false
        draft = CreationDraft.fresh(
            kind: draft.kind,
            accountID: draft.accountID,
            audience: drafts.lastAudience(),
            originPath: draft.originPath
        )
    }

    func textChanged(_ value: String) {
        draft.text = value
        draft.mentions = CreationEntityParser.mentions(in: value)
        draft.topics = CreationEntityParser.topics(in: value)
        draft.state = .editing
        persist()
        refreshSuggestions(for: value)
    }

    func handlePaste(_ value: String) {
        textChanged(value)
        if capabilities.linkPreview || capabilities.linkPost,
           let url = CreationEntityParser.firstURL(in: value) {
            pasteLinkSuggestion = url
        }
    }

    func refreshSuggestions(for text: String) {
        if capabilities.mentionsLookup {
            updateMentionQuery(ModulaComposerState.mentionQuery(in: text))
        } else {
            mentionSuggestions = []
        }
        if capabilities.topicsLookup {
            updateHashtagQuery(ModulaComposerState.hashtagQuery(in: text))
        } else {
            hashtagSuggestions = []
        }
    }

    func updateMentionQuery(_ query: String?) {
        mentionTask?.cancel()
        guard let client, let query, !query.isEmpty else {
            mentionSuggestions = []
            return
        }
        mentionTask = Task { [client] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
            guard let value = try? await client.json("GET", path: "/v1/search?q=\(escaped)&entityType=profile&limit=6") else { return }
            let people = DiscoverPayloadDecoder.searchPage(from: value).results.compactMap(\.person)
            guard !Task.isCancelled else { return }
            mentionSuggestions = people.map {
                ModulaComposerMention(id: $0.id, handle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL)
            }
        }
    }

    func updateHashtagQuery(_ query: String?) {
        hashtagTask?.cancel()
        guard let client, let query, !query.isEmpty else {
            hashtagSuggestions = []
            return
        }
        hashtagTask = Task { [client] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
            guard let value = try? await client.authenticatedJSON("GET", path: "/v1/hashtags/suggest?q=\(escaped)") else { return }
            guard !Task.isCancelled else { return }
            hashtagSuggestions = (value["items"]?.array ?? []).compactMap { $0["tag"]?.string }.filter { $0 != query.lowercased() }
        }
    }

    func applyMention(_ mention: ModulaComposerMention) {
        draft.text = ModulaComposerState.applying(mention: mention.handle, to: draft.text)
        textChanged(draft.text)
        HapticEngine.shared.play(.selection)
    }

    func applyHashtag(_ tag: String) {
        draft.text = ModulaComposerState.applying(hashtag: tag, to: draft.text)
        textChanged(draft.text)
        HapticEngine.shared.play(.selection)
    }

    /// Inserts a URL into post text without switching to the unavailable `.link` kind.
    func insertLinkAsText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prefix = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
        draft.text += "\(prefix)\(trimmed)"
        showsLocalLinkEditor = false
        textChanged(draft.text)
        composerTip = "Link added."
        HapticEngine.shared.play(.lightImpact)
    }

    func insertPollAsText(_ body: String) {
        let prefix = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        draft.text += "\(prefix)\(body)"
        showsLocalPollEditor = false
        draft.poll = nil
        if draft.kind == .poll { draft.kind = .post }
        textChanged(draft.text)
        composerTip = "Poll inserted as text. Native polls aren’t on SocialPost yet."
        HapticEngine.shared.play(.lightImpact)
    }

    func attachCameraImage(_ image: UIImage) async {
        let quality = ModulaPreferences.highResolutionUploads ? 0.92 : 0.86
        guard let data = image.jpegData(compressionQuality: quality) else {
            publishError = "Couldn't capture that photo. Your draft is safe."
            return
        }
        await attachCapturedPhoto(data, mimeType: "image/jpeg")
    }

    func attachCameraVideo(_ url: URL) async {
        preparingMedia = true
        defer { preparingMedia = false }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let mimeType = "video/quicktime"
            guard CreationAttachmentPolicy.accepts(mimeType: mimeType, byteCount: values.fileSize ?? 0) else {
                publishError = "That video type or size isn't supported. Your draft is safe."
                return
            }
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration).seconds
            let naturalSize = try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)
            let media = try mediaStore.importFile(
                at: url,
                accountID: draft.accountID,
                kind: .video,
                mimeType: mimeType,
                originalFilename: "Camera.mov",
                width: naturalSize.map { Int(abs($0.width)) },
                height: naturalSize.map { Int(abs($0.height)) },
                duration: duration
            )
            draft.media.append(media)
            if draft.kind == .post { draft.kind = .video }
            HapticEngine.shared.play(.lightImpact)
            persist()
        } catch {
            publishError = "Couldn't add that video. Your draft is safe."
        }
    }

    func acceptPastedLink() {
        guard let url = pasteLinkSuggestion else { return }
        draft.link = LinkDraft(
            urlString: url.absoluteString,
            title: nil,
            description: nil,
            domain: url.host,
            imageURLString: nil,
            previewFromServer: false
        )
        if draft.kind == .post { draft.kind = .link }
        pasteLinkSuggestion = nil
        persist()
        HapticEngine.shared.play(.lightImpact)
    }

    func dismissPastedLink() {
        pasteLinkSuggestion = nil
    }

    func setAudience(_ audience: AudienceSelection) {
        draft.audience = audience
        drafts.rememberAudience(audience)
        persist()
        HapticEngine.shared.play(.selection)
    }

    /// Uploads above this size wait for Wi‑Fi when the user prefers it.
    nonisolated static let largeUploadThreshold: Int64 = 25 * 1_024 * 1_024

    nonisolated static func shouldWaitForWiFi(
        pendingBytes: Int64,
        prefersWiFi: Bool = ModulaPreferences.preferWiFiForUploads,
        expensiveNetwork: Bool = NetworkConditions.shared.isExpensive
    ) -> Bool {
        prefersWiFi && expensiveNetwork && pendingBytes > largeUploadThreshold
    }

    /// Settings → Media → Images. Unless "Keep original file data" is on, photos are
    /// re-encoded (EXIF orientation applied) so location and camera metadata stay on
    /// the device; "Prefer high-resolution uploads" (off, or Data saver on) caps size.
    nonisolated static func preparePhotoForUpload(
        _ data: Data, type: UTType,
        keepOriginal: Bool = ModulaPreferences.keepOriginalPhotoData,
        highResolution: Bool = ModulaPreferences.highResolutionUploads
    ) async throws -> (data: Data, mimeType: String, fileExtension: String)? {
        if type.conforms(to: .gif) { return nil }
        if keepOriginal && highResolution { return nil }
        let prepared = try await MediaPreparation.jpegFitting(
            data,
            maxBytes: highResolution ? 14_000_000 : 1_800_000,
            maxPixel: highResolution ? 4_096 : 2_048,
            minPixel: highResolution ? 2_048 : 1_440
        )
        return (prepared.data, prepared.mimeType, "jpg")
    }

    func attachImages(_ items: [PhotosPickerItem]) async {
        guard capabilities.photoPost || capabilities.storyPhoto || capabilities.carouselPost else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        for item in items {
            guard var data = try? await item.loadTransferable(type: Data.self) else { continue }
            do {
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
                var mimeType = type.preferredMIMEType ?? "image/jpeg"
                var fileExtension = type.preferredFilenameExtension ?? "jpg"
                if let prepared = try? await Self.preparePhotoForUpload(data, type: type) {
                    data = prepared.data
                    mimeType = prepared.mimeType
                    fileExtension = prepared.fileExtension
                }
                guard CreationAttachmentPolicy.accepts(mimeType: mimeType, byteCount: data.count) else {
                    publishError = "That photo type or size isn't supported. Your draft is safe."
                    continue
                }
                let dimensions = Self.imageDimensions(data)
                let payload = data
                let payloadMimeType = mimeType
                let payloadFilename = "Photo.\(fileExtension)"
                let media = try await Task.detached(priority: .userInitiated) { [mediaStore, accountID = draft.accountID] in
                    try mediaStore.importData(
                        payload, accountID: accountID, kind: .image,
                        mimeType: payloadMimeType,
                        originalFilename: payloadFilename,
                        width: dimensions?.0, height: dimensions?.1
                    )
                }.value
                draft.media.append(media)
                if draft.kind == .post { draft.kind = draft.media.count > 1 ? .carousel : .photo }
                HapticEngine.shared.play(.lightImpact)
            } catch {
                publishError = "Couldn't add that photo. Your draft is safe."
            }
        }
        persist()
    }

    /// A photo taken with the composer camera (Settings → Camera decides format/save).
    func attachCapturedPhoto(_ captured: Data, mimeType capturedMimeType: String) async {
        guard capabilities.photoPost || capabilities.carouselPost else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        let type: UTType = capturedMimeType == "image/heic" ? .heic : .jpeg
        var data = captured
        var mimeType = capturedMimeType
        var fileExtension = type.preferredFilenameExtension ?? "jpg"
        if let prepared = try? await Self.preparePhotoForUpload(data, type: type) {
            data = prepared.data
            mimeType = prepared.mimeType
            fileExtension = prepared.fileExtension
        }
        guard CreationAttachmentPolicy.accepts(mimeType: mimeType, byteCount: data.count) else {
            publishError = "That photo couldn't be added. Your draft is safe."
            return
        }
        let dimensions = Self.imageDimensions(data)
        let payload = data
        let payloadMimeType = mimeType
        let payloadFilename = "Camera.\(fileExtension)"
        do {
            let media = try await Task.detached(priority: .userInitiated) { [mediaStore, accountID = draft.accountID] in
                try mediaStore.importData(
                    payload, accountID: accountID, kind: .image,
                    mimeType: payloadMimeType,
                    originalFilename: payloadFilename,
                    width: dimensions?.0, height: dimensions?.1
                )
            }.value
            draft.media.append(media)
            if draft.kind == .post { draft.kind = draft.media.count > 1 ? .carousel : .photo }
            HapticEngine.shared.play(.lightImpact)
        } catch {
            publishError = "Couldn't add that photo. Your draft is safe."
        }
        persist()
    }

    func attachVideos(_ items: [PhotosPickerItem]) async {
        guard capabilities.videoPost else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        for item in items {
            guard let picked = try? await item.loadTransferable(type: CreationPickedVideo.self) else { continue }
            defer { try? FileManager.default.removeItem(at: picked.url) }
            do {
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) }) ?? .mpeg4Movie
                let mimeType = type.preferredMIMEType ?? "video/mp4"
                let values = try picked.url.resourceValues(forKeys: [.fileSizeKey])
                let byteCount = values.fileSize ?? 0
                guard CreationAttachmentPolicy.accepts(mimeType: mimeType, byteCount: byteCount) else {
                    publishError = "That video type or size isn't supported. Your draft is safe."
                    continue
                }
                let asset = AVURLAsset(url: picked.url)
                let duration = try? await asset.load(.duration).seconds
                let naturalSize = try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)
                let media = try mediaStore.importFile(
                        at: picked.url, accountID: draft.accountID, kind: .video,
                        mimeType: mimeType,
                        originalFilename: "Video.\(type.preferredFilenameExtension ?? "mp4")",
                        width: naturalSize.map { Int(abs($0.width)) },
                        height: naturalSize.map { Int(abs($0.height)) },
                        duration: duration
                )
                draft.media.append(media)
                if draft.kind == .post { draft.kind = .video }
            } catch {
                publishError = "Couldn't add that video. Your draft is safe."
            }
        }
        persist()
    }

    func attachFiles(_ urls: [URL]) async {
        preparingMedia = true
        defer { preparingMedia = false }
        for source in urls.prefix(max(0, (capabilities.maxMediaCount ?? 10) - draft.media.count)) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                let values = try source.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .nameKey])
                let type = values.contentType ?? UTType(filenameExtension: source.pathExtension) ?? .data
                let mimeType = type.preferredMIMEType ?? "application/octet-stream"
                guard CreationAttachmentPolicy.accepts(mimeType: mimeType, byteCount: values.fileSize ?? 0) else {
                    publishError = "\(values.name ?? source.lastPathComponent) has an unsupported type or size."
                    continue
                }
                let kind: CreationMedia.Kind
                if type.conforms(to: .pdf) { kind = .pdf }
                else if type.conforms(to: .audio) { kind = .audio }
                else if type.conforms(to: .movie) { kind = .video }
                else if type.conforms(to: .image) { kind = .image }
                else { kind = .document }
                let pageCount = kind == .pdf ? PDFDocument(url: source)?.pageCount : nil
                let duration: TimeInterval?
                if kind == .audio || kind == .video {
                    duration = try? await AVURLAsset(url: source).load(.duration).seconds
                } else { duration = nil }
                let media = try mediaStore.importFile(
                    at: source, accountID: draft.accountID, kind: kind,
                    mimeType: mimeType,
                    originalFilename: values.name ?? source.lastPathComponent,
                    duration: duration, pageCount: pageCount
                )
                draft.media.append(media)
            } catch {
                publishError = "Couldn't add \(source.lastPathComponent). Your draft is safe."
            }
        }
        persist()
    }

    func rotateMedia(_ id: String) async {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        let item = draft.media[index]
        guard let data = try? mediaStore.read(item) else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        do {
            let prepared = try await MediaPreparation.rotatedJPEG(data, quarterTurns: 1)
            var rotated = try mediaStore.importJPEG(
                prepared.data,
                accountID: draft.accountID,
                id: item.id,
                width: prepared.width,
                height: prepared.height
            )
            rotated.altText = item.altText
            rotated.sensitive = item.sensitive
            if item.filename != rotated.filename { mediaStore.remove(item) }
            draft.media[index] = rotated
            persist()
        } catch {
            publishError = "Couldn't rotate that photo."
        }
    }

    func setAltText(_ id: String, text: String) {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        draft.media[index].altText = text
        draft.accessibility.altTextByMediaID[id] = text
        persist()
    }

    func moveMedia(id: String, earlier: Bool) {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        let target = earlier ? index - 1 : index + 1
        guard draft.media.indices.contains(target) else { return }
        draft.media.swapAt(index, target)
        persist()
        HapticEngine.shared.play(.drop)
    }

    func removeMedia(_ id: String) {
        let removed = draft.media.filter { $0.id == id }
        draft.media.removeAll { $0.id == id }
        mediaStore.remove(ids: [id], from: removed)
        if draft.media.isEmpty, draft.kind == .photo || draft.kind == .carousel {
            draft.kind = .post
        }
        persist()
        HapticEngine.shared.play(.warning)
    }

    func reorderMedia(from source: IndexSet, to destination: Int) {
        draft.media.move(fromOffsets: source, toOffset: destination)
        persist()
        HapticEngine.shared.play(.drop)
    }

    func setLinkURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft.link = nil
            if draft.kind == .link { draft.kind = .post }
        } else {
            draft.link = LinkDraft(
                urlString: trimmed,
                title: draft.link?.title,
                description: draft.link?.description,
                domain: URL(string: trimmed)?.host,
                imageURLString: nil,
                previewFromServer: false
            )
            // Only switch kind when structured link posts are publishable.
            if capabilities.linkPost, draft.kind == .post { draft.kind = .link }
        }
        persist()
    }

    func setPoll(_ poll: PollDraft) {
        draft.poll = poll
        if capabilities.pollPost, draft.media.isEmpty {
            draft.kind = .poll
        }
        persist()
    }

    func persist(debounce: Bool = true) {
        guard !draft.accountID.isEmpty, draft.state != .published, draft.state != .discarded else { return }
        drafts.upsertCreation(draft, debounce: debounce)
    }

    func flush() {
        persist(debounce: false)
        drafts.flush()
    }

    func discard() {
        drafts.discardPost(id: draft.id)
        draft.state = .discarded
        HapticEngine.shared.play(.warning)
    }

    func requestExit() -> CreationExitDecision {
        if draft.hasContent {
            showExitPrompt = true
            return .prompt
        }
        return .dismiss
    }

    @discardableResult
    func saveAndExit() -> Bool {
        persist(debounce: false)
        showExitPrompt = false
        guard drafts.flush() else {
            publishError = drafts.saveError
            return false
        }
        return true
    }

    func publish() async -> SocialPost? {
        if let problem = validation {
            publishError = problem.accessibilityHint
            return nil
        }
        // Settings → Network → "Prefer Wi‑Fi for large uploads".
        let pendingBytes = draft.media.filter { $0.remoteAttachmentID == nil }.reduce(Int64(0)) { $0 + Int64($1.byteCount ?? 0) }
        if Self.shouldWaitForWiFi(pendingBytes: pendingBytes) {
            publishError = "Waiting for Wi‑Fi. This upload is large and “Prefer Wi‑Fi for large uploads” is on (Settings → Network). Your draft is saved."
            HapticEngine.shared.play(.warning)
            persist(debounce: false)
            return nil
        }
        do {
            HapticEngine.shared.play(.confirmation)
            if !draft.media.isEmpty {
                draft.state = .uploading
                persist(debounce: false)
                for index in draft.media.indices where draft.media[index].remoteAttachmentID == nil {
                    try Task.checkCancellation()
                    draft.media[index].uploadState = .uploading
                    draft.media[index].uploadError = nil
                    let media = draft.media[index]
                    let fileURL = mediaStore.fileURL(media)
                    let checksum = try await Self.sha256(fileURL)
                    draft.media[index].checksum = checksum
                    let prepared = PreparedMedia(
                        id: media.id, kind: media.kind, fileURL: fileURL,
                        mimeType: media.mimeType ?? "application/octet-stream",
                        filename: media.originalFilename ?? URL(fileURLWithPath: media.filename).lastPathComponent,
                        altText: media.altText, byteCount: media.byteCount ?? 0, checksum: checksum,
                        width: media.pixelWidth, height: media.pixelHeight, duration: media.duration, pageCount: media.pageCount,
                        uploadSessionID: media.uploadSessionID, pendingAttachmentID: media.pendingAttachmentID
                    )
                    let uploaded = try await uploader.upload(
                        prepared,
                        progress: { [weak self] fraction in
                            Task { @MainActor in
                                guard let self, let live = self.draft.media.firstIndex(where: { $0.id == media.id }) else { return }
                                self.draft.media[live].uploadProgress = fraction
                                let completed = Double(self.draft.media.filter { $0.remoteAttachmentID != nil }.count)
                                self.uploadFraction = (completed + fraction) / Double(max(self.draft.media.count, 1))
                            }
                        },
                        sessionCreated: { [weak self] uploadID, attachmentID in
                            Task { @MainActor in
                                guard let self, let live = self.draft.media.firstIndex(where: { $0.id == media.id }) else { return }
                                self.draft.media[live].uploadSessionID = uploadID
                                self.draft.media[live].pendingAttachmentID = attachmentID
                                self.persist(debounce: false)
                            }
                        }
                    )
                    guard let live = draft.media.firstIndex(where: { $0.id == media.id }) else { continue }
                    draft.media[live].remoteAttachmentID = uploaded.remoteID
                    draft.media[live].uploadSessionID = nil
                    draft.media[live].pendingAttachmentID = nil
                    draft.media[live].uploadState = .ready
                    draft.media[live].uploadProgress = 1
                    persist(debounce: false)
                }
            }
            draft.state = .publishing
            uploadFraction = nil
            persist(debounce: false)
            let post = try await publisher.publish(draft)
            draft.state = .published
            drafts.markPublished(id: draft.id)
            publishError = nil
            HapticEngine.shared.play(.success)
            // Only fires if the account had no posts when first seen (see CelebrationCenter).
            CelebrationCenter.shared.reach(.firstPost)
            return post
        } catch is CancellationError {
            uploadFraction = nil
            resetActiveUploads(to: .cancelled, message: nil)
            draft.state = .cancelled
            persist(debounce: false)
            return nil
        } catch MediaUploadError.cancelled {
            uploadFraction = nil
            resetActiveUploads(to: .cancelled, message: nil)
            draft.state = .cancelled
            persist(debounce: false)
            return nil
        } catch where Task.isCancelled {
            uploadFraction = nil
            resetActiveUploads(to: .cancelled, message: nil)
            draft.state = .cancelled
            persist(debounce: false)
            return nil
        } catch let api as APIError where api == .unauthenticated {
            resetActiveUploads(to: .failed, message: "Sign in required")
            draft.state = .failed
            persist(debounce: false)
            publishError = "Sign in to publish. Your draft is safe."
            HapticEngine.shared.play(.failure)
            return nil
        } catch {
            resetActiveUploads(to: .failed, message: "Upload failed")
            draft.state = .failed
            persist(debounce: false)
            publishError = "Couldn't publish your post. Your draft is safe."
            ModulaLog.app.error("create.publish.failed diagnostic=\(String(describing: error), privacy: .private)")
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    /// Preserve the server IDs for reconciliation on Retry. The uploader reuses a failed
    /// session, recovers a ready attachment after a lost response, and creates a fresh session
    /// only when the prior server state is no longer usable.
    private func resetActiveUploads(to state: DraftAttachmentState, message: String?) {
        for index in draft.media.indices where draft.media[index].uploadState == .uploading {
            draft.media[index].uploadState = state
            draft.media[index].uploadError = message
            draft.media[index].uploadProgress = 0
        }
    }

    private nonisolated static func sha256(_ fileURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                digest.update(data: data)
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private nonisolated static func imageDimensions(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? Int,
              let height = values[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

enum CreationExitDecision {
    case dismiss
    case prompt
}

private struct CreationPickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("creation-video-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return CreationPickedVideo(url: copy)
        }
    }
}
