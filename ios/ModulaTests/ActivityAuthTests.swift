import XCTest
@testable import Modula

final class AuthErrorMappingTests: XCTestCase {
    func testInvalidCredentialsMapsToFriendlyCopy() {
        let error = APIError.rejected(401, "INVALID_CREDENTIALS")
        XCTAssertEqual(error.userFacingMessage, "Incorrect email or password.")
        XCTAssertTrue(error.diagnosticDescription.contains("INVALID_CREDENTIALS"))
        XCTAssertNotEqual(error.userFacingMessage, error.diagnosticDescription)
    }

    func testUnauthenticatedMapsToSignInCopy() {
        XCTAssertEqual(APIError.rejected(401, "UNAUTHENTICATED").userFacingMessage, "Sign in to Modula to continue.")
    }
}

@MainActor
final class ShellChromePolicyN3ATests: XCTestCase {
    func testActivityKeepsTabRailAndAccessory() {
        let policy = ShellChromePolicy.policy(for: .activity(.all))
        XCTAssertTrue(policy.bottomBarVisible)
        XCTAssertTrue(policy.contextRailVisible)
        XCTAssertTrue(policy.shellAccessoryVisible)
    }

    func testAuthHidesRootChrome() {
        for route in [AppRoute.auth(.login), .auth(.forgotPassword), .auth(.register)] {
            let policy = ShellChromePolicy.policy(for: route)
            XCTAssertFalse(policy.bottomBarVisible, RouteSerializer.serialize(route))
            XCTAssertFalse(policy.contextRailVisible, RouteSerializer.serialize(route))
            XCTAssertFalse(policy.shellAccessoryVisible, RouteSerializer.serialize(route))
        }
    }

    func testAccountSettingsHidesRootChrome() {
        let policy = ShellChromePolicy.policy(for: .settings(.account(.root)))
        XCTAssertFalse(policy.bottomBarVisible)
        XCTAssertFalse(policy.contextRailVisible)
        XCTAssertFalse(policy.shellAccessoryVisible)
    }

    func testGeneralSettingsKeepsTabBarWithoutAccessoryTools() {
        let policy = ShellChromePolicy.policy(for: .settings(.appearance(.root)))
        XCTAssertTrue(policy.bottomBarVisible)
        XCTAssertFalse(policy.contextRailVisible)
        XCTAssertFalse(policy.shellAccessoryVisible)
    }

    func testAuthReturnRouteRoundTrip() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.activity)
        coordinator.requestAuthentication(returningTo: .activity(.mentions))
        XCTAssertEqual(coordinator.pendingReturnRoute, .activity(.mentions))
        XCTAssertEqual(coordinator.currentRoute, .auth(.login))
        coordinator.completeAuthenticationReturn()
        XCTAssertNil(coordinator.pendingReturnRoute)
        XCTAssertEqual(coordinator.currentRoute, .activity(.mentions))
    }
}

final class ActivityPayloadDecoderTests: XCTestCase {
    func testDecodesDemoActivityShape() {
        let payload: JSONValue = .array([
            .object([
                "id": .string("activity-1"),
                "group": .string("today"),
                "type": .string("like"),
                "actor": .object([
                    "id": .string("profile-gaia"),
                    "handle": .string("gaia.modula"),
                    "displayName": .string("Gaia")
                ]),
                "description": .string("liked your post"),
                "timestamp": .string("2026-07-26T21:38:51.715Z"),
                "preview": .string("Phase 1 goal")
            ]),
            .object([
                "id": .string("activity-4"),
                "group": .string("earlier"),
                "type": .string("mention"),
                "actor": .object([
                    "id": .string("profile-sophia"),
                    "displayName": .string("Sophia")
                ]),
                "description": .string("mentioned you"),
                "timestamp": .string("2026-07-25T10:00:00.000Z"),
                "preview": .string("hello @you")
            ])
        ])
        let page = ActivityPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.events.count, 2)
        XCTAssertEqual(page.events[0].kind, .like)
        XCTAssertEqual(page.events[1].kind, .mention)
        XCTAssertEqual(page.events[0].preview?.text, "Phase 1 goal")
        XCTAssertEqual(page.events[0].actor?.displayName, "Gaia")
    }

    func testDecodesPaginatedEnvelopeWithCursor() {
        let payload: JSONValue = .object([
            "items": .array([
                .object([
                    "id": .string("n1"),
                    "type": .string("follow_request"),
                    "isRead": .bool(false),
                    "createdAt": .string("2026-09-15T12:00:00.000Z"),
                    "from": .object(["id": .string("u1"), "displayName": .string("Mia")])
                ])
            ]),
            "nextCursor": .string("cursor-2"),
            "unreadCount": .number(3)
        ])
        let page = ActivityPayloadDecoder.page(from: payload, defaultKindHint: .followRequest)
        XCTAssertEqual(page.events.count, 1)
        XCTAssertEqual(page.events[0].kind, .followRequest)
        XCTAssertEqual(page.nextCursor, "cursor-2")
        XCTAssertEqual(page.unreadCount, 3)
        XCTAssertFalse(page.events[0].isRead)
        XCTAssertEqual(page.events[0].destination, .activityRequests)
    }

    func testMalformedItemsAreSkipped() {
        let payload: JSONValue = .array([
            .object(["type": .string("like")]),
            .object(["id": .string("ok"), "type": .string("comment"), "description": .string("commented")])
        ])
        let page = ActivityPayloadDecoder.page(from: payload)
        XCTAssertEqual(page.events.map(\.id), ["ok"])
    }

    func testDeterministicSummaryCategories() {
        let events = [
            ActivityEvent(
                id: "1", kind: .mention, actor: ActivityActor(id: "a", handle: nil, displayName: "Sophia", avatarURL: nil),
                actors: [], createdAt: Date(), isRead: false, subject: nil,
                preview: ActivityPreview(text: "Phase 1 goal", thumbnailURL: nil),
                destination: .none, descriptionText: "mentioned you", groupHint: "today", requestID: nil
            ),
            ActivityEvent(
                id: "2", kind: .like, actor: ActivityActor(id: "b", handle: nil, displayName: "Marcus", avatarURL: nil),
                actors: [], createdAt: Date(), isRead: true, subject: nil, preview: nil,
                destination: .none, descriptionText: "liked your post", groupHint: "today", requestID: nil
            ),
            ActivityEvent(
                id: "3", kind: .followRequest, actor: ActivityActor(id: "c", handle: nil, displayName: "Mia", avatarURL: nil),
                actors: [], createdAt: Date(), isRead: false, subject: nil, preview: nil,
                destination: .activityRequests, descriptionText: "wants to follow you", groupHint: nil, requestID: "3"
            )
        ]
        let summary = ActivitySummary.aggregates(from: events, pendingRequests: 2)
        XCTAssertEqual(summary.source, .aggregates)
        XCTAssertEqual(summary.unreadCount, 2)
        XCTAssertEqual(summary.mentionCount, 1)
        XCTAssertEqual(summary.requestCount, 2)
        XCTAssertEqual(summary.reactionCount, 1)
        XCTAssertTrue(summary.mostActiveNames.contains("Sophia") || summary.mostActiveNames.contains("Marcus") || summary.mostActiveNames.contains("Mia"))
        XCTAssertFalse(summary.highlights.isEmpty)
    }

    func testActivityFilterUnread() {
        let unread = ActivityEvent(
            id: "1", kind: .like, actor: nil, actors: [], createdAt: Date(), isRead: false,
            subject: nil, preview: nil, destination: .none, descriptionText: "liked", groupHint: nil, requestID: nil
        )
        let read = ActivityEvent(
            id: "2", kind: .like, actor: nil, actors: [], createdAt: Date(), isRead: true,
            subject: nil, preview: nil, destination: .none, descriptionText: "liked", groupHint: nil, requestID: nil
        )
        XCTAssertTrue(ActivityFilter.unread.matches(unread))
        XCTAssertFalse(ActivityFilter.unread.matches(read))
        XCTAssertTrue(ActivityFilter.posts.matches(unread))
        XCTAssertTrue(ActivityFilter.modules.matches(
            ActivityEvent(id: "3", kind: .moduleUpdate, actor: nil, actors: [], createdAt: Date(), isRead: true,
                          subject: nil, preview: nil, destination: .none, descriptionText: "updated", groupHint: nil, requestID: nil)
        ))
    }
}

