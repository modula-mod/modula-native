import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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

    private let drafts: DraftStore
    private let mediaStore: DraftMediaStore
    private let publisher: PublishingRepository
    private let uploader: MediaUploading
    private var started = false

    init(
        kind: CreationKind,
        accountID: String,
        originPath: String?,
        drafts: DraftStore,
        mediaStore: DraftMediaStore,
        publisher: PublishingRepository,
        uploader: MediaUploading,
        capabilities: CreationCapabilities
    ) {
        self.drafts = drafts
        self.mediaStore = mediaStore
        self.publisher = publisher
        self.uploader = uploader
        self.capabilities = capabilities
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
    }

    func handlePaste(_ value: String) {
        textChanged(value)
        guard capabilities.linkPreview || capabilities.linkPost else { return }
        if let url = CreationEntityParser.firstURL(in: value) {
            pasteLinkSuggestion = url
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

    func attachImages(_ items: [PhotosPickerItem]) async {
        guard capabilities.photoPost || capabilities.storyPhoto || capabilities.carouselPost else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            do {
                let prepared = try await MediaPreparation.jpegStrippingMetadata(data)
                let media = try await Task.detached(priority: .userInitiated) { [mediaStore, accountID = draft.accountID] in
                    try mediaStore.importJPEG(prepared.data, accountID: accountID, width: prepared.width, height: prepared.height)
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

    func rotateMedia(_ id: String) async {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        let item = draft.media[index]
        guard let data = try? mediaStore.read(item) else { return }
        preparingMedia = true
        defer { preparingMedia = false }
        do {
            let prepared = try await MediaPreparation.rotatedJPEG(data, quarterTurns: 1)
            try mediaStore.importJPEG(prepared.data, accountID: draft.accountID, id: item.id, width: prepared.width, height: prepared.height)
            draft.media[index].pixelWidth = prepared.width
            draft.media[index].pixelHeight = prepared.height
            draft.media[index].byteCount = prepared.data.count
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
            if draft.kind == .post { draft.kind = .link }
        }
        persist()
    }

    func setPoll(_ poll: PollDraft) {
        if draft.poll != nil, draft.media.isEmpty {
            draft.poll = poll
            draft.kind = .poll
            persist()
            return
        }
        draft.poll = poll
        persist()
    }

    func persist(debounce: Bool = true) {
        guard !draft.accountID.isEmpty else { return }
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

    func saveAndExit() {
        persist(debounce: false)
        showExitPrompt = false
    }

    func publish() async -> SocialPost? {
        if let problem = validation {
            publishError = problem.accessibilityHint
            return nil
        }
        HapticEngine.shared.play(.confirmation)
        draft.state = .publishing
        persist(debounce: false)
        do {
            let post = try await publisher.publish(draft)
            draft.state = .published
            drafts.markPublished(id: draft.id)
            publishError = nil
            HapticEngine.shared.play(.success)
            return post
        } catch is CancellationError {
            draft.state = .cancelled
            persist(debounce: false)
            return nil
        } catch let api as APIError where api == .unauthenticated {
            draft.state = .failed
            persist(debounce: false)
            publishError = "Sign in to publish. Your draft is safe."
            HapticEngine.shared.play(.failure)
            return nil
        } catch {
            draft.state = .failed
            persist(debounce: false)
            publishError = "Couldn't publish your post. Your draft is safe."
            ModulaLog.app.error("create.publish.failed diagnostic=\(String(describing: error), privacy: .private)")
            HapticEngine.shared.play(.failure)
            return nil
        }
    }
}

enum CreationExitDecision {
    case dismiss
    case prompt
}
