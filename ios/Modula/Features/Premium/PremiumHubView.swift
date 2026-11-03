import SwiftUI
import UIKit

// MARK: - Modula Premium hub (phase 1, UI only)
//
// Settings → Modula Premium, and "What's in Horizon" from a premium mark's popover.
// Psychology (see the plan page): few clearly ordered plans with one labelled recommendation
// (Hick–Hyman; choice overload treated as conditional), honest price framing (annual total next to
// the per-month figure), and no urgency, scarcity or guilt copy anywhere.

extension PremiumPlan {
    /// Accent used for plan chrome (cards, pills). Badge marks themselves come from the identity marks.
    var tint: Color {
        switch self {
        case .core: Color.secondary
        case .plus: Color(red: 0.55, green: 0.59, blue: 0.65)
        case .horizon: Color(red: 0.886, green: 0.71, blue: 0.29)
        case .horizonPlus: Color(red: 0.93, green: 0.54, blue: 0.42)
        case .studio: Color(red: 0.36, green: 0.34, blue: 0.40)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .horizonPlus:
            LinearGradient(colors: [Color(red: 0.96, green: 0.84, blue: 0.48), Color(red: 0.93, green: 0.54, blue: 0.42), Color(red: 0.43, green: 0.34, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .studio:
            LinearGradient(colors: [Color(red: 0.23, green: 0.23, blue: 0.26), Color(red: 0.07, green: 0.07, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var symbol: String {
        switch self {
        case .core: "circle.grid.2x2"
        case .plus: "sparkle"
        case .horizon: "sun.horizon.fill"
        case .horizonPlus: "sun.max.fill"
        case .studio: "building.2.fill"
        }
    }
}

struct PremiumHubView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = PremiumEntitlementStore.shared
    @State private var audience: PremiumAudience = .personal
    @State private var expandedFAQ: String?
    @State private var catalogueNote: String?

    var body: some View {
        SettingsScrollCanvas {
            // Reference order: promise + Unit stage, billing toggle, side-by-side plans, benefits grid.
            PremiumPromiseMasthead()
            PremiumHeroCard(plan: store.plan, previewing: store.isPreviewing)

            Picker("Audience", selection: $audience) {
                ForEach(PremiumAudience.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("premium.audience")
            .onChange(of: audience) { _, value in
                guard !value.plans.contains(store.selectedPlan) else { return }
                store.selectedPlan = value == .personal ? .recommended : .studio
            }

            HStack {
                PremiumBillingToggle(selection: $store.selectedBilling)
                    .accessibilityIdentifier("premium.billing")
                Spacer(minLength: 8)
                if PremiumPricing.annualSaveUpTo > 0 {
                    Text("Save up to \(PremiumPricing.annualSaveUpTo)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(audience.plans) { plan in
                        PremiumPlanColumn(
                            plan: plan,
                            billing: store.selectedBilling,
                            selected: store.selectedPlan == plan,
                            current: store.plan == plan
                        ) {
                            withAnimation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                                store.selectedPlan = plan
                            }
                            HapticEngine.shared.play(.selection)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier("premium.plans")

            Text(PremiumPricing.placeholderNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("premium.placeholderNote")

            PremiumWhatYouGetGrid {
                app.navigation.open(.settings(.premium(.compare)))
            }

            TelegramSettingsCard {
                TelegramRow(title: "Dashboard", symbol: "square.grid.2x2", tint: app.appearance.liveAccent, value: store.plan.shortTitle) {
                    app.navigation.open(.settings(.premium(.dashboard)))
                }
                .accessibilityIdentifier("premium.dashboard.link")
                TelegramDivider()
                TelegramRow(title: "Compare plans", symbol: "checklist", tint: app.appearance.liveAccent) {
                    app.navigation.open(.settings(.premium(.compare)))
                }
                TelegramDivider()
                TelegramRow(title: "Why Horizon", symbol: "sun.horizon.fill", tint: app.appearance.liveAccent) {
                    app.navigation.open(.settings(.premium(.intro)))
                }
                .accessibilityIdentifier("premium.intro.link")
                TelegramDivider()
                TelegramRow(title: "Premium badge", symbol: "seal.fill", tint: app.appearance.liveAccent, value: store.plan.showsBadge ? store.plan.shortTitle : "Core") {
                    app.navigation.open(.settings(.premium(.badge)))
                }
                .accessibilityIdentifier("premium.badge.link")
            }

            faq

            if let catalogueNote {
                SettingsAPIFootnote(text: catalogueNote)
            }
            Text(PremiumCatalog.membershipDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("premium.disclaimer")

            #if DEBUG
            PremiumDeveloperCard(store: store)
            #endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PremiumStickyCTA(plan: store.selectedPlan, billing: store.selectedBilling, currentPlan: store.plan) {
                app.navigation.open(.settings(.premium(.compare)))
            }
        }
        .navigationTitle("Modula Premium")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.hub")
        .task { await refreshCatalogue() }
    }

    private func billingLabel(_ billing: PremiumBilling) -> String {
        if billing == .annual, PremiumPricing.annualSaveUpTo > 0 {
            return "Yearly · \(PremiumPricing.annualSaveUpTo)%"
        }
        return billing == .monthly ? "Monthly" : "Yearly"
    }

    private func refreshCatalogue() async {
        guard app.auth.isSignedIn else {
            catalogueNote = "Sign in to refresh the live catalogue. Prices shown are the on-device catalogue."
            return
        }
        do {
            _ = try await PremiumRemote.loadTiers(client: app.client)
            await app.premiumPurchases.prepare()
            catalogueNote = app.premiumPurchases.message
                ?? "GreenField’s confirmed Apple Sandbox mappings are available. Apple supplies the checkout price."
        } catch {
            catalogueNote = "Couldn’t refresh the live catalogue. Showing the on-device catalogue."
        }
    }

    private var faq: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions").font(.headline)
            TelegramSettingsCard {
                ForEach(Array(PremiumCatalog.faq.enumerated()), id: \.element.id) { index, item in
                    PremiumFAQRow(item: item, expanded: expandedFAQ == item.id) {
                        withAnimation(ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                            expandedFAQ = expandedFAQ == item.id ? nil : item.id
                        }
                    }
                    if index < PremiumCatalog.faq.count - 1 {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 1 / UIScreen.main.scale).padding(.leading, 16)
                    }
                }
            }
        }
        .accessibilityIdentifier("premium.faq")
    }
}

// MARK: Hero

struct PremiumHeroCard: View {
    let plan: PremiumPlan
    let previewing: Bool

    var body: some View {
        // Compact member status. The big visual is the Unit stage in the masthead above, so this
        // card no longer repeats a scene image (one focal point per screen).
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack(spacing: ModulaSpacing.sm) {
                ModulaUnitMark(style: .glass(ModulaBrandPalette.lavenderDeep))
                    .frame(width: ModulaPremiumMetrics.planIconSize, height: ModulaPremiumMetrics.planIconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ModulaSpacing.hairline) {
                    Text("Modula Premium").font(.title3.weight(.semibold))
                    Text(statusLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(PremiumCatalog.positioning)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ModulaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false, tint: ModulaBrandPalette.lavender, specular: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("premium.hero")
    }

    private var statusLine: String {
        if previewing { return "Previewing \(plan.shortTitle) · Debug only" }
        return plan.isPaid ? "You’re on \(plan.title)" : "You’re on Modula Core — free, forever"
    }
}

// MARK: Plan card

struct PremiumPlanCard: View {
    let plan: PremiumPlan
    let billing: PremiumBilling
    let selected: Bool
    let current: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: ModulaSpacing.sm) {
                Image(systemName: plan.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: ModulaPremiumMetrics.planIconSize, height: ModulaPremiumMetrics.planIconSize)
                    .background(plan.gradient, in: RoundedRectangle(cornerRadius: ModulaRadius.small, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
                    HStack(spacing: ModulaSpacing.xs) {
                        Text(plan.title).font(.body.weight(.semibold))
                        if plan == .recommended {
                            // Recommendation uses the accent, matching the selected state and CTA.
                            PremiumPill(text: "Recommended", tint: app.appearance.liveAccent)
                        }
                        if current {
                            PremiumPill(text: "Current", tint: .secondary)
                        }
                    }
                    Text(plan.tagline).font(.subheadline).foregroundStyle(.secondary)
                    if let reason = plan.recommendationReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    // Price is the second thing the eye lands on after the name (clear card hierarchy).
                    HStack(spacing: ModulaSpacing.xs) {
                        Text(PremiumPricing.priceLine(plan, billing: billing))
                            .font(.headline.monospacedDigit())
                        Text("Placeholder")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2])))
                    }
                    if billing == .annual, PremiumPricing.annualMonthsIncluded(plan) > 0 {
                        Text("\(PremiumPricing.annualMonthsIncluded(plan)) months included vs paying monthly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? app.appearance.liveAccent : Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(ModulaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98))
        // Unselected cards sit on soft lavender glass; the selected one switches to the accent.
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: true, tint: selected ? app.appearance.liveAccent.opacity(0.25) : ModulaBrandPalette.lavender.opacity(0.6), specular: true)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous)
                    .strokeBorder(app.appearance.liveAccent.opacity(0.85), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("premium.plan.\(plan.rawValue)")
    }
}

struct PremiumPill: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((tint == .secondary ? Color.secondary : tint).opacity(0.16), in: Capsule())
            .lineLimit(1)
    }
}

/// Primary call to action. Phase 1: opens the upgrade preview; buying is disabled ("Coming soon").
struct PremiumPrimaryButton: View {
    let plan: PremiumPlan
    let currentPlan: PremiumPlan
    /// Phase 1 before the upgrade flow exists: shows "Coming soon" and stays disabled.
    var comingSoon = false
    var identifier = "premium.continue"
    var action: () -> Void

    private var label: String {
        if currentPlan == plan { return "You’re on \(plan.shortTitle)" }
        return comingSoon ? "\(plan.shortTitle) · \(PremiumPricing.comingSoon)" : "Choose \(plan.shortTitle)"
    }

    var body: some View {
        Button(action: action) {
            // No local foreground colour: `modulaAccentCTA` owns it (white on solid accent, accent
            // text on the outline when disabled — previously white-on-pale read as washed out).
            Text(label)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.ctaHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97))
        .modulaAccentCTA()
        .disabled(currentPlan == plan || comingSoon)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Comparison + FAQ rows

struct PremiumComparisonRowView: View {
    let row: PremiumComparisonRow
    let plan: PremiumPlan

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: row.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(plan.tint)
                .frame(width: 30, height: 30)
                .background(plan.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.area).font(.subheadline.weight(.semibold))
                Text(row.value(for: plan)).font(.subheadline)
                Text("Core: \(row.value(for: .core))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct PremiumFAQRow: View {
    let item: PremiumFAQItem
    let expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.question).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                if expanded {
                    Text(item.answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

#if DEBUG
/// Debug builds only: preview each plan locally. Never written to a real account or sent to the server.
struct PremiumDeveloperCard: View {
    let store: PremiumEntitlementStore
    @State private var enabled = PremiumFeatureFlags.premiumEnabled()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Developer").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Premium surface", isOn: $enabled)
                    .onChange(of: enabled) { _, value in store.setPremiumEnabled(value) }
                HStack {
                    Text("Preview plan")
                    Spacer()
                    Picker("Preview plan", selection: Binding(
                        get: { store.debugOverride ?? .core },
                        set: { store.setDebugOverride($0) }
                    )) {
                        ForEach(PremiumPlan.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("premium.debugPlan")
                }
                Text("Local presentation preview only. It never changes GreenField membership or substitutes for an Apple Sandbox purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .accessibilityIdentifier("premium.developer")
    }
}
#endif

// MARK: - Reference redesign pieces

struct PremiumPromiseMasthead: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text("MODULA PREMIUM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(app.appearance.liveAccent.opacity(0.12), in: Capsule())
                (Text("More possibilities with ") + Text("Modula.").foregroundStyle(app.appearance.liveAccent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("More reach. More room. More expression.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(app.appearance.liveAccent.opacity(0.18)).blur(radius: 24)
                ModulaUnitMark(style: .glass(ModulaBrandPalette.lavenderDeep))
                    .frame(width: 92, height: 92)
                Image(PremiumBadgeAsset.crown.rawValue).resizable().scaledToFit().frame(width: 34).offset(x: 40, y: -44)
                Image(PremiumBadgeAsset.analytics.rawValue).resizable().scaledToFit().frame(width: 30).offset(x: -46, y: -30)
                Image(PremiumBadgeAsset.sparkle.rawValue).resizable().scaledToFit().frame(width: 28).offset(x: 46, y: 40)
            }
            .frame(width: 130, height: 140)
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }
}

struct PremiumBillingToggle: View {
    @Binding var selection: PremiumBilling
    @Environment(AppEnvironment.self) private var app
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(PremiumBilling.allCases) { billing in
                let on = selection == billing
                Button {
                    withAnimation(.snappy) { selection = billing }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Text(billing == .monthly ? "Monthly" : "Yearly")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(width: 100, height: 40)
                        .background {
                            if on { Capsule().fill(app.appearance.liveAccent).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .modulaGlass(in: Capsule(), interactive: true)
    }
}

struct PremiumPlanColumn: View {
    let plan: PremiumPlan
    let billing: PremiumBilling
    let selected: Bool
    let current: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    private var perks: [String] {
        let included = PremiumFeature.allCases.filter { $0.minimumPlan.rank <= plan.rank && $0.minimumPlan != .core }
        if plan == .core { return ["The full social OS", "Modules & Product Hub", "Moliboos & Studio"] }
        return Array(included.suffix(4).map(\.title))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 8) {
                Group {
                    if let mark = PremiumBadgeAsset.profileMark(for: plan) {
                        Image(mark.rawValue).resizable().scaledToFit()
                    } else {
                        ModulaUnitMark(style: .glass(nil))
                    }
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
                Text(plan.shortTitle).font(.headline)
                Text(PremiumPricing.priceLine(plan, billing: billing))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(plan == .core ? Color.primary : app.appearance.liveAccent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(plan.tagline).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(perks, id: \.self) { perk in
                        Label {
                            Text(perk).font(.caption2).lineLimit(2)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(plan == .recommended ? app.appearance.liveAccent : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                Spacer(minLength: 6)
                Text(current ? "Current plan" : (selected ? "Selected" : "Choose"))
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .modulaAccentCTA()
                    .disabled(current || !selected)
            }
            .padding(12)
            .frame(width: 150, height: 330)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true, tint: selected ? app.appearance.liveAccent.opacity(0.18) : nil, specular: true)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? app.appearance.liveAccent : .clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if plan == .recommended {
                Text("Recommended")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(app.appearance.liveAccent, in: Capsule())
                    .offset(y: -10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("premium.plan.\(plan.rawValue)")
    }
}

struct PremiumWhatYouGetGrid: View {
    var onSeeAll: () -> Void
    @Environment(AppEnvironment.self) private var app
    private let items: [(String, String, PremiumBadgeAsset)] = [
        ("Premium mark", "Shown on your profile", .pearl),
        ("Profile plate", "Exclusive frames", .frame),
        ("In-Mail", "Message beyond follows", .inMail),
        ("Visitors", "See who viewed you", .analytics),
        ("Modules", "Unlimited installs", .tokens),
        ("Scenes", "Exclusive Studio scenes", .sparkle),
        ("Early access", "New features first", .ticket),
        ("Moliboos", "Premium companions", .gift)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What you get").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onSeeAll) {
                    HStack(spacing: 4) { Text("See all features"); Image(systemName: "chevron.right") }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .padding(.horizontal, 12).frame(height: 30)
                        .overlay(Capsule().strokeBorder(app.appearance.liveAccent.opacity(0.4)))
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4), spacing: 14) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 6) {
                        Image(item.2.rawValue)
                            .resizable().scaledToFit()
                            .frame(width: 34, height: 34)
                            .frame(width: 54, height: 54)
                            .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, specular: true)
                        Text(item.0).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8)
                        Text(item.1).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct PremiumStickyCTA: View {
    let plan: PremiumPlan
    let billing: PremiumBilling
    let currentPlan: PremiumPlan
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentPlan == plan ? "You’re on \(plan.shortTitle)" : "Get \(plan.title)")
                        .font(.headline)
                    Text("\(PremiumPricing.priceLine(plan, billing: billing)) · Cancel anytime")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22), in: Circle())
            }
            .padding(.leading, 20).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98))
        .modulaAccentCTA()
        .disabled(currentPlan == plan)
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 8)
        .accessibilityIdentifier("premium.continue")
    }
}
