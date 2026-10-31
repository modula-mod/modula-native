import Foundation
import Observation

// MARK: - Modula Premium — phase 1 (UI only)
//
// Spec: "Modula Premium — Concept & Build Plan" page. Phase 1 is local and UI-only:
// - no StoreKit, no payment or receipt code, no server entitlements (phase 2 / phase 4 need Andy's go-ahead);
// - the whole surface sits behind `PremiumFeatureFlags`, which is always off in Release builds;
// - the only way to "have" a paid plan is the Debug-only preview override, which is local to this
//   device and is never sent to the server or written into a real account.
// Everything free today stays free: gating only ever applies to *new* premium capabilities.

// MARK: Feature flag

enum PremiumBuild {
    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif
}

enum PremiumFeatureFlags {
    /// Debug-only toggle (Settings → Modula Premium → Developer). Ignored in Release.
    static let enabledKey = "dev.premium.enabled"
    /// Debug-only preview plan. Ignored in Release.
    static let debugPlanKey = "dev.premium.debugPlan"

    /// `premiumEnabled`: off in Release so real users never see unfinished paywalls; on by default in
    /// Debug (can be switched off) so the surface can be reviewed on device and simulator.
    static func premiumEnabled(defaults: UserDefaults = .standard, isDebugBuild: Bool = PremiumBuild.isDebug) -> Bool {
        guard isDebugBuild else { return false }
        if ProcessInfo.processInfo.arguments.contains("--premium-disabled") { return false }
        return defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// Authenticated premium routes from the Greenfield HTTP atlas (`premium/routes.ts`).
/// Phase 1 does not call them. The atlas has no purchase or checkout route, so the hub cannot buy a plan.
/// Admin QA routes and `/v1/commerce/entitlements` are a different surface and are not used here.
/// Verification is `GET /v1/me/verification` and is never a premium purchase.
enum PremiumAPI {
    static let tiers = "/v1/premium/tiers"
    static let membership = "/v1/me/membership"
    static let entitlements = "/v1/me/entitlements"
    static let badgeVisibility = "/v1/me/membership/badge-visibility"

    static func entitlement(capabilityId: String) -> String {
        "/v1/me/entitlements/\(capabilityId)"
    }
}

/// Body for `PATCH /v1/me/membership/badge-visibility`. The atlas field is `visible`.
struct PremiumBadgeVisibilityRequest: Encodable, Equatable {
    var visible: Bool
}

// MARK: Plans

/// The plan ladder. `ModulaPremiumTier` (identity marks) is the *visual* tier; this is the product plan
/// with its limits and placeholder prices. `core` is the free plan and has no badge.
enum PremiumPlan: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case core, plus, horizon, horizonPlus, studio

    var id: String { rawValue }
    static let recommended: PremiumPlan = .horizon
    static let paid: [PremiumPlan] = [.plus, .horizon, .horizonPlus, .studio]

    /// Ladder order. Studio is a separate per-seat business plan that includes everything in Horizon Plus.
    var rank: Int {
        switch self {
        case .core: 0
        case .plus: 1
        case .horizon: 2
        case .horizonPlus: 3
        case .studio: 4
        }
    }

    var title: String {
        switch self {
        case .core: "Modula Core"
        case .plus: "Modula Plus"
        case .horizon: "Modula Horizon"
        case .horizonPlus: "Modula Horizon Plus"
        case .studio: "Modula Studio"
        }
    }

    var shortTitle: String {
        switch self {
        case .core: "Core"
        case .plus: "Plus"
        case .horizon: "Horizon"
        case .horizonPlus: "Horizon Plus"
        case .studio: "Studio"
        }
    }

    var tagline: String {
        switch self {
        case .core: "Free, forever. The full social OS."
        case .plus: "Express yourself."
        case .horizon: "Grow your reach."
        case .horizonPlus: "Everything, for creators."
        case .studio: "For businesses and teams."
        }
    }

    /// Why Horizon is recommended — the recommendation always says why (default effect, honestly used).
    var recommendationReason: String? {
        self == .recommended ? "Recommended: In-Mail, profile visitors and unlimited modules cover what most people upgrade for." : nil
    }

    var isPaid: Bool { self != .core }
    var showsBadge: Bool { self != .core }
    var isPerSeat: Bool { self == .studio }

    /// Placeholder prices in GBP minor units. NOT real prices — to be validated (and set in App Store
    /// Connect) before phase 4. Always shown with `PremiumPricing.placeholderNote`.
    var placeholderMonthlyMinor: Int {
        switch self {
        case .core: 0
        case .plus: 399
        case .horizon: 899
        case .horizonPlus: 1499
        case .studio: 2999
        }
    }

    var placeholderAnnualMinor: Int {
        switch self {
        case .core: 0
        case .plus: 3999
        case .horizon: 8999
        case .horizonPlus: 14999
        case .studio: 29999
        }
    }

    // Limits (placeholders, phase 2 moves them server-side). `nil` = unlimited.
    var moduleSlots: Int? {
        switch self {
        case .core: 5
        case .plus: 10
        case .horizon, .horizonPlus, .studio: nil
        }
    }

    var inMailCreditsPerMonth: Int {
        switch self {
        case .core: 0
        case .plus: 3
        case .horizon: 10
        case .horizonPlus: 25
        case .studio: 50
        }
    }

    var storageGB: Int {
        switch self {
        case .core: 5
        case .plus: 50
        case .horizon: 200
        case .horizonPlus, .studio: 1000
        }
    }

    var visitorHistoryDays: Int {
        switch self {
        case .core: 0
        case .plus: 30
        case .horizon: 90
        case .horizonPlus, .studio: 365
        }
    }

    var scheduledPosts: Int? {
        switch self {
        case .core: 3
        case .plus: 10
        case .horizon, .horizonPlus, .studio: nil
        }
    }

    func includes(_ other: PremiumPlan) -> Bool { rank >= other.rank }
}

enum PremiumBilling: String, CaseIterable, Identifiable, Hashable, Sendable {
    case monthly, annual
    var id: String { rawValue }
    var title: String { self == .monthly ? "Monthly" : "Annual" }
}

enum PremiumPricing {
    static let placeholderNote = "Placeholder prices — not final. Purchases aren’t available yet."
    static let comingSoon = "Coming soon"

