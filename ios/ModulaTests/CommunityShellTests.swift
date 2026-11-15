import Foundation
import XCTest
@testable import Modula

final class CommunityShellTests: XCTestCase {
    func testCommunityCapabilityIsEnabledInReleaseAndDebug() {
        let defaults = UserDefaults(suiteName: "community.tests.\(UUID().uuidString)")!
        XCTAssertTrue(CommunityFeatureFlags.isEnabled(defaults: defaults, release: true))
        XCTAssertTrue(CommunityFeatureFlags.isEnabled(defaults: defaults, release: false))
    }

    func testCommunityRoutesRoundTrip() {
        for route in CommunityRoute.allCases {
            let appRoute = AppRoute.community(route)
            let path = RouteSerializer.serialize(appRoute)
            XCTAssertEqual(RouteParser.parse(path), appRoute, path)
            XCTAssertNil(appRoute.tab)
        }
        XCTAssertEqual(RouteParser.parse("/community"), .community(.hub))
        XCTAssertEqual(RouteSerializer.serialize(.community(.modulaBuilders)), "/community/modula-builders")
        XCTAssertNil(RouteParser.parse("/community/nope"))
    }

    func testCommunityAPIUsesDedicatedAtlasContracts() {
        let id = "11111111-1111-4111-8111-111111111111"
        let poll = "22222222-2222-4222-8222-222222222222"
        let event = "33333333-3333-4333-8333-333333333333"
        XCTAssertEqual(CommunityAPI.community(id), "/v1/communities/\(id)")
        XCTAssertEqual(CommunityAPI.join(id), "/v1/communities/\(id)/join")
        XCTAssertEqual(CommunityAPI.leave(id), "/v1/communities/\(id)/leave")
        XCTAssertEqual(CommunityAPI.postCollection(id), "/v1/communities/\(id)/posts")
        XCTAssertEqual(CommunityAPI.settings(id), "/v1/communities/\(id)/settings")
        XCTAssertEqual(CommunityAPI.vote(id, pollID: poll), "/v1/communities/\(id)/polls/\(poll)/vote")
        XCTAssertEqual(CommunityAPI.response(id, eventID: event), "/v1/communities/\(id)/events/\(event)/response")
        XCTAssertTrue(CommunityAPI.members(id, cursor: "a|b").contains("cursor=a%7Cb"))
        XCTAssertTrue(CommunityAPI.list(query: "Modula Builders", membership: "joined").contains("query=Modula%20Builders"))
    }

    func testCommunityDecoderPreservesServerMembershipRoleAndVersion() throws {
        let details = try CommunityPayloadDecoder.details(communityJSON())
        XCTAssertEqual(details.summary.name, "Modula Builders")
        XCTAssertEqual(details.summary.membership, .active)
        XCTAssertEqual(details.summary.viewerRole, .moderator)
        XCTAssertEqual(details.summary.memberCount, 42)
        XCTAssertEqual(details.summary.version, 7)
        XCTAssertEqual(details.membershipPolicy, .open)
        XCTAssertEqual(details.postingPolicy, .moderators)
    }

    func testCapabilitiesAreDerivedFromServerRoleAndPostingPolicy() throws {
        let details = try CommunityPayloadDecoder.details(communityJSON())
        let moderator = CommunityCapabilities.derive(from: details, settings: nil)
        XCTAssertTrue(moderator.canPost)
        XCTAssertTrue(moderator.canModerate)
        XCTAssertFalse(moderator.canManage)
        XCTAssertTrue(moderator.canVoteAndRSVP)

        let outsider = CommunityDetails(
            summary: replacingMembership(details.summary, membership: .none, role: nil),
            ownerActorID: details.ownerActorID,
            membershipPolicy: details.membershipPolicy,
            postingPolicy: details.postingPolicy,
            createdAt: details.createdAt,
            updatedAt: details.updatedAt
        )
        let denied = CommunityCapabilities.derive(from: outsider, settings: nil)
        XCTAssertEqual(denied, .init(canPost: false, canModerate: false, canManage: false, canVoteAndRSVP: false))
    }

