import XCTest
@testable import Modula

final class DiscoverPayloadDecoderTests: XCTestCase {
    func testDecodesDiscoverDashboardWithoutFabricatingVelocity() {
        let payload: JSONValue = .object([
            "suggestedProfiles": .array([
                .object([
                    "id": .string("profile-andrei"),
                    "handle": .string("andrei.modula"),
                    "displayName": .string("Andrei"),
                    "bio": .string("Building Modula"),
                    "postCount": .number(5),
                    "followerCount": .number(5),
                    "isFollowing": .bool(false),
                    "followsViewer": .bool(false),
                    "identityClaims": .array([])
                ]),
                .object([
                    "id": .string("profile-empty"),
                    "handle": .string("p7fixture"),
                    "displayName": .string("Empty"),
                    "bio": .string(""),
                    "postCount": .number(0),
                    "isFollowing": .bool(false)
                ])
            ]),
            "trendingTopics": .array([
                .object(["id": .string("topic-profile-os"), "label": .string("Profile OS"), "postCount": .number(1840)])
            ]),
            "featuredModules": .array([
                .object(["id": .string("module-vault-notes"), "name": .string("Vault Notes"), "status": .string("Preview")])
            ]),
            "media": .array([
                .object(["id": .string("m1"), "kind": .string("image"), "title": .string("Study"), "colour": .string("#369CAA")])
            ])
        ])
        let dash = DiscoverPayloadDecoder.dashboard(from: payload)
        XCTAssertEqual(dash.people.count, 2)
        XCTAssertEqual(dash.people[0].routeID, "andrei.modula")
        XCTAssertFalse(dash.people[0].isVerified)
        XCTAssertGreaterThan(dash.people[0].usefulness, dash.people[1].usefulness)
        XCTAssertEqual(dash.topics[0].label, "Profile OS")
        XCTAssertEqual(dash.topics[0].postCount, 1840)
        XCTAssertEqual(dash.topics[0].postCountLabel, "1.8K posts")
        XCTAssertNil(dash.topics[0].summary)
        XCTAssertEqual(dash.featuredModules[0].id, "module-vault-notes")
        XCTAssertEqual(dash.media.count, 1)
    }

    func testSearchHitsDecodeEntityTypes() {
        let payload: JSONValue = .object([
            "results": .array([
                .object([
                    "entityType": .string("profile"),
                    "entityId": .string("profile-1"),
                    "title": .string("Modula"),
                    "excerpt": .string("modula_org"),
                    "score": .number(18),
                    "metadata": .object(["handle": .string("modula_org"), "kind": .string("person")])
                ]),
                .object([
                    "entityType": .string("post"),
                    "entityId": .string("post-1"),
                    "title": .string("Hello"),
                    "excerpt": .string("Hello world"),
                    "metadata": .object(["kind": .string("text"), "handle": .string("andrei.modula"), "authorDisplayName": .string("Andrei")])
                ]),
                .object([
                    "entityType": .string("module"),
                    "entityId": .string("digital.modula.vault-notes"),
                    "title": .string("Vault Notes"),
                    "excerpt": .string("Notes")
                ])
            ]),
            "nextCursor": .string("cursor-2")
        ])
        let page = DiscoverPayloadDecoder.searchPage(from: payload)
        XCTAssertEqual(page.results.count, 3)
        XCTAssertEqual(page.nextCursor, "cursor-2")
        XCTAssertEqual(page.results[0].destination, .profile("modula_org", .overview))
        XCTAssertEqual(page.results[1].destination, .post("post-1", .root))
        XCTAssertEqual(page.results[2].destination, .productHub(.module("digital.modula.vault-notes", .overview)))
    }

