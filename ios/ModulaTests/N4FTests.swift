import XCTest
@testable import Modula

final class CreationRouteTests: XCTestCase {
    func testComposeRoutesRoundTrip() {
        for route in ComposeRoute.allCases {
            let appRoute = AppRoute.compose(route)
            let path = RouteSerializer.serialize(appRoute)
            XCTAssertEqual(RouteParser.parse(path), appRoute, path)
        }
        XCTAssertEqual(RouteParser.parse("/stories/create"), .stories(.create))
        XCTAssertEqual(RouteParser.parse("/reels"), .reels(.feed))
    }

    func testComposeChromeHidesShell() {
        let policy = ShellChromePolicy.policy(for: .compose(.post), isTabRoot: false)
        XCTAssertFalse(policy.bottomBarVisible)
        XCTAssertFalse(policy.shellAccessoryVisible)
        XCTAssertFalse(policy.contextRailVisible)
        XCTAssertFalse(policy.showsBack)
        XCTAssertEqual(policy.topBarStyle, .hidden)
    }
}

final class CreationCapabilityTests: XCTestCase {
    func testProductionGates() {
        let caps = CreationCapabilities.production
        XCTAssertTrue(caps.textPost)
        XCTAssertTrue(caps.canPublish(.post))
        XCTAssertFalse(caps.canPublish(.photo))
        XCTAssertFalse(caps.canPublish(.carousel))
        XCTAssertFalse(caps.canPublish(.video))
        XCTAssertFalse(caps.canPublish(.link))
        XCTAssertFalse(caps.canPublish(.poll))
        XCTAssertFalse(caps.canPublish(.audio))
        XCTAssertFalse(caps.canPublish(.movie))
        XCTAssertFalse(caps.canPublish(.story))
        XCTAssertFalse(caps.canPublish(.reel))
        XCTAssertNil(caps.characterLimit)
        XCTAssertFalse(caps.toolVisible(.photo, kind: .post, developerMode: false))
        XCTAssertTrue(caps.toolVisible(.photo, kind: .post, developerMode: true))
    }

    func testCreateActionsHideUnavailableKinds() {
        let caps = CommandCapabilitySnapshot(signedIn: true, photoCompose: false, pollCompose: false, storyCreate: false)
        let actions = CreateActionRegistry.actions(capabilities: caps)
        XCTAssertTrue(actions.contains { $0.id == "post" })
        XCTAssertFalse(actions.contains { $0.id == "photo" && $0.availability == .available })
        XCTAssertFalse(actions.contains { $0.id == "poll" && $0.availability == .available })
    }
}

final class CreationDraftTests: XCTestCase {
    @MainActor
    func testAutosaveRestoreDiscardAndAccountIsolation() async throws {
        let storeA = DraftStore(
            fileStore: PrivateFileStore(domain: .drafts),
            mediaStore: DraftMediaStore(),
            autosaveMilliseconds: 5
        )
        storeA.setAccountID("acct-a")
        storeA.discardPost(id: "n4f-a")
        let draft = CreationDraft.fresh(kind: .post, accountID: "acct-a", audience: .followers)
        var writable = draft
        writable.id = "n4f-a"
        writable.text = "Native creation studio"
        storeA.upsertCreation(writable, debounce: false)
        XCTAssertEqual(storeA.creationDraft(id: "n4f-a")?.text, "Native creation studio")
        XCTAssertEqual(storeA.creationDraft(id: "n4f-a")?.audience, .followers)

        storeA.setAccountID("acct-b")
        XCTAssertNil(storeA.creationDraft(id: "n4f-a"))

        storeA.setAccountID("acct-a")
        XCTAssertEqual(storeA.creationDraft(id: "n4f-a")?.preview.contains("Native"), true)

        storeA.discardPost(id: "n4f-a")
        XCTAssertNil(storeA.creationDraft(id: "n4f-a"))
    }

    @MainActor
    func testMultipleDraftsAndPublishCleanup() {
        let store = DraftStore(autosaveMilliseconds: 1)
        store.setAccountID("acct-multi")
        var one = CreationDraft.fresh(kind: .post, accountID: "acct-multi", audience: .everyone)
        one.id = "draft-one"
        one.text = "First"
        var two = CreationDraft.fresh(kind: .post, accountID: "acct-multi", audience: .everyone)
        two.id = "draft-two"
        two.text = "Second"
        store.upsertCreation(one, debounce: false)
        store.upsertCreation(two, debounce: false)
        XCTAssertEqual(store.countsByKind[.post], 2)
        store.markPublished(id: "draft-one")
        XCTAssertNil(store.creationDraft(id: "draft-one"))
        XCTAssertEqual(store.creationDraft(id: "draft-two")?.text, "Second")
        store.discardPost(id: "draft-two")
    }

