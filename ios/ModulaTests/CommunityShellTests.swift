import XCTest
@testable import Modula

final class CommunityShellTests: XCTestCase {
    func testReleaseBuildNeverEnablesTheShell() {
        let defaults = suite()
        XCTAssertFalse(CommunityFeatureFlags.isEnabled(defaults: defaults, release: true))
        defaults.set(true, forKey: CommunityFeatureFlags.storageKey)
        XCTAssertFalse(CommunityFeatureFlags.isEnabled(defaults: defaults, release: true))
    }

    func testDebugDefaultIsOnUntilTurnedOff() {
        let defaults = suite()
        XCTAssertTrue(CommunityFeatureFlags.isEnabled(defaults: defaults, release: false))
        defaults.set(false, forKey: CommunityFeatureFlags.storageKey)
        XCTAssertFalse(CommunityFeatureFlags.isEnabled(defaults: defaults, release: false))
        defaults.set(true, forKey: CommunityFeatureFlags.storageKey)
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
        XCTAssertEqual(RouteParser.parse("/community/hub"), .community(.hub))
        XCTAssertEqual(RouteSerializer.serialize(.community(.hub)), "/community")
        XCTAssertEqual(RouteSerializer.serialize(.community(.modulaBuilders)), "/community/modula-builders")
        XCTAssertNil(RouteParser.parse("/community/nope"))
        XCTAssertNil(RouteParser.parse("/community/for-you/extra"))
    }

    func testCopyDoesNotInventMembersOrCounts() {
        let blob = CommunityCopy.catalogued.joined(separator: "\n")
        XCTAssertNil(blob.range(of: #"\d"#, options: .regularExpression))
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("members"))
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("going"))
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("votes"))
    }

    func testLocalSettingsRoundTripWithoutAServer() {
        let defaults = suite()
        var settings = CommunityLocalSettings()
        XCTAssertEqual(settings.shownName, CommunityCopy.buildersTitle)
        settings.displayName = "Local draft"
        settings.summary = "On this device"
        settings.isPrivate = true
        settings.interestedOnDevice = true
        settings.blockedWords = "spam"
        settings.save(defaults: defaults)
        let loaded = CommunityLocalSettings.load(defaults: defaults)
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.shownName, "Local draft")
    }

    func testCommentPollVoteMatchesTheAtlasRoute() {
        XCTAssertEqual(CommentPollVote.path(commentID: "cmt_1"), "/v1/comments/cmt_1/poll/vote")
        XCTAssertEqual(
            CommentPollVote.path(commentID: "a b"),
            "/v1/comments/a%20b/poll/vote"
        )
        XCTAssertEqual(CommentPollVote.body(optionIndex: 2), .object(["optionIndex": .number(2)]))
        XCTAssertEqual(CommentPollVote.body(optionIndex: nil), .object(["optionIndex": .null]))
        XCTAssertTrue(CommunityPollListing.acceptsPostID("post-1"))
        XCTAssertFalse(CommunityPollListing.acceptsPostID(" "))
        XCTAssertFalse(CommunityPollListing.acceptsPostID("post/1"))
    }

    func testPollListingUsesOnlyCommentPolls() {
        var withPoll = comment("c1", text: "Question")
        var media = SocialCommentMedia(id: "poll:1", kind: .poll, url: SocialCommentMedia.placeholderURL)
        media.poll = CommentPoll(
            question: "Real question",
            options: ["A", "B"],
            counts: [1, 0],
            totalVotes: 1,
            viewerVote: 0,
            closed: false,
            closesAt: nil
        )
        withPoll.media = [media]
        let plain = comment("c2", text: "Hello")
        let rows = CommunityPollListing.rows(in: [plain, withPoll])
        XCTAssertEqual(rows.map(\.id), ["c1"])
        XCTAssertEqual(rows.first?.poll.question, "Real question")
        XCTAssertEqual(rows.first?.poll.totalVotes, 1)
    }

    private func comment(_ id: String, text: String) -> SocialComment {
        SocialComment(
            id: id,
            postID: "post-1",
            author: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            editedAt: nil,
            text: text,
            parentID: nil,
            replyCount: 0,
            liked: false,
            likeCount: 0,
            isPending: false
        )
    }

    private func suite() -> UserDefaults {
        let name = "community.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