    func testTopicSearchHitsComeFromDiscoverTopicsNotSearchIndex() {
        let topics = [
            DiscoverTopic(id: "topic-profile-os", label: "Profile OS", postCount: 1840, summary: nil),
            DiscoverTopic(id: "topic-module-sdk", label: "Module SDK", postCount: 820, summary: nil)
        ]
        let hits = topics.filter { $0.label.localizedCaseInsensitiveContains("profile") }.map(SearchHit.from(topic:))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].entityType, "topic")
        XCTAssertEqual(hits[0].excerpt, "1.8K posts")
        XCTAssertNil(hits[0].destination)
    }

    func testFeaturedModulePrefersCanonicalModuleIdWhenPresent() {
        let payload: JSONValue = .object([
            "id": .string("module-vault-notes"),
            "name": .string("Vault Notes"),
            "moduleId": .string("digital.modula.vault-notes"),
            "status": .string("Preview")
        ])
        let featured = DiscoverPayloadDecoder.featuredModule(payload)
        XCTAssertEqual(featured?.id, "module-vault-notes")
        XCTAssertEqual(featured?.catalogueID, "digital.modula.vault-notes")
        let product = CatalogueProduct(
            moduleId: "digital.modula.vault-notes",
            productKind: "module",
            name: "Vault Notes",
            description: "Notes",
            publisherId: "digital.modula",
            publisherName: "Modula",
            latestVersion: "1.7.0",
            status: "published",
            installable: true,
            platforms: ["ios"],
            betaClassification: nil,
            installability: nil
        )
        XCTAssertEqual(GreenfieldDiscoverRepository.resolve(featured!, in: [product])?.moduleId, "digital.modula.vault-notes")
    }

    func testProfilePostsPage() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("post-local-1"),
                    "text": .string("Phase 1 goal"),
                    "kind": .string("text"),
                    "likeCount": .number(0),
                    "replyCount": .number(0),
                    "createdAt": .string("2026-07-16T11:52:00.000Z"),
                    "author": .object([
                        "id": .string("profile-andrei"),
                        "handle": .string("andrei.modula"),
                        "displayName": .string("Andrei")
                    ])
                ])
            ]),
            "nextCursor": .string("2026-07-16T11:52:00.000Z|post-local-1"),
            "hasMore": .bool(true)
        ])
        let page = DiscoverPayloadDecoder.postsPage(from: payload)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].kind, .text)
        XCTAssertEqual(page.nextCursor, "2026-07-16T11:52:00.000Z|post-local-1")
    }

    func testFeaturedModuleResolvesAgainstCatalogueName() {
        let featured = DiscoverFeaturedModule(id: "module-vault-notes", name: "Vault Notes", status: "Preview", catalogueID: nil)
        let product = CatalogueProduct(
            moduleId: "digital.modula.vault-notes",
            productKind: "module",
            name: "Vault Notes",
            description: "Notes",
            publisherId: "digital.modula",
            publisherName: "Modula",
            latestVersion: "1.7.0",
            status: "published",
            installable: true,
            platforms: ["ios"],
            betaClassification: nil,
            installability: nil
        )
        XCTAssertEqual(GreenfieldDiscoverRepository.resolve(featured, in: [product])?.moduleId, "digital.modula.vault-notes")
    }

    func testPeopleFiltersDoNotInventVerified() {
        var filters = PeopleFilters()
        XCTAssertFalse(filters.isActive)
        filters.followingOnly = true
        XCTAssertTrue(filters.isActive)
        let following = DiscoverPerson(
            id: "1", handle: "a", displayName: "A", kind: nil, bio: nil, avatarURL: nil,
            followerCount: 0, followingCount: 0, postCount: 0, isFollowing: true, followsViewer: false,
            isVerified: false, joinedAt: nil
        )
        XCTAssertEqual(following.followState, .following)
    }
}

