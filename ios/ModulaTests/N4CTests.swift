import ImageIO
import UIKit
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
            "/messages/to/andrei.modula",
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

    func testDirectConversationMatchesHandleOrIDNeverInbox() {
        XCTAssertEqual(RouteParser.parse("/messages/to/andrei.modula"), .messages(.direct("andrei.modula")))
        XCTAssertNil(RouteParser.parse("/messages/to"))
        let store = MessagingStore(
            client: GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        )
        #if DEBUG
        store.installDebugInbox([MessagingFixtures.unreadConversation, MessagingFixtures.readConversation])
        XCTAssertEqual(store.directConversation(with: "sophia.chen")?.id, "convo-sophia")
        XCTAssertEqual(store.directConversation(with: "@Sophia.Chen")?.id, "convo-sophia")
        XCTAssertEqual(store.directConversation(with: MessagingFixtures.unreadConversation.participants[0].id)?.id, "convo-sophia")
        XCTAssertNil(store.directConversation(with: "nobody.here"))
        XCTAssertNil(store.directConversation(with: ""))
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

    /// Prod regression: `GET /v1/stories/rail` returns the owner's real group as a summary
    /// (`itemCount` > 0, no `items`). It must not be mistaken for the "add:" composer tile.
    func testOwnRailSummaryWithItemsIsALiveStoryNotTheComposer() {
        let value: JSONValue = .object(["items": .array([.object([
            "groupId": .string("66ca2bf3-edfc-4c14-9ab6-307401d8ea47"),
            "ownerActorId": .string("actor-1"),
            "ownerProfileId": .string("profile-1"),
            "displayName": .string("Andrei"),
            "handle": .string("modula_orgggg"),
            "ringState": .string("owner"),
            "itemCount": .number(4),
            "unviewedCount": .number(4),
            "expiresAt": .string("2026-10-02T12:43:59.850Z"),
            "isOwner": .bool(true)
        ])])])
        let own = StoryPayloadDecoder.rail(from: value)[0]
        XCTAssertTrue(own.isOwn)
        XCTAssertEqual(own.itemCount, 4)
        XCTAssertTrue(own.hasStories)
        XCTAssertFalse(own.isComposerPlaceholder, "A posted story must open the viewer, not the composer")
        XCTAssertTrue(own.needsHydration)
    }

    /// The exact envelope shape `POST /v1/stories` returns (201, `ok/data/meta`, null fields).
    func testCreateResponseEnvelopeDecodesToOwnGroup() throws {
        let body = """
        {"ok":true,"data":{"groupId":"g-1","ownerActorId":"actor-1","ownerProfileId":"profile-1",
        "displayName":"Andrei","handle":"modula_orgggg","avatarUrl":null,"visibility":"public",
        "expiresAt":"2026-10-02T12:43:59.850Z","isOwner":true,"items":[
        {"itemId":"i-1","groupId":"g-1","mediaKind":"image","mediaUrl":"https://api.modula.digital/v1/media/stories/i-1.jpg",
        "caption":null,"status":"ready","durationMs":5000,"viewed":false,"createdAt":"2026-10-01T12:42:32.745Z"},
        {"itemId":"i-2","groupId":"g-1","mediaKind":"image","mediaUrl":"https://api.modula.digital/v1/media/stories/i-2.jpg",
        "caption":"Hi","status":"ready","durationMs":5000,"viewed":false,"createdAt":"2026-10-01T12:43:59.850Z"}]},
        "meta":{"requestId":"req-1","serverTime":"2026-10-01T12:43:59.900Z"}}
        """
        let url = try XCTUnwrap(URL(string: "https://api.modula.digital/v1/stories"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        let value: JSONValue = try GreenfieldClient.decodeEnvelope(Data(body.utf8), response: response, method: "POST", path: "/v1/stories")
        let group = try XCTUnwrap(StoryPayloadDecoder.group(value))
        XCTAssertEqual(group.id, "g-1")
        XCTAssertTrue(group.isOwn)
        XCTAssertEqual(group.items.map(\.id), ["i-1", "i-2"])
        XCTAssertEqual(group.items.first?.media?.url?.host, "api.modula.digital")
        XCTAssertNil(group.items.first?.text)
        XCTAssertFalse(group.isComposerPlaceholder)
        XCTAssertFalse(group.needsHydration)
    }

    /// After Share the store holds the full group; the follow-up rail refresh must keep it.
    func testRailRefreshKeepsPublishedItemsAndRehydratesWhenCountGrows() {
        let me = ConversationParticipant(id: "profile-1", handle: "me", displayName: "Me", avatarURL: nil)
        let item = StoryItem(id: "i-1", author: me, createdAt: Date(), expiresAt: nil, kind: .image, media: nil,
                             text: nil, background: nil, seen: false, isOwn: true, viewerCount: nil)
        let published = StoryGroup(id: "g-1", author: me, items: [item], isOwn: true, reportedRing: .own, itemCount: 1)
        let summary = StoryGroup(id: "g-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 1)

        let merged = StoryStore.merge(rail: [summary], previous: [published])
        XCTAssertEqual(merged.first?.items.map(\.id), ["i-1"])
        XCTAssertFalse(merged.first?.isComposerPlaceholder ?? true)
        XCTAssertFalse(merged.first?.needsHydration ?? true)

        var grown = summary
        grown.itemCount = 2
        let refreshed = StoryStore.merge(rail: [grown], previous: [published])
        XCTAssertTrue(refreshed.first?.items.isEmpty ?? false, "Stale items are dropped when the rail reports more")
        XCTAssertTrue(refreshed.first?.needsHydration ?? false)
        XCTAssertFalse(refreshed.first?.isComposerPlaceholder ?? true)

        let placeholder = StoryGroup(id: "add:actor-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 0)
        XCTAssertTrue(StoryStore.merge(rail: [placeholder], previous: [published]).first?.isComposerPlaceholder ?? false)
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
    func testProductionCapabilitiesMatchLiveVPSRoutes() {
        // Live since backend migration 075_greenfield_messaging.
        XCTAssertTrue(MessagingBackendCapabilities.production.listConversations)
        XCTAssertTrue(MessagingBackendCapabilities.production.send)
        XCTAssertTrue(MessagingBackendCapabilities.production.messageRequests)
        XCTAssertTrue(MessagingBackendCapabilities.production.readReceipts)
        XCTAssertTrue(InMailBackendCapabilities.production.list)
        XCTAssertTrue(InMailBackendCapabilities.production.reply)
        // Still not implemented server-side.
        XCTAssertFalse(MessagingBackendCapabilities.production.realtime)
        XCTAssertFalse(MessagingBackendCapabilities.production.attachments)
        XCTAssertFalse(MessagingBackendCapabilities.production.typing)
        XCTAssertFalse(InMailBackendCapabilities.production.privacySettings)
        XCTAssertFalse(InMailBackendCapabilities.production.serverSearch)
        XCTAssertTrue(StoryBackendCapabilities.production.list)
        XCTAssertTrue(StoryBackendCapabilities.production.create)
        XCTAssertTrue(ReelBackendCapabilities.production.seedList)
        XCTAssertFalse(ReelBackendCapabilities.production.rankedFeed)
    }
}

// MARK: - Story upload budget and non-JSON HTTP errors

private final class StubHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var contentType = "application/json"
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GreenfieldNonJSONErrorTests: XCTestCase {
    private let nginx413 = Data("""
    <html>
    <head><title>413 Request Entity Too Large</title></head>
    <body>
    <center><h1>413 Request Entity Too Large</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>
    """.utf8)

    private func response(_ status: Int, type: String = "text/html; charset=utf-8") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://native-n1.modula.digital/v1/stories")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    }

    func testNginxHTML413MapsToPayloadTooLarge() {
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(nginx413, response: response(413), method: "POST", path: "/v1/stories") as JSONValue
        ) { error in
            XCTAssertEqual(error as? APIError, .rejected(413, "PAYLOAD_TOO_LARGE"))
            XCTAssertEqual((error as? APIError)?.userFacingMessage, "That file is too large to upload. Try a smaller photo.")
        }
    }

    func testHTML5xxMapsToServerUnavailable() {
        for status in [500, 502, 503, 504] {
            XCTAssertThrowsError(
                try GreenfieldClient.decodeEnvelope(Data("<html>Bad Gateway</html>".utf8), response: response(status),
                                                    method: "GET", path: "/v1/stories/rail") as JSONValue
            ) { error in
                XCTAssertEqual(error as? APIError, .rejected(status, "SERVER_UNAVAILABLE"))
                XCTAssertEqual((error as? APIError)?.userFacingMessage, "Modula is having trouble right now. Try again in a moment.")
            }
        }
    }

    func testNonJSON429AndOtherStatuses() {
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 429), .rejected(429, "RATE_LIMITED"))
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 200), .invalidResponse)
        XCTAssertEqual(GreenfieldClient.nonEnvelopeError(status: 404), .invalidResponse)
    }

    func testJSONEnvelopeErrorsKeepServerCode() {
        let body = Data(#"{"ok":false,"error":{"code":"VALIDATION_FAILED","message":"x"}}"#.utf8)
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(body, response: response(400, type: "application/json"),
                                                method: "POST", path: "/v1/stories") as JSONValue
        ) { error in
            XCTAssertEqual(error as? APIError, .rejected(400, "VALIDATION_FAILED"))
        }
        let json5xx = Data(#"{"ok":false,"error":{"code":"SERVER_ERROR"}}"#.utf8)
        XCTAssertEqual(
            APIError.rejected(500, "SERVER_ERROR").userFacingMessage,
            "Modula is having trouble right now. Try again in a moment."
        )
        XCTAssertThrowsError(
            try GreenfieldClient.decodeEnvelope(json5xx, response: response(500, type: "application/json"),
                                                method: "POST", path: "/v1/stories") as JSONValue
        )
    }

    func testClientSurfacesProxy413AsAPIError() async {
        StubHTTPProtocol.status = 413
        StubHTTPProtocol.contentType = "text/html"
        StubHTTPProtocol.body = nginx413
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTPProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://stub.modula.invalid"), transport: URLSession(configuration: configuration))
        do {
            _ = try await client.publicJSON("POST", path: "/v1/stories", body: .object([:]))
            XCTFail("Expected a 413 rejection")
        } catch {
            XCTAssertEqual(error as? APIError, .rejected(413, "PAYLOAD_TOO_LARGE"))
        }
    }
}

final class StoryUploadBudgetTests: XCTestCase {
    func testBudgetDerivesFromSingleBodyConstantUnderServerLimit() {
        XCTAssertEqual(StoryUploadBudget.maximumBodyBytes, 20_000_000)
        XCTAssertLessThan(StoryUploadBudget.maximumBodyBytes, 25 * 1_048_576, "server JSON/edge body limit")
        let budget = StoryUploadBudget.imageByteBudget(captionByteCount: 0)
        XCTAssertGreaterThan(budget, 14_000_000)
        XCTAssertLessThan(Double(budget) * 4 / 3 * 1.02, Double(StoryUploadBudget.maximumBodyBytes))
        XCTAssertLessThan(StoryUploadBudget.imageByteBudget(captionByteCount: 2_000), budget)
        XCTAssertEqual(StoryUploadBudget.targetLongEdge, 3072)
        XCTAssertEqual(StoryUploadBudget.minimumLongEdge, 3072)
        XCTAssertEqual(StoryUploadBudget.preferredQuality, 0.9)
        XCTAssertEqual(StoryUploadBudget.requestTimeout, 120)
    }

    func testLargePreparedPhotoKeepsFullScreenResolutionWithinBudget() async throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG())
        let prepared = try MediaPreparation.jpegStrippingMetadataSync(
            source, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
        )
        XCTAssertEqual(max(prepared.width, prepared.height), 3072)
        XCTAssertGreaterThan(prepared.data.count, 1_048_576, "fixture must exceed the old 1 MiB proxy limit")

        let body = try await StoryBackendRepository.uploadableBody(image: prepared, caption: "Golden hour", visibility: "public")
        let encoded = try JSONEncoder().encode(body)
        XCTAssertLessThanOrEqual(encoded.count, StoryUploadBudget.maximumBodyBytes)
        XCTAssertEqual(body["contentType"]?.string, "image/jpeg")
        XCTAssertEqual(body["caption"]?.string, "Golden hour")
        let data = try XCTUnwrap(body["base64"]?.string.flatMap { Data(base64Encoded: $0) })
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(max(image.width, image.height), 3072, "full-screen long edge is kept")
        XCTAssertEqual(data, prepared.data, "q0.9 3072px fits the budget, so it is sent unchanged")
        XCTAssertEqual(body["width"]?.number, Double(image.width))
        XCTAssertEqual(body["height"]?.number, Double(image.height))
        XCTAssertNil((CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])?[kCGImagePropertyGPSDictionary])
        print("story-fit prepared=\(prepared.data.count)B \(prepared.width)x\(prepared.height) sent=\(data.count)B \(image.width)x\(image.height) body=\(encoded.count)B")
    }

    func testQualityStepsDownBeforeResolution() throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG())
        let full = try MediaPreparation.jpegFittingSync(source, maxBytes: .max)
        XCTAssertEqual(max(full.width, full.height), 3072)
        // A budget just under the q0.9 size must be met at 3072px by lowering quality.
        let fitted = try MediaPreparation.jpegFittingSync(source, maxBytes: full.data.count - 1)
        XCTAssertEqual(max(fitted.width, fitted.height), 3072)
        XCTAssertLessThan(fitted.data.count, full.data.count)
        // Only when 3072px at the lowest quality can't fit does resolution drop.
        let squeezed = try MediaPreparation.jpegFittingSync(source, maxBytes: 1_500_000)
        XCTAssertLessThan(max(squeezed.width, squeezed.height), 3072)
        XCTAssertLessThanOrEqual(squeezed.data.count, 1_500_000)
    }

    func testSmallPhotoIsSentUnchanged() async throws {
        let small = try MediaPreparation.jpegStrippingMetadataSync(
            try XCTUnwrap(StoryUITestPhoto.detailedJPEG(width: 200, height: 300)), maxPixel: 3072, quality: 0.9
        )
        let body = try await StoryBackendRepository.uploadableBody(image: small, caption: "  ", visibility: "followers")
        XCTAssertEqual(body["base64"]?.string, small.data.base64EncodedString())
        XCTAssertNil(body["caption"])
        XCTAssertEqual(body["visibility"]?.string, "followers")
    }

    func testFittingReportsImpossibleBudget() throws {
        let source = try XCTUnwrap(StoryUITestPhoto.detailedJPEG(width: 1200, height: 1600))
        XCTAssertThrowsError(try MediaPreparation.jpegFittingSync(source, maxBytes: 2_000)) { error in
            XCTAssertEqual(error as? MediaPreparationError, .exceedsByteBudget)
        }
        let fitted = try MediaPreparation.jpegFittingSync(source, maxBytes: 1_500_000)
        XCTAssertLessThanOrEqual(fitted.data.count, 1_500_000)
        XCTAssertEqual(max(fitted.width, fitted.height), 1600, "never upscales")
    }
}

