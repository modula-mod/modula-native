import XCTest
@testable import Modula

final class N4CRouteTests: XCTestCase {
    func testMessagesCanonicalDefaultsAndRoundTrips() throws {
        XCTAssertEqual(RouteParser.parse("/messages"), .messages(.inbox))
        XCTAssertEqual(RouteSerializer.serialize(.messages(.inbox)), "/messages/inbox")
        let paths = [
            "/messages/inbox",
            "/messages/requests",
            "/messages/in-mail",
            "/messages/new",
            "/messages/conversation-1",
            "/messages/in-mail/new",
            "/messages/in-mail/thread-1",
            "/stories/story-1",
            "/stories/create",
            "/reels",
            "/reels/reel-1"
        ]
        for path in paths {
            let route = try XCTUnwrap(RouteParser.parse(path), path)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route, path)
        }
        XCTAssertEqual(RouteSerializer.serialize(.stories(.story("story-1"))), "/stories/story-1")
        XCTAssertEqual(RouteSerializer.serialize(.reels(.feed)), "/reels")
        XCTAssertNil(RouteParser.parse("/messages/inbox/extra"))
        XCTAssertEqual(RouteParser.parse("/stories/"), .stories(.root))
        XCTAssertEqual(RouteParser.parse("/stories"), .stories(.root))
        XCTAssertEqual(RouteParser.parse("/messages/inbox"), .messages(.inbox))
        XCTAssertNotEqual(RouteParser.parse("/messages/inbox"), .messages(.conversation("inbox")))
    }

    func testNotificationRouteResolver() {
        XCTAssertEqual(
            NotificationRouteResolver.route(kind: "conversation", identifier: "c1"),
            .messages(.conversation("c1"))
        )
        XCTAssertEqual(
            NotificationRouteResolver.route(kind: "in-mail", identifier: "t1"),
            .messages(.inMail(.thread("t1")))
        )
        XCTAssertEqual(NotificationRouteResolver.route(kind: "story", identifier: "s1"), .stories(.story("s1")))
        XCTAssertEqual(NotificationRouteResolver.route(kind: "reel", identifier: "r1"), .reels(.reel("r1")))
        XCTAssertNil(NotificationRouteResolver.route(kind: "conversation", identifier: "../x"))
        XCTAssertNil(NotificationRouteResolver.route(kind: "unknown", identifier: "x"))
    }
}

@MainActor
final class MessagingDomainTests: XCTestCase {
    func testConversationDecodingAndOrdering() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("c-old"),
                    "kind": .string("direct"),
                    "updatedAt": .string("2026-01-01T00:00:00Z"),
                    "unreadCount": .number(0),
                    "participants": .array([
                        .object(["id": .string("u1"), "handle": .string("sophia.chen"), "displayName": .string("Sophia Chen")])
                    ]),
                    "lastMessage": .object(["id": .string("m1"), "body": .string("Hi"), "sentAt": .string("2026-01-01T00:00:00Z")])
                ]),
                .object([
                    "id": .string("c-new"),
                    "kind": .string("direct"),
                    "updatedAt": .string("2026-09-01T00:00:00Z"),
                    "unreadCount": .number(2),
                    "participants": .array([
                        .object(["id": .string("u2"), "handle": .string("marcus"), "displayName": .string("Marcus")])
                    ])
                ])
            ]),
            "nextCursor": .string("cursor-2"),
            "hasMore": .bool(true)
        ])
        let page = MessagingPayloadDecoder.conversationPage(from: payload)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.nextCursor, "cursor-2")
        XCTAssertTrue(page.hasMore)
        let ordered = MessagingOrdering.conversationsNewestFirst(page.items)
        XCTAssertEqual(ordered.first?.id, "c-new")
        XCTAssertEqual(ordered.first?.unreadCount, 2)
        XCTAssertTrue(ordered.first?.isUnread == true)
        XCTAssertFalse(ordered.last?.isUnread == true)
    }

    func testMessageOrderingAndOwnFlag() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("m2"),
                    "body": .string("Second"),
                    "sentAt": .string("2026-09-01T00:02:00Z"),
                    "sender": .object(["id": .string("me"), "displayName": .string("You")])
                ]),
                .object([
                    "id": .string("m1"),
                    "body": .string("First"),
                    "sentAt": .string("2026-09-01T00:01:00Z"),
                    "sender": .object(["id": .string("u1"), "displayName": .string("Sophia")])
                ])
            ])
        ])
        let page = MessagingPayloadDecoder.messagePage(from: payload, conversationID: "c1", viewerID: "me")
        let ordered = MessagingOrdering.messagesChronological(page.items)
        XCTAssertEqual(ordered.map(\.id), ["m1", "m2"])
        XCTAssertFalse(ordered[0].isOwn)
        XCTAssertTrue(ordered[1].isOwn)
    }

    func testOptimisticSendRollbackPreservesDraft() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")),
            capabilities: MessagingBackendCapabilities()
        )
        store.drafts["c1"] = "Keep this"
        await store.send(conversation: "c1", viewer: MessagingFixtures.me)
        XCTAssertEqual(store.drafts["c1"], "Keep this")
        XCTAssertEqual(store.actionError, "Couldn't send message.")
    }

    func testRequestStateRestoreOnFailure() async {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        #if DEBUG
        store.installDebugRequests([MessagingFixtures.request])
        #endif
        let result = await store.acceptRequest(MessagingFixtures.request)
        XCTAssertNil(result)
        #if DEBUG
        XCTAssertEqual(store.requests.count, 1)
        #endif
    }

    func testLocalSearchDoesNotClaimServerHistory() {
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        XCTAssertTrue(store.searchIsLocalOnly)
        #if DEBUG
        store.installDebugInbox([MessagingFixtures.unreadConversation, MessagingFixtures.readConversation])
        store.conversationQuery = "sophia"
        XCTAssertEqual(store.visibleConversations.map(\.id), ["convo-sophia"])
        #endif
    }
}

