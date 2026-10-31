import XCTest
@testable import Modula

/// Modula Premium phase 1: feature flag, local entitlement store, gating and plan content.
@MainActor
final class PremiumTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "premium-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: Feature flag

    func testPremiumRoutesMatchTheAtlasAndDoNotInventPurchases() throws {
        XCTAssertEqual(PremiumAPI.tiers, "/v1/premium/tiers")
        XCTAssertEqual(PremiumAPI.membership, "/v1/me/membership")
        XCTAssertEqual(PremiumAPI.entitlements, "/v1/me/entitlements")
        XCTAssertEqual(PremiumAPI.entitlement(capabilityId: "in-mail"), "/v1/me/entitlements/in-mail")
        XCTAssertEqual(PremiumAPI.badgeVisibility, "/v1/me/membership/badge-visibility")
        let data = try JSONEncoder().encode(PremiumBadgeVisibilityRequest(visible: false))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"visible\":false}")
        let source = PremiumAPI.tiers + PremiumAPI.membership + PremiumAPI.entitlements + PremiumAPI.badgeVisibility
        XCTAssertFalse(source.contains("checkout"))
        XCTAssertFalse(source.contains("/admin/"))
        XCTAssertFalse(source.contains("/commerce/"))
        XCTAssertEqual(PremiumCatalog.membershipDisclaimer, "Modula Premium is a paid membership. It does not verify identity.")
    }

    func testProfileBadgeFollowsTierAndIsNotVerification() {
        XCTAssertEqual(PremiumBadgeAsset.allCases.count, 16)
        XCTAssertNil(PremiumBadgeAsset.profileMark(for: .core))
        XCTAssertEqual(PremiumBadgeAsset.profileMark(for: .plus), .pearl)
        XCTAssertEqual(PremiumBadgeAsset.profileMark(for: .horizon), .horizon)
        XCTAssertEqual(PremiumBadgeAsset.profileMark(for: .horizonPlus), .horizonPlus)
        XCTAssertEqual(PremiumBadgeAsset.profileMark(for: .studio), .obsidian)
        let marks = PremiumPlan.paid.compactMap(PremiumBadgeAsset.profileMark(for:))
        XCTAssertEqual(Set(marks.map(\.rawValue)).count, 4)
        XCTAssertFalse(PremiumBadgeAsset.tierMarks.contains(.memberMark))
        XCTAssertTrue(PremiumBadgeAsset.gallery.contains(.memberMark))
        XCTAssertEqual(
            RouteParser.parse("/settings/premium/badge"),
            .settings(.premium(.badge))
        )
        XCTAssertEqual(
            RouteSerializer.serialize(.settings(.premium(.badge))),
            "/settings/premium/badge"
        )
    }

    func testFlagIsAlwaysOffInRelease() {
        defaults.set(true, forKey: PremiumFeatureFlags.enabledKey)
        XCTAssertFalse(PremiumFeatureFlags.premiumEnabled(defaults: defaults, isDebugBuild: false))
    }

    func testFlagDefaultsOnInDebugAndCanBeTurnedOff() {
        XCTAssertTrue(PremiumFeatureFlags.premiumEnabled(defaults: defaults, isDebugBuild: true))
        defaults.set(false, forKey: PremiumFeatureFlags.enabledKey)
        XCTAssertFalse(PremiumFeatureFlags.premiumEnabled(defaults: defaults, isDebugBuild: true))
    }

    // MARK: Entitlement store

    func testStoreDefaultsToCore() {
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        XCTAssertEqual(store.plan, .core)
        XCTAssertEqual(store.entitlement, .core)
        XCTAssertFalse(store.isPreviewing)
        XCTAssertFalse(store.showsOwnBadge, "Core never shows a badge")
        XCTAssertEqual(store.selectedPlan, .horizon, "Horizon is the recommended default")
    }

    func testDebugOverridePreviewsEachTierAndPersistsLocally() {
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        for plan in PremiumPlan.paid {
            store.setDebugOverride(plan)
            XCTAssertEqual(store.plan, plan)
            XCTAssertTrue(store.isPreviewing)
            XCTAssertTrue(store.showsOwnBadge)
        }
        let reloaded = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        XCTAssertEqual(reloaded.plan, .studio)
        store.setDebugOverride(nil)
        XCTAssertEqual(store.plan, .core)
        XCTAssertNil(defaults.string(forKey: PremiumFeatureFlags.debugPlanKey))
    }

    func testDebugOverrideIgnoredInRelease() {
        defaults.set(PremiumPlan.horizon.rawValue, forKey: PremiumFeatureFlags.debugPlanKey)
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: false)
        XCTAssertEqual(store.plan, .core)
        store.setDebugOverride(.horizonPlus)
        XCTAssertEqual(store.plan, .core)
        XCTAssertFalse(store.premiumEnabled)
        XCTAssertEqual(store.decision(for: .inMail), .hidden)
    }

    func testFlagOffHidesEverythingEvenWithOverride() {
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        store.setDebugOverride(.horizon)
        store.setPremiumEnabled(false)
        XCTAssertEqual(store.plan, .core)
        XCTAssertFalse(store.showsOwnBadge)
        for feature in PremiumFeature.allCases {
            XCTAssertEqual(store.decision(for: feature), .hidden, feature.rawValue)
        }
    }

    func testHidingBadgeKeepsFeatures() {
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        store.setDebugOverride(.horizon)
        store.badgeVisible = false
        XCTAssertFalse(store.showsOwnBadge)
        XCTAssertEqual(store.decision(for: .inMail), .available)
        XCTAssertEqual(store.decision(for: .profilePlate), .available)
        XCTAssertFalse(PremiumEntitlementStore(defaults: defaults, isDebugBuild: true).badgeVisible)
    }

    // MARK: Gating

    func testGateUpgradesToSmallestIncludingPlan() {
        XCTAssertEqual(PremiumGate.decision(for: .inMail, plan: .core, premiumEnabled: true), .upgrade(to: .plus))
        XCTAssertEqual(PremiumGate.decision(for: .profilePlate, plan: .plus, premiumEnabled: true), .upgrade(to: .horizon))
        XCTAssertEqual(PremiumGate.decision(for: .premiumMoliboos, plan: .horizon, premiumEnabled: true), .upgrade(to: .horizonPlus))
        XCTAssertEqual(PremiumGate.decision(for: .teamSeats, plan: .horizonPlus, premiumEnabled: true), .upgrade(to: .studio))
        XCTAssertEqual(PremiumGate.decision(for: .profilePlate, plan: .horizon, premiumEnabled: true), .available)
        XCTAssertEqual(PremiumGate.decision(for: .creatorStorefront, plan: .studio, premiumEnabled: true), .available)
    }

    func testEveryFeatureAvailableOnStudioAndNoneOnCore() {
        for feature in PremiumFeature.allCases {
            XCTAssertEqual(PremiumGate.decision(for: feature, plan: .studio, premiumEnabled: true), .available, feature.rawValue)
            XCTAssertNotEqual(PremiumGate.decision(for: feature, plan: .core, premiumEnabled: true), .available, feature.rawValue)
        }
    }

    func testModuleInstallsGatedOnlyAboveFreeLimitAndNeverWhenOff() {
        XCTAssertTrue(PremiumGate.canInstallAnotherModule(installed: 4, plan: .core, premiumEnabled: true))
        XCTAssertFalse(PremiumGate.canInstallAnotherModule(installed: 5, plan: .core, premiumEnabled: true))
        XCTAssertTrue(PremiumGate.canInstallAnotherModule(installed: 50, plan: .horizon, premiumEnabled: true))
        XCTAssertTrue(PremiumGate.canInstallAnotherModule(installed: 50, plan: .core, premiumEnabled: false), "Flag off: today's behaviour is unchanged")
    }

    // MARK: Plans and pricing

    func testLadderOrderAndLimitsAreMonotonic() {
        let ladder: [PremiumPlan] = [.core, .plus, .horizon, .horizonPlus, .studio]
        XCTAssertEqual(ladder.map(\.rank), Array(0...4))
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            XCTAssertLessThanOrEqual(a.inMailCreditsPerMonth, b.inMailCreditsPerMonth)
            XCTAssertLessThanOrEqual(a.storageGB, b.storageGB)
            XCTAssertLessThanOrEqual(a.visitorHistoryDays, b.visitorHistoryDays)
        }
        XCTAssertEqual(PremiumPlan.recommended, .horizon)
        XCTAssertNotNil(PremiumPlan.horizon.recommendationReason)
        XCTAssertNil(PremiumPlan.plus.recommendationReason)
        XCTAssertFalse(PremiumPlan.core.showsBadge)
    }

    func testPricesArePlaceholdersAndAnnualShowsTotal() {
        XCTAssertTrue(PremiumPricing.placeholderNote.lowercased().contains("placeholder"))
        XCTAssertEqual(PremiumPricing.priceLine(.core, billing: .annual), "Free")
        XCTAssertEqual(PremiumPricing.priceLine(.core, billing: .monthly), "Free")
        XCTAssertEqual(PremiumPricing.priceLine(.plus, billing: .monthly), "£3.99/mo")
        XCTAssertEqual(PremiumPricing.priceLine(.horizon, billing: .monthly), "£8.99/mo")
        XCTAssertEqual(PremiumPricing.priceLine(.horizonPlus, billing: .monthly), "£14.99/mo")
        XCTAssertEqual(PremiumPricing.priceLine(.studio, billing: .monthly), "from £29.99/mo per seat")
        let annual = PremiumPricing.priceLine(.horizon, billing: .annual)
        XCTAssertTrue(annual.hasPrefix("£89.99/yr"), annual)
        XCTAssertTrue(annual.contains("/mo"), "Annual always shows the per-month figure next to the total")
        XCTAssertEqual(PremiumPricing.annualMonthsIncluded(.horizon), 2)
        XCTAssertEqual(PremiumPricing.annualSavePercent(.horizon), 17)
        XCTAssertEqual(PremiumPricing.annualSaveUpTo, 17)
        XCTAssertEqual(RouteParser.parse("/settings/premium/compare"), .settings(.premium(.compare)))
        XCTAssertEqual(RouteParser.parse("/settings/premium/intro"), .settings(.premium(.intro)))
        XCTAssertEqual(PremiumPricing.annualMonthsIncluded(.horizonPlus), 2)
    }

    func testComparisonCoversEveryPlanAndCoreStaysFree() {
        XCTAssertFalse(PremiumCatalog.comparison.isEmpty)
        for row in PremiumCatalog.comparison {
            XCTAssertEqual(row.values.count, PremiumPlan.allCases.count, row.area)
            XCTAssertFalse(row.value(for: .core).isEmpty, row.area)
        }
        let moliboos = PremiumCatalog.comparison.first { $0.area == "Moliboos" }
        XCTAssertEqual(moliboos?.value(for: .core), "All 115 as today, Studio", "The 115 existing Moliboos are never re-gated")
        XCTAssertTrue(moliboos?.value(for: .horizonPlus).contains("#116") ?? false, "Premium-only Moliboos start at #116")
    }

    func testFAQIsHonestAboutVerificationAndCancelling() {
        let text = PremiumCatalog.faq.map { $0.question + " " + $0.answer }.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("verification is separate"))
        XCTAssertTrue(text.contains("never be bought"))
        XCTAssertTrue(text.contains("nothing is deleted"))
        for banned in ["only today", "hurry", "last chance", "are you sure you want to lose"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
    }
}