    static func format(minor: Int, locale: Locale = Locale(identifier: "en_GB")) -> String {
        let value = Decimal(minor) / 100
        return value.formatted(.currency(code: "GBP").locale(locale))
    }

    /// Honest price line: annual always shows the total billed next to the per-month equivalent
    /// (anchoring + framing, both figures visible together, no fake "was" prices).
    static func priceLine(_ plan: PremiumPlan, billing: PremiumBilling, locale: Locale = Locale(identifier: "en_GB")) -> String {
        guard plan.isPaid else { return "Free" }
        let seat = plan.isPerSeat ? " per seat" : ""
        let from = plan.isPerSeat ? "from " : ""
        switch billing {
        case .monthly:
            return "\(from)\(format(minor: plan.placeholderMonthlyMinor, locale: locale))/mo\(seat)"
        case .annual:
            let perMonth = format(minor: Int((Double(plan.placeholderAnnualMinor) / 12).rounded()), locale: locale)
            return "\(from)\(format(minor: plan.placeholderAnnualMinor, locale: locale))/yr\(seat) · \(perMonth)/mo"
        }
    }

    /// Annual saving vs 12 monthly payments, in whole months (framed as "months included").
    static func annualMonthsIncluded(_ plan: PremiumPlan) -> Int {
        guard plan.isPaid, plan.placeholderMonthlyMinor > 0 else { return 0 }
        let saved = plan.placeholderMonthlyMinor * 12 - plan.placeholderAnnualMinor
        // Nearest whole month. The £x.99 annual totals sit a few pence under exactly two months free.
        return max(0, Int((Double(saved) / Double(plan.placeholderMonthlyMinor)).rounded()))
    }
}

// MARK: Features and gating

/// New premium capabilities only. Existing free features are deliberately *not* listed: Premium never
/// makes the free platform worse.
enum PremiumFeature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case badge
    case profilePlate
    case inMail
    case profileVisitors
    case unlimitedModules
    case qrCardStyles
    case exclusiveScenes
    case premiumMoliboos
    case cloudNodus
    case creatorStorefront
    case teamSeats