@MainActor
final class InMailDomainTests: XCTestCase {
    func testSubjectRecipientAndBodyValidation() {
        XCTAssertNotNil(InMailValidation.subject(" "))
        XCTAssertNil(InMailValidation.subject("Partnership idea"))
        XCTAssertNotNil(InMailValidation.subject(String(repeating: "a", count: 181)))
        XCTAssertNotNil(InMailValidation.recipient(""))
        XCTAssertNil(InMailValidation.recipient("sophia.chen"))
        XCTAssertNotNil(InMailValidation.body("   "))
        XCTAssertNil(InMailValidation.body("Hello"))
    }

    func testThreadOrderingAndUnread() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("t1"),
                    "subject": .string("Partnership idea"),
                    "preview": .string("I wanted to ask"),
                    "unread": .bool(true),
                    "updatedAt": .string("2026-09-01T00:00:00Z"),
                    "participants": .array([
                        .object(["id": .string("u1"), "displayName": .string("Sophia Chen"), "handle": .string("sophia.chen")])
                    ])
                ])
            ])
        ])
        let page = InMailPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.items[0].subject, "Partnership idea")
        XCTAssertTrue(page.items[0].unread)
        let messages = InMailPayloadDecoder.messages(
            from: .object([
                "messages": .array([
                    .object([
                        "id": .string("im2"),
                        "body": .string("Reply"),
                        "createdAt": .string("2026-09-01T01:00:00Z"),
                        "sender": .object(["id": .string("me"), "displayName": .string("You")])
                    ]),
                    .object([
                        "id": .string("im1"),
                        "body": .string("Hello"),
                        "createdAt": .string("2026-09-01T00:00:00Z"),
                        "sender": .object(["id": .string("u1"), "displayName": .string("Sophia")])
                    ])
                ])
            ]),
            viewerID: "me"
        )
        let ordered = messages.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(ordered.map(\.id), ["im1", "im2"])
        XCTAssertTrue(ordered[1].isOwn)
    }

    func testDraftPersistsWhenSendUnavailable() async {
        let store = InMailStore(client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")))
        store.draft = InMailDraft(toHandle: "sophia.chen", subject: "Hi", body: "Body")
        let result = await store.sendDraft()
        XCTAssertNil(result)
        XCTAssertEqual(store.draft.body, "Body")
        XCTAssertEqual(store.sendState, .failed)
        XCTAssertEqual(store.sendError, "Couldn't send message.")
    }
}