// MARK: - Session recovery (prod: POST /v1/stories → 401 after the session was revoked)

private final class SessionRouterProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var log: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.log.append("\(request.httpMethod ?? "GET") \(path) \(request.value(forHTTPHeaderField: "Authorization") ?? "-")")
        let (status, body) = Self.handler?(request) ?? (500, "{}")
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GreenfieldSessionRecoveryTests: XCTestCase {
    private static func tokens(_ n: Int, accessMinutes: Double = 15) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let access = f.string(from: Date().addingTimeInterval(accessMinutes * 60))
        let refresh = f.string(from: Date().addingTimeInterval(30 * 86_400))
        return #"{"ok":true,"data":{"accessToken":"access-\#(n)","refreshToken":"refresh-\#(n)","sessionId":"s","accessExpiresAt":"\#(access)","refreshExpiresAt":"\#(refresh)"}}"#
    }
    private static let me = #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#
    private static let unauthorized = #"{"ok":false,"error":{"code":"UNAUTHENTICATED"}}"#

    private func makeClient() -> GreenfieldClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        SessionRouterProtocol.log = []
        return GreenfieldClient(baseURL: URL(string: "https://session-test-\(UUID().uuidString.prefix(8)).modula.test")!,
                                transport: URLSession(configuration: config))
    }

    override func tearDown() {
        SessionRouterProtocol.handler = nil
        super.tearDown()
    }

    func testRejectedAccessTokenRefreshesOnceAndRetries() async throws {
        let client = makeClient()
        SessionRouterProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            case ("POST", "/v1/sessions/refresh"): return (200, Self.tokens(2))
            case ("POST", "/v1/stories"):
                return auth == "Bearer access-2" ? (201, #"{"ok":true,"data":{"groupId":"g"}}"#) : (401, Self.unauthorized)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let value = try await client.authenticatedJSON("POST", path: "/v1/stories", body: .object([:]))
        XCTAssertEqual(value["groupId"]?.string, "g")
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/sessions/refresh") }.count, 1)
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testRevokedSessionSignsOutAndNotifiesInsteadOfLingering() async throws {
        let client = makeClient()
        let notified = expectation(description: "session invalidated")
        await client.setSessionInvalidationHandler { notified.fulfill() }
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            default: return (401, Self.unauthorized) // revoked: refresh is rejected too
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        do {
            _ = try await client.authenticatedJSON("POST", path: "/v1/stories", body: .object([:]))
            XCTFail("expected unauthenticated")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthenticated)
        }
        await fulfillment(of: [notified], timeout: 2)
        let hasSession = await client.hasSession()
        XCTAssertFalse(hasSession)
    }

    func testOfflineRefreshKeepsTheSession() async throws {
        let client = makeClient()
        var offline = false
        SessionRouterProtocol.handler = { request in
            if offline { return (0, "") }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, Self.tokens(1, accessMinutes: 0))
            case ("GET", "/v1/accounts/me"): return (200, Self.me)
            default: return (404, "{}")
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        offline = true
        do {
            _ = try await client.authenticatedJSON("GET", path: "/v1/stories/rail")
            XCTFail("expected a network error")
        } catch {
            XCTAssertFalse(GreenfieldClient.refreshFailureEndsSession(error))
        }
        let hasSession = await client.hasSession()
        XCTAssertTrue(hasSession, "Being offline while the access token expires must not sign the user out")
    }
}