    var id: String { rawValue }

    var minimumPlan: PremiumPlan {
        switch self {
        case .badge, .inMail, .profileVisitors: .plus
        case .profilePlate, .unlimitedModules, .qrCardStyles, .exclusiveScenes, .cloudNodus: .horizon
        case .premiumMoliboos, .creatorStorefront: .horizonPlus
        case .teamSeats: .studio
        }
    }

    var title: String {
        switch self {
        case .badge: "Premium mark"
        case .profilePlate: "Profile plate"
        case .inMail: "In-Mail credits"
        case .profileVisitors: "Profile visitors"
        case .unlimitedModules: "Unlimited modules"
        case .qrCardStyles: "QR card styles"
        case .exclusiveScenes: "Exclusive Studio scenes"
        case .premiumMoliboos: "Premium Moliboos (#116+)"
        case .cloudNodus: "Opt-in cloud Nodus"
        case .creatorStorefront: "Creator storefront"
        case .teamSeats: "Team seats"
        }
    }
}

enum PremiumGateDecision: Equatable, Sendable {
    /// The plan includes it.
    case available
    /// Show a contextual glass prompt for the smallest plan that includes it.
    case upgrade(to: PremiumPlan)
    /// Premium surface is off (Release, or flag disabled): render nothing premium at all.
    case hidden
}

enum PremiumGate {
    static func decision(for feature: PremiumFeature, plan: PremiumPlan, premiumEnabled: Bool) -> PremiumGateDecision {
        guard premiumEnabled else { return .hidden }
        if plan.includes(feature.minimumPlan) { return .available }
        return .upgrade(to: feature.minimumPlan)
    }

    /// Module installs are gated only above the free limit, and existing installs are never removed.
    static func canInstallAnotherModule(installed: Int, plan: PremiumPlan, premiumEnabled: Bool) -> Bool {
        guard premiumEnabled, let slots = plan.moduleSlots else { return true }
        return installed < slots
    }
}

// MARK: Entitlement

struct PremiumEntitlement: Equatable, Sendable {
    enum Source: String, Sendable { case none, debugPreview }
    var plan: PremiumPlan
    var source: Source
    var since: Date?

    static let core = PremiumEntitlement(plan: .core, source: .none, since: nil)
}

/// Local, phase-1 entitlement state. Defaults to Core. Phase 2 reads `serverPlan` from
/// `GET /v1/me/membership` (see `PremiumAPI`). Until then the Debug preview is the only paid plan,
/// and it never leaves the device.
@MainActor
@Observable
final class PremiumEntitlementStore {
    static let shared = PremiumEntitlementStore()

    private let defaults: UserDefaults
    private let isDebugBuild: Bool

    /// Server-verified plan (phase 2, `GET /v1/me/membership`). Always Core in phase 1.
    private(set) var serverPlan: PremiumPlan = .core
    private(set) var debugOverride: PremiumPlan?
    private(set) var debugSince: Date?
    /// Owner's choice to show the premium mark/plate. Local preference; hiding never removes features.
    var badgeVisible: Bool {
        didSet { defaults.set(badgeVisible, forKey: Self.badgeVisibleKey) }
    }
    /// Plan picked in the upgrade flow (Horizon by default — the recommended plan).
    var selectedPlan: PremiumPlan = .recommended
    var selectedBilling: PremiumBilling = .monthly
    /// Locally ticked first-week steps (preview only).
    private(set) var completedActivation: Set<String>

    static let badgeVisibleKey = "premium.badgeVisible"
    static let activationKey = "premium.activation.completed"