@MainActor
final class StoryDomainTests: XCTestCase {
    func testGroupingSeenUnseenAndExpiry() {
        let groups = StoryGrouping.groups(from: [StoryFixtures.unseen, StoryFixtures.seen, StoryFixtures.own])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.author.id == MessagingFixtures.sophia.id }?.ring, .unseen)
        XCTAssertEqual(groups.first { $0.author.id == MessagingFixtures.marcus.id }?.ring, .seen)
        XCTAssertEqual(groups.first { $0.isOwn }?.ring, .own)
        XCTAssertNotNil(StoryFixtures.unseen.expiresAt)
    }

    func testProgressPauseResumeAndAdvance() {
        let engine = StoryProgressEngine(durations: [1, 1])
        XCTAssertEqual(engine.tick(0.5), .none)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        engine.pause()
        XCTAssertEqual(engine.tick(0.5), .none)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.001)
        engine.resume()
        XCTAssertEqual(engine.tick(0.5), .advanced)
        XCTAssertEqual(engine.index, 1)
        engine.isAppActive = false
        let pausedAt = engine.progress
        XCTAssertEqual(engine.tick(1), .none)
        XCTAssertEqual(engine.progress, pausedAt, accuracy: 0.001)
        engine.isAppActive = true
        XCTAssertEqual(engine.next(), .finished)
    }

    func testStoryRouteDoesNotInventIdentifiers() {
        XCTAssertNil(RouteParser.parse("/stories/ "))
        XCTAssertEqual(RouteParser.parse("/stories/create"), .stories(.create))
        XCTAssertNotEqual(RouteParser.parse("/stories/create"), .stories(.story("create")))
    }

    func testRailDecoderUsesGreenfieldDTO() {
        let value: JSONValue = .object([
            "items": .array([
                .object([
                    "groupId": .string("add:actor-1"),
                    "ownerActorId": .string("actor-1"),
                    "ownerProfileId": .string("profile-1"),
                    "displayName": .string("Andrei"),
                    "handle": .string("modula_orgggg"),
                    "avatarUrl": .string("https://api.modula.digital/v1/media/profiles/a.jpg"),
                    "ringState": .string("owner"),
                    "itemCount": .number(0),
                    "unviewedCount": .number(0),
                    "isOwner": .bool(true)
                ]),
                .object([
                    "groupId": .string("group-2"),
                    "ownerProfileId": .string("profile-2"),
                    "displayName": .string("Sophia"),
                    "handle": .string("sophia"),
                    "ringState": .string("unviewed"),
                    "itemCount": .number(2),
                    "isOwner": .bool(false)
                ])
            ])
        ])
        let groups = StoryPayloadDecoder.rail(from: value)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[0].isComposerPlaceholder)
        XCTAssertEqual(groups[0].ring, .own)
        XCTAssertEqual(groups[1].id, "group-2")
        XCTAssertEqual(groups[1].ring, .unseen)
        XCTAssertEqual(groups[1].author.displayName, "Sophia")
    }

    func testGroupDecoderUsesItemIdsAndMediaUrl() {
        let value: JSONValue = .object([
            "groupId": .string("group-2"),
            "displayName": .string("Sophia"),
            "handle": .string("sophia"),
            "isOwner": .bool(false),
            "items": .array([
                .object([
                    "itemId": .string("item-1"),
                    "mediaKind": .string("image"),
                    "mediaUrl": .string("https://api.modula.digital/v1/media/stories/item-1.jpg"),
                    "caption": .string("Hello"),
                    "viewed": .bool(false),
                    "createdAt": .string("2026-09-20T19:00:00.000Z")
                ])
            ])
        ])
        let group = StoryPayloadDecoder.group(value)
        XCTAssertEqual(group?.id, "group-2")
        XCTAssertEqual(group?.items.first?.id, "item-1")
        XCTAssertEqual(group?.items.first?.kind, .image)
        XCTAssertEqual(group?.items.first?.text, "Hello")
        XCTAssertEqual(group?.items.first?.media?.url?.lastPathComponent, "item-1.jpg")
        XCTAssertFalse(group?.items.first?.seen ?? true)
    }
}