// MARK: - Home pagination vs refresh race

private final class DelayedFeedProtocol: URLProtocol, @unchecked Sendable {
    /// cursor (or "first") → (delay seconds, body)
    nonisolated(unsafe) static var responses: [String: (Double, String)] = [:]
    /// cursor → HTTP status (default 200).
    nonisolated(unsafe) static var statuses: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let key = items.first(where: { $0.name == "cursor" })?.value ?? "first"
        let (delay, body) = Self.responses[key] ?? (0, #"{"ok":true,"data":{"items":[]}}"#)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.statuses[key] ?? 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class HomePaginationRaceTests: XCTestCase {
    private static func page(_ ids: [String], cursor: String?) -> String {
        let posts = ids.map { #"{"id":"\#($0)","createdAt":"2026-10-01T12:00:00.000Z","kind":"text","text":"\#($0)","author":{"id":"a","handle":"a","displayName":"A"}}"# }
        let next = cursor.map { #","nextCursor":"\#($0)","hasMore":true"# } ?? #","hasMore":false"#
        return #"{"ok":true,"data":{"items":[\#(posts.joined(separator: ","))]\#(next)}}"#
    }

    func testRefreshDuringLoadMoreKeepsTheRefreshedFeed() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedFeedProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://home-race.modula.test")!, transport: URLSession(configuration: config))
        let posts = PostStateStore()
        let store = HomeStore(client: client, posts: posts, postActions: PostActionController(client: client, state: posts))

        DelayedFeedProtocol.responses = ["first": (0, Self.page(["old-1", "old-2"], cursor: "c1"))]
        await store.refresh(.forYou, signedIn: false)
        XCTAssertEqual(store.state(for: .forYou).items.map(\.id), ["old-1", "old-2"])

        DelayedFeedProtocol.responses = [
            "c1": (0.6, Self.page(["old-3"], cursor: "c2")),
            "first": (0, Self.page(["new-1"], cursor: "n1"))
        ]
        let more = Task { await store.loadMore(.forYou) }
        try await Task.sleep(for: .milliseconds(100))
        await store.refresh(.forYou, signedIn: false)
        await more.value

        let state = store.state(for: .forYou)
        XCTAssertEqual(state.items.map(\.id), ["new-1"], "A stale next page must not overwrite the refreshed feed")
        XCTAssertEqual(state.nextCursor, "n1")
        XCTAssertEqual(state.loadState, .loaded)
    }

    func testFailedNextPageCanBeRetried() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedFeedProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://home-retry.modula.test")!, transport: URLSession(configuration: config))
        let posts = PostStateStore()
        let store = HomeStore(client: client, posts: posts, postActions: PostActionController(client: client, state: posts))
        defer { DelayedFeedProtocol.statuses = [:] }

        DelayedFeedProtocol.responses = [
            "first": (0, Self.page(["p-1", "p-2"], cursor: "c1")),
            "c1": (0, #"{"ok":false,"error":{"code":"internal","message":"boom"}}"#)
        ]
        DelayedFeedProtocol.statuses = ["c1": 500]
        await store.refresh(.forYou, signedIn: false)
        await store.loadMore(.forYou)
        var state = store.state(for: .forYou)
        XCTAssertNotNil(state.loadMoreError, "a failed page must surface a retryable footer")
        XCTAssertEqual(state.nextCursor, "c1", "the cursor is kept so retry asks for the same page")
        XCTAssertEqual(state.loadState, .loaded)

        DelayedFeedProtocol.statuses = [:]
        DelayedFeedProtocol.responses["c1"] = (0, Self.page(["p-3"], cursor: nil))
        await store.loadMore(.forYou)
        state = store.state(for: .forYou)
        XCTAssertNil(state.loadMoreError)
        XCTAssertEqual(state.items.map(\.id), ["p-1", "p-2", "p-3"])
        XCTAssertFalse(state.hasMore)
    }
}

@MainActor
final class ProductHubInstalledStateTests: XCTestCase {
    func testSigningOutClearsThePreviousAccountsInstalledModules() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        let client = GreenfieldClient(baseURL: URL(string: "https://hub-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct","primaryHandle":"me","status":"active"}}"#)
            case ("GET", "/v1/registry/products"): return (200, #"{"ok":true,"data":{"items":[]}}"#)
            case ("GET", "/v1/modules/installed"): return (200, #"{"ok":true,"data":{"items":[{"moduleId":"digital.modula.vault-notes"}]}}"#)
            case ("DELETE", "/v1/sessions/current"): return (200, #"{"ok":true,"data":{"revoked":true}}"#)
            default: return (404, "{}")
            }
        }
        defer { SessionRouterProtocol.handler = nil }
        let store = ProductHubStore(client: client)
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        await store.load()
        XCTAssertEqual(store.installedIDs, ["digital.modula.vault-notes"])
        try await client.signOut()
        await store.load()
        XCTAssertTrue(store.installedIDs.isEmpty, "Signed out must not show another account's modules as installed")
    }
}

final class ModuleHostAvailabilityTests: XCTestCase {
    private func manifest(_ id: String, runtime: String = "react-native", bridge: String = "0.1.0") throws -> ModuleManifest {
        let json = #"{"id":"\#(id)","name":"Vault Notes","version":"1.0.0","runtime":"\#(runtime)","entry":"vault","permissions":[],"minHostVersion":"0.1.0","minBridgeVersion":"\#(bridge)"}"#
        return try JSONDecoder().decode(ModuleManifest.self, from: Data(json.utf8))
    }

    func testUnavailableModulesExplainWhyInsteadOfABareState() throws {
        let manifests = [try manifest("vault"), try manifest("future", bridge: "0.9.0"), try manifest("expo", runtime: "expo")]
        XCTAssertNil(ModuleRuntimeController.unavailableReason(for: "vault", in: manifests))
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "missing", in: manifests), "This module isn’t included in this version of Modula.")
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "future", in: manifests), "Vault Notes needs a newer version of Modula. Update the app to open it.")
        XCTAssertEqual(ModuleRuntimeController.unavailableReason(for: "expo", in: manifests), "Vault Notes uses a runtime this app doesn’t support.")
    }
}