    init(defaults: UserDefaults = .standard, isDebugBuild: Bool = PremiumBuild.isDebug) {
        self.defaults = defaults
        self.isDebugBuild = isDebugBuild
        badgeVisible = defaults.object(forKey: Self.badgeVisibleKey) as? Bool ?? true
        completedActivation = Set(defaults.stringArray(forKey: Self.activationKey) ?? [])
        if isDebugBuild, let raw = defaults.string(forKey: PremiumFeatureFlags.debugPlanKey), let plan = PremiumPlan(rawValue: raw), plan != .core {
            debugOverride = plan
            debugSince = defaults.object(forKey: PremiumFeatureFlags.debugPlanKey + ".since") as? Date
        }
    }

    var premiumEnabled: Bool { PremiumFeatureFlags.premiumEnabled(defaults: defaults, isDebugBuild: isDebugBuild) }

    var entitlement: PremiumEntitlement {
        guard premiumEnabled else { return .core }
        if isDebugBuild, let debugOverride {
            return PremiumEntitlement(plan: debugOverride, source: .debugPreview, since: debugSince)
        }
        return PremiumEntitlement(plan: serverPlan, source: .none, since: nil)
    }

    var plan: PremiumPlan { entitlement.plan }
    var isPreviewing: Bool { entitlement.source == .debugPreview }

    /// The mark/plate shows only for a paid entitlement (or the Debug preview) and only if the owner
    /// hasn't hidden it.
    var showsOwnBadge: Bool { premiumEnabled && plan.showsBadge && badgeVisible }

    func decision(for feature: PremiumFeature) -> PremiumGateDecision {
        PremiumGate.decision(for: feature, plan: plan, premiumEnabled: premiumEnabled)
    }

    /// Debug builds only. Local preview; never persisted to a real account or sent anywhere.
    func setDebugOverride(_ plan: PremiumPlan?, now: Date = .now) {
        guard isDebugBuild else { return }
        if let plan, plan != .core {
            if debugOverride == nil { debugSince = now }
            debugOverride = plan
            defaults.set(plan.rawValue, forKey: PremiumFeatureFlags.debugPlanKey)
            defaults.set(debugSince, forKey: PremiumFeatureFlags.debugPlanKey + ".since")
        } else {
            debugOverride = nil
            debugSince = nil
            defaults.removeObject(forKey: PremiumFeatureFlags.debugPlanKey)
            defaults.removeObject(forKey: PremiumFeatureFlags.debugPlanKey + ".since")
        }
    }

    func setPremiumEnabled(_ enabled: Bool) {
        guard isDebugBuild else { return }
        defaults.set(enabled, forKey: PremiumFeatureFlags.enabledKey)
    }

    func markActivation(_ id: String, done: Bool = true) {
        if done { completedActivation.insert(id) } else { completedActivation.remove(id) }
        defaults.set(Array(completedActivation).sorted(), forKey: Self.activationKey)
    }
}

// MARK: Comparison and FAQ content

struct PremiumComparisonRow: Identifiable, Hashable, Sendable {
    let area: String
    let symbol: String
    let values: [String] // core, plus, horizon, horizonPlus, studio
    var id: String { area }

    func value(for plan: PremiumPlan) -> String {
        let index = PremiumPlan.allCases.firstIndex(of: plan) ?? 0
        return values.indices.contains(index) ? values[index] : ""
    }
}

struct PremiumFAQItem: Identifiable, Hashable, Sendable {
    let question: String
    let answer: String
    var id: String { question }
}

enum PremiumCatalog {
    static let positioning = "Your profile, with more power behind it: more reach, more room and more expression."