@MainActor
final class ReelDomainTests: XCTestCase {
    func testCanonicalVideoPostPowersReelPlaybackAndEngagement() throws {
        let payload: JSONValue = .object(["post": .object([
            "id": .string("video-post"), "createdAt": .string("2026-09-30T12:00:00Z"),
            "author": .object(["id": .string("author"), "handle": .string("author"), "displayName": .string("Author")]),
            "kind": .string("media"), "text": .string("A real video #modula"), "saved": .bool(true),
            "content": .array([.object([
                "id": .string("block"), "type": .string("video"), "order": .number(0),
                "attachment": .object([
                    "id": .string("attachment"), "kind": .string("video"), "status": .string("ready"),
                    "mimeType": .string("video/mp4"), "filename": .string("video.mp4"),
                    "originalURL": .string("https://api.modula.digital/v1/attachments/attachment/content"),
                    "duration": .number(12)
                ])
            ])])
        ])])
        let reel = try XCTUnwrap(ReelPayloadDecoder.reel(payload))
        XCTAssertEqual(reel.postID, "video-post")
        XCTAssertEqual(reel.attachment?.id, "attachment")
        XCTAssertEqual(reel.attachment?.mimeType, "video/mp4")
        XCTAssertTrue(reel.media?.canPlayVideo == true)
        XCTAssertTrue(reel.asSocialPost().saved)
        XCTAssertEqual(reel.asSocialPost().media.first?.duration, 12)
    }

    func testSeedDecodingWithoutFakeVideo() {
        let payload: JSONValue = .object([
            "reels": .array([
                .object([
                    "id": .string("reel-1"),
                    "author": .string("Sophia"),
                    "caption": .string("Hello"),
                    "colour": .string("#369CAA"),
                    "liked": .bool(true),
                    "likeCount": .number(4),
                    "replyCount": .number(1)
                ])
            ])
        ])
        let page = ReelPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].caption, "Hello")
        XCTAssertNil(page.items[0].media?.url)
        XCTAssertNil(page.items[0].audio)
        XCTAssertTrue(page.items[0].engagement.liked)
        let post = page.items[0].asSocialPost()
        XCTAssertEqual(post.id, "reel-1")
        XCTAssertEqual(post.likeCount, 4)
    }

    func testActivePlaybackOwnershipAndRestoration() {
        let store = ReelStore(client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital")))
        #if DEBUG
        store.installDebugReels([
            ReelFixtures.preview,
            Reel(
                id: "reel-2",
                postID: "post-2",
                creator: SocialAuthor(id: "m", handle: "marcus", displayName: "Marcus", avatarURL: nil),
                media: nil,
                caption: "Two",
                audio: nil,
                posterColor: "#000000",
                engagement: PostEngagement(
                    liked: false, saved: false, reposted: false, viewerReaction: nil,
                    likeCount: 0, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0
                ),
                createdAt: Date()
            )
        ])
        XCTAssertEqual(store.activeID, "reel-preview")
        store.activate("reel-2")
        XCTAssertEqual(store.activeID, "reel-2")
        XCTAssertEqual(store.restoredID, "reel-2")
        XCTAssertEqual(store.index(of: "reel-2"), 1)
        #endif
        XCTAssertTrue(ReelBackendCapabilities.production.seedList)
        XCTAssertTrue(ReelBackendCapabilities.production.videoPlayback)
        XCTAssertFalse(ReelBackendCapabilities.production.audioAttribution)
    }

    func testDiscoverDashboardDecodesReelsWithoutFabricatingFeed() {
        let payload: JSONValue = .object([
            "suggestedProfiles": .array([]),
            "trendingTopics": .array([]),
            "featuredModules": .array([]),
            "media": .array([]),
            "reels": .array([
                .object(["id": .string("r1"), "caption": .string("Seed"), "colour": .string("#111")])
            ])
        ])
        let dash = DiscoverPayloadDecoder.dashboard(from: payload)
        XCTAssertEqual(dash.reels.count, 1)
        XCTAssertEqual(dash.reels[0].id, "r1")
    }
}