@MainActor
final class DiscoverRoutingAndChromeTests: XCTestCase {
    func testDiscoverDefaultsToTrendingAndRoundTrips() {
        XCTAssertEqual(RouteParser.parse("/discover"), .discover(.trending))
        XCTAssertEqual(RouteSerializer.serialize(.discover(.trending)), "/discover/trending")
        for scope in DiscoverRoute.allCases {
            let route = AppRoute.discover(scope)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(route)), route)
        }
        XCTAssertEqual(RouteParser.parse("/search/topics?q=ios"), .search(.section(.topics, "ios")))
        XCTAssertNil(RouteParser.parse("/discover/search"))
    }

    func testDiscoverHasScopePickerNotRailAndSearchHidesAccessory() {
        let discover = ShellChromePolicy.policy(for: .discover(.people))
        XCTAssertTrue(discover.bottomBarVisible)
        XCTAssertFalse(discover.contextRailVisible)
        XCTAssertTrue(discover.shellAccessoryVisible)
        XCTAssertFalse(discover.showsBack)
        let search = ShellChromePolicy.policy(for: .search(.root(nil)))
        XCTAssertTrue(search.bottomBarVisible)
        XCTAssertFalse(search.shellAccessoryVisible)
        XCTAssertTrue(search.showsBack)
        let module = ShellChromePolicy.policy(for: .productHub(.module("digital.modula.vault-notes", .overview)))
        XCTAssertTrue(module.bottomBarVisible)
    }

    func testDiscoverAccessoryIsToolsNotScopes() {
        let config = ShellAccessoryConfiguration.configuration(for: .discover(.trending), activity: nil, signedIn: false)
        XCTAssertEqual(config.title, "Tools")
        XCTAssertEqual(config.actions.map(\.id), ["customise", "refresh"])
        XCTAssertFalse(config.actions.contains(where: { ["Trending", "People", "Topics", "Posts", "Modules"].contains($0.title) }))
        XCTAssertFalse(config.showsSearch)
        XCTAssertTrue(config.showsMore)
    }

    func testSearchHandoffPreservesDiscoverRoot() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.discover)
        coordinator.replaceContext(with: .discover(.people))
        coordinator.open(.search(.root(nil)))
        XCTAssertEqual(coordinator.root(for: .discover), .discover(.people))
        XCTAssertEqual(coordinator.currentRoute, .search(.root(nil)))
        coordinator.replaceTop(with: .search(.section(.posts, "modula")))
        XCTAssertEqual(coordinator.currentRoute, .search(.section(.posts, "modula")))
        coordinator.close()
        XCTAssertEqual(coordinator.currentRoute, .discover(.people))
    }

    func testDiscoverPushesProfilePostAndModuleWithoutStealingTabs() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.discover)
        coordinator.replaceContext(with: .discover(.modules))
        coordinator.push(.profile("andrei.modula", .overview))
        XCTAssertEqual(coordinator.selectedTab, .discover)
        XCTAssertEqual(coordinator.currentRoute, .profile("andrei.modula", .overview))
        coordinator.close()
        coordinator.push(.post("post-local-1", .root))
        XCTAssertEqual(coordinator.selectedTab, .discover)
        coordinator.close()
        coordinator.push(.productHub(.module("digital.modula.vault-notes", .overview)))
        XCTAssertEqual(coordinator.selectedTab, .discover)
        XCTAssertEqual(coordinator.currentRoute, .productHub(.module("digital.modula.vault-notes", .overview)))
        coordinator.close()
        XCTAssertEqual(coordinator.currentRoute, .discover(.modules))
    }

    func testSignedOutFollowRequestsAuthReturn() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.discover)
        coordinator.requestAuthentication(returningTo: .profile("andrei.modula", .overview))
        XCTAssertEqual(coordinator.currentRoute, .auth(.login))
        coordinator.completeAuthenticationReturn()
        XCTAssertEqual(coordinator.currentRoute, .profile("andrei.modula", .overview))
    }
}

@MainActor
final class DiscoverGreenfieldContractTests: XCTestCase {
    func testPublicDiscoverReturnsDashboard() async throws {
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        let value = try await client.publicJSON("GET", path: "/v1/discover")
        let dash = DiscoverPayloadDecoder.dashboard(from: value)
        XCTAssertFalse(dash.people.isEmpty)
        XCTAssertFalse(dash.topics.isEmpty)
        XCTAssertNotNil(dash.topics.first?.postCount)
    }

    func testSearchRequiresQueryAndFiltersProfiles() async throws {
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        do {
            _ = try await client.publicJSON("GET", path: "/v1/search")
            XCTFail("Expected 400")
        } catch let error as APIError {
            if case .rejected(let status, _) = error {
                XCTAssertEqual(status, 400)
            } else {
                XCTFail("Unexpected API error \(error)")
            }
        }
        let page = DiscoverPayloadDecoder.searchPage(
            from: try await client.publicJSON("GET", path: "/v1/search?q=modula&entityType=profile&limit=2")
        )
        XCTAssertTrue(page.results.allSatisfy { $0.entityType == "profile" })
    }

    func testUnauthenticatedFollowIsRejected() async throws {
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        do {
            _ = try await client.authenticatedJSON("POST", path: "/v1/profiles/andrei.modula/follow", body: .object([:]))
            XCTFail("Expected unauthenticated")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthenticated)
        }
    }
}
final class DiscoverHeaderCollapseTests: XCTestCase {
    func testHysteresisBand() {
        XCTAssertFalse(DiscoverHeaderCollapse.isCollapsed(offset: 48, current: false))
        XCTAssertTrue(DiscoverHeaderCollapse.isCollapsed(offset: 61, current: false))
        XCTAssertTrue(DiscoverHeaderCollapse.isCollapsed(offset: 30, current: true), "stays collapsed inside the band")
        XCTAssertFalse(DiscoverHeaderCollapse.isCollapsed(offset: 19, current: true))
    }

    /// Regression for the Discover freeze: a header-height-induced offset shift of up to the
    /// band width must never flip the state back (no collapse/expand loop).
    func testNoOscillationUnderOffsetFeedback() {
        for start in stride(from: CGFloat(0), through: 200, by: 1) {
            var state = false
            var offset = start
            var flips = 0
            for _ in 0..<20 {
                let next = DiscoverHeaderCollapse.isCollapsed(offset: offset, current: state)
                if next != state { flips += 1; offset += next ? -39 : 39 }
                state = next
            }
            XCTAssertLessThanOrEqual(flips, 1, "offset \(start) oscillated")
        }
    }
}