    static let comparison: [PremiumComparisonRow] = [
        .init(area: "Badge", symbol: "seal", values: ["None", "Pearl mark", "Gold glass mark", "Horizon gradient mark", "Obsidian-gold mark"]),
        .init(area: "Profile", symbol: "person.crop.rectangle", values: ["Full profile, cover, QR card", "Accent colour, 3 pinned posts", "Profile plate, QR card styles", "Animated cover and avatar", "Business layout, team row"]),
        .init(area: "Modules", symbol: "shippingbox", values: ["Up to 5 installed", "Up to 10", "Unlimited", "Unlimited + early access", "Team modules, shared CRM"]),
        .init(area: "Messaging", symbol: "envelope.badge", values: ["Unlimited DMs, message requests", "3 In-Mail a month", "10 In-Mail, scheduled send", "25 In-Mail, priority filters", "50 In-Mail per seat, team inbox"]),
        .init(area: "Moliboos", symbol: "pawprint", values: ["All 115 as today, Studio", "Monthly wardrobe drop", "Exclusive scenes, seasonal outfits", "New characters (#116+), Legend scenes", "Brand Moliboo colourway"]),
        .init(area: "Analytics", symbol: "chart.bar", values: ["Post counts", "30-day visitor count", "90-day visitors, post insights", "365-day, audience insights", "Team dashboards"]),
        .init(area: "Storage", symbol: "internaldrive", values: ["5 GB", "50 GB", "200 GB", "1 TB", "1 TB pooled per seat"]),
        .init(area: "AI · Nodus", symbol: "brain", values: ["On-device Nodus", "On-device composer assist", "Opt-in cloud Nodus", "Higher cloud limits", "Team AI, admin controls"]),
        .init(area: "Creator tools", symbol: "sparkles.rectangle.stack", values: ["3 scheduled posts", "10 scheduled posts", "Unlimited scheduling", "Creator subscriptions, storefront", "Catalogue, roles, invoices"]),
    ]

    static let faq: [PremiumFAQItem] = [
        .init(question: "Will anything free get worse?", answer: "No. Everything in Modula Core today stays free. Premium only adds new things."),
        .init(question: "Does the premium mark mean I’m verified?", answer: "No. The mark shows a paid membership. Verification is separate, free, and can never be bought."),
        .init(question: "What happens if I cancel or downgrade?", answer: "You keep your plan until the end of the period. Nothing is deleted: outfits, characters and scenes you claimed stay yours, and data over a limit becomes read-only, never removed."),
        .init(question: "How do I cancel?", answer: "Two taps: Settings → Modula Premium → Manage → Cancel. No questions you can’t skip."),
        .init(question: "Will I be reminded before I’m charged?", answer: "Yes — before any trial ends and before every annual renewal."),
        .init(question: "Can I hide the badge?", answer: "Yes. Hiding the mark never removes any features."),
        .init(question: "Are these the final prices?", answer: "No. Prices shown are placeholders while plans are being finalised."),
    ]
}

// MARK: Downgrade — never deletes

struct PremiumUsage: Equatable, Sendable {
    var installedModules: Int = 0
    var storageUsedGB: Double = 0
    var unusedInMailCredits: Int = 0
    var claimedPremiumItems: Int = 0
}

struct PremiumDowngradeOutcome: Identifiable, Hashable, Sendable {
    enum Effect: String, Hashable, Sendable { case kept, readOnly, paused, frozen, hidden }
    let id: String
    let title: String
    let detail: String
    let effect: Effect
    /// Invariant: always false. Downgrading never deletes user data, outfits or ownership.
    let deletesData: Bool
}