final class StoryViewerSegmentTests: XCTestCase {
    /// Viewer opened on a partial group (1 item); hydration brings 3. The bar must show
    /// 3 segments and keep the item being watched, with its progress.
    func testEngineResizesWhenTheGroupGainsItemsAndKeepsTheCurrentItem() {
        let engine = StoryProgressEngine(count: 1)
        _ = engine.tick(1)
        XCTAssertEqual(engine.segmentCount, 1)
        engine.resize(count: 3, keepingIndex: 2) // the watched item is now third
        XCTAssertEqual(engine.segmentCount, 3)
        XCTAssertEqual(engine.index, 2)
        XCTAssertEqual(engine.progress, 0, accuracy: 0.0001)
        _ = engine.tick(1)
        let progress = engine.progress
        engine.resize(count: 4, keepingIndex: 2)
        XCTAssertEqual(engine.segmentCount, 4)
        XCTAssertEqual(engine.progress, progress, accuracy: 0.0001, "same item keeps its progress")
        XCTAssertEqual(engine.next(), .advanced, "the new trailing item is reachable")
        engine.resize(count: 1, keepingIndex: nil)
        XCTAssertEqual(engine.index, 0, "shrinking clamps the index")
    }
}

final class StoryViewerFailedMediaTests: XCTestCase {
    private func item(_ id: String, kind: StoryKind = .image) -> StoryItem {
        StoryItem(id: id, author: MessagingFixtures.me, createdAt: Date(), expiresAt: nil, kind: kind, media: nil,
                  text: nil, background: nil, seen: false, isOwn: false, viewerCount: nil)
    }

