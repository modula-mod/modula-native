import StoreKit
import StoreKitTest
import XCTest
@testable import Modula

/// Modula Premium: server-authoritative membership, sandbox contract parsing and UI invariants.
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

    func testPremiumRoutesMatchTheAtlasAndUseOnlySignedAppleTransactions() throws {
        XCTAssertEqual(PremiumAPI.tiers, "/v1/premium/tiers")
        XCTAssertEqual(PremiumAPI.membership, "/v1/me/membership")
        XCTAssertEqual(PremiumAPI.entitlements, "/v1/me/entitlements")
        XCTAssertEqual(PremiumAPI.entitlement(capabilityId: "in-mail"), "/v1/me/entitlements/in-mail")
        XCTAssertEqual(PremiumAPI.badgeVisibility, "/v1/me/membership/badge-visibility")
        XCTAssertEqual(PremiumAPI.applePurchaseContext, "/v1/me/membership/apple-purchase-context")
        XCTAssertEqual(PremiumAPI.appleTransactions, "/v1/premium/apple/transactions")
        let data = try JSONEncoder().encode(PremiumBadgeVisibilityRequest(visible: false))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"visible\":false}")
        let source = PremiumAPI.tiers + PremiumAPI.membership + PremiumAPI.entitlements + PremiumAPI.badgeVisibility
        XCTAssertFalse(source.contains("checkout"))
        XCTAssertFalse(source.contains("/admin/"))
        XCTAssertFalse(source.contains("/commerce/"))
        XCTAssertEqual(PremiumCatalog.membershipDisclaimer, "Modula Premium is a paid membership. It does not verify identity.")
    }

    func testAppleContextRequiresServerConfirmedSandboxMappings() throws {
        let context = try XCTUnwrap(PremiumApplePurchaseContext(json: .object([
            "environment": .string("sandbox"),
            "appAccountToken": .string("f13d8133-a9bd-496c-8f64-ef969d9d2f3d"),
            "products": .array([
                .object([
                    "productId": .string("digital.modula.premium.horizon.monthly"),
                    "tier": .string("horizon"), "billingPeriod": .string("monthly"),
                    "environment": .string("sandbox"), "state": .string("active")
                ]),
                .object([
                    "productId": .string("digital.modula.premium.horizon-plus.annual"),
                    "tier": .string("horizon_plus"), "billingPeriod": .string("annual"),
                    "environment": .string("sandbox"), "state": .string("active")
                ])
            ])
        ])))
        XCTAssertEqual(context.product(plan: .horizon, billing: .monthly)?.productID,
                       "digital.modula.premium.horizon.monthly")
        XCTAssertEqual(context.product(plan: .horizonPlus, billing: .annual)?.productID,
                       "digital.modula.premium.horizon-plus.annual")

        XCTAssertNil(PremiumApplePurchaseContext(json: .object([
            "environment": .string("production"),
            "appAccountToken": .string(UUID().uuidString),
            "products": .array([])
        ])))
    }

    func testServerMembershipIsAuthoritativeAndRevocationReturnsCore() throws {
        let store = PremiumEntitlementStore(defaults: defaults, isDebugBuild: true)
        let active = try XCTUnwrap(PremiumMembershipSnapshot(json: membership(
            tier: "horizon", status: "active", badgeVisible: false, revision: 3
        )))
        store.apply(active)
        XCTAssertEqual(store.plan, .horizon)
        XCTAssertEqual(store.entitlement.source, .serverVerified)
        XCTAssertFalse(store.showsOwnBadge)
        XCTAssertEqual(store.serverStatus, .active)
        XCTAssertEqual(store.serverRevision, 3)

        let revoked = try XCTUnwrap(PremiumMembershipSnapshot(json: membership(
            tier: "horizon", status: "revoked", badgeVisible: true, revision: 4
        )))
        store.apply(revoked)
        XCTAssertEqual(store.plan, .core)
        XCTAssertEqual(store.serverStatus, .revoked)
        XCTAssertFalse(store.showsOwnBadge)
    }

    func testAppleTransactionResponseMustMatchSandboxContract() throws {
        let accepted = try XCTUnwrap(PremiumAppleTransactionResult(json: .object([
            "accepted": .bool(true), "replay": .bool(false), "environment": .string("sandbox"),
            "transactionId": .string("1000000123456789"),
            "originalTransactionId": .string("1000000123000000"),
            "productId": .string("digital.modula.premium.plus.monthly"),
            "tier": .string("plus"), "status": .string("active"),
            "expiresAt": .string("2026-12-01T00:00:00.000Z"), "membershipRevision": .number(1)
        ])))
        XCTAssertEqual(accepted.plan, .plus)
        XCTAssertEqual(accepted.status, .active)
        XCTAssertNil(PremiumAppleTransactionResult(json: .object([
            "accepted": .bool(true), "replay": .bool(false), "environment": .string("production"),
            "transactionId": .string("1"), "productId": .string("product"),
            "tier": .string("studio"), "status": .string("active")
        ])))
    }

    func testLocalStoreKitPurchaseRenewalAndRevocation() async throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "ModulaPremium",
                withExtension: "storekit"
            )
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        defer { session.clearTransactions() }

        let productID = "modula.premium.plus.monthly"
        let products = try await Product.products(for: [productID])
        XCTAssertEqual(products.map(\.id), [productID])

        let purchased = try await session.buyProduct(identifier: productID, options: [])
        XCTAssertEqual(purchased.productID, productID)
        let original = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == productID }
        )
        XCTAssertTrue(original.autoRenewingEnabled)

        try session.forceRenewalOfSubscription(productIdentifier: productID)
        XCTAssertGreaterThanOrEqual(
            session.allTransactions().filter { $0.productIdentifier == productID }.count,
            2
        )

        try session.disableAutoRenewForTransaction(identifier: original.identifier)
        let disabled = try XCTUnwrap(
            session.allTransactions().first { $0.identifier == original.identifier }
        )
        XCTAssertFalse(disabled.autoRenewingEnabled)

        try session.refundTransaction(identifier: original.identifier)
        let refunded = try XCTUnwrap(
            session.allTransactions().first { $0.identifier == original.identifier }
        )
        XCTAssertNotNil(refunded.cancelDate)
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
        XCTAssertEqual(PremiumPricing.annualMonthsIncluded(.horizonPlus), 2)
        XCTAssertEqual(RouteParser.parse("/settings/premium/compare"), .settings(.premium(.compare)))
        XCTAssertEqual(RouteParser.parse("/settings/premium/intro"), .settings(.premium(.intro)))
        XCTAssertEqual(PremiumAPI.verification, "/v1/me/verification")
        XCTAssertEqual(PremiumAPI.insights, "/v1/creator/insights")
        XCTAssertEqual(PremiumAPI.invoices, "/v1/commerce/invoices")
        XCTAssertEqual(PremiumAPI.billingAdapters, "/v1/commerce/billing-adapters")
        XCTAssertEqual(PremiumAPI.payouts, "/v1/creator/payouts")
        XCTAssertEqual(PremiumAPI.inMail, "/v1/in-mail")
        XCTAssertFalse(PremiumAPI.billingAdapters.contains("entitlements"))
        XCTAssertEqual(PremiumStoreKitConfiguration.productSource, "GreenField confirmed sandbox mapping")
        XCTAssertFalse(PremiumStoreKitConfiguration.localConfigurationIsAppleSandboxEvidence)
        XCTAssertEqual(PremiumPurchaseCopy.sandbox, "Apple Sandbox purchases don’t charge your payment method.")
        XCTAssertEqual(PremiumPurchaseCopy.welcomeTitle, "You’re Premium!")
        XCTAssertEqual(PremiumMemberSettingsView.upsell(from: .plus), .horizon)
        XCTAssertEqual(PremiumMemberSettingsView.upsell(from: .horizon), .horizonPlus)
        XCTAssertNil(PremiumMemberSettingsView.upsell(from: .studio))
        XCTAssertEqual(RouteParser.parse("/settings/premium/purchase"), .settings(.premium(.purchase)))
        XCTAssertEqual(RouteParser.parse("/settings/premium/welcome"), .settings(.premium(.welcome)))
        for path in ["/settings/premium/dashboard", "/settings/premium/manage", "/settings/premium/visitors", "/settings/premium/storage", "/settings/premium/possibilities"] {
            XCTAssertEqual(RouteSerializer.serialize(try XCTUnwrap(RouteParser.parse(path))), path)
        }
    }

    func testDowngradeNeverDeletesData() {
        let usage = PremiumUsage(installedModules: 12, storageUsedGB: 80, unusedInMailCredits: 2, claimedPremiumItems: 3)
        let outcomes = PremiumDowngrade.outcomes(from: .horizon, to: .core, usage: usage)
        XCTAssertFalse(outcomes.isEmpty)
        XCTAssertTrue(outcomes.allSatisfy { $0.deletesData == false })
        XCTAssertTrue(outcomes.contains { $0.id == "verification" })
    }

    private func membership(tier: String, status: String, badgeVisible: Bool, revision: Int) -> JSONValue {
        .object([
            "schemaVersion": .number(1), "accountId": .string("account-premium-test"),
            "tier": .string(tier), "recordedTier": .string(tier),
            "subscriptionStatus": .string(status), "entitlementSource": .string("apple_verified"),
            "effectiveAt": .string("2026-11-03T12:00:00.000Z"),
            "expiresAt": .string("2026-12-03T12:00:00.000Z"),
            "membershipSince": .string("2026-11-03T12:00:00.000Z"),
            "badgeVisible": .bool(badgeVisible), "revision": .number(Double(revision))
        ])
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