    func testSettingsDecoderUsesServerCapabilityAndNotificationPreferences() throws {
        let settings = try CommunityPayloadDecoder.settings(.object([
            "communityId": .string("11111111-1111-4111-8111-111111111111"),
            "canManage": .bool(false),
            "membershipPolicy": .string("open"),
            "postingPolicy": .string("members"),
            "inviteLinksEnabled": .bool(false),
            "allowAttachments": .bool(true),
            "reactionsEnabled": .bool(true),
            "featuredPostsEnabled": .bool(false),
            "blockedWords": .null,
            "notificationPreferences": .object([
                "notifyMentions": .bool(false), "weeklyDigest": .bool(true), "eventReminders": .bool(false),
            ]),
            "version": .number(7),
            "updatedAt": .string("2026-11-02T12:00:00.000Z"),
        ]))
        XCTAssertFalse(settings.canManage)
        XCTAssertFalse(settings.notifyMentions)
        XCTAssertTrue(settings.weeklyDigest)
        XCTAssertNil(settings.blockedWords)
        XCTAssertEqual(settings.version, 7)
    }

    func testPollDecoderUsesCommunityPollContract() throws {
        let poll = try CommunityPayloadDecoder.poll(.object([
            "id": .string("22222222-2222-4222-8222-222222222222"),
            "communityId": .string("11111111-1111-4111-8111-111111111111"),
            "creatorActorId": .string("actor-1"),
            "question": .string("What next?"),
            "options": .array([
                .object(["id": .string("option-1"), "position": .number(0), "text": .string("Profiles"), "voteCount": .number(3)]),
                .object(["id": .string("option-2"), "position": .number(1), "text": .string("Modules"), "voteCount": .number(2)]),
            ]),
            "closesAt": .string("2026-11-03T12:00:00.000Z"),
            "allowVoteChanges": .bool(true),
            "resultsVisibility": .string("afterVote"),
            "status": .string("open"),
            "closed": .bool(false),
            "viewerOptionId": .string("option-2"),
            "totalVotes": .number(5),
            "version": .number(1),
        ]))
        XCTAssertEqual(poll.viewerOptionID, "option-2")
        XCTAssertEqual(poll.totalVotes, 5)
        XCTAssertEqual(poll.options.map(\.text), ["Profiles", "Modules"])
    }

    func testCursorPageAndCommentPollContractsRemainDistinct() throws {
        let page = try CommunityPayloadDecoder.page(.object([
            "items": .array([communityJSON()]),
            "nextCursor": .string("cursor-2"),
            "hasMore": .bool(true),
        ]), decode: CommunityPayloadDecoder.summary)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "cursor-2")
        XCTAssertTrue(page.hasMore)

        XCTAssertEqual(CommentPollVote.path(commentID: "cmt_1"), "/v1/comments/cmt_1/poll/vote")
        XCTAssertEqual(CommentPollVote.body(optionIndex: 2), .object(["optionIndex": .number(2)]))
    }

    private func communityJSON() -> JSONValue {
        .object([
            "id": .string("11111111-1111-4111-8111-111111111111"),
            "slug": .string("modula-builders"),
            "name": .string("Modula Builders"),
            "description": .string("Build Modula together."),
            "category": .string("Technology"),
            "visibility": .string("public"),
            "discoverable": .bool(true),
            "featured": .bool(true),
            "memberCount": .number(42),
            "membership": .string("active"),
            "viewerRole": .string("moderator"),
            "recentActivityAt": .string("2026-11-02T12:00:00.000Z"),
            "artwork": .object(["iconUrl": .null, "coverUrl": .null]),
            "version": .number(7),
            "ownerActorId": .string("owner-1"),
            "membershipPolicy": .string("open"),
            "postingPolicy": .string("moderators"),
            "createdAt": .string("2026-10-01T12:00:00.000Z"),
            "updatedAt": .string("2026-11-02T12:00:00.000Z"),
        ])
    }

    private func replacingMembership(
        _ value: CommunitySummary,
        membership: CommunityMembership,
        role: CommunityRole?
    ) -> CommunitySummary {
        CommunitySummary(
            id: value.id, slug: value.slug, name: value.name, description: value.description,
            category: value.category, visibility: value.visibility, discoverable: value.discoverable,
            featured: value.featured, memberCount: value.memberCount, membership: membership,
            viewerRole: role, recentActivityAt: value.recentActivityAt, artwork: value.artwork, version: value.version
        )
    }
}