    func testTapNavigationStaysAvailableWhenTheImageFailed() {
        let story = item("s1")
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: nil), "still loading")
        XCTAssertTrue(StoryViewerGate.allowsTapNavigation(item: story, loadedID: "s1", failedID: nil))
        XCTAssertTrue(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: "s1"),
                      "a failed image must not trap the viewer")
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: story, loadedID: nil, failedID: "other"))
        XCTAssertFalse(StoryViewerGate.allowsTapNavigation(item: item("v", kind: .video), loadedID: "v", failedID: "v"))
    }
}

final class HomeStoryTrayTests: XCTestCase {
    func testHomeTrayHasNoSecondCreateEntry() {
        let me = MessagingFixtures.me
        let friend = ConversationParticipant(id: "f", handle: "f", displayName: "F", avatarURL: nil)
        let placeholder = StoryGroup(id: "add:actor-1", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 0)
        let ownLive = StoryGroup(id: "g-own", author: me, items: [], isOwn: true, reportedRing: .own, itemCount: 2)
        let friendGroup = StoryGroup(id: "g-f", author: friend, items: [], isOwn: false, reportedRing: .unseen, itemCount: 1)
        XCTAssertEqual(StoryStore.homeTrayGroups([placeholder, friendGroup]).map(\.id), ["g-f"],
                       "the header + is Home's only create control")
        XCTAssertEqual(StoryStore.homeTrayGroups([ownLive, friendGroup]).map(\.id), ["g-own", "g-f"],
                       "a live own story stays in the tray")
    }
}