    @MainActor
    func testPublishFailureRetainsDraft() async {
        let drafts = DraftStore(autosaveMilliseconds: 1)
        drafts.setAccountID("acct-fail")
        var draft = CreationDraft.fresh(kind: .post, accountID: "acct-fail", audience: .everyone)
        draft.id = "fail-draft"
        draft.text = "Keep me"
        drafts.upsertCreation(draft, debounce: false)
        let store = CreationStudioStore(
            kind: .post,
            accountID: "acct-fail",
            originPath: "/home/following",
            drafts: drafts,
            mediaStore: DraftMediaStore(),
            publisher: MockPublishingRepository(behavior: .failure),
            uploader: DisabledMediaUploader(),
            capabilities: .production
        )
        store.draft = draft
        let published = await store.publish()
        XCTAssertNil(published)
        XCTAssertEqual(store.publishError, "Couldn't publish your post. Your draft is safe.")
        XCTAssertEqual(drafts.creationDraft(id: "fail-draft")?.text, "Keep me")
        drafts.discardPost(id: "fail-draft")
    }

    func testShareExtensionFactory() {
        let draft = CreationDraft.fromShare(
            text: "Hello",
            url: URL(string: "https://modula.digital"),
            imageIDs: [],
            accountID: "acct"
        )
        XCTAssertEqual(draft.kind, .link)
        XCTAssertEqual(draft.link?.urlString, "https://modula.digital")
        XCTAssertEqual(draft.text, "Hello")
    }
}

final class CreationValidationTests: XCTestCase {
    func testEmptyAndCapabilityOff() {
        let caps = CreationCapabilities.production
        var draft = CreationDraft.fresh(kind: .post, accountID: "acct", audience: .everyone)
        XCTAssertEqual(CreationValidator.problem(for: draft, capabilities: caps), .empty)
        draft.text = "Hello"
        XCTAssertNil(CreationValidator.problem(for: draft, capabilities: caps))
        draft.kind = .video
        XCTAssertEqual(CreationValidator.problem(for: draft, capabilities: caps), .kindUnavailable(.video))
        draft.kind = .poll
        draft.poll = PollDraft.blank()
        XCTAssertEqual(CreationValidator.problem(for: draft, capabilities: caps), .kindUnavailable(.poll))
    }

    func testPayloadEncoderKeys() {
        var draft = CreationDraft.fresh(kind: .post, accountID: "acct", audience: .followers)
        draft.text = "  Hello world  "
        draft.idempotencyKey = "idem-1"
        let body = CreationPayloadEncoder.textPostBody(from: draft)
        XCTAssertEqual(CreationPayloadEncoder.keys(in: body), ["audience", "idempotencyKey", "kind", "text"])
        XCTAssertEqual(body["kind"]?.string, "text")
        XCTAssertEqual(body["audience"]?.string, "followers")
        XCTAssertEqual(body["text"]?.string, "Hello world")
        XCTAssertNil(body["media"])
        XCTAssertNil(body["poll"])
        XCTAssertNil(body["mentions"])
    }

    func testMentionsAndTopicsAreExtractedNotInvented() {
        let text = "Hello @sophia and #native from Modula"
        XCTAssertEqual(CreationEntityParser.mentions(in: text).map(\.handle), ["sophia"])
        XCTAssertEqual(CreationEntityParser.topics(in: text), ["native"])
        XCTAssertEqual(CreationEntityParser.firstURL(in: "See https://modula.digital/docs")?.host, "modula.digital")
    }
}

final class CreationMediaTests: XCTestCase {
    func testJPEGPreparationStripsToJPEG() async throws {
        let png = tinyPNG()
        let prepared = try await MediaPreparation.jpegStrippingMetadata(png, maxPixel: 32, quality: 0.8)
        XCTAssertFalse(prepared.data.isEmpty)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertGreaterThan(prepared.width, 0)
    }

    func testDraftMediaCleanupAndCacheClearIsolation() throws {
        let mediaStore = DraftMediaStore()
        let jpeg = try MediaPreparation.jpegStrippingMetadataSync(tinyPNG(), maxPixel: 16, quality: 0.7)
        let media = try mediaStore.importJPEG(jpeg.data, accountID: "acct-media", id: "media-1", width: jpeg.width, height: jpeg.height)
        XCTAssertNotNil(try mediaStore.read(media))
        XCTAssertGreaterThan(mediaStore.byteCount(accountID: "acct-media"), 0)
        StorageUsageSnapshot.clearCache()
        XCTAssertNotNil(try mediaStore.read(media), "Clear cache must not delete draft media")
        mediaStore.cleanupOrphans(referenced: [], accountID: "acct-media")
        XCTAssertNil(try mediaStore.read(media))
    }

