import XCTest
@testable import Modula

final class HomeFeedTests: XCTestCase {
    func testHomeRoutesRoundTrip() {
        XCTAssertEqual(RouteParser.parse("/home"), .home(.following))
        XCTAssertEqual(RouteSerializer.serialize(.home(.following)), "/home/following")
        XCTAssertEqual(RouteParser.parse("/home/for-you"), .home(.forYou))
        XCTAssertEqual(RouteSerializer.serialize(.home(.forYou)), "/home/for-you")
        XCTAssertEqual(RouteParser.parse("/home/modules"), .home(.modules))
        for mode in HomeMode.allCases {
            let route = AppRoute.home(mode)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route)
        }
    }

    func testHomeModeApiQueryValues() {
        XCTAssertEqual(HomeMode.following.apiQueryValue, "following")
        XCTAssertEqual(HomeMode.forYou.apiQueryValue, "forYou")
        XCTAssertEqual(HomeMode.modules.apiQueryValue, "modules")
        XCTAssertTrue(HomeMode.following.requiresAuth)
        XCTAssertFalse(HomeMode.forYou.requiresAuth)
    }

    func testDecodeSocialPostDto() throws {
        let json: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("post-1"),
                    "createdAt": .string("2026-09-16T12:00:00.000Z"),
                    "feed": .string("forYou"),
                    "text": .string("Hello from Modula"),
                    "kind": .string("text"),
                    "liked": .bool(true),
                    "saved": .bool(false),
                    "reposted": .bool(false),
                    "viewerReaction": .string("like"),
                    "likeCount": .number(12),
                    "replyCount": .number(3),
                    "repostCount": .number(1),
                    "quoteCount": .number(0),
                    "reactionCount": .number(12),
                    "author": .object([
                        "id": .string("acct-1"),
                        "handle": .string("ada"),
                        "displayName": .string("Ada Lovelace"),
                        "avatarUrl": .string("https://cdn.example/ada.png")
                    ]),
                    "media": .array([
                        .object([
                            "id": .string("m1"),
                            "kind": .string("image"),
                            "url": .string("https://cdn.example/photo.jpg"),
                            "altText": .string("Circuit board")
                        ])
                    ]),
                    "link": .object([
                        "url": .string("https://modula.digital"),
                        "title": .string("Modula"),
                        "domain": .string("modula.digital")
                    ]),
                    "module": .object([
                        "id": .string("digital.modula.vault-notes"),
                        "name": .string("Vault Notes"),
                        "status": .string("available")
                    ])
                ])
            ]),
            "nextCursor": .string("cursor-abc"),
            "hasMore": .bool(true),
            "rankingVersion": .string("ranking-v1")
        ])
        let page = SocialPayloadDecoder.homePage(from: json)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "cursor-abc")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.rankingVersion, "ranking-v1")
        let post = try XCTUnwrap(page.items.first)
        XCTAssertEqual(post.id, "post-1")
        XCTAssertEqual(post.text, "Hello from Modula")
        XCTAssertEqual(post.kind, .text)
        XCTAssertTrue(post.liked)
        XCTAssertEqual(post.viewerReaction, .like)
        XCTAssertEqual(post.likeCount, 12)
        XCTAssertEqual(post.author?.handle, "ada")
        XCTAssertEqual(post.media.count, 1)
        XCTAssertEqual(post.link?.domain, "modula.digital")
        XCTAssertEqual(post.module?.id, "digital.modula.vault-notes")
    }

    func testRankingVersionParse() {
        let page = SocialPayloadDecoder.homePage(from: .object([
            "items": .array([]),
            "ranking_version": .string("following-graph-v1"),
            "has_more": .bool(false)
        ]))
        XCTAssertEqual(page.rankingVersion, "following-graph-v1")
        XCTAssertFalse(page.hasMore)
    }

    @MainActor
    func testChromePolicyHome() {
        let policy = ShellChromePolicy.policy(for: .home(.forYou))
        XCTAssertTrue(policy.bottomBarVisible)
        XCTAssertTrue(policy.contextRailVisible)
        XCTAssertTrue(policy.shellAccessoryVisible)
        XCTAssertFalse(policy.showsBack)
        let config = ShellAccessoryConfiguration.configuration(for: .home(.following), activity: nil, signedIn: true)
        XCTAssertEqual(config.title, "Tools")
        XCTAssertEqual(config.actions.map(\.id), ["feeds", "summary", "tools"])
        XCTAssertFalse(config.showsSearch)
        XCTAssertFalse(config.showsMore)
    }

    func testProgressiveHeaderProgressClamp() {
        XCTAssertEqual(ModulaScrollProgress.clamp(-1), 0)
        XCTAssertEqual(ModulaScrollProgress.clamp(0), 0)
        XCTAssertEqual(ModulaScrollProgress.clamp(0.5), 0.5)
        XCTAssertEqual(ModulaScrollProgress.clamp(2), 1)
        XCTAssertEqual(ModulaScrollProgress.progress(offsetY: 0), 0)
        XCTAssertEqual(ModulaScrollProgress.progress(offsetY: 28, collapseDistance: 56), 0.5)
        XCTAssertEqual(ModulaScrollProgress.progress(offsetY: 120, collapseDistance: 56), 1)
        let path = ModulaScrollProgress.softEdgePathLabel
        XCTAssertTrue(path == "native-soft-edge" || path == "fallback-masked-material")
    }

    func testFeedSummaryAggregate() {
        let posts = [
            SocialPost(
                id: "1", author: SocialAuthor(id: "a", handle: "a", displayName: "Ada", avatarURL: nil),
                createdAt: Date(), editedAt: nil, feed: "forYou", text: "Hi", kind: .text,
                visibility: .public, audience: nil, media: [], link: nil, module: nil, glowColour: nil,
                engagement: PostEngagement(
                    liked: false, saved: false, reposted: false, viewerReaction: nil,
                    likeCount: 2, replyCount: 1, repostCount: 0, quoteCount: 0, reactionCount: 0
                )
            ),
            SocialPost(
                id: "2", author: SocialAuthor(id: "b", handle: "b", displayName: "Ben", avatarURL: nil),
                createdAt: Date(), editedAt: nil, feed: "forYou", text: "Yo", kind: .media,
                visibility: .public, audience: nil,
                media: [SocialPostMedia(id: "m", url: nil, altText: "x", kind: "image", aspectRatio: nil)],
                link: nil, module: nil, glowColour: nil,
                engagement: PostEngagement(
                    liked: false, saved: false, reposted: false, viewerReaction: nil,
                    likeCount: 3, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0
                )
            )
        ]
        let summary = FeedSummary.aggregate(from: posts, rankingVersion: "ranking-v1")
        XCTAssertEqual(summary.source, .aggregate)
        XCTAssertEqual(summary.postCount, 2)
        XCTAssertEqual(summary.likeCount, 5)
        XCTAssertEqual(summary.mediaCount, 1)
        XCTAssertEqual(summary.rankingVersion, "ranking-v1")
        XCTAssertFalse(summary.highlights.isEmpty)
    }
}