// MARK: - Product Hub: store listing, install state and lifecycle (Phase D)

private func bodyJSON(_ request: URLRequest) -> JSONValue? {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = Data(); var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&chunk, maxLength: chunk.count); if n <= 0 { break }; buffer.append(chunk, count: n) }
        data = buffer
    }
    return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

final class ModuleStoreTests: XCTestCase {
    private static let vault = CatalogueProduct(
        moduleId: "digital.modula.vault-notes", productKind: "module", name: "Vault Notes", description: "Notes",
        publisherId: "modula", publisherName: "Modula", latestVersion: "1.7.0", status: "published", installable: true,
        platforms: ["ios"], betaClassification: nil, installability: .init(status: "available", reasonCode: nil, reason: nil))

    private static let vault180 = CatalogueProduct(
        moduleId: "digital.modula.vault-notes", productKind: "module", name: "Vault Notes", description: "Notes",
        publisherId: "modula", publisherName: "Modula", latestVersion: "1.8.0", status: "published", installable: true,
        platforms: ["ios"], betaClassification: nil, installability: .init(status: "available", reasonCode: nil, reason: nil))

    private func state(_ status: String?, version: String? = "1.7.0", op: ModuleOperation? = nil, bundled: Bool = true,
                       bundledVersion: String? = "1.7.0", signedIn: Bool = true, product: CatalogueProduct = vault,
                       declarativeHost: Bool = false) -> ModulePrimaryAction {
        ModuleDetailPresentation(product: product,
                                 installation: status.map { ModuleInstallation(moduleId: product.moduleId, status: $0, version: version) },
                                 operation: op, bundled: bundled, bundledVersion: bundledVersion, signedIn: signedIn,
                                 declarativeHost: declarativeHost).primaryAction
    }

    func testPrimaryActionFollowsServerInstallState() {
        XCTAssertEqual(state(nil), .install, "Bundled code alone is not an installation")
        XCTAssertEqual(state(nil, signedIn: false), .signIn)
        XCTAssertEqual(state("enabled"), .open)
        XCTAssertEqual(state("installing"), .installing)
        XCTAssertEqual(state("uninstalling"), .uninstalling)
        XCTAssertEqual(state("removed"), .install)
        XCTAssertEqual(state("uninstalled"), .install, "Legacy 'uninstalled' rows are not installs")
        XCTAssertEqual(state("enabled", version: "1.6.0"), .update)
        XCTAssertEqual(state("enabled", version: "1.7.0", product: Self.vault180), .update,
                       "A newer registry release is offered even when the bundled module code is labelled older")
        XCTAssertEqual(state("enabled", version: "1.7.0", bundledVersion: "1.6.0"), .open, "Up to date with the registry's latest")
        XCTAssertEqual(state(nil, op: .installing), .installing)
        XCTAssertEqual(state(nil, bundled: false), .unavailable)
        let local = CatalogueProduct(
            moduleId: "digital.modula.basic-echo", productKind: "module", name: "Basic Echo", description: "Local",
            publisherId: "modula", publisherName: "Modula", latestVersion: "0.1.0", status: "published", installable: true,
            platforms: ["ios"], betaClassification: "local-development", installability: .init(status: "installable", reasonCode: nil, reason: nil))
        XCTAssertEqual(state(nil, bundled: false, product: local, declarativeHost: true), .install,
                       "A declarative local package can install without bundled React Native code")
        XCTAssertEqual(state(nil, bundled: false, signedIn: false, product: local, declarativeHost: true), .signIn)
        XCTAssertEqual(state("enabled", version: "0.1.0", bundled: false, product: local, declarativeHost: true), .open)
        XCTAssertEqual(state("enabled", version: "0.1.0", bundled: false, bundledVersion: nil, product: CatalogueProduct(
            moduleId: local.moduleId, productKind: local.productKind, name: local.name, description: local.description,
            publisherId: local.publisherId, publisherName: local.publisherName, latestVersion: "0.1.1", status: local.status,
            installable: true, platforms: local.platforms, betaClassification: "local-development",
            installability: local.installability), declarativeHost: true), .update)
        XCTAssertTrue(ModuleVersion.isOlder("1.9.2", than: "1.10.0"))
        XCTAssertFalse(ModuleVersion.isOlder("1.7.0", than: "1.7"))
    }

