import XCTest
@testable import Modula

@MainActor
final class SettingsRealFeaturesTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: Phase 1 — local preferences that change behaviour

    func testSharingMethodFollowsPreferences() {
        XCTAssertEqual(PostSharing.method(copyAsLink: true, preferSystemSheet: true), .copyLink)
        XCTAssertEqual(PostSharing.method(copyAsLink: false, preferSystemSheet: true), .systemSheet)
        XCTAssertEqual(PostSharing.method(copyAsLink: false, preferSystemSheet: false), .modulaSheet)
    }

    func testInlineMessageContentHonoursChatSettings() {
        let text = "look https://example.com/photo.png"
        if case .image? = MessageInlineContent.detect(in: text, inlineMedia: true, linkPreviews: true) {} else { XCTFail("expected inline image") }
        if case .link? = MessageInlineContent.detect(in: text, inlineMedia: false, linkPreviews: true) {} else { XCTFail("expected link preview") }
        XCTAssertNil(MessageInlineContent.detect(in: text, inlineMedia: false, linkPreviews: false))
        XCTAssertNil(MessageInlineContent.detect(in: "no links here", inlineMedia: true, linkPreviews: true))
    }

    func testLargeUploadsWaitForWiFiOnlyWhenPreferred() {
        let big = CreationStudioStore.largeUploadThreshold + 1
        XCTAssertTrue(CreationStudioStore.shouldWaitForWiFi(pendingBytes: big, prefersWiFi: true, expensiveNetwork: true))
        XCTAssertFalse(CreationStudioStore.shouldWaitForWiFi(pendingBytes: big, prefersWiFi: false, expensiveNetwork: true))
        XCTAssertFalse(CreationStudioStore.shouldWaitForWiFi(pendingBytes: big, prefersWiFi: true, expensiveNetwork: false))
        XCTAssertFalse(CreationStudioStore.shouldWaitForWiFi(pendingBytes: 1_024, prefersWiFi: true, expensiveNetwork: true))
    }

    func testPreferenceStoreDefaultsAndOverrides() {
        let suite = "settings-real-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let previous = ModulaPreferences.store
        ModulaPreferences.store = defaults
        defer { ModulaPreferences.store = previous; defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ModulaPreferences.feedDefaultMode, .following)
        XCTAssertTrue(ModulaPreferences.videoStartsMuted)
        defaults.set("modules", forKey: ModulaPreferences.Key.feedDefaultMode)
        defaults.set(true, forKey: ModulaPreferences.Key.batteryDataSaver)
        XCTAssertEqual(ModulaPreferences.feedDefaultMode, .modules)
        XCTAssertFalse(ModulaPreferences.highResolutionUploads, "Data saver caps upload resolution")
        XCTAssertFalse(ModulaPreferences.chatLinkPreviews, "Data saver turns off link previews")
    }

    // MARK: Phase 1 — quiet hours

    func testQuietHoursWindowCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        }
        let overnight = QuietHoursWindow(enabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(overnight.contains(at(23), calendar: calendar))
        XCTAssertTrue(overnight.contains(at(6, 59), calendar: calendar))
        XCTAssertFalse(overnight.contains(at(7), calendar: calendar))
        XCTAssertFalse(overnight.contains(at(12), calendar: calendar))
        let day = QuietHoursWindow(enabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60)
        XCTAssertTrue(day.contains(at(12), calendar: calendar))
        XCTAssertFalse(QuietHoursWindow(enabled: false, startMinutes: 0, endMinutes: 23 * 60).contains(at(12), calendar: calendar))
        XCTAssertEqual(QuietHoursWindow.clock(7 * 60 + 5), "07:05")
        XCTAssertEqual(QuietHoursWindow.minutes("22:30"), 22 * 60 + 30)
        XCTAssertNil(QuietHoursWindow.minutes("25:00"))
    }

    // MARK: Phase 2 — mutes/blocks, insights, payouts, invoices

    func testRelationshipListDecodesAndBuildsUndoPath() throws {
        let value = try json(#"{"items":[{"profileId":"p 1","actorId":"a1","handle":"ada","displayName":"Ada","avatarUrl":null,"since":"2026-10-01T10:00:00.000Z"}]}"#)
        let list = try GreenfieldValueDecoder.decode(RelationshipListResponse.self, from: value)
        XCTAssertEqual(list.items.first?.handle, "ada")
        XCTAssertEqual(RelationshipListKind.muted.undoPath(profileID: "p 1"), "/v1/profiles/p%201/mute")
        XCTAssertEqual(RelationshipListKind.blocked.undoPath(profileID: "p1"), "/v1/profiles/p1/block")
    }

    func testInsightsDecodeTotalsAndTrend() throws {
        let value = try json("""
        {"days":7,"generatedAt":"2026-10-03T19:00:00.000Z",
         "totals":{"likes":3,"reactions":1,"comments":2,"shares":0,"saves":1,"newFollowers":2,"posts":1,"storyViews":4,"followers":10},
         "series":[{"date":"2026-10-02","likes":1,"reactions":0,"comments":1,"shares":0,"saves":0,"newFollowers":1,"posts":1,"storyViews":2}],
         "topPosts":[{"postId":"post-1","kind":"text","excerpt":"Hello","createdAt":"2026-10-02T09:00:00.000Z","likes":3,"reactions":1,"replies":2,"reposts":0,"shares":0,"saves":1}],
         "notTracked":["impressions","profileViews","reach"]}
        """)
        let insights = try GreenfieldValueDecoder.decode(CreatorInsightsResponse.self, from: value)
        XCTAssertEqual(insights.totals.engagement, 7)
        XCTAssertEqual(insights.series.first?.engagement, 2)
        XCTAssertEqual(insights.topPosts.first?.interactions, 7)
        XCTAssertEqual(CreatorInsightsResponse.trend([1, 1, 2, 2]) ?? 0, 1.0, accuracy: 0.001)
        XCTAssertNil(CreatorInsightsResponse.trend([0, 0, 3, 4]), "No baseline means no trend, never an invented one")
        XCTAssertEqual(CreatorInsightsView.trendLabel(-0.25), "Down 25% versus the first half of the period")
        XCTAssertTrue(CreatorInsightsView.untrackedLabel(insights.notTracked).contains("profile views"))
    }

    func testPayoutsAndInvoicesHaveTrueZeroState() throws {
        let ledger = try GreenfieldValueDecoder.decode(PayoutsLedgerResponse.self, from: json(#"{"provider":null,"payoutsEnabled":false,"reason":"No payment provider","balances":[],"entries":[]}"#))
        XCTAssertNil(ledger.provider)
        XCTAssertFalse(ledger.payoutsEnabled)
        XCTAssertTrue(ledger.entries.isEmpty)
        let invoices = try GreenfieldValueDecoder.decode(InvoicesResponse.self, from: json(#"{"provider":null,"items":[]}"#))
        XCTAssertTrue(invoices.items.isEmpty)
        XCTAssertEqual(SettingsMoney.format(minor: 1234, currency: "GBP", locale: Locale(identifier: "en_GB")), "£12.34")
        XCTAssertEqual(SettingsMoney.format(minor: 500, currency: "JPY", locale: Locale(identifier: "en_GB")), "JP¥500")
    }

    func testDigestStatusDecodesAndLabelsOutcomes() throws {
        let value = try json("""
        {"preferences":{"digests.weekly":true},"version":2,"updatedAt":null,
         "digests":{"deliveryEmail":"an***@example.com","emailVerified":true,"weeklyEnabled":true,"morningEnabled":false,"timeZone":"Europe/London",
          "schedule":{"morning":"Daily","weekly":"Mondays"},"recent":[{"kind":"weekly","period":"2026-W41","outcome":"quiet","at":"2026-10-05T08:00:00.000Z"}]}}
        """)
        let response = try GreenfieldValueDecoder.decode(AppPreferencesResponse.self, from: value)
        XCTAssertTrue(response.digests.weeklyEnabled)
        XCTAssertEqual(response.digests.recent.first?.id, "weekly-2026-W41")
        XCTAssertEqual(DigestsSettingsView.outcomeLabel("quiet"), "Skipped — nothing new")
        XCTAssertEqual(DigestsSettingsView.outcomeLabel("queued"), "Sent")
    }

    // MARK: Phase 3 — deletion and username

    func testDeletionStatusDecodesPendingRequest() throws {
        let none = try GreenfieldValueDecoder.decode(DeletionStatusResponse.self, from: json(#"{"request":null,"gracePeriodDays":7}"#))
        XCTAssertNil(none.request)
        let pending = try GreenfieldValueDecoder.decode(DeletionStatusResponse.self, from: json(#"{"request":{"requestId":"r1","state":"WAITING_RETENTION","requestedAt":"2026-10-03T19:00:00.000Z","scheduledFor":"2026-10-10T19:00:00.000Z","cancellable":true},"gracePeriodDays":7}"#))
        XCTAssertEqual(pending.request?.state, "WAITING_RETENTION")
        XCTAssertNotNil(SettingsISODate.parse(pending.request?.scheduledFor))
    }

    func testUsernameRulesMirrorServer() {
        XCTAssertEqual(UsernameRules.sanitize("Ada Lovelace!"), "adalovelace")
        XCTAssertNil(UsernameRules.problem("ada.lovelace"))
        XCTAssertNil(UsernameRules.problem("a_1"))
        XCTAssertNotNil(UsernameRules.problem("ad"))
        XCTAssertNotNil(UsernameRules.problem(".ada"))
        XCTAssertNotNil(UsernameRules.problem("ada..x"))
        XCTAssertNotNil(UsernameRules.problem("ada-"))
    }

    func testReportLabels() {
        XCTAssertEqual(MyReportsView.statusLabel("reviewing"), "In review")
        XCTAssertEqual(MyReportsView.statusLabel("dismissed"), "No action")
        XCTAssertEqual(MyReportsView.targetLabel("post"), "Post")
    }

    // MARK: Phase 4 — downloads

    func testDownloadsIndexListsDeletesAndClears() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateFileStore(domain: .attachmentDownloads, rootURL: root)
        let index = DownloadedMediaIndex(store: store)
        try store.saveData(Data(repeating: 1, count: 2_048), filename: "a.jpg")
        index.record(filename: "a.jpg", title: "Sunset.jpg", kind: "image", mimeType: "image/jpeg", at: Date(timeIntervalSince1970: 100))
        try store.saveData(Data(repeating: 2, count: 1_024), filename: "b.pdf")
        let listed = index.list()
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.first { $0.filename == "a.jpg" }?.title, "Sunset.jpg")
        XCTAssertEqual(listed.first { $0.filename == "b.pdf" }?.kind, "pdf", "Unindexed files are still listed by type")
        try index.remove(filename: "a.jpg")
        XCTAssertEqual(index.list().map(\.filename), ["b.pdf"])
        XCTAssertEqual(try index.removeAll(), 1_024)
        XCTAssertTrue(index.list().isEmpty)
    }

    // MARK: Registry honesty

    func testImplementedPagesAreNoLongerMarkedUnavailable() {
        for route: SettingsRoute in [.account(.username), .account(.deleteAccount), .safety(.muted), .safety(.reporting), .privacy(.blocked), .creator(.insights), .monetisation(.payouts), .monetisation(.invoices), .notifications(.social), .notifications(.modules), .notifications(.quietHours)] {
            XCTAssertEqual(SettingsRegistry.destination(for: route)?.availability, .implemented, "\(route)")
        }
        XCTAssertEqual(SettingsRegistry.destination(for: .account(.email))?.availability, .capabilityUnavailable)
    }

    // MARK: Phase 6 — decision-gated pages show real data

    func testConnectorProvidersDecodeLiveShapeAndNeverClaimAvailability() throws {
        let value = try json(#"[{"providerId":"modula.github","displayName":"GitHub","configuredStatus":"not-configured","operational":false,"privacySummary":"After permission.","capabilities":["identity.profile.read"],"extra":1}]"#)
        let providers = try GreenfieldValueDecoder.decode([ConnectorProvider].self, from: value)
        XCTAssertEqual(providers.first?.canConnect, false)
        XCTAssertEqual(providers.first?.statusLabel, "Not set up on Modula’s servers yet")
        XCTAssertEqual(ConnectorsSettingsView.connectionTitle(try json(#"{"displayName":"Work GitHub"}"#)), "Work GitHub")
    }

    func testPasskeyCreationNeedsMatchingAssociation() {
        XCTAssertFalse(PasskeySupport.nativeCreationReady(bundleID: "digital.modula.app.native", hasEntitlement: true))
        XCTAssertFalse(PasskeySupport.nativeCreationReady(bundleID: "digital.modula.app", hasEntitlement: false))
        XCTAssertTrue(PasskeySupport.nativeCreationReady(bundleID: "digital.modula.app", hasEntitlement: true))
    }
}