    func testUploadMockProgressSuccessFailureCancel() async throws {
        let prepared = PreparedMedia(
            id: "m1",
            kind: .image,
            data: Data([0xFF, 0xD8]),
            mimeType: "image/jpeg",
            filename: "m1.jpg",
            altText: "A photo"
        )
        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Double] = []
            func append(_ value: Double) {
                lock.lock()
                values.append(value)
                lock.unlock()
            }
            var isEmpty: Bool {
                lock.lock()
                defer { lock.unlock() }
                return values.isEmpty
            }
        }
        let fractions = ProgressBox()
        let success = try await MockMediaUploader(behavior: .success).upload(prepared) { fractions.append($0) }
        XCTAssertEqual(success.remoteID, "remote-m1")
        XCTAssertFalse(fractions.isEmpty)
        do {
            _ = try await MockMediaUploader(behavior: .failure).upload(prepared) { _ in }
            XCTFail("expected failure")
        } catch MediaUploadError.failed {}
        do {
            _ = try await MockMediaUploader(behavior: .cancel).upload(prepared) { _ in }
            XCTFail("expected cancel")
        } catch MediaUploadError.cancelled {}
        do {
            _ = try await DisabledMediaUploader().upload(prepared) { _ in }
            XCTFail("disabled uploader must not succeed")
        } catch MediaUploadError.unavailable {}
    }

    private func tinyPNG() -> Data {
        let png: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
            0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
            0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
            0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(png)
    }
}

final class CreationPublishingTests: XCTestCase {
    @MainActor
    func testSuccessfulPublishIngestsCanonicalPost() async throws {
        let post = SocialPost(
            id: "pub-1",
            author: SocialAuthor(id: "acct", handle: "andrei", displayName: "Andrei", avatarURL: nil),
            createdAt: Date(),
            editedAt: nil,
            feed: "following",
            text: "Hello",
            kind: .text,
            visibility: .public,
            audience: "public",
            media: [],
            link: nil,
            module: nil,
            glowColour: nil,
            engagement: PostEngagement(
                liked: false, saved: false, reposted: false, viewerReaction: nil,
                likeCount: 0, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0
            )
        )
        let drafts = DraftStore(autosaveMilliseconds: 1)
        drafts.setAccountID("acct")
        var draft = CreationDraft.fresh(kind: .post, accountID: "acct", audience: .everyone)
        draft.id = "to-publish"
        draft.text = "Hello"
        drafts.upsertCreation(draft, debounce: false)
        let store = CreationStudioStore(
            kind: .post,
            accountID: "acct",
            originPath: "/home/following",
            drafts: drafts,
            mediaStore: DraftMediaStore(),
            publisher: MockPublishingRepository(behavior: .success(post)),
            uploader: DisabledMediaUploader(),
            capabilities: .production
        )
        store.draft = draft
        let result = await store.publish()
        XCTAssertEqual(result?.id, "pub-1")
        XCTAssertNil(drafts.creationDraft(id: "to-publish"))
    }

    func testAudienceValuesAreGreenfieldOnly() {
        XCTAssertEqual(AudienceSelection.allCases.map(\.greenfieldValue), ["public", "followers", "private"])
        XCTAssertEqual(AudienceSelection(greenfield: "followers"), .followers)
        XCTAssertEqual(AudienceSelection(greenfield: "mystery"), .everyone)
    }
}

final class CreationAccessibilityModelTests: XCTestCase {
    func testPublishHintsAndPollMinimum() {
        var draft = CreationDraft.fresh(kind: .post, accountID: "acct", audience: .everyone)
        XCTAssertEqual(CreationValidator.problem(for: draft, capabilities: .production)?.accessibilityHint, "Write something to publish.")
        draft.text = "Hi"
        draft.kind = .photo
        XCTAssertTrue(CreationValidator.problem(for: draft, capabilities: .production)?.accessibilityHint.contains("available") == true)
        XCTAssertEqual(PollDraft.minimumOptions, 2)
    }

    func testAppIntentStillOpensComposerOnly() {
        XCTAssertEqual(ModulaAppIntentBridge.route(for: "create.post", parameter: nil), .compose(.post))
    }
}