    func testListingDecodesMarketplaceAndToleratesMissingFields() throws {
        let json = #"""
        {"moduleId":"digital.modula.vault-notes","name":"Vault Notes","description":"D","latestVersion":"1.7.0","trust":"firstParty",
         "publisher":{"displayName":"Modula","website":"https://modula.digital"},
         "permissions":[{"permission":"functions:register","risk":"high","reason":"Actions"},{"permission":"events:subscribe","risk":"medium","reason":"Events"}],
         "compatibility":{"platforms":["ios"],"minimumModulaHostVersion":"0.1.0"},
         "marketplace":{"category":{"state":"declared","value":"Productivity"},"ageRating":{"state":"declared","value":"4+"},
           "syncSupport":{"state":"declared","value":true},"privacy":{"state":"undeclared","value":"x"},
           "previews":[{"id":"p1","type":"image","source":"https://cdn.modula.digital/a.png","width":1170,"height":2532},{"id":"bad","type":"image","source":"http://insecure/a.png"}],
           "rating":{"average":4.5,"count":12},"installations":{"count":3},"chart":{"rank":1,"category":"Productivity"},
           "release":{"publishedAt":"2026-08-24T00:00:00.000Z","sizeBytes":4200000,"notes":["One","Two"]},
           "icon":"https://cdn.modula.digital/icon.png"}}
        """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let listing = try XCTUnwrap(ModuleListing(json: value))
        XCTAssertEqual(listing.category, "Productivity")
        XCTAssertNil(listing.privacy, "Undeclared values are not shown as facts")
        XCTAssertEqual(listing.highRiskCount, 1)
        XCTAssertEqual(listing.previews.map(\.id), ["p1"], "Only https previews are loaded")
        XCTAssertEqual(listing.ratingCount, 12)
        XCTAssertEqual(listing.sizeBytes, 4_200_000)
        XCTAssertEqual(listing.releaseNotes, ["One", "Two"])
        XCTAssertNotNil(listing.publishedAt)
        XCTAssertEqual(listing.iconURL?.host, "cdn.modula.digital")
        let minimal = try XCTUnwrap(ModuleListing(json: .object(["moduleId": .string("x.y")])))
        XCTAssertEqual(minimal.permissions, [])
        XCTAssertNil(ModuleListing(json: .object([:])))
    }

    func testArtworkComesOnlyFromTheRegistryListing() throws {
        var listing = try XCTUnwrap(ModuleListing(json: .object(["moduleId": .string("digital.modula.vault-notes")])))
        listing.iconURL = URL(string: "https://cdn.modula.digital/icon.png")
        listing.previews = [.init(id: "p1", source: URL(string: "https://cdn.modula.digital/a.png")!, alt: "List", aspect: nil)]
        let remote = ModuleArtwork(listing: listing)
        XCTAssertEqual(remote.icon, .remote(URL(string: "https://cdn.modula.digital/icon.png")!))
        XCTAssertNil(remote.cover, "Missing cover falls back to the neutral placeholder")
        XCTAssertEqual(remote.screenshots.map(\.alt), ["List"])
        let none = ModuleArtwork(listing: nil)
        XCTAssertNil(none.icon); XCTAssertNil(none.cover); XCTAssertTrue(none.screenshots.isEmpty)
        XCTAssertNil(ModuleArtSource("asset:VaultNotesIcon"), "Bundled asset references are not artwork sources")
        XCTAssertNil(ModuleArtSource("javascript:alert(1)"))
        XCTAssertNotNil(ModuleArtSource("https://cdn.modula.digital/cover.jpg"))
    }

    func testRegistryPresentationFromLatestVersionDrivesArtwork() throws {
        let json = #"""
        {"moduleId":"digital.modula.vault-notes","latestVersion":"1.8.0",
         "presentation":{"version":"1.8.0",
           "icon":{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/icon","sha256":"77bf","width":1024,"height":1024,"available":true},
           "cover":{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/cover","sha256":"cef9","width":1600,"height":900,"available":true},
           "screenshots":[{"url":"https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/s1","sha256":"s1","width":1280,"height":720,"alt":"Shot"},
                          {"url":"http://insecure/s2","sha256":"s2"}]},
         "marketplace":{"icon":"https://cdn.modula.digital/old-icon.png","cover":"https://cdn.modula.digital/old-cover.png"}}
        """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let listing = try XCTUnwrap(ModuleListing(json: value))
        XCTAssertEqual(listing.iconURL?.lastPathComponent, "icon", "Registry presentation wins over legacy marketplace art")
        XCTAssertEqual(listing.coverURL?.lastPathComponent, "cover")
        XCTAssertEqual(listing.previews.map(\.alt), ["Shot"], "Only https screenshots are loaded")

        let product = try XCTUnwrap(GreenfieldDiscoverRepository.decodeProduct(value))
        XCTAssertEqual(product.presentation?.version, "1.8.0")
        let fromList = ModuleArtwork(listing: nil, product: product)
        XCTAssertEqual(fromList.icon, .remote(URL(string: "https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/icon")!))
        XCTAssertEqual(fromList.cover, .remote(URL(string: "https://api.modula.digital/v1/registry/releases/r%3A1.8.0/assets/cover")!))
        XCTAssertEqual(fromList.screenshots.count, 1)

        let catalogue = try JSONDecoder().decode(CatalogueProduct.self, from: Data(#"""
        {"moduleId":"m","productKind":"module","name":"M","description":"","publisherId":"p","publisherName":"P","status":"published",
         "installable":true,"platforms":[],"presentation":{"icon":{"url":"https://api.modula.digital/a/icon","available":false},"cover":null}}
        """#.utf8))
        let missing = ModuleArtwork(listing: nil, product: catalogue)
        XCTAssertNil(missing.icon, "Unavailable assets fall back to the placeholder")
        XCTAssertNil(missing.cover)
    }

    func testBundledManifestsCarryNoInventedPresentationBlock() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "manifests", withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertFalse(raw.isEmpty)
        XCTAssertTrue(raw.allSatisfy { $0["presentation"] == nil })
        XCTAssertNoThrow(try JSONDecoder().decode([ModuleManifest].self, from: Data(contentsOf: url)))
        XCTAssertNil(UIImage(named: "VaultNotesIcon"), "The app bundles no module artwork")
    }

    @MainActor
    func testInstallEnablesAndUninstallSettlesAgainstServer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        SessionRouterProtocol.log = []
        defer { SessionRouterProtocol.handler = nil }
        let client = GreenfieldClient(baseURL: URL(string: "https://store-test-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        let lock = NSLock()
        nonisolated(unsafe) var status: String? = nil
        nonisolated(unsafe) var polls = 0
        nonisolated(unsafe) var installBody: JSONValue?
        nonisolated(unsafe) var uninstallBody: JSONValue?
        SessionRouterProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/install"):
                installBody = bodyJSON(request); status = "installing"; polls = 0
                return (202, #"{"ok":true,"data":{"installationId":"i1","status":"installing"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/enable"):
                status = "enabled"; return (202, #"{"ok":true,"data":{"status":"enabling"}}"#)
            case ("DELETE", "/v1/modules/digital.modula.vault-notes/install"):
                uninstallBody = bodyJSON(request); status = "uninstalling"; polls = 0
                return (202, #"{"ok":true,"data":{"status":"uninstalling"}}"#)
            case ("GET", "/v1/modules/installed"):
                polls += 1
                if status == "installing", polls >= 2 { status = "installedDisabled" }
                if status == "uninstalling", polls >= 2 { status = "removed" }
                let items = status == nil || status == "removed" ? "[]" : #"[{"installationId":"i1","moduleId":"digital.modula.vault-notes","status":"\#(status!)","version":"1.7.0"}]"#
                return (200, #"{"ok":true,"data":{"items":\#(items)}}"#)
            default: return (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: client)
        store.settlePollInterval = .milliseconds(5)

        let installed = await store.install("digital.modula.vault-notes", permissions: ["functions:register"])
        XCTAssertTrue(installed, store.lifecycleErrors.description)
        XCTAssertEqual(store.installations["digital.modula.vault-notes"]?.status, "enabled")
        XCTAssertTrue(store.installedIDs.contains("digital.modula.vault-notes"))
        XCTAssertNil(store.operations["digital.modula.vault-notes"])
        XCTAssertEqual(installBody?["platform"]?.string, "ios")
        XCTAssertEqual(installBody?["approvedPermissions"]?.array?.compactMap(\.string), ["functions:register"])
        XCTAssertTrue(installBody?["idempotencyKey"]?.string?.hasPrefix("ios-install-") == true)
        XCTAssertEqual(SessionRouterProtocol.log.filter { $0.hasPrefix("POST /v1/modules/digital.modula.vault-notes/enable") }.count, 1,
                       "A disabled installation is enabled exactly once")

        let removed = await store.uninstall("digital.modula.vault-notes")
        XCTAssertTrue(removed)
        XCTAssertEqual(uninstallBody?["choice"]?.string, "keepData")
        XCTAssertFalse(store.installedIDs.contains("digital.modula.vault-notes"))
    }

    @MainActor
    func testInstallFailureSurfacesMessageAndClearsOperation() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionRouterProtocol.self]
        defer { SessionRouterProtocol.handler = nil }
        let client = GreenfieldClient(baseURL: URL(string: "https://store-fail-\(UUID().uuidString.prefix(8)).modula.test")!,
                                      transport: URLSession(configuration: config))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tokens = #"{"ok":true,"data":{"accessToken":"a","refreshToken":"r","sessionId":"s","accessExpiresAt":"\#(f.string(from: Date().addingTimeInterval(900)))","refreshExpiresAt":"\#(f.string(from: Date().addingTimeInterval(86_400)))"}}"#
        SessionRouterProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/v1/sessions"): return (201, tokens)
            case ("GET", "/v1/accounts/me"): return (200, #"{"ok":true,"data":{"accountId":"acct-1","primaryHandle":"me","status":"active"}}"#)
            case ("POST", "/v1/modules/digital.modula.vault-notes/install"): return (403, #"{"ok":false,"error":{"code":"CAPABILITY_DISABLED"}}"#)
            case ("GET", "/v1/modules/installed"): return (200, #"{"ok":true,"data":{"items":[]}}"#)
            default: return (404, #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#)
            }
        }
        _ = try await client.signIn(email: "a@b.c", password: "pw")
        let store = ProductHubStore(client: client)
        let ok = await store.install("digital.modula.vault-notes", permissions: [])
        XCTAssertFalse(ok)
        XCTAssertNil(store.operations["digital.modula.vault-notes"])
        XCTAssertNotNil(store.lifecycleErrors["digital.modula.vault-notes"])
    }
}
