import Foundation
import XCTest
import UserNotifications
@testable import Modula

@MainActor
final class PushNotificationTests: XCTestCase {
    func test_hexEncodesDeviceToken() {
        XCTAssertTrue(PushAPI.hexToken(Data([0x00, 0xab, 0xff, 0x10])) == "00abff10")
    }

    func test_neverOffersWithoutFlagSignInOrWhenDecided() {
        let policy = PushPrePromptPolicy(launches: 5, dismissals: 0, lastDismissedAt: nil)
        XCTAssertFalse(policy.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: false))
        XCTAssertFalse(policy.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: false, flagEnabled: true))
        XCTAssertFalse(policy.shouldOffer(moment: .messageSent, status: .authorized, signedIn: true, flagEnabled: true))
        XCTAssertFalse(policy.shouldOffer(moment: .messageSent, status: .denied, signedIn: true, flagEnabled: true))
        XCTAssertTrue(policy.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: true))
    }

    func test_activityMomentWaitsForSecondLaunch() {
        let first = PushPrePromptPolicy(launches: 1, dismissals: 0, lastDismissedAt: nil)
        XCTAssertFalse(first.shouldOffer(moment: .activityViewed, status: .notDetermined, signedIn: true, flagEnabled: true))
        let second = PushPrePromptPolicy(launches: 2, dismissals: 0, lastDismissedAt: nil)
        XCTAssertTrue(second.shouldOffer(moment: .activityViewed, status: .notDetermined, signedIn: true, flagEnabled: true))
    }

    func test_coolDownGrowsAndCapsAfterDismissals() {
        let now = Date()
        let recent = PushPrePromptPolicy(launches: 9, dismissals: 1, lastDismissedAt: now.addingTimeInterval(-3 * 86_400))
        XCTAssertFalse(recent.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: true, now: now))
        let later = PushPrePromptPolicy(launches: 9, dismissals: 1, lastDismissedAt: now.addingTimeInterval(-8 * 86_400))
        XCTAssertTrue(later.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: true, now: now))
        let twice = PushPrePromptPolicy(launches: 9, dismissals: 2, lastDismissedAt: now.addingTimeInterval(-8 * 86_400))
        XCTAssertFalse(twice.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: true, now: now))
        let capped = PushPrePromptPolicy(launches: 9, dismissals: 3, lastDismissedAt: now.addingTimeInterval(-90 * 86_400))
        XCTAssertFalse(capped.shouldOffer(moment: .messageSent, status: .notDetermined, signedIn: true, flagEnabled: true, now: now))
        XCTAssertTrue(capped.shouldOffer(moment: .settings, status: .notDetermined, signedIn: true, flagEnabled: true, now: now))
    }

    func test_parsesPayloadAndDeepLinksIntoCanonicalRoutes() {
        let payload = PushPayload(userInfo: ["modula": ["deliveryId": "d1", "category": "comments", "deepLink": "modula://post/p1/comments", "resourceType": "post", "resourceId": "p1"]])
        XCTAssertTrue(payload.route == .post("p1", .comments))
        XCTAssertTrue(PushPayload(userInfo: ["modula": ["deepLink": "modula://activity/requests"]]).route == .activity(.requests))
        XCTAssertTrue(PushPayload(userInfo: ["modula": ["deepLink": "modula://messages/c1"]]).route == .messages(.conversation("c1")))
        XCTAssertTrue(PushPayload(userInfo: ["modula": ["deepLink": "modula://profile/alice"]]).route == .profile("alice", .overview))
        XCTAssertTrue(PushPayload(userInfo: ["modula": ["deepLink": "https://evil.example/post/1"]]).route == nil)
        XCTAssertTrue(PushPayload(userInfo: [:]).route == nil)
    }

    func test_mapsActionsToRealGreenfieldRoutes() {
        let post = PushPayload(userInfo: ["modula": ["category": "comments", "resourceType": "post", "resourceId": "p1"]])
        XCTAssertTrue(PushNotificationAction.like.request(for: post)?.path == "/v1/posts/p1/like")
        let reply = PushNotificationAction.reply("  nice  ").request(for: post)
        XCTAssertTrue(reply?.path == "/v1/posts/p1/comments")
        XCTAssertTrue(reply?.body == .object(["text": .string("nice")]))
        XCTAssertTrue(PushNotificationAction.reply("   ").request(for: post) == nil)
        let message = PushPayload(userInfo: ["modula": ["category": "messages", "conversationId": "c1"]])
        XCTAssertTrue(PushNotificationAction.reply("hi").request(for: message)?.path == "/v1/conversations/c1/messages")
        let request = PushPayload(userInfo: ["modula": ["category": "follows", "followRequestId": "r1"]])
        XCTAssertTrue(PushNotificationAction.accept.request(for: request)?.path == "/v1/follow-requests/r1/accept")
        XCTAssertTrue(PushNotificationAction.open.request(for: post) == nil)
        XCTAssertTrue(PushNotificationAction(identifier: PushNotificationCategories.replyAction, text: "x") == .reply("x"))
        XCTAssertTrue(PushNotificationAction(identifier: UNNotificationDefaultActionIdentifier, text: nil) == .open)
    }

    func test_registersCategoriesMatchingTheWorker() {
        let ids = Set(PushNotificationCategories.all().map(\.identifier))
        XCTAssertTrue(ids == ["MODULA_COMMENT", "MODULA_MESSAGE", "MODULA_FOLLOW_REQUEST", "MODULA_GUBIC_INVITE"])
    }

    func test_decodesServerPreferences() throws {
        let json = #"{"enabled":true,"categories":{"likes":false,"molibooCare":true},"quietHours":{"enabled":true,"start":"22:00","end":"07:00","timezone":"Europe/London"},"version":3,"updatedAt":"2026-11-01T00:00:00Z"}"#
        let prefs = try JSONDecoder().decode(PushPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(prefs.categories["likes"] == false)
        XCTAssertTrue(prefs.quietHours.timezone == "Europe/London")
        XCTAssertTrue(prefs.version == 3)
    }
}