enum PremiumDowngrade {
    static func outcomes(from current: PremiumPlan, to target: PremiumPlan, usage: PremiumUsage) -> [PremiumDowngradeOutcome] {
        guard target.rank < current.rank else { return [] }
        var result: [PremiumDowngradeOutcome] = [
            .init(id: "owned", title: "Outfits, characters and scenes", detail: usage.claimedPremiumItems > 0 ? "All \(usage.claimedPremiumItems) items you claimed stay owned and wearable." : "Everything you claimed stays owned and wearable.", effect: .kept, deletesData: false),
            .init(id: "moliboo", title: "Saved outfits and Moliboo state", detail: "Untouched.", effect: .kept, deletesData: false),
        ]
        if let slots = target.moduleSlots, usage.installedModules > slots {
            result.append(.init(id: "modules", title: "Modules over the \(slots)-module limit", detail: "\(usage.installedModules - slots) stay installed with their data; read-only until you choose which \(slots) stay active.", effect: .readOnly, deletesData: false))
        } else {
            result.append(.init(id: "modules", title: "Modules", detail: "All installed modules keep working.", effect: .kept, deletesData: false))
        }
        if usage.storageUsedGB > Double(target.storageGB) {
            result.append(.init(id: "storage", title: "Storage over \(target.storageGB) GB", detail: "Nothing is deleted. New uploads pause until you’re under the limit.", effect: .paused, deletesData: false))
        }
        if usage.unusedInMailCredits > 0, target.inMailCreditsPerMonth < current.inMailCreditsPerMonth {
            result.append(.init(id: "inmail", title: "\(usage.unusedInMailCredits) unused In-Mail credits", detail: "Frozen, and restored if you come back within 90 days.", effect: .frozen, deletesData: false))
        }
        result.append(.init(id: "analytics", title: "Analytics history", detail: "Kept. Older ranges are hidden, not deleted.", effect: .hidden, deletesData: false))
        if !target.showsBadge {
            result.append(.init(id: "badge", title: "Premium mark and plate", detail: "Removed at the end of the period. Your “member since” history is kept.", effect: .hidden, deletesData: false))
        }
        result.append(.init(id: "verification", title: "Verification", detail: "Unaffected — it’s never tied to Premium.", effect: .kept, deletesData: false))
        return result
    }
}

// MARK: First week (activation) and cancel

struct PremiumActivationStep: Identifiable, Hashable, Sendable {
    let id: String
    let day: Int
    let title: String
    let detail: String
    /// If–then plan the member can opt into (implementation intention). Optional.
    let plan: String
}

enum PremiumActivation {
    static let maxNudgesPerDay = 1

    static func steps(for plan: PremiumPlan) -> [PremiumActivationStep] {
        guard plan.isPaid else { return [] }
        var steps: [PremiumActivationStep] = [
            .init(id: "wardrobe", day: 0, title: "Claim a wardrobe item", detail: "Pick one \(plan.shortTitle) item for your Moliboo. It’s yours to keep.", plan: "When I open my Moliboo, I’ll try the new item."),
            .init(id: "visitors", day: 1, title: "See who stopped by", detail: "Profile visitors are unlocked.", plan: "When I finish a post, I’ll check who saw my profile."),
            .init(id: "inmail", day: 2, title: "Send your first In-Mail", detail: "The credit comes back if they reply.", plan: "When I find someone I want to work with, I’ll send an In-Mail."),
        ]
        if plan.includes(.horizon) {
            steps.append(.init(id: "module", day: 3, title: "Add a module beyond the free limit", detail: "Pick one that fits your profile.", plan: "When I need a tool, I’ll look in Modules first."))
            steps.append(.init(id: "scene", day: 5, title: "Try an exclusive Studio scene", detail: "Dress your Moliboo’s world.", plan: "When I change my outfit, I’ll try a new scene."))
        }
        steps.append(.init(id: "recap", day: 7, title: "Your first-week recap", detail: "What \(plan.shortTitle) did for you, in real numbers.", plan: "When the recap arrives, I’ll keep what helped."))
        return steps
    }
}

enum PremiumCancelFlow {
    /// Settings → Modula Premium → Manage → "Cancel membership" → confirm: two taps from Manage.
    static let tapsFromManage = 2
    static let optionalQuestion = "What should we improve?"

    static func endingCopy(plan: PremiumPlan, periodEnd: Date?) -> String {
        if let periodEnd {
            return "You keep \(plan.shortTitle) until \(periodEnd.formatted(.dateTime.day().month(.wide))). Everything you own stays yours."
        }
        return "You keep \(plan.shortTitle) until the end of your period. Everything you own stays yours."
    }
}