@MainActor
final class ActivityRouteAndAccessoryTests: XCTestCase {
    func testActivityRoutesRoundTrip() {
        XCTAssertEqual(RouteParser.parse("/activity"), .activity(.all))
        XCTAssertEqual(RouteSerializer.serialize(.activity(.all)), "/activity/all")
        XCTAssertEqual(RouteParser.parse("/activity/mentions"), .activity(.mentions))
        XCTAssertEqual(RouteParser.parse("/activity/requests"), .activity(.requests))
    }

    func testActivityAccessoryDoesNotDuplicateRailModes() {
        let config = ShellAccessoryConfiguration.configuration(for: .activity(.mentions), activity: nil, signedIn: true)
        XCTAssertEqual(config.title, "Activity")
        XCTAssertFalse(config.actions.contains(where: { $0.title == "Mentions" || $0.title == "All" || $0.title == "Requests" }))
        XCTAssertEqual(Set(config.actions.map(\.id)), Set(["summary", "filter", "mark-read"]))
        XCTAssertFalse(config.showsSearch)
    }

    func testMarkAllReadDisabledWhenEverythingRead() {
        let store = ActivityStore(client: GreenfieldClient(baseURL: URL(string: "https://example.invalid")))
        // Empty store → no unread → mark-read disabled
        let config = ShellAccessoryConfiguration.configuration(for: .activity(.all), activity: store, signedIn: true)
        XCTAssertFalse(config.actions.first { $0.id == "mark-read" }?.enabled ?? true)
    }
}

@MainActor
final class GreenfieldAuthContractTests: XCTestCase {
    func testInvalidPasswordAgainstProductionRejectsWithMappedError() async throws {
        // Contract probe only — never stores credentials. Confirms encoding + error mapping path.
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        do {
            _ = try await client.signIn(email: "native-n3a-invalid@example.invalid", password: "definitely-wrong-password")
            XCTFail("Expected rejection")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected(401, "INVALID_CREDENTIALS"))
            XCTAssertEqual(error.userFacingMessage, "Incorrect email or password.")
        }
    }

    func testProtectedNotificationRequiresAuthentication() async throws {
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.digital"))
        do {
            _ = try await client.authenticatedJSON("GET", path: "/v1/notifications?limit=1")
            XCTFail("Expected unauthenticated")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthenticated)
        }
    }

    func testFixtureLoginAgainstNativeN1Succeeds() async throws {
        let secretPath = ProcessInfo.processInfo.environment["N1_SECRET_FILE"]
            ?? "/Users/msjoy/Developer/modula-native/.env.n1.local"
        let data = try Data(contentsOf: URL(fileURLWithPath: secretPath))
        struct Fixture: Decodable { let email: String; let password: String }
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        // Debug app points at the Cloudflare N1 edge, not localhost tunnel.
        let client = GreenfieldClient(baseURL: URL(string: "https://native-n1.modula.digital"))
        let account = try await client.signIn(email: fixture.email, password: fixture.password)
        XCTAssertEqual(account.status, "active")
        XCTAssertFalse(account.accountId.isEmpty)
        try await client.signOut()
    }
}