final class ProfileCustomizationTests: XCTestCase {
    func testHeadlineLanguagesAndAccentDecode() {
        let payload: JSONValue = .object([
            "id": .string("p1"),
            "handle": .string("ada"),
            "displayName": .string("Ada"),
            "bio": .string("Notes"),
            "headline": .string("Founder of Modula"),
            "languages": .array([.string("English"), .string("Romanian")]),
            "presentation": .object(["accent": .string("violet")]),
            "location": .object(["label": .string("United Kingdom"), "visibility": .string("public")]),
            "email": .string("hidden@example.com"),
            "links": .array([
                .object([
                    "id": .string("l1"),
                    "label": .string("Site"),
                    "url": .string("https://modula.digital"),
                    "visibility": .string("public")
                ]),
                .object([
                    "id": .string("l2"),
                    "label": .string("Private"),
                    "url": .string("https://secret.example"),
                    "visibility": .string("private")
                ])
            ])
        ])
        let profile = ProfilePayloadDecoder.profile(from: payload)
        XCTAssertEqual(profile?.headline, "Founder of Modula")
        XCTAssertEqual(profile?.languages, ["English", "Romanian"])
        XCTAssertEqual(profile?.presentation.accent, .violet)
        XCTAssertTrue(ProfileFieldPrivacy.blockedKeys.contains("email"))
        let visitor = profile?.visitorVisible
        XCTAssertEqual(visitor?.publicLinks.count, 1)
        XCTAssertFalse(visitor?.links.contains(where: { $0.visibility == .private }) ?? true)
    }

    func testEditDraftIncludesPresentationWithoutClaimingWrites() {
        let profile = ModulaProfile(
            id: "p1",
            handle: "ada",
            displayName: "Ada",
            kind: "person",
            avatarURL: nil,
            coverURL: nil,
            coverColour: nil,
            bio: "Notes",
            headline: "Founder of Modula",
            pronouns: nil,
            location: nil,
            website: nil,
            languages: ["English"],
            presentation: ProfilePresentation(accent: .violet, featuredModuleIDs: ["digital.modula.vault-notes"], featuredLinkIDs: []),
            coverFocalPoint: CoverFocalPoint(x: 0.4, y: 0.6),
            followerCount: 0,
            followingCount: 0,
            moduleCount: 0,
            postCount: 0,
            joinedAt: nil,
            focusStatus: nil,
            identityClaims: [],
            links: [],
            featuredModuleIds: ["digital.modula.vault-notes"],
            isFollowing: false,
            followsViewer: false,
            version: 3,
            visibility: .public
        )
        let draft = ProfileEditDraft.from(profile)
        XCTAssertEqual(draft.headline, "Founder of Modula")
        XCTAssertEqual(draft.accent, .violet)
        XCTAssertEqual(draft.featuredModuleIDs, ["digital.modula.vault-notes"])
        XCTAssertFalse(ProfileCustomizationCapabilities.production.accentWritable)
        XCTAssertFalse(ProfileCustomizationCapabilities.production.featuredModulesWritable)
    }

    func testAppAccentAndProfileAccentRemainDistinct() {
        XCTAssertEqual(AppearanceStore.Accent.violet.hex, ProfileAccent.violet.hex)
        XCTAssertEqual(ProfileAccent.violet.title, "Violet")
    }
}

final class MediaPipelineTests: XCTestCase {
    func testMediaResourceDecoding() {
        let value: JSONValue = .object([
            "id": .string("m1"),
            "kind": .string("video"),
            "url": .string("https://cdn.example/a.mp4"),
            "posterUrl": .string("https://cdn.example/a.jpg"),
            "duration": .number(12),
            "width": .number(1080),
            "height": .number(1920)
        ])
        let media = MediaPayloadDecoder.resource(from: value, fallbackID: "m1")
        XCTAssertEqual(media?.kind, .video)
        XCTAssertTrue(media?.canPlayVideo == true)
        XCTAssertEqual(media?.duration, 12)
        XCTAssertEqual(media?.dimensions?.width, 1080)
    }
}

final class MessagingCapabilityHonestyTests: XCTestCase {
    func testProductionCapabilitiesStayClosedUntilVPS() {
        XCTAssertFalse(MessagingBackendCapabilities.production.listConversations)
        XCTAssertFalse(MessagingBackendCapabilities.production.send)
        XCTAssertFalse(MessagingBackendCapabilities.production.realtime)
        XCTAssertFalse(MessagingBackendCapabilities.production.readReceipts)
        XCTAssertFalse(MessagingBackendCapabilities.production.attachments)
        XCTAssertFalse(InMailBackendCapabilities.production.list)
        XCTAssertFalse(InMailBackendCapabilities.production.privacySettings)
        XCTAssertTrue(StoryBackendCapabilities.production.list)
        XCTAssertTrue(StoryBackendCapabilities.production.create)
        XCTAssertTrue(ReelBackendCapabilities.production.seedList)
        XCTAssertFalse(ReelBackendCapabilities.production.rankedFeed)
    }
}
