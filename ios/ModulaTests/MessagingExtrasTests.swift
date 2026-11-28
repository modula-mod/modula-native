import XCTest
@testable import Modula

/// Messaging batch 1: device-local stores (pinned messages, manual unread, scheduled
/// messages, quick replies), reminder planning and chat export. No network.
@MainActor
final class MessagingExtrasTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "MessagingExtrasTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_784_000_000)
    private let sam = ConversationParticipant(id: "a-sam", handle: "sam", displayName: "Sam Lee", avatarURL: nil)

    private func message(_ id: String, _ text: String, own: Bool = false, at offset: TimeInterval = 0, in chat: String = "c1") -> Message {
        Message(id: id, conversationID: chat, sender: sam, body: .text(text), sentAt: now.addingTimeInterval(offset),
                delivery: .sent, isOwn: own, localDraft: nil)
    }

    // MARK: Pinned messages

    func testPinTogglePersistsAndUnpins() {
        let extras = MessagingExtras(defaults: defaults)
        extras.togglePin(message("m1", "Dinner at 8?"), now: now)
        XCTAssertTrue(extras.isMessagePinned("m1", in: "c1"))
        XCTAssertEqual(MessagingExtras(defaults: defaults).pins(for: "c1").map(\.id), ["m1"])
        extras.togglePin(message("m1", "Dinner at 8?"), now: now)
        XCTAssertFalse(extras.isMessagePinned("m1", in: "c1"))
        XCTAssertNil(defaults.data(forKey: MessagePinnedStore.key))
    }

    func testPinLimitDropsOldest() {
        let extras = MessagingExtras(defaults: defaults)
        for i in 1...4 { extras.togglePin(message("m\(i)", "Message \(i)"), now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(extras.pins(for: "c1").map(\.id), ["m4", "m3", "m2"])
    }

    func testPinsAreScopedPerChat() {
        let extras = MessagingExtras(defaults: defaults)
        extras.togglePin(message("m1", "Hi", in: "c1"), now: now)
        extras.togglePin(message("m2", "Yo", in: "c2"), now: now)
        XCTAssertEqual(extras.pins(for: "c1").count, 1)
        XCTAssertEqual(extras.pins(for: "c2").count, 1)
        extras.unpin("m2", in: "c2")
        XCTAssertTrue(extras.pins(for: "c2").isEmpty)
    }

    func testPinExcerptIsTrimmed() {
        let long = String(repeating: "a", count: 400)
        let excerpt = MessagePinnedStore.excerpt(long)
        XCTAssertEqual(excerpt.count, MessagePinnedStore.excerptLength)
        XCTAssertTrue(excerpt.hasSuffix("…"))
    }

    // MARK: Manual unread

    func testMarkUnreadPersistsAndClears() {
        let extras = MessagingExtras(defaults: defaults)
        extras.markUnread("c1")
        XCTAssertTrue(MessagingExtras(defaults: defaults).isMarkedUnread("c1"))
        extras.clearUnreadMark("c1")
        XCTAssertFalse(MessagingExtras(defaults: defaults).isMarkedUnread("c1"))
    }

    // MARK: Scheduled messages

    func testScheduleValidation() {
        XCTAssertEqual(MessageScheduleStore.validate(text: "  ", sendAt: now.addingTimeInterval(3600), now: now, pendingCount: 0), .empty)
        XCTAssertEqual(MessageScheduleStore.validate(text: "Hi", sendAt: now.addingTimeInterval(10), now: now, pendingCount: 0), .tooSoon)
        XCTAssertEqual(MessageScheduleStore.validate(text: "Hi", sendAt: now.addingTimeInterval(31 * 86_400), now: now, pendingCount: 0), .tooFar)
        XCTAssertEqual(MessageScheduleStore.validate(text: String(repeating: "x", count: 4001), sendAt: now.addingTimeInterval(3600), now: now, pendingCount: 0), .tooLong)
        XCTAssertEqual(MessageScheduleStore.validate(text: "Hi", sendAt: now.addingTimeInterval(3600), now: now, pendingCount: 50), .queueFull)
        XCTAssertEqual(MessageScheduleStore.validate(text: "Hi", sendAt: now.addingTimeInterval(3600), now: now, pendingCount: 0), .ok)
    }

    func testScheduleStoresSortedAndPersists() {
        let extras = MessagingExtras(defaults: defaults)
        XCTAssertEqual(extras.schedule(text: "later", at: now.addingTimeInterval(7200), in: "c1", now: now), .ok)
        XCTAssertEqual(extras.schedule(text: " sooner ", at: now.addingTimeInterval(3600), in: "c1", now: now), .ok)
        let reloaded = MessagingExtras(defaults: defaults).scheduled(for: "c1")
        XCTAssertEqual(reloaded.map(\.text), ["sooner", "later"])
    }

    func testDispatchSendsOnlyDueAndRemovesThem() async {
        let extras = MessagingExtras(defaults: defaults)
        extras.schedule(text: "first", at: now.addingTimeInterval(120), in: "c1", now: now)
        extras.schedule(text: "second", at: now.addingTimeInterval(7200), in: "c2", now: now)
        var sent: [(String, String)] = []
        let count = await extras.dispatchDue(now: now.addingTimeInterval(600)) { text, id in
            sent.append((text, id)); return true
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(sent.map(\.0), ["first"])
        XCTAssertEqual(sent.map(\.1), ["c1"])
        XCTAssertEqual(extras.scheduled.map(\.text), ["second"])
    }

    func testDispatchFailureRetriesThenMarksFailed() async {
        let extras = MessagingExtras(defaults: defaults)
        extras.schedule(text: "hello", at: now.addingTimeInterval(120), in: "c1", now: now)
        for _ in 0..<MessageScheduleStore.maxAttempts {
            _ = await extras.dispatchDue(now: now.addingTimeInterval(600)) { _, _ in false }
        }
        XCTAssertEqual(extras.scheduled.count, 1)
        XCTAssertTrue(extras.scheduled[0].failed)
        var calls = 0
        _ = await extras.dispatchDue(now: now.addingTimeInterval(900)) { _, _ in calls += 1; return true }
        XCTAssertEqual(calls, 0, "Failed items wait for a manual retry")
        extras.retryScheduled(extras.scheduled[0].id)
        XCTAssertFalse(extras.scheduled[0].failed)
    }

    func testCancelScheduled() {
        let extras = MessagingExtras(defaults: defaults)
        extras.schedule(text: "bye", at: now.addingTimeInterval(3600), in: "c1", now: now)
        extras.cancelScheduled(extras.scheduled[0].id)
        XCTAssertTrue(MessagingExtras(defaults: defaults).scheduled.isEmpty)
    }

    // MARK: Quick replies

    func testQuickRepliesDefaultsAddDedupeAndPersist() {
        let extras = MessagingExtras(defaults: defaults)
        XCTAssertEqual(extras.quickReplies, MessageQuickReplyStore.defaults)
        extras.addQuickReply("  on my way!  ")
        XCTAssertEqual(extras.quickReplies.first, "on my way!")
        XCTAssertEqual(extras.quickReplies.filter { $0.lowercased() == "on my way!" }.count, 1)
        extras.addQuickReply("   ")
        XCTAssertEqual(MessagingExtras(defaults: defaults).quickReplies, extras.quickReplies)
    }

    func testQuickReplyLimit() {
        var items: [String] = []
        for i in 0..<30 { items = MessageQuickReplyStore.adding("Reply \(i)", to: items) }
        XCTAssertEqual(items.count, MessageQuickReplyStore.limit)
        XCTAssertEqual(items.first, "Reply 29")
    }

    func testQuickReplySlashMatching() {
        let items = ["On my way!", "Thanks so much!", "Call you later"]
        XCTAssertNil(MessageQuickReplyStore.matches(for: "hello", in: items))
        XCTAssertEqual(MessageQuickReplyStore.matches(for: "/", in: items), items)
        XCTAssertEqual(MessageQuickReplyStore.matches(for: "/than", in: items), ["Thanks so much!"])
        XCTAssertNil(MessageQuickReplyStore.matches(for: "/a\nb", in: items))
    }

    func testQuickReplyRemoveAndMove() {
        let extras = MessagingExtras(defaults: defaults)
        extras.moveQuickReplies(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(extras.quickReplies[2], MessageQuickReplyStore.defaults[0])
        extras.removeQuickReplies(at: IndexSet(integer: 2))
        XCTAssertFalse(extras.quickReplies.contains(MessageQuickReplyStore.defaults[0]))
    }

    // MARK: Reminders

    func testReminderDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(MessageReminderOption.in1Hour.fireDate(from: now, calendar: calendar), now.addingTimeInterval(3600))
        let morning = MessageReminderOption.tomorrowMorning.fireDate(from: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: morning), 9)
        XCTAssertGreaterThan(morning, now)
        XCTAssertLessThanOrEqual(morning.timeIntervalSince(now), 2 * 86_400)
    }

    func testReminderContentDeepLinksToChat() {
        let content = MessageReminderPlanner.content(messageText: "Bring the keys", senderName: "Sam Lee", chatTitle: "Sam Lee", conversationID: "c1")
        XCTAssertEqual(content.body, "Sam Lee: Bring the keys")
        let modula = content.userInfo["modula"] as? [String: Any]
        let link = modula?["deepLink"] as? String
        XCTAssertEqual(link.flatMap(RouteParser.parse), .messages(.conversation("c1")))
        XCTAssertEqual(MessageReminderPlanner.identifier(for: "m1"), "messages.reminder.m1")
        XCTAssertEqual(MessageReminderPlanner.seconds(until: now.addingTimeInterval(-10), now: now), 5)
    }

    // MARK: Export

    func testTranscript() {
        var unsent = message("m3", "oops", own: true, at: 120)
        unsent.isDeleted = true
        let text = ChatTranscriptExporter.transcript(
            title: "Sam Lee",
            messages: [message("m1", "Hi"), message("m2", "Hey!", own: true, at: 60), unsent],
            timeZone: TimeZone(identifier: "UTC")!
        )
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Chat with Sam Lee")
        XCTAssertTrue(lines[1].contains("3 messages"))
        XCTAssertTrue(lines[3].hasSuffix("Sam Lee: Hi"))
        XCTAssertTrue(lines[4].hasSuffix("You: Hey!"))
        XCTAssertTrue(lines[5].hasSuffix("You: (unsent)"))
    }

    // MARK: Actions

    func testExtraActionsSkipLocalAndVoice() {
        let ids = MessageExtraActions.items(for: message("m1", "Hello"), local: false).map(\.id)
        XCTAssertEqual(ids, ["pinMessage", "selectText", "translate", "shareMessage", "remind"])
        let localIDs = MessageExtraActions.items(for: message("local-1", "Hello"), local: true).map(\.id)
        XCTAssertFalse(localIDs.contains("pinMessage"))
        XCTAssertFalse(localIDs.contains("remind"))
    }
}