private final class CommunityContractProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var captured: [(String, String, JSONValue?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        let body = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let responseBody: String
        switch (method, path) {
        case ("POST", "/v1/sessions"):
            let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
            responseBody = #"{"ok":true,"data":{"accessToken":"access","refreshToken":"refresh","sessionId":"session","accessExpiresAt":"\#(future)","refreshExpiresAt":"\#(future)"}}"#
        case ("GET", "/v1/accounts/me"):
            responseBody = #"{"ok":true,"data":{"accountId":"account","primaryHandle":"me","status":"active"}}"#
        case ("POST", let value) where value.hasSuffix("/posts"):
            Self.captured.append((method, path, body))
            responseBody = #"{"ok":true,"data":{"item":{"communityId":"11111111-1111-4111-8111-111111111111","moderationState":"visible","featuredAt":null,"post":{"id":"post-server","createdAt":"2026-11-02T12:00:00.000Z","text":"Hello builders","kind":"text","audience":"public","media":[]}}}}"#
        case ("PUT", let value) where value.hasSuffix("/vote"):
            Self.captured.append((method, path, body))
            responseBody = #"{"ok":true,"data":{"poll":{"id":"22222222-2222-4222-8222-222222222222","communityId":"11111111-1111-4111-8111-111111111111","creatorActorId":"actor","question":"What next?","options":[{"id":"option-2","position":0,"text":"Modules","voteCount":1}],"closesAt":"2026-12-02T12:00:00.000Z","allowVoteChanges":true,"resultsVisibility":"afterVote","status":"open","closed":false,"viewerOptionId":"option-2","totalVotes":1,"version":1}}}"#
        case ("PUT", let value) where value.hasSuffix("/response"):
            Self.captured.append((method, path, body))
            responseBody = #"{"ok":true,"data":{"event":{"id":"33333333-3333-4333-8333-333333333333","communityId":"11111111-1111-4111-8111-111111111111","creatorActorId":"actor","title":"QA Review","description":"","startsAt":"2026-12-10T18:00:00.000Z","endsAt":"2026-12-10T19:00:00.000Z","timezone":"Europe/London","location":{"type":"online","name":null,"onlineUrl":"https://example.invalid/qa"},"coverAttachmentId":null,"coverUrl":null,"capacity":25,"status":"scheduled","goingCount":0,"interestedCount":1,"viewerResponse":"interested","version":1,"createdAt":"2026-11-02T12:00:00.000Z","updatedAt":"2026-11-02T12:00:00.000Z"}}}"#
        default:
            responseBody = #"{"ok":false,"error":{"code":"NOT_FOUND"}}"#
        }
        let status = responseBody.contains(#""ok":true"#) ? 200 : 404
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CommunityRepositoryContractTests: XCTestCase {
    func testMutationsUseExactGreenFieldPathsAndBodies() async throws {
        CommunityContractProtocol.captured = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommunityContractProtocol.self]
        let client = GreenfieldClient(
            baseURL: URL(string: "https://community-contract-\(UUID().uuidString.prefix(8)).modula.test")!,
            transport: URLSession(configuration: configuration)
        )
        _ = try await client.signIn(email: "community@example.com", password: "test-only")
        let repository = GreenfieldCommunityRepository(client: client)
        let communityID = "11111111-1111-4111-8111-111111111111"
        let pollID = "22222222-2222-4222-8222-222222222222"
        let eventID = "33333333-3333-4333-8333-333333333333"

        let post = try await repository.createPost(
            communityID, text: "Hello builders", idempotencyKey: "community-post-contract"
        )
        let poll = try await repository.vote(communityID: communityID, pollID: pollID, optionID: "option-2")
        let event = try await repository.respond(communityID: communityID, eventID: eventID, response: .interested)

        XCTAssertEqual(post.id, "post-server")
        XCTAssertEqual(poll.viewerOptionID, "option-2")
        XCTAssertEqual(event.viewerResponse, .interested)
        XCTAssertEqual(CommunityContractProtocol.captured.count, 3)
        XCTAssertEqual(CommunityContractProtocol.captured[0].0, "POST")
        XCTAssertEqual(CommunityContractProtocol.captured[0].1, "/v1/communities/\(communityID)/posts")
        XCTAssertEqual(CommunityContractProtocol.captured[0].2, .object([
            "text": .string("Hello builders"), "idempotencyKey": .string("community-post-contract"),
        ]))
        XCTAssertEqual(CommunityContractProtocol.captured[1].1, "/v1/communities/\(communityID)/polls/\(pollID)/vote")
        XCTAssertEqual(CommunityContractProtocol.captured[1].2, .object(["optionId": .string("option-2")]))
        XCTAssertEqual(CommunityContractProtocol.captured[2].1, "/v1/communities/\(communityID)/events/\(eventID)/response")
        XCTAssertEqual(CommunityContractProtocol.captured[2].2, .object(["response": .string("interested")]))
    }
}
