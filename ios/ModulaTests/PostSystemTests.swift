import XCTest
@testable import Modula

final class PostSystemTests: XCTestCase {
    func testPostSectionRoutesRoundTrip() {
        let id = "post-abc"
        for section in PostSection.allCases {
            let route = AppRoute.post(id, section)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route)
        }
        XCTAssertEqual(RouteParser.parse("/post/post-abc"), .post("post-abc", .root))
        XCTAssertEqual(RouteParser.parse("/post/post-abc/comments"), .post("post-abc", .comments))
        XCTAssertEqual(RouteParser.parse("/post/post-abc/likes"), .post("post-abc", .likes))
        XCTAssertEqual(RouteParser.parse("/post/post-abc/reactions"), .post("post-abc", .reactions))
        XCTAssertEqual(RouteParser.parse("/post/post-abc/shares"), .post("post-abc", .shares))
        XCTAssertEqual(RouteParser.parse("/post/post-abc/edit"), .post("post-abc", .edit))
    }

    @MainActor
    func testPostChromeHidesRailAndAccessory() {
        let policy = ShellChromePolicy.policy(for: .post("x", .root), isTabRoot: false)
        XCTAssertTrue(policy.showsBack)
        XCTAssertFalse(policy.contextRailVisible)
        XCTAssertFalse(policy.shellAccessoryVisible)
        XCTAssertFalse(policy.bottomBarVisible)
        let metrics = ShellChromeMetrics.resolve(policy: policy)
        XCTAssertEqual(metrics.occupiedBottomHeight, 0)
        XCTAssertEqual(metrics.contentBottomInset, 8)
    }

    @MainActor
    func testCatalogInspectionChromeDoesNotObscureSamples() {
        let policy = ShellChromePolicy.policy(for: .developer(.components), isTabRoot: false)
        XCTAssertTrue(policy.bottomBarVisible)
        XCTAssertFalse(policy.shellAccessoryVisible)
        XCTAssertFalse(policy.contextRailVisible)
        XCTAssertEqual(ShellChromeMetrics.resolve(policy: policy).occupiedBottomHeight, 49)
    }

    func testDecodeUnknownKindDoesNotCrash() {
        let post = SocialPayloadDecoder.post(.object([
            "id": .string("p1"),
            "createdAt": .string("2026-09-16T12:00:00.000Z"),
            "kind": .string("music"),
            "text": .string("reserved"),
            "liked": .bool(false),
            "saved": .bool(false),
            "reposted": .bool(false),
            "likeCount": .number(0),
            "replyCount": .number(0),
            "repostCount": .number(0),
            "quoteCount": .number(0)
        ]))
        XCTAssertEqual(post?.kind, .audio)
        XCTAssertFalse(post?.kind.isFullyRenderable ?? true)
    }

    func testDecodeCarouselFromMultipleMedia() {
        let post = SocialPayloadDecoder.post(.object([
            "id": .string("p2"),
            "createdAt": .string("2026-09-16T12:00:00.000Z"),
            "kind": .string("media"),
            "liked": .bool(false),
            "saved": .bool(false),
            "reposted": .bool(false),
            "likeCount": .number(0),
            "replyCount": .number(0),
            "repostCount": .number(0),
            "quoteCount": .number(0),
            "media": .array([
                .object(["id": .string("m1"), "kind": .string("image"), "url": .string("https://cdn.example/1.jpg")]),
                .object(["id": .string("m2"), "kind": .string("image"), "url": .string("https://cdn.example/2.jpg")])
            ])
        ]))
        XCTAssertEqual(post?.kind, .carousel)
        XCTAssertEqual(post?.media.count, 2)
    }

    func testDecodeOrderedGreenfieldAttachments() throws {
        let post = SocialPayloadDecoder.post(.object([
            "id": .string("post-rich"),
            "createdAt": .string("2026-09-27T12:00:00.000Z"),
            "kind": .string("media"),
            "content": .array([
                .object([
                    "id": .string("content-image"), "type": .string("image"), "order": .number(1),
                    "attachment": .object([
                        "id": .string("att-image"), "kind": .string("image"), "mimeType": .string("image/png"),
                        "filename": .string("Photo.png"), "byteSize": .number(100), "status": .string("ready"),
                        "originalURL": .string("https://api.example.test/v1/attachments/att-image/content"),
                        "thumbnailURL": .string("https://api.example.test/v1/attachments/att-image/thumbnail")
                    ])
                ]),
                .object([
                    "id": .string("content-pdf"), "type": .string("pdf"), "order": .number(0),
                    "caption": .string("Architecture"),
                    "attachment": .object([
                        "id": .string("att-pdf"), "kind": .string("pdf"), "mimeType": .string("application/pdf"),
                        "filename": .string("Architecture.pdf"), "byteSize": .number(200), "status": .string("ready"),
                        "originalURL": .string("https://api.example.test/v1/attachments/att-pdf/content")
                    ])
                ])
            ])
        ]))

        XCTAssertEqual(post?.media.map(\.id), ["att-pdf", "att-image"])
        XCTAssertEqual(post?.media.map(\.kind), ["pdf", "image"])
        XCTAssertEqual(post?.media.first?.altText, "Architecture")
        XCTAssertEqual(post?.media.map(\.status), ["ready", "ready"])
        XCTAssertEqual(post?.media.last?.thumbnailURL?.lastPathComponent, "thumbnail")
        let canonical = try XCTUnwrap(post.map(ModulaPostMapper.map))
        XCTAssertEqual(canonical.content.map(PostRendererKind.resolve), [.pdf, .image])
    }

    func testProcessingAttachmentWithoutURLRemainsVisible() throws {
        let post = SocialPayloadDecoder.post(.object([
            "id": .string("post-processing"),
            "createdAt": .string("2026-09-27T12:00:00.000Z"),
            "kind": .string("media"),
            "content": .array([
                .object([
                    "id": .string("content-video"), "type": .string("video"), "order": .number(0),
                    "attachment": .object([
                        "id": .string("att-video"), "kind": .string("video"),
                        "mimeType": .string("video/mp4"), "filename": .string("Clip.mp4"),
                        "status": .string("processing")
                    ])
                ])
            ])
        ]))

        XCTAssertEqual(post?.media.count, 1)
        XCTAssertNil(post?.media.first?.url)
        let attachment = try XCTUnwrap(post?.media.first.map(ModulaPostMapper.attachment))
        XCTAssertEqual(attachment.resolvedRemoteState, .processing)
    }

    func testPresentationPolicyUsesOneCanonicalPostModel() {
        let attachment = ModulaAttachment(
            id: "image-1",
            kind: .image,
            remoteURL: URL(string: "https://api.example.test/v1/attachments/image-1/content"),
            mimeType: "image/jpeg"
        )
        let post = ModulaPost(
            id: "post-1",
            author: nil,
            createdAt: Date(),
            editedAt: nil,
            body: "Caption",
            content: [.image(.init(attachment: attachment))],
            context: PostContext(feed: nil, location: nil, audience: nil, visibility: .public, audioTitle: nil, collection: nil, topic: nil, module: nil),
            engagement: PostEngagement(liked: false, saved: false, reposted: false, viewerReaction: nil, likeCount: 0, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0)
        )

        XCTAssertEqual(post.presentationStyle, .immersiveImage)
        XCTAssertTrue(ModulaPostLayoutPolicy.resolve(post).prefersActionRail)
        let mixed = ModulaPost(
            id: post.id,
            author: post.author,
            createdAt: post.createdAt,
            editedAt: post.editedAt,
            body: post.body,
            content: post.content + [.pdf(.init(attachment: attachment))],
            context: post.context,
            engagement: post.engagement
        )
        XCTAssertEqual(mixed.presentationStyle, .mixed)
        XCTAssertFalse(ModulaPostLayoutPolicy.resolve(mixed).prefersActionRail)
    }

    func testCommentPageDecode() {
        let page = SocialPayloadDecoder.commentPage(from: .object([
            "items": .array([
                .object([
                    "id": .string("c1"),
                    "text": .string("Hello"),
                    "createdAt": .string("2026-09-16T12:00:00.000Z"),
                    "author": .object([
                        "id": .string("a1"),
                        "handle": .string("ada"),
                        "displayName": .string("Ada")
                    ]),
                    "replyCount": .number(2),
                    "likeCount": .number(1)
                ]),
                .object([
                    "id": .string("c2"),
                    "text": .string("Reply"),
                    "parentId": .string("c1"),
                    "createdAt": .string("2026-09-16T12:01:00.000Z")
                ])
            ]),
            "nextCursor": .string("n1"),
            "hasMore": .bool(true)
        ]), postID: "p1")
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[0].text, "Hello")
        XCTAssertEqual(page.items[1].parentID, "c1")
        XCTAssertTrue(page.hasMore)
    }

    func testLiveGreenfieldCommentSnakeCaseDecode() {
        let page = SocialPayloadDecoder.commentPage(from: .object([
            "items": .array([
                .object([
                    "comment_id": .string("comment-phase6s-top-1"),
                    "post_id": .string("post-local-owner-media"),
                    "author_actor_id": .string("actor-gaia"),
                    "parent_comment_id": .null,
                    "text": .string("Top-level Phase 6S comment fixture."),
                    "depth": .number(0),
                    "reply_count": .number(1),
                    "created_at": .string("2026-07-18T10:11:55.194Z"),
                    "updated_at": .string("2026-07-26T21:38:51.715Z"),
                    "deleted_at": .null
                ])
            ])
        ]), postID: "post-local-owner-media")
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "comment-phase6s-top-1")
        XCTAssertEqual(page.items[0].text, "Top-level Phase 6S comment fixture.")
        XCTAssertEqual(page.items[0].author?.id, "actor-gaia")
        XCTAssertNil(page.items[0].parentID)
        XCTAssertEqual(page.items[0].replyCount, 1)
        XCTAssertTrue(PostBackendCapabilities.production.commentReplies)
        XCTAssertTrue(PostBackendCapabilities.production.commentsDelete)
        XCTAssertTrue(PostBackendCapabilities.production.commentsList)
    }

    @MainActor
    func testPostStateStoreSyncsEngagement() {
        let store = PostStateStore()
        var post = fixturePost(id: "sync-1", liked: false, likeCount: 1)
        store.upsert(post)
        store.applyEngagement(postID: "sync-1") { engagement in
            engagement.liked = true
            engagement.likeCount = 2
            engagement.viewerReaction = .like
        }
        let resolved = store.resolved(post)
        XCTAssertTrue(resolved.liked)
        XCTAssertEqual(resolved.likeCount, 2)
        XCTAssertEqual(resolved.viewerReaction, .like)

        post.liked = false
        post.likeCount = 1
        let again = store.resolved(post)
        XCTAssertTrue(again.liked)
        XCTAssertEqual(again.likeCount, 2)
    }

    @MainActor
    func testPostStateStoreDeleteAndHide() {
        let store = PostStateStore()
        store.upsert(fixturePost(id: "del-1", liked: false, likeCount: 0))
        store.markDeleted("del-1")
        XCTAssertNil(store.post(id: "del-1"))
        store.hideLocally("hide-1")
        XCTAssertTrue(store.isHidden("hide-1"))
    }

    func testOwnVersusOtherContextMenus() {
        let own = PostContextActions.menu(isOwn: true, saved: false, capabilities: .production)
        XCTAssertFalse(own.contains { $0.id == "mute-author" })
        XCTAssertTrue(own.contains { $0.id == "copy-link" })
        XCTAssertFalse(own.contains { $0.id == "edit-post" }) // editOwnPost false in production caps

        var caps = PostBackendCapabilities.production
        caps.editOwnPost = true
        caps.deleteOwnPost = true
        let ownEnabled = PostContextActions.menu(isOwn: true, saved: true, capabilities: caps)
        XCTAssertTrue(ownEnabled.contains { $0.id == "edit-post" })
        XCTAssertTrue(ownEnabled.contains { $0.id == "delete" })

        let other = PostContextActions.menu(isOwn: false, saved: false, capabilities: .production)
        XCTAssertTrue(other.contains { $0.id == "mute-author" })
        XCTAssertTrue(other.contains { $0.id == "hide" })
        XCTAssertFalse(other.contains { $0.id == "report" }) // reportPost false
    }

    func testGestureThresholdsCentralized() {
        XCTAssertGreaterThan(PostGestureThresholds.longPressDuration, 0.2)
        XCTAssertGreaterThanOrEqual(PostGestureThresholds.minimumHitTarget, 44)
        XCTAssertGreaterThan(PostGestureThresholds.horizontalDominanceRatio, 1)
        XCTAssertGreaterThan(PostGestureThresholds.railMorphThreshold, PostGestureThresholds.dragActivationDistance)
    }

    func testReactionNetworkSupportMatchesGreenfieldVocabulary() {
        XCTAssertEqual(Set(SocialReaction.networkSupported.map(\.rawValue)), ["like", "love", "laugh", "fire", "celebrate", "insightful", "support", "curious"])
        XCTAssertTrue(PostBackendCapabilities.production.multiReactions)
    }

    func testSocialTextLinksUseCanonicalRoutesWithoutLinkingEmailAddresses() throws {
        let attributed = PostTextLinks.attributed("Hello @andrei.modula, #travel. someone@example.com")
        let urls = attributed.runs.compactMap(\.link)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(PostTextLinks.route(for: urls[0]), .profile("andrei.modula", .overview))
        XCTAssertEqual(PostTextLinks.route(for: urls[1]), .search(.section(.posts, "#travel")))
        XCTAssertNil(PostTextLinks.route(for: URL(string: "https://example.com")!))
    }

    func testVoiceOverSummaryIncludesEngagement() {
        var post = fixturePost(id: "vo-1", liked: true, likeCount: 12)
        post.replyCount = 3
        post.repostCount = 1
        let summary = post.voiceOverSummary
        XCTAssertTrue(summary.contains("Ada"))
        XCTAssertTrue(summary.contains("Hello"))
        XCTAssertTrue(summary.contains("reactions") || summary.contains("12"))
        XCTAssertTrue(summary.contains("comments") || summary.contains("3"))
    }

    func testDiscoverBridgePreservesIdentity() {
        let discover = DiscoverPost(
            id: "d1",
            author: DiscoverPerson(
                id: "a", handle: "ada", displayName: "Ada", kind: nil, bio: nil,
                avatarURL: nil, followerCount: nil, followingCount: nil, postCount: nil,
                isFollowing: false, followsViewer: false, isVerified: false, joinedAt: nil
            ),
            createdAt: Date(),
            text: "Hi",
            kind: .text,
            media: nil,
            likeCount: 4,
            replyCount: 1,
            audience: "public"
        )
        let social = discover.asSocialPost()
        XCTAssertEqual(social.id, "d1")
        XCTAssertEqual(social.likeCount, 4)
        XCTAssertEqual(social.author?.handle, "ada")
    }

    private func fixturePost(id: String, liked: Bool, likeCount: Int) -> SocialPost {
        SocialPost(
            id: id,
            author: SocialAuthor(id: "a", handle: "ada", displayName: "Ada", avatarURL: nil),
            createdAt: Date(),
            editedAt: nil,
            feed: "forYou",
            text: "Hello",
            kind: .text,
            visibility: .public,
            audience: "public",
            media: [],
            link: nil,
            module: nil,
            glowColour: nil,
            engagement: PostEngagement(
                liked: liked,
                saved: false,
                reposted: false,
                viewerReaction: liked ? .like : nil,
                likeCount: likeCount,
                replyCount: 0,
                repostCount: 0,
                quoteCount: 0,
                reactionCount: likeCount
            )
        )
    }
}
